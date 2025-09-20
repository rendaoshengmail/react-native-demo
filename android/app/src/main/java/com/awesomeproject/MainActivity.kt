package com.awesomeproject

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.view.View
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate
import com.awesomeproject.hotupdate.HotUpdateConfig
import com.awesomeproject.hotupdate.HotUpdateManager
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ReactActivity() {

    private val activityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val UPDATE_REQUEST_CODE = 1001

    companion object {
        // 用于防止重复检查，使用伴生对象使其成为静态变量
        private var isCheckingUpdate = false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen() // For react-native-splash-screen or similar
        super.onCreate(null)

        // 仅在热更新启用时检查
        if (HotUpdateConfig.IS_HOT_UPDATE_ENABLED && !isCheckingUpdate) {
            isCheckingUpdate = true
            // 在setContentView之前检查更新，以显示启动屏
            checkUpdate()
        }
    }

    private fun checkUpdate() {
        activityScope.launch {
            val updateInfo = HotUpdateManager.checkUpdate(this@MainActivity)
            withContext(Dispatchers.Main) {
                if (updateInfo != null) {
                    // 发现新版本，跳转到更新页
                    val intent = Intent(this@MainActivity, com.awesomeproject.hotupdate.UpdateActivity::class.java)
                    intent.putExtra("updateInfo", Gson().toJson(updateInfo))
                    startActivityForResult(intent, UPDATE_REQUEST_CODE)
                } else {
                    // 没有新版本或检查失败，直接加载RN页面
                    // delegate.loadApp() 会在 super.onCreate() 之后被框架自动调用
                    // 所以这里什么都不用做
                }
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == UPDATE_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                // 更新成功，重启Activity以加载新的JSBundle
                recreate()
            } else {
                // 更新失败，用户可以选择退出或重试
                // 为简化，这里直接关闭应用
                finish()
            }
        }
    }

    /**
     * Returns the name of the main component registered from JavaScript. This is used to schedule
     * rendering of the component.
     */
    override fun getMainComponentName(): String = "AwesomeProject"

    /**
     * Returns the instance of the [ReactActivityDelegate]. We use [DefaultReactActivityDelegate]
     * which allows you to enable New Architecture with a single boolean flags [fabricEnabled]
     */
    override fun createReactActivityDelegate(): ReactActivityDelegate =
        DefaultReactActivityDelegate(this, mainComponentName, fabricEnabled)
}
