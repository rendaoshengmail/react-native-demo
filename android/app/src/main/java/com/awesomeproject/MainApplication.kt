package com.awesomeproject

import android.app.Application
import com.facebook.react.PackageList
import com.facebook.react.ReactApplication
import com.facebook.react.ReactHost
import com.facebook.react.ReactNativeApplicationEntryPoint.loadReactNative
import com.facebook.react.ReactNativeHost
import com.facebook.react.ReactPackage
import com.facebook.react.defaults.DefaultReactHost.getDefaultReactHost
import com.facebook.react.defaults.DefaultReactNativeHost
import com.awesomeproject.hotupdate.HotUpdateConfig
import com.awesomeproject.hotupdate.HotUpdateManager
import java.io.File

class MainApplication : Application(), ReactApplication {

  override val reactNativeHost: ReactNativeHost =
      object : DefaultReactNativeHost(this) {
        override fun getPackages(): List<ReactPackage> =
            PackageList(this).packages.apply {
              // Packages that cannot be autolinked yet can be added manually here, for example:
              // add(MyReactNativePackage())
            }

        override fun getJSMainModuleName(): String = "index"

        // 在这里修改，当热更新启用时，关闭开发者支持
        override fun getUseDeveloperSupport(): Boolean =
            BuildConfig.DEBUG && !HotUpdateConfig.IS_HOT_UPDATE_ENABLED


        override fun getJSBundleFile(): String? {
            // 如果关闭了热更新（例如：普通调试模式），则从Metro加载
            if (!HotUpdateConfig.IS_HOT_UPDATE_ENABLED) {
                return super.getJSBundleFile()
            }

            // 热更新逻辑开启（生产环境 或 调试热更新模式）
            val bundleInfo = HotUpdateManager.getCurrentRNBundleInfo(applicationContext)

            val bundleFile = File(bundleInfo.bundlePath)
            if (bundleFile.exists()) {
                // 如果本地文件存在（已热更），则加载
                return bundleInfo.bundlePath
            } else {
                // 检查是否是assets路径
                if (bundleInfo.bundlePath.startsWith("assets://")) {
                    // 首次安装或热更失败，加载assets中的默认包
                    return bundleInfo.bundlePath
                } else {
                    // 热更新文件丢失，但配置存在，这是一个异常情况
                    // 理论上应该 fallback 到 assets 包，这里为了健壮性再次检查
                    // 注意：这里需要确保你的assets里始终有一个基础包
                    val defaultBundlePath = "assets://${HotUpdateConfig.JS_BUNDLE_FILE_NAME}"

                    // 调试热更新模式下，如果本地没有bundle，也没有assets bundle
                    // 允许从metro加载，避免调试时必须先打包
                    if (BuildConfig.DEBUG) {
                        // 可以在这里检查assets里到底有没有包，没有的话就返回super，让它走metro
                        // 这里简化处理，直接返回默认assets路径，RN加载不到会报错，但更符合生产逻辑
                    }

                    return defaultBundlePath
                }
            }
        }

        override val isNewArchEnabled: Boolean = BuildConfig.IS_NEW_ARCHITECTURE_ENABLED
        override val isHermesEnabled: Boolean = BuildConfig.IS_HERMES_ENABLED
      }

  override val reactHost: ReactHost
    get() = getDefaultReactHost(applicationContext, reactNativeHost)

  override fun onCreate() {
    super.onCreate()
    loadReactNative(this)
  }
}
