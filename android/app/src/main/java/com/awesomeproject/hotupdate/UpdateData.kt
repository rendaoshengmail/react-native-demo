package com.awesomeproject.hotupdate

// 用于 GSON 解析
data class UpdateCheckRequest(
    val platform: String,
    val native_version: String
)

data class UpdateCheckResponse(
    val rn_version: String,
    val rn_zip_url: String,
    val checksum: String
)
