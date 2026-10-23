#if os(macOS)
import SwiftUI
import AppKit

/// 主界面（v2.0.0，docs/v2-ui-design.md §2）：
/// nav == .projectList → 启动页（工程列表）；其余 → 工程工作区
/// （NavigationSplitView 侧边栏 + 内容区 + 底部状态栏）。
struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.nav == .projectList {
                ProjectListView()
            } else {
                WorkspaceView()
            }
        }
        .background { LibraryMaintenanceControls() }
        .tint(Theme.accent)
        .frame(minWidth: 1080, minHeight: 680)
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
                    .padding(.bottom, 46)
                    .onTapGesture { appState.toast = nil }
            }
        }
    }
}

/// 工程工作区：侧边栏分组导航 + 统一工具栏 + 底部状态栏。
struct WorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showQuotaSearch = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            DetailView()
                .navigationTitle(detailTitle)
                .navigationSubtitle(detailSubtitle)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    appState.nav = .projectList
                } label: {
                    Label("工程列表", systemImage: "chevron.left")
                }
                .help("返回工程列表")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showQuotaSearch = true
                } label: {
                    Label("定额搜索", systemImage: "magnifyingglass")
                }
                .help("全局搜索定额（当前工程方案），选中即加入工程量")
                Button {
                    appState.nav = .batch
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .help("从 Excel 批量导入工程量（批量生成页）")
                Button {
                    appState.nav = .export
                } label: {
                    Label("导出", systemImage: "square.and.arrow.up")
                }
                .disabled(!appState.hasProject)
                .help("导出预算书（报表导出页）")
                Button {
                    appState.flushSaves()
                } label: {
                    Label("保存", systemImage: "checkmark.circle")
                }
                .keyboardShortcut("s", modifiers: .command)
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
        .sheet(isPresented: $showQuotaSearch) {
            QuotaPickerSheet()
        }
    }

    private var detailTitle: String {
        if appState.nav.requiresProject, let name = appState.openProject?.name {
            return name
        }
        return appState.nav.label
    }

    private var detailSubtitle: String {
        if appState.nav.requiresProject {
            return appState.nav.label
        }
        return ""
    }
}

/// 左侧边栏：分组导航（工程 / 资料库 / 系统），SF Symbols 图标，系统材质。
struct SidebarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            if let project = appState.openProject {
                Section {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text("方案：\(appState.projectProfile?.name ?? "—")")
                            .font(.caption).foregroundColor(.secondary)
                        if let result = appState.calcResult(for: project) {
                            Text("总造价 \(money(result.table1.grandIncl)) 元")
                                .font(.caption).foregroundColor(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            Section(header: Text("工程")) {
                ForEach([NavDestination.overview, .projectInfo, .workload, .fees, .export],
                        id: \.self) { dest in
                    SidebarRow(dest: dest, disabled: !appState.hasProject)
                }
            }
            Section(header: Text("资料库")) {
                Text("库").font(.caption).foregroundColor(.secondary)
                ForEach([LibraryViewKey.quotas, .shortlist, .materials, .machinePrices,
                         .instrumentPrices], id: \.self) { key in
                    SidebarRow(dest: .libraries(key))
                }
                Text("映射关系").font(.caption).foregroundColor(.secondary)
                ForEach([LibraryViewKey.rulesVariant, .rulesAlt, .quotaMachines,
                         .quotaInstruments], id: \.self) { key in
                    SidebarRow(dest: .libraries(key))
                }
                Text("取费规则").font(.caption).foregroundColor(.secondary)
                ForEach(FeeRuleTab.allCases, id: \.self) { tab in
                    SidebarRow(dest: .feeRules(tab))
                }
                SidebarRow(dest: .profiles)
            }
            Section(header: Text("系统")) {
                SidebarRow(dest: .validation,
                           disabled: !appState.hasProject,
                           badge: appState.hasProject && appState.openProjectIssueCount > 0
                               ? appState.openProjectIssueCount : nil)
                SidebarRow(dest: .batch)
                SidebarRow(dest: .settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(appDisplayName)
        .safeAreaInset(edge: .bottom) {
            Text("资料库方案：\(appState.editingProfile?.name ?? "—")")
                .font(.caption).foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 6)
        }
    }
}

struct SidebarRow: View {
    @EnvironmentObject private var appState: AppState
    var dest: NavDestination
    var disabled: Bool = false
    var badge: Int? = nil

    var body: some View {
        Button {
            appState.nav = dest
        } label: {
            HStack {
                Label(dest.label, systemImage: dest.systemImage)
                Spacer()
                if let badge {
                    Text("\(badge)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.orange)
                        .cornerRadius(7)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .foregroundColor(appState.nav == dest ? Theme.accent : .primary)
        .fontWeight(appState.nav == dest ? .semibold : .regular)
    }
}

/// 内容区：按导航切换页面；需工程的页面未打开工程时给空状态引导。
struct DetailView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.nav.requiresProject, appState.openProject == nil {
                EmptyStateView(
                    systemImage: "folder.badge.questionmark",
                    title: "尚未打开工程",
                    message: "先到工程列表打开一个工程，再使用\(appState.nav.label)。",
                    actionTitle: "去工程列表",
                    action: { appState.nav = .projectList }
                )
            } else {
                switch appState.nav {
                case .projectList:
                    ProjectListView()
                case .overview:
                    if let p = appState.openProject { OverviewView(project: p) }
                case .projectInfo:
                    if let p = appState.openProject { ProjectInfoView(project: p) }
                case .workload:
                    if let p = appState.openProject { WorkloadView(project: p) }
                case .fees:
                    if let p = appState.openProject { FeesView(project: p) }
                case .export:
                    if let p = appState.openProject { ExportView(project: p) }
                case .libraries(let key):
                    LibrariesView(viewKey: key)
                case .feeRules(let tab):
                    FeeRulesView(tab: tab)
                case .profiles:
                    ProfilesView()
                case .validation:
                    ValidationView()
                case .batch:
                    BatchView()
                case .settings:
                    SettingsView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 底部状态栏（常驻）：问题数 · 总造价（大数字）· 工日 · 保存状态 · 最后修改 · 操作提示。
struct StatusBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                Text(statusHintFor(appState.nav))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if let project = appState.openProject,
                   let result = appState.calcResult(for: project) {
                    let issues = appState.openProjectIssues
                    Button {
                        appState.nav = .validation
                    } label: {
                        Label(
                            issues.isEmpty ? "校验通过" : "\(issues.count) 个问题",
                            systemImage: issues.isEmpty ? "checkmark.shield" : "exclamationmark.triangle"
                        )
                        .foregroundColor(issues.isEmpty ? .secondary : .orange)
                    }
                    .buttonStyle(.plain)
                    .help("打开校验中心")
                    Text("工日 \(num2(result.techDays + result.laborDays))")
                        .monospacedDigit()
                    HStack(spacing: 4) {
                        Text("总造价").foregroundColor(.secondary)
                        Text("¥\(money(result.table1.grandIncl))")
                            .font(.title3).fontWeight(.bold)
                            .monospacedDigit()
                    }
                    Text("改于 \(dateTimeText(project.updatedAt))")
                        .foregroundColor(.secondary)
                }
                Text(appState.saveState.text)
                    .foregroundColor(appState.saveState.status == .dirty ? .red : .secondary)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}
#endif
