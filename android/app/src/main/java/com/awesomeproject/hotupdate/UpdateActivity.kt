package com.awesomeproject.hotupdate

import android.app.Activity
import android.os.Bundle
import android.widget.Toast
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import com.awesomeproject.R
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.Job // 显式导入 Job
import kotlinx.coroutines.cancel // 导入 cancel 扩展函数
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class UpdateActivity : AppCompatActivity() {

    companion object {
        private const val TAG = "UpdateActivity"
    }

    private val activityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_update)

        // 禁止返回
        this.setFinishOnTouchOutside(false)

        val updateInfoJson = intent.getStringExtra("updateInfo")
        if (updateInfoJson == null) {
            Toast.makeText(this, "更新信息错误", Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        val updateInfo = Gson().fromJson(updateInfoJson, UpdateCheckResponse::class.java)

        Log.d(TAG, "updateInfo: $updateInfo")

        activityScope.launch {

            Log.d(TAG, "before HotUpdateManager.downloadAndInstall")

            val success = HotUpdateManager.downloadAndInstall(this@UpdateActivity, updateInfo)

            Log.d(TAG, "downloadAndInstall success: $success")

            withContext(Dispatchers.Main) {
                if (success) {
                    setResult(Activity.RESULT_OK)
                    finish()
                } else {
                    Toast.makeText(this@UpdateActivity, "更新失败，请重启应用重试", Toast.LENGTH_LONG).show()
                    setResult(Activity.RESULT_CANCELED)
                    finish()
                }
            }
        }
    }

    // 屏蔽返回键
    override fun onBackPressed() {
        // do nothing
    }

//    override fun onDestroy() {
//        super.onDestroy()
//        (activityScope.coroutineContext[SupervisorJob] as SupervisorJob).cancel()
//    }

    override fun onDestroy() {
        super.onDestroy()
        activityScope.cancel() // 直接取消 Scope
    }
}
