import Foundation

/// 品牌常量（v1.0.2 改名：软件名 → 滑洲智算；单一事实源）。
/// 窗口标题 / 启动打印 / xlsx creator 默认值都引用 appDisplayName，不许散落硬编码旧名。
/// 不变的东西（用户 2026-10-17 定，零迁移）：Bundle ID 保持 com.zhang.txbudget；
/// 数据目录名保持“通信概预算”（DatabaseStore.appSupportDirName，见设计文档 §10.7）。
public let appDisplayName = "滑洲智算"
public let appBundleIdentifier = "com.zhang.txbudget"
