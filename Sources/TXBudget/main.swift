#if os(macOS)
import SwiftUI
// 原生 Mac 入口：SwiftUI App（阶段 4 由 TXBudgetApp.swift 提供）。
TXBudgetApp.main()
#else
// 非 macOS（Linux CI 占位 / 本地构建）：SwiftUI 不可用，仅打印版本。
print("通信概预算 v\(TXBudget.version)（原生 Mac 版，开发中）")
#endif
