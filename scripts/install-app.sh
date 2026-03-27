#!/bin/bash
# 将 VoiceFlow 打包为 macOS .app 并安装到 /Applications
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="VoiceFlow"
VERSION=$(grep 'static let version' "$PROJECT_DIR/Sources/VoiceFlowLib/Version.swift" | sed 's/.*"\(.*\)".*/\1/')
APP_PATH="/Applications/${APP_NAME}.app"
BUNDLE_ID="com.voiceflow.app"

echo "Building release..."
cd "$PROJECT_DIR"
swift build -c release --disable-sandbox 2>&1 | grep -E "error:|Build complete" || true

echo "Creating app bundle..."
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# 复制可执行文件
cp .build/release/VoiceFlow "$APP_PATH/Contents/MacOS/VoiceFlow"

# 复制图标
cp assets/VoiceFlow.icns "$APP_PATH/Contents/Resources/AppIcon.icns"
cp assets/icon.png "$APP_PATH/Contents/Resources/icon.png"

# 创建 Info.plist
cat > "$APP_PATH/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>VoiceFlow 需要麦克风权限来进行语音输入</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>VoiceFlow 需要控制备忘录来保存语音日记</string>
</dict>
</plist>
PLIST

echo "Updating LaunchAgent..."
cat > "$HOME/Library/LaunchAgents/com.voiceflow.app.plist" << LAUNCHD
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${BUNDLE_ID}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP_PATH}/Contents/MacOS/VoiceFlow</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/voiceflow.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/voiceflow.err</string>
</dict>
</plist>
LAUNCHD

# 签名：自定义 designated requirement 只匹配 identifier，不匹配 cdhash
# 这样更新二进制后 macOS TCC 权限不会失效
codesign -f -s - --identifier "${BUNDLE_ID}" \
    -r="designated => identifier \"${BUNDLE_ID}\"" \
    "$APP_PATH"

echo ""
echo "✓ 已安装到 ${APP_PATH}"
echo "✓ LaunchAgent 已更新"
echo ""
echo "请在 系统设置 → 隐私与安全性 → 辅助功能 中授权 VoiceFlow.app"
