#!/bin/bash
# 组装 .app + .dmg (分支构建版，仅生成 DMG 供下载，不发 Release)
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${VERSION:-}" ]]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'branch')"
  SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'dev')"
  VERSION="${BRANCH//\//-}-${SHA}"
fi

APP_DIR="build/滑洲智算.app"
DMG="build/滑洲智算-${VERSION}-mac-arm64.dmg"
rm -rf "$APP_DIR" "$DMG"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp .build/release/TXBudget "$APP_DIR/Contents/MacOS/TXBudget"
chmod +x "$APP_DIR/Contents/MacOS/TXBudget"

if [[ -d "Assets/AppIcon.iconset" ]]; then
  iconutil -c icns "Assets/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns" || true
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>TXBudget</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.zhang.txbudget</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>滑洲智算</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

hdiutil create -volname "滑洲智算" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG"
ls -la "$DMG"
