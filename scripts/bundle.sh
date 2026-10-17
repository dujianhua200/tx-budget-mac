#!/bin/bash
# 组装 .app + .dmg（无签名）。输入：.build/release/TXBudget；输出：build/tx-budget-mac-<version>-mac-arm64.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${GITHUB_REF:-}" == refs/tags/* ]]; then
  VERSION="${GITHUB_REF#refs/tags/}"
  VERSION="${VERSION#v}"
else
  VERSION="dev"
fi

APP_DIR="build/通信概预算.app"
DMG="build/tx-budget-mac-${VERSION}-mac-arm64.dmg"
rm -rf "$APP_DIR" "$DMG"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp .build/release/TXBudget "$APP_DIR/Contents/MacOS/TXBudget"
chmod +x "$APP_DIR/Contents/MacOS/TXBudget"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>zh_CN</string>
	<key>CFBundleExecutable</key>
	<string>TXBudget</string>
	<key>CFBundleIdentifier</key>
	<string>com.zhang.txbudget</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>通信概预算</string>
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

hdiutil create -volname "通信概预算" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG"
ls -la "$DMG"
