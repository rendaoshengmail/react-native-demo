#!/bin/bash

# 该脚本用于自动化React Native安卓APK的打包流程。
# 它会生成一个JS bundle，并将其打包进APK中。
# 使用方法: ./scripts/build-android.sh --rnv <版本号>
# 示例: ./scripts/build-android.sh --rnv 1.0.5

# 默认版本号为空
RN_VERSION=""

# 使用 while 循环手动解析命令行参数，支持长选项
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --rnv)
      # 检查是否提供了版本号值
      if [ -n "$2" ] && [[ ! "$2" =~ ^- ]]; then
        RN_VERSION="$2"
        shift # 移动到下一个参数
      else
        echo "错误：--rnv 参数需要一个值。" >&2
        exit 1
      fi
      ;;
    *)
      echo "错误：无效的参数: $1" >&2
      exit 1
      ;;
  esac
  shift # 移动到下一个参数或值
done

# 检查是否传入了版本号
if [ -z "$RN_VERSION" ]; then
  echo "错误：请提供React Native版本号，格式为 --rnv <版本号>。"
  echo "用法: ./scripts/build-android.sh --rnv <版本号>"
  echo "例如: ./scripts/build-android.sh --rnv 1.0.5"
  exit 1
fi

PROJECT_NAME="AwesomeProject"

echo "---"
echo "开始构建项目：$PROJECT_NAME"
echo "传入的RN版本号：$RN_VERSION"
echo "---"

# 在项目根目录执行，所以不需要再 `cd "$PROJECT_NAME"`

# 清理旧的 JS Bundle 和资源文件
echo "正在清理旧的 JS Bundle 和安卓资源..."
rm -rf android/app/src/main/assets/index.android.bundle
rm -rf android/app/src/main/res/drawable-*
rm -rf android/app/src/main/res/raw
mkdir -p android/app/src/main/assets/

# 生成 React Native 的 JS Bundle
echo "正在为安卓平台生成 JS Bundle..."
# --platform android: 指定为安卓平台
# --dev false: 禁用开发者模式，用于正式发布
# --entry-file index.js: 入口文件，如果你的入口文件是index.tsx，请修改此行
# --bundle-output: 输出JS Bundle的路径
# --assets-dest: 输出图片等资源的路径
react-native bundle \
  --platform android \
  --dev false \
  --entry-file index.js \
  --bundle-output android/app/src/main/assets/index.android.bundle \
  --assets-dest android/app/src/main/res/

# 切换到安卓项目目录并执行 Gradle 打包
echo "正在使用 Gradle 打包 APK..."
cd android || { echo "安卓目录不存在。请检查路径。"; exit 1; }
./gradlew assembleRelease -PdefaultRnVersion="$RN_VERSION"

# 查找并显示生成的 APK 路径
APK_PATH=$(find app/build/outputs/apk/release -name "app-release.apk")
if [ -f "$APK_PATH" ]; then
  echo "---"
  echo "构建完成！"
  # 脚本在android目录下执行到这里，所以路径需要加上`android/`来显示完整路径
  echo "APK 文件路径: android/$APK_PATH"
  echo "---"
else
  echo "警告: 未找到APK文件，构建可能失败。请检查日志。"
fi
