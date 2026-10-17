#!/bin/bash
# 组装 .app + .dmg（无签名）。输入：.build/release/TXBudget；输出：build/滑洲智算-<version>-mac-arm64.dmg
# 图标：Assets/AppIcon.iconset（已提交进仓库）→ iconutil 生成 .icns；失败即停，不出无图标包。
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${GITHUB_REF:-}" == refs/tags/* ]]; then
  VERSION="${GITHUB_REF#refs/tags/}"
  VERSION="${VERSION#v}"
else
  VERSION="dev"
fi

APP_DIR="build/滑洲智算.app"
DMG="build/滑洲智算-${VERSION}-mac-arm64.dmg"
rm -rf "$APP_DIR" "$DMG"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp .build/release/TXBudget "$APP_DIR/Contents/MacOS/TXBudget"
chmod +x "$APP_DIR/Contents/MacOS/TXBudget"

# 图标：iconset 必须存在（仓库内），iconutil 只在 macOS 上有。
if [[ ! -d "Assets/AppIcon.iconset" ]]; then
  echo "错误：缺少 Assets/AppIcon.iconset（图标集未提交进仓库）" >&2
  exit 1
fi
iconutil -c icns "Assets/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
if [[ ! -s "$APP_DIR/Contents/Resources/AppIcon.icns" ]]; then
  echo "错误：iconutil 未生成有效的 AppIcon.icns" >&2
  exit 1
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
