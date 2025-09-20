package com.awesomeproject.hotupdate

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okio.buffer
import okio.sink
import okio.source
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.math.BigInteger
import java.security.MessageDigest
import java.util.zip.ZipInputStream

data class RNBundleInfo(val version: String, val bundlePath: String)

object HotUpdateManager {

    private const val TAG = "HotUpdateManager"

    private val client = OkHttpClient()
    private val gson = Gson()

    /**
     * 获取当前正在使用的RN包信息（版本和路径）
     */
    fun getCurrentRNBundleInfo(context: Context): RNBundleInfo {
        val configFile = File(context.filesDir, "${HotUpdateConfig.RN_HOTUPDATE_DIR}/${HotUpdateConfig.RN_CONFIG_FILE}")
        // 如果配置文件存在，且内容合法，则读取信息
        if (configFile.exists()) {
            try {
                val configJson = configFile.readText()
                val info = gson.fromJson(configJson, RNBundleInfo::class.java)
                val bundleFile = File(info.bundlePath)
                if (bundleFile.exists()) {
                    return info
                }
            } catch (e: Exception) {
                // 配置文件损坏或内容非法，继续使用默认包
                e.printStackTrace()
            }
        }
        // 默认情况，返回assets中的包信息
        return RNBundleInfo(HotUpdateConfig.DEFAULT_RN_VERSION, "assets://${HotUpdateConfig.JS_BUNDLE_FILE_NAME}")
    }

    /**
     * 检查是否有新版本
     */
    suspend fun checkUpdate(context: Context): UpdateCheckResponse? = withContext(Dispatchers.IO) {
        try {
            val currentVersion = getCurrentRNBundleInfo(context).version
            val requestBody = gson.toJson(UpdateCheckRequest("android", HotUpdateConfig.NATIVE_APP_VERSION))

//            Log.d(TAG, "Current RN version: $currentRnVersion, Native version: $nativeVersion")
            Log.d(TAG, "requestBody: $requestBody")

            val request = Request.Builder()
                .url(HotUpdateConfig.VERSION_API_URL)
                .post(requestBody.toRequestBody("application/json".toMediaType()))
                .build()

            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext null
                val responseBody = response.body?.string() ?: return@withContext null

                Log.d(TAG, "responseBody: $responseBody")

                val updateInfo = gson.fromJson(responseBody, UpdateCheckResponse::class.java)

                val remoteRnVersion = updateInfo.rn_version
                Log.d(TAG, "updateInfo.rn_version: $remoteRnVersion")
                Log.d(TAG, "currentVersion: $currentVersion")

                // 版本号比较，简单地按字符串比较
                if (updateInfo.rn_version > currentVersion) {

                    Log.d(TAG, "return updateInfo")

                    return@withContext updateInfo
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return@withContext null
    }

    /**
     * 下载、校验并安装新版本
     */
    suspend fun downloadAndInstall(context: Context, updateInfo: UpdateCheckResponse): Boolean = withContext(Dispatchers.IO) {
        val hotUpdateDir = File(context.filesDir, HotUpdateConfig.RN_HOTUPDATE_DIR)
        if (!hotUpdateDir.exists()) hotUpdateDir.mkdirs()

        val tempZipFile = File(hotUpdateDir, "temp_${updateInfo.rn_version}.zip")
        val newVersionDir = File(hotUpdateDir, updateInfo.rn_version)

        try {
            // 1. 下载
            val request = Request.Builder().url(updateInfo.rn_zip_url).build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext false

                Log.d(TAG, "download RN zip success")

                response.body?.source()?.use { source ->
                    tempZipFile.sink().buffer().use { sink ->
                        sink.writeAll(source)
                    }
                } ?: return@withContext false
            }

            // 2. MD5校验
            val fileMD5 = calculateMD5(tempZipFile)
            if (fileMD5.equals(updateInfo.checksum, ignoreCase = true)) {
                // 校验成功
                Log.d(TAG, "check md5 success")
            } else {
                // 校验失败
                Log.d(TAG, "check md5 failed")
                tempZipFile.delete()
                return@withContext false
            }

            // 3. 解压
            if (newVersionDir.exists()) newVersionDir.deleteRecursively()
            newVersionDir.mkdirs()
            unzip(tempZipFile, newVersionDir)

            // 4. 检查解压后bundle文件是否存在
            val bundleFile = File(newVersionDir, HotUpdateConfig.JS_BUNDLE_FILE_NAME)
            if (!bundleFile.exists()) {
                newVersionDir.deleteRecursively() // 清理不完整的解压目录
                return@withContext false
            }

            // 5. 更新配置文件（原子操作）
            val newInfo = RNBundleInfo(updateInfo.rn_version, bundleFile.absolutePath)

            Log.d(TAG, "Writing config for new bundle. Path: ${newInfo.bundlePath}")

            val configFile = File(hotUpdateDir, HotUpdateConfig.RN_CONFIG_FILE)
            configFile.writeText(gson.toJson(newInfo))

            Log.d(TAG, "New config file path: ${configFile.absolutePath}")
            if (configFile.exists()) {
                Log.d(TAG, "New config file exists. Content: ${configFile.readText()}")
            } else {
                Log.e(TAG, "New config file does NOT exist!")
            }
            return@withContext true

        } catch (e: Exception) {
            e.printStackTrace()
            // 出错时清理临时文件和目录
            if (tempZipFile.exists()) tempZipFile.delete()
            if (newVersionDir.exists()) newVersionDir.deleteRecursively()
            return@withContext false
        } finally {
            // 确保临时zip文件被删除
            if (tempZipFile.exists()) tempZipFile.delete()
        }
    }

    private fun calculateMD5(file: File): String {
        val digest = MessageDigest.getInstance("MD5")
        FileInputStream(file).use { fis ->
            val buffer = ByteArray(8192)
            var read: Int
            while (fis.read(buffer).also { read = it } > 0) {
                digest.update(buffer, 0, read)
            }
        }
        val md5sum = digest.digest()
        val bigInt = BigInteger(1, md5sum)
        return bigInt.toString(16).padStart(32, '0')
    }

    private fun unzip(zipFile: File, targetDirectory: File) {
        ZipInputStream(FileInputStream(zipFile)).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                val newFile = File(targetDirectory, entry.name)
                if (entry.isDirectory) {
                    newFile.mkdirs()
                } else {
                    File(newFile.parent!!).mkdirs()
                    FileOutputStream(newFile).use { fos ->
                        zis.copyTo(fos)
                    }
                }
                entry = zis.nextEntry
            }
        }
    }
}
