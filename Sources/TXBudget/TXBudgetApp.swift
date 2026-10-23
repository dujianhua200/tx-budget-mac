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
        .commands {
            // 「方案」菜单（v2.5.0 §12.5）：当前资料库方案打勾切换 + 方案文件与
            // 资料库维护入口，全部复用页面既有实现，不另写一套。
            CommandMenu("方案") {
                let currentId = appState.editingProfile?.id
                ForEach(appState.db.configurationProfiles, id: \.id) { profile in
                    Button {
                        appState.setEditingProfile(profile.id)
                    } label: {
                        if profile.id == currentId {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
                Divider()
                Button("编辑方案…") { appState.nav = .profiles }
                Button("新建方案…") { appState.nav = .profiles }
                Button("复制当前方案") { appState.duplicateEditingProfile() }
                Divider()
                Button("导入方案文件…") { appState.importProfileViaPanel() }
                Button("导出当前方案…") { appState.exportEditingProfileViaPanel() }
                Divider()
                Button("补全并校正定额库…") { appState.libraryMaintenanceRequest = .completion }
                Button("按官方清理…") { appState.libraryMaintenanceRequest = .cleanup }
            }
            // 「模板」菜单（v2.5.0 §12.5）：现有模板概念 = settings.defaultInfo
            // （新建工程的默认工程信息），入口跳设置页的「工程信息模板」卡片区。
            CommandMenu("模板") {
                Button("工程信息模板…") {
                    appState.nav = .settings
                    appState.settingsFocusToken += 1
                }
            }
        }
    }
}
#endif
