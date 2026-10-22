# 滑洲智算 · Mac 原生应用

Swift + SwiftUI 重写，Mac 专用。Electron 版（`dujianhua200/tx-budget`，v3.0.0）保持原样、只出 Windows 版；本仓库不碰 Electron 仓库的任何 tag/Release。

- 架构设计：`docs/native-design.md`（数据/引擎/导出，先读它再动手）；v2 界面架构：`docs/v2-ui-design.md`
- 部署目标：macOS 13+，Apple Silicon；临时签名（ad-hoc），DMG 分发，首次打开右键 → 打开
- 数据格式与 Electron v2/v3 互通：同一 JSON 格式、同一数据路径（`~/Library/Application Support/通信概预算/budget-data.json`），旧数据直接打开，不迁移

## 开发

```bash
swift test          # 测试
swift build -c release
./scripts/bundle.sh # 组装 .app + .dmg（需 macOS）
```

## 发布

CI（`.github/workflows/build.yml`）每次推送（main）+ tag（`v*`）都跑（编译 + 测试），CI 绿了才发布；另支持手动触发。

**本环境 Linux 无 Xcode**：Swift 编译/测试只能走 CI（macOS runner）+ 用户真机验收。
