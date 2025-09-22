#!/bin/bash

# scripts/bundle-rn.sh

set -e # Exit immediately if a command exits with a non-zero status.

PLATFORM=$1
RN_VERSION=$2
DEV_MODE=${3:-false}

if [ -z "$PLATFORM" ] || [ -z "$RN_VERSION" ]; then
  echo "Usage: ./scripts/bundle-rn.sh <ios|android> <rn_version> [dev_mode]"
  echo "Example: ./scripts/bundle-rn.sh android 3.1.0"
  exit 1
fi

OUTPUT_DIR="./dist"
BUNDLE_DIR="$OUTPUT_DIR/bundle-$PLATFORM-$RN_VERSION"
ZIP_NAME="rn_${PLATFORM:0:1}_${RN_VERSION}.zip" # rn_a_3.1.0.zip or rn_i_3.1.0.zip
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"

echo "Start bundling for $PLATFORM version $RN_VERSION..."

# 清理旧文件
rm -rf "$BUNDLE_DIR"
rm -f "$ZIP_PATH"
mkdir -p "$BUNDLE_DIR"

# 打包
if [ "$PLATFORM" == "android" ]; then
  npx react-native bundle \
    --platform android \
    --dev $DEV_MODE \
    --entry-file index.js \
    --bundle-output "$BUNDLE_DIR/index.android.bundle" \
    --assets-dest "$BUNDLE_DIR"
else # ios
  npx react-native bundle \
    --platform ios \
    --dev $DEV_MODE \
    --entry-file index.js \
    --bundle-output "$BUNDLE_DIR/main.jsbundle" \
    --assets-dest "$BUNDLE_DIR"
fi

echo "Bundling complete. Zipping bundle..."

# 压缩
(cd "$BUNDLE_DIR" && zip -r "../$ZIP_NAME" .)

echo "Zipping complete. Calculating MD5 checksum..."

# 计算 MD5
if [[ "$OSTYPE" == "darwin"* ]]; then
  CHECKSUM=$(md5 -q "$ZIP_PATH")
else
  CHECKSUM=$(md5sum "$ZIP_PATH" | awk '{ print $1 }')
fi

echo "Checksum: $CHECKSUM"
echo "$CHECKSUM" > "$OUTPUT_DIR/checksum_${PLATFORM}_${RN_VERSION}.txt"

echo "-----------------------------------"
echo "RN Bundle for $PLATFORM $RN_VERSION is ready!"
echo "  - ZIP File: $ZIP_PATH"
echo "  - Checksum: $CHECKSUM"
echo "-----------------------------------"