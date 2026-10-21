#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "未找到 xcodegen，请先执行: brew install xcodegen"
  exit 1
fi

xcodegen generate

xcodebuild \
  -project WiFiDrop.xcodeproj \
  -scheme WiFiDrop \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ONLY_ACTIVE_ARCH=NO \
  build

rm -rf Payload WiFiDrop-unsigned.ipa
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/WiFiDrop.app Payload/
zip -qry WiFiDrop-unsigned.ipa Payload

echo "已生成: $(pwd)/WiFiDrop-unsigned.ipa"
