package com.awesomeproject.hotupdate

import com.awesomeproject.BuildConfig

object HotUpdateConfig {
    /**
     * 热更新调试开关。
     * - true: 在Debug模式下，也强制执行热更新逻辑，用于测试。
     * - false: 在Debug模式下，从Metro服务器加载JSBundle，不执行热更新。
     */
    const val DEBUG_HOT_UPDATE = true // 在这里切换调试模式

    /**
     * 是否启用热更新逻辑
     * 生产环境始终开启，Debug环境根据 DEBUG_HOT_UPDATE 变量决定
     */
    val IS_HOT_UPDATE_ENABLED = !BuildConfig.DEBUG || DEBUG_HOT_UPDATE

    // App原生版本号，从 aaptOptions 读取
    const val NATIVE_APP_VERSION: String = BuildConfig.VERSION_NAME

    // App内置的默认RN版本号，需要与assets里的bundle包版本一致
    const val DEFAULT_RN_VERSION = "0.0.1" // 假设初始版本是3.0.0

    // 版本检查接口
    const val VERSION_API_URL = "http://localhost:3000/api/hotupdate"

    // RN包在本地存储的根目录
    const val RN_HOTUPDATE_DIR = "rn_hotupdate"

    // 指向当前RN版本的配置文件名
    const val RN_CONFIG_FILE = "config.json"

    // 默认的RN bundle文件名
    const val JS_BUNDLE_FILE_NAME = "index.android.bundle"
}
