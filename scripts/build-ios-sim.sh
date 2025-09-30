#!/bin/bash

# ===================================================================
# 1. 脚本配置变量
# ===================================================================

# 1.1 项目配置
WORKSPACE_NAME="AwesomeProject"
SCHEME_NAME="AwesomeProject"
# 模拟器打包通常使用 Debug 配置
BUILD_CONFIGURATION="Debug" 

# 1.2 输出路径 (相对于 AwesomeProject/ 目录)
OUTPUT_DIR="../build/simulator" 
APP_NAME="${SCHEME_NAME}.app"

# 1.3 命令行参数解析
if [ -z "$1" ]; then
    echo "错误: 必须提供 React Native 版本号作为第一个参数!"
    echo "用法: ./scripts/build-ios-sim.sh <RN版本号>"
    exit 1
fi

RN_VERSION="$1"

# ===================================================================
# 2. 准备工作
# ===================================================================

echo "==================================================="
echo "  AwesomeProject iOS 模拟器打包开始 (RN: $RN_VERSION)"
echo "==================================================="

# 创建输出目录
mkdir -p "$OUTPUT_DIR"
# 创建一个临时目录用于存放 DerivedData
TEMP_BUILD_DIR=$(mktemp -d)

# ===================================================================
# 3. 构建 `.app` 文件 (使用 build 命令和模拟器 SDK)
# ===================================================================

echo "开始构建 .app 文件..."

# 构造 xcodebuild build 命令
BUILD_COMMAND="xcodebuild build \
    -workspace ios/${WORKSPACE_NAME}.xcworkspace \
    -scheme ${SCHEME_NAME} \
    -configuration ${BUILD_CONFIGURATION} \
    -sdk iphonesimulator \
    -derivedDataPath ${TEMP_BUILD_DIR} \
    RN_VERSION_FROM_BUILD=\"${RN_VERSION}\" \
    ONLY_ACTIVE_ARCH=NO" 

echo "-> $BUILD_COMMAND"
eval $BUILD_COMMAND

# 检查上一步是否成功
if [ $? -ne 0 ]; then
    echo "==================================================="
    echo "  ❌ 模拟器构建失败!"
    echo "==================================================="
    rm -rf "$TEMP_BUILD_DIR" 
    exit 1
fi

# ===================================================================
# 4. 复制并压缩 `.app` 文件
# ===================================================================

echo "---------------------------------------------------"
echo "复制并压缩 .app 文件..."

# 找到 DerivedData 中的 .app 路径
APP_SOURCE_PATH="${TEMP_BUILD_DIR}/Build/Products/${BUILD_CONFIGURATION}-iphonesimulator/${APP_NAME}"
FINAL_APP_PATH="${OUTPUT_DIR}/${APP_NAME}"
FINAL_ZIP_PATH="${OUTPUT_DIR}/${SCHEME_NAME}_${RN_VERSION}_Simulator.zip"

# 复制 .app 文件到输出目录
cp -R "${APP_SOURCE_PATH}" "${FINAL_APP_PATH}"

# 压缩为 zip 包
cd "$OUTPUT_DIR"
zip -r "$(basename "$FINAL_ZIP_PATH")" "$(basename "$FINAL_APP_PATH")"
cd - > /dev/null 

# 清理临时文件
rm -rf "$TEMP_BUILD_DIR"
rm -rf "$FINAL_APP_PATH" 

# ===================================================================
# 5. 完成
# ===================================================================

echo "==================================================="
echo "  ✅ iOS 模拟器打包成功!"
echo "  ZIP 路径 (可分发): ${OUTPUT_DIR}/$(basename "$FINAL_ZIP_PATH")"
echo "==================================================="