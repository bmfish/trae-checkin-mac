#!/bin/bash
# 构建 macOS 菜单栏 App：SwiftPM release → 组装 .app → ad-hoc 签名
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Trae 签到"
APP="build/${APP_NAME}.app"
BINARY="TraeCheckinMac"

echo "==> swift build -c release"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${BINARY}"
if [ ! -f "$BIN_PATH" ]; then
    echo "构建产物不存在: $BIN_PATH" >&2
    exit 1
fi

echo "==> 组装 ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/${BINARY}"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> ad-hoc 签名"
codesign --force --deep --sign - "$APP"

echo "完成: ${APP}"
echo "安装: cp -R \"${APP}\" /Applications/ && open \"/Applications/${APP_NAME}.app\""
