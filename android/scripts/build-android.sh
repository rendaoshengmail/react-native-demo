#!/bin/bash

# 该脚本用于自动化React Native安卓APK的打包流程。
# 它会生成一个JS bundle，并将其打包进APK中。
# 注意：该脚本假定在 AwesomeProject/android 目录下执行。
# 使用方法: ../scripts/build-android.sh <版本号>
# 示例: ../scripts/build-android.sh 3.1.0

# 检查参数数量
if [ "$#" -ne 1 ]; then
  echo "错误：请提供React Native版本号。"
  echo "用法: ../scripts/build-android.sh <版本号>"
  echo "例如: ../scripts/build-android.sh 3.1.0"
  exit 1
fi

# 获取版本号 (使用第一个位置参数 $1)
RN_VERSION="$1"

PROJECT_NAME="AwesomeProject"

echo "---"
echo "开始构建项目：$PROJECT_NAME (在 android 目录中执行)"
echo "传入的RN版本号：$RN_VERSION"
echo "---"

# 脚本现在在 android 目录下执行。
# 所有对 'android/' 内部文件的引用路径都需要去除 'android/' 前缀。

# 1. 清理旧的 JS Bundle 和资源文件 (路径已调整)
echo "正在清理旧的 JS Bundle 和安卓资源..."
rm -rf app/src/main/assets/index.android.bundle
rm -rf app/src/main/res/drawable-*
rm -rf app/src/main/res/raw
mkdir -p app/src/main/assets/

# 2. 生成 React Native 的 JS Bundle (路径已调整，且 react-native 命令在 android 目录下需要调整相对路径)
# 我们需要从 android/ 目录回到项目根目录才能正确执行 react-native bundle
echo "正在为安卓平台生成 JS Bundle..."
# 切换到项目根目录
cd .. || { echo "无法切换到项目根目录。"; exit 1; }

react-native bundle \
  --platform android \
  --dev false \
  --entry-file index.js \
  --bundle-output android/app/src/main/assets/index.android.bundle \
  --assets-dest android/app/src/main/res/

# 3. 切换回安卓项目目录并执行 Gradle 打包
echo "正在使用 Gradle 打包 APK..."
# 切换回 android 目录
cd android || { echo "无法切换回安卓目录。"; exit 1; }
# 在 android 目录下执行 gradlew
./gradlew assembleRelease -PdefaultRnVersion="$RN_VERSION"

# 4. 查找并显示生成的 APK 路径 (路径已调整)
# 脚本在 android 目录下执行，所以 APK_PATH 已经是相对于 android 目录的相对路径
APK_PATH=$(find app/build/outputs/apk/release -name "app-release.apk")
if [ -f "$APK_PATH" ]; then
  echo "---"
  echo "构建完成！"
  # 显示相对于当前执行目录 (android) 的路径
  echo "APK 文件路径: $APK_PATH"
  echo "---"
else
  echo "警告: 未找到APK文件，构建可能失败。请检查日志。"
fi

