#if os(macOS)
import SwiftUI
import AppKit

/// 主界面：左侧边栏（可收起）+ 顶栏工具 + 底栏提示，一次只显示一个功能。
/// 导航状态 section/tab 单一事实源（AppState.nav）。
struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("新建工程") { appState.createProject(name: nextProjectName()) }
                Button("打开工程") { appState.nav = .projects }
                Button("保存工程") { appState.flushSaves() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("工程管理") { appState.nav = .projects }
                Button("导出") {
                    if appState.hasProject { appState.nav = .current(.export) }
                    else { appState.nav = .projects }
                }
                Text(appState.saveState.text)
                    .foregroundColor(appState.saveState.status == .dirty ? .red : .secondary)
                Button("退出") {
                    // 先同步落盘再退出（willTerminate 观察者也会 flush，双重保险）。
                    appState.flushSaves()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            StatusBarView()
        }
        .alert("数据加载失败", isPresented: Binding(
            get: { appState.loadError != nil },
            set: { if !$0 { appState.loadError = nil } }
        )) {
            Button("重试") { appState.reloadFromDisk() }
            Button("继续使用空白库", role: .cancel) { appState.loadError = nil }
        } message: {
            Text(appState.loadError ?? "")
        }
        .overlay(alignment: .bottom) {
            if let toast = appState.toast {
                Text(toast)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color.black.opacity(0.75))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .padding(.bottom, 40)
                    .onTapGesture { appState.toast = nil }
            }
        }
        .frame(minWidth: 1000, minHeight: 620)
    }

    private func nextProjectName() -> String {
        let names = Set(appState.db.projects.map { $0.name })
        var name = "新工程"
        var i = 2
        while names.contains(name) { name = "新工程 (\(i))"; i += 1 }
        return name
    }
}

/// 左侧边栏：一次只显示一个功能；当前工程分组未选中工程时禁用。
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section {
                SidebarRow(label: "工程", isActive: appState.nav == .projects) {
                    appState.nav = .projects
                }
            }
            Section(header: Text("当前工程 \(appState.hasProject ? "" : "（先选工程）")")) {
                ForEach(CurrentTab.allCases, id: \.self) { tab in
                    SidebarRow(label: tab.label,
                               isActive: appState.nav == .current(tab),
                               disabled: !appState.hasProject) {
                        appState.nav = .current(tab)
                    }
                }
            }
            Section {
                SidebarRow(label: "批量生成", isActive: appState.nav == .batch) {
                    appState.nav = .batch
                }
            }
            Section(header: Text("基础库")) {
                Text("库").font(.caption).foregroundColor(.secondary)
                ForEach([LibraryViewKey.quotas, .shortlist, .materials, .machinePrices, .instrumentPrices], id: \.self) { key in
                    SidebarRow(label: key.label,
                               isActive: appState.nav == .libraries(key)) {
                        appState.nav = .libraries(key)
                    }
                }
                Text("映射关系").font(.caption).foregroundColor(.secondary)
                ForEach([LibraryViewKey.rulesVariant, .rulesAlt, .quotaMachines, .quotaInstruments], id: \.self) { key in
                    SidebarRow(label: key.label,
                               isActive: appState.nav == .libraries(key)) {
                        appState.nav = .libraries(key)
                    }
                }
                Text("正在编辑方案：\(appState.editingProfile?.name ?? "—")")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section(header: Text("取费规则")) {
                ForEach(FeeRuleTab.allCases, id: \.self) { tab in
                    SidebarRow(label: tab.label,
                               isActive: appState.nav == .feeRules(tab)) {
                        appState.nav = .feeRules(tab)
                    }
                }
                Text("正在编辑方案：\(appState.editingProfile?.name ?? "—")")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section {
                SidebarRow(label: "配置方案", isActive: appState.nav == .profiles) {
                    appState.nav = .profiles
                }
                SidebarRow(label: "设置", isActive: appState.nav == .settings) {
                    appState.nav = .settings
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("通信概预算")
    }
}

struct SidebarRow: View {
    var label: String
    var isActive: Bool = false
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .foregroundColor(isActive ? .accentColor : .primary)
        .fontWeight(isActive ? .semibold : .regular)
    }
}

/// 主区：按导航切换视图；当前工程分组未选中工程时提示先选工程。
struct DetailView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.nav {
            case .projects:
                ProjectsView()
            case .current(let tab):
                if let project = appState.openProject {
                    CurrentProjectView(project: project, tab: tab)
                } else {
                    Text("请先在“工程”列表中打开一个工程。")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .batch:
                BatchView()
            case .libraries(let key):
                LibrariesView(viewKey: key)
            case .feeRules(let tab):
                FeeRulesView(tab: tab)
            case .profiles:
                ProfilesView()
            case .settings:
                SettingsView()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 当前工程各标签。
struct CurrentProjectView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord
    var tab: CurrentTab

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Text(project.name).font(.title2).fontWeight(.bold)
                Text("配置方案：\(appState.projectProfile?.name ?? "—")")
                    .foregroundColor(.secondary)
                if let result = appState.calcResult(for: project) {
                    Text("总计（含税）\(money(result.table1.grandIncl)) 元")
                        .foregroundColor(.secondary)
                    Text("工日 \(num2(result.techDays)) / \(num2(result.laborDays))")
                        .foregroundColor(.secondary)
                }
            }
            Divider()
            switch tab {
            case .info:
                ProjectInfoView(project: project)
            case .workload3a:
                Workload3AView(project: project)
            case .workload4a:
                WorkloadMaterialsView(project: project)
            case .workloadEquip:
                WorkloadEquipView(project: project)
            case .workload3b:
                WorkloadMachinesView(project: project)
            case .workload3c:
                WorkloadInstrumentsView(project: project)
            case .fee:
                FeeView(project: project)
            case .table5:
                Table5View(project: project)
            case .export:
                ExportView(project: project)
            }
        }
    }
}

/// 底栏：操作提示 + 当前工程/方案。
struct StatusBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack {
            Text(statusHintFor(appState.nav))
            Spacer()
            if let name = appState.openProject?.name {
                Text("当前工程：\(name)")
            }
            if let profile = appState.projectProfile?.name {
                Text("方案：\(profile)")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
#endif
