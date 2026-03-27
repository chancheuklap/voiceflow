#!/bin/bash
# 一键发版：构建 → 打包 → 算 SHA256 → 更新 Cask → 推 Git tag → 创建 GitHub Release
# 用法：./scripts/release.sh [版本号]
#   ./scripts/release.sh          — 使用 Version.swift 中的当前版本
#   ./scripts/release.sh 0.4.0    — 先将 Version.swift 更新为 0.4.0，再发版
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="VoiceFlow"
CASK_FILE="$PROJECT_DIR/Casks/voiceflow.rb"
VERSION_FILE="$PROJECT_DIR/Sources/VoiceFlowLib/Version.swift"
DIST_DIR="$PROJECT_DIR/.dist"

cd "$PROJECT_DIR"

# ── 步骤 1：确定版本号 ──
if [ -n "$1" ]; then
    NEW_VERSION="$1"
    echo "→ 更新版本号为 $NEW_VERSION"
    sed -i '' "s/static let version = \".*\"/static let version = \"$NEW_VERSION\"/" "$VERSION_FILE"
fi
VERSION=$(grep 'static let version' "$VERSION_FILE" | sed 's/.*"\(.*\)".*/\1/')
echo "→ 发版版本：v$VERSION"

# ── 步骤 2：构建 Release 包 ──
echo "→ 编译..."
swift build -c release --disable-sandbox 2>&1 | grep -E "error:|warning:|Build complete" | grep -v "warning:" || true

# ── 步骤 3：打包 .app ──
echo "→ 打包 .app..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$DIST_DIR/$APP_NAME.app/Contents/Resources"

cp ".build/release/$APP_NAME" "$DIST_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
cp "assets/$APP_NAME.icns"   "$DIST_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"
cp "assets/icon.png"         "$DIST_DIR/$APP_NAME.app/Contents/Resources/icon.png"

cat > "$DIST_DIR/$APP_NAME.app/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.voiceflow.app</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
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

# ── 步骤 3.5：签名（确保 TCC 按 bundle identifier 匹配权限）──
echo "→ 签名..."
codesign -f -s - --identifier com.voiceflow.app \
    -r='designated => identifier "com.voiceflow.app"' \
    "$DIST_DIR/$APP_NAME.app"

# ── 步骤 4：压缩 zip ──
echo "→ 压缩 zip..."
ZIP_NAME="$APP_NAME.app.zip"
cd "$DIST_DIR"
zip -r -q "$ZIP_NAME" "$APP_NAME.app"
cd "$PROJECT_DIR"

# ── 步骤 5：计算 SHA256，更新 Cask ──
echo "→ 计算 SHA256..."
SHA256=$(shasum -a 256 "$DIST_DIR/$ZIP_NAME" | awk '{print $1}')
echo "   SHA256: $SHA256"

sed -i '' "s/version \".*\"/version \"$VERSION\"/" "$CASK_FILE"
sed -i '' "s/sha256 \".*\"/sha256 \"$SHA256\"/" "$CASK_FILE"
echo "→ Cask 已更新"

# ── 步骤 6：Git commit + tag ──
echo "→ Git commit & tag..."
# 提交版本号、Cask 和其他已跟踪文件的变更（-u 排除未跟踪的构建产物）
git add -u
git add "$VERSION_FILE" "$CASK_FILE"
git commit -m "chore: 发版 v$VERSION"
git tag "v$VERSION"
git push origin main
git push origin "v$VERSION"

# ── 步骤 7：编写发布说明 ──
PREV_TAG=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo "")
NOTES_FILE=$(mktemp /tmp/vf_release_notes.XXXXXX.md)

# 自动生成本次提交列表作为草稿
{
    echo "## 更新内容"
    echo ""
    if [ -n "$PREV_TAG" ]; then
        git log --pretty=format:"- %s" "$PREV_TAG"..HEAD~1
    else
        git log --pretty=format:"- %s" HEAD~1
    fi
    echo ""
    echo ""
    echo "## 安装"
    echo ""
    echo '```bash'
    echo "brew upgrade --cask voiceflow"
    echo '```'
} > "$NOTES_FILE"

# 打开编辑器让用户修改
EDITOR="${EDITOR:-nano}"
echo "→ 请在编辑器中完善发布说明，保存后关闭即可继续..."
"$EDITOR" "$NOTES_FILE"

echo "→ 创建 GitHub Release..."
gh release create "v$VERSION" \
    "$DIST_DIR/$ZIP_NAME" \
    --title "v$VERSION" \
    --notes-file "$NOTES_FILE"

rm -f "$NOTES_FILE"

# ── 步骤 8：更新本地安装 ──
echo "→ 更新本地 /Applications/VoiceFlow.app..."
pkill -f "Contents/MacOS/VoiceFlow" 2>/dev/null || true
sleep 1
rsync -a --delete "$DIST_DIR/$APP_NAME.app/" "/Applications/$APP_NAME.app/"
open "/Applications/$APP_NAME.app"

echo ""
echo "✓ v$VERSION 发版完成！"
echo "  下载地址：https://github.com/chancheuklap/voiceflow/releases/tag/v$VERSION"
echo ""
echo "用户通过菜单栏「检查更新」或重启应用即可自动拿到新版本。"
