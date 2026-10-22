#if os(macOS)
import SwiftUI

/// App 入口（无 @main，由 main.swift 的顶层代码调用 TXBudgetApp.main()，
/// 避免 @main 与测试库构建的入口冲突）。
struct TXBudgetApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .defaultSize(width: 1280, height: 800)
    }
}
#endif
