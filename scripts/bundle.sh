#!/bin/bash
# 组装 .app + .dmg（临时签名 ad-hoc，无需证书）。输入：.build/release/TXBudget；输出：build/huazhou-zhisuan-<version>-mac-arm64.dmg
# 命名约定（见 docs/native-design.md §8）：DMG 文件名（Release 资产名）用拼音 ASCII，
# 因为 GitHub 会剥掉 Release 资产名里的非 ASCII 字符；.app / 卷名 / CFBundleName 保持中文。
# 图标：Assets/AppIcon.iconset（已提交进仓库）→ iconutil 生成 .icns；失败即停，不出无图标包。
set -euo pipefail
cd "$(dirname "$0")/.."

# VERSION 优先用外部传入（workflow_dispatch 补传 Release 时用）；否则从 tag 取；再否则 dev。
if [[ -z "${VERSION:-}" ]]; then
  if [[ "${GITHUB_REF:-}" == refs/tags/* ]]; then
    VERSION="${GITHUB_REF#refs/tags/}"
    VERSION="${VERSION#v}"
  else
    VERSION="dev"
  fi
fi

APP_DIR="build/滑洲智算.app"
DMG="build/huazhou-zhisuan-${VERSION}-mac-arm64.dmg"
rm -rf "$APP_DIR" "$DMG"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp .build/release/TXBudget "$APP_DIR/Contents/MacOS/TXBudget"
chmod +x "$APP_DIR/Contents/MacOS/TXBudget"

# SwiftPM 资源包（内置完整库 full-library.json，v2.1.0）：运行时由
# Logic/FullLibrary.swift 以显式路径查找（资源包内 / Resources 根松散副本 /
# 限深递归兜底）；v2.5.1 起禁止再依赖 Bundle.module 访问器（打包布局下找不到
# 资源包会 assertionFailure 闪退，见 docs/v2.5.1-crash-fix.md）。
# 缺失即停，不出没有完整库的包（与图标同等对待）。
RES_BUNDLE=""
for cand in ".build/release/TXBudget_TXBudget.bundle" ".build/release/TXBudget_TXBudget.resources"; do
  if [[ -d "$cand" ]]; then RES_BUNDLE="$cand"; break; fi
done
if [[ -z "$RES_BUNDLE" ]]; then
  echo "错误：缺少 SwiftPM 资源包（TXBudget_TXBudget.bundle，内置完整库未构建）" >&2
  exit 1
fi
cp -R "$RES_BUNDLE" "$APP_DIR/Contents/Resources/"
if [[ ! -f "$APP_DIR/Contents/Resources/$(basename "$RES_BUNDLE")/full-library.json" ]]; then
  echo "错误：资源包内缺少 full-library.json" >&2
  exit 1
fi

# 双保险（v2.5.1）：full-library.json 再松散拷一份到 Contents/Resources 根下，
# 使运行时第二候选路径直接命中，不依赖资源包目录名/布局。
cp "$APP_DIR/Contents/Resources/$(basename "$RES_BUNDLE")/full-library.json" \
   "$APP_DIR/Contents/Resources/full-library.json"

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

# 打包末尾断言（v2.5.1 防回归）：full-library.json 两处副本必须都在，缺一即停。
# CI 另有一步挂载 DMG 复验同一断言（见 .github/workflows/build.yml）。
for f in "$APP_DIR/Contents/Resources/full-library.json" \
         "$APP_DIR/Contents/Resources/TXBudget_TXBudget.bundle/full-library.json"; do
  if [[ ! -f "$f" ]]; then
    echo "错误：打包断言失败，缺少 $f" >&2
    exit 1
  fi
  echo "打包断言通过：$f"
done

# 临时签名（ad-hoc）：无需任何证书，CI 的 macOS runner 可直接跑。
# 作用：把“已损坏，无法打开”（完全无签名时 Gatekeeper 的拦截，无法绕过）变成
# “无法验证开发者”（右键 → 打开可绕过）。这是无证书下的最优解。
# 局限：仍会弹“无法验证开发者”；彻底无提示需付费苹果开发者账号 + Developer ID 签名 + 公证（待用户另行决定）。
# 注意：签名必须是组装 .app 的最后一步（所有文件落盘之后），之后只做 hdiutil 打包。
codesign --force --deep --sign - "$APP_DIR"

hdiutil create -volname "滑洲智算" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG"
ls -la "$DMG"
