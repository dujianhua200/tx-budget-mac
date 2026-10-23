#if os(macOS)
import SwiftUI

/// 工程列表（启动页，v2.0.0；v2.6.0 起只有列表模式——用户裁决去掉卡片模式）：
/// 多选列表 + 搜索 + 新建工程向导。启动先到这里选工程（docs/v2.6-batch-design.md §1）。
struct ProjectListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var selected: Set<String> = []
    @State private var showWizard = false
    @State private var pendingDelete: [ProjectRecord] = []
    @State private var showDeleteConfirm = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题区
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appDisplayName).font(.largeTitle).fontWeight(.bold)
                    Text("通信工程概预算 · 选择工程开始工作，或新建一个工程")
                        .foregroundColor(.secondary)
                }
                Spacer()
                searchField
                Button("批量生成") { appState.nav = .batch }
                Button("＋ 新建工程") { showWizard = true }
                    .buttonStyle(.borderedProminent)
            }

            if filteredProjects.isEmpty {
                EmptyStateView(
                    systemImage: "folder.badge.plus",
                    title: appState.db.projects.isEmpty ? "还没有工程" : "没有匹配的工程",
                    message: appState.db.projects.isEmpty
                        ? "新建第一个工程，或到批量生成从 Excel 导入已有工程量。"
                        : "换个关键词试试。",
                    actionTitle: "＋ 新建工程",
                    action: { showWizard = true }
                )
                .cardStyle()
            } else {
                listMode
            }
            Spacer(minLength: 0)
            HStack {
                Text("共 \(appState.db.projects.count) 个工程 · 数据文件与 Electron 版互通")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(appState.saveState.text)
                    .font(.caption)
                    .foregroundColor(appState.saveState.status == .dirty ? .red : .secondary)
            }
        }
        .padding(Theme.pagePadding)
        .sheet(isPresented: $showWizard) {
            NewProjectWizard()
        }
        .alert("删除工程？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { pendingDelete = [] }
            Button("确认删除", role: .destructive) {
                appState.deleteProjects(pendingDelete.map { $0.id })
                selected.subtract(pendingDelete.map { $0.id })
                pendingDelete = []
            }
        } message: {
            Text("将删除 \(pendingDelete.count) 个工程（含工程量、材料调整与费率覆盖），删除前已备份。")
        }
    }

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("搜索工程名称", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .frame(width: 180)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
    }

    private var listMode: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("导出选中（Excel）") { exportSelected() }
                    .disabled(selected.isEmpty)
                Button("删除选中") {
                    pendingDelete = appState.db.projects.filter { selected.contains($0.id) }
                    showDeleteConfirm = true
                }
                .disabled(selected.isEmpty)
                .tint(.red)
                Spacer()
                Text("已选 \(selected.count) 个").font(.caption).foregroundColor(.secondary)
            }
            .controlSize(.small)
            Table(filteredProjects, selection: $selected) {
                TableColumn("工程名称") { p in
                    Button(p.name) { appState.openProject(p.id) }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.accent)
                }
                TableColumn("配置方案") { p in
                    Text(profileName(of: p))
                }
                TableColumn("工程量行数") { p in
                    Text("\(p.quantities.count)")
                }
                TableColumn("总造价（含税）") { p in
                    MoneyText(value: appState.calcResult(for: p)?.table1.grandIncl)
                }
                TableColumn("更新时间") { p in
                    Text(dateTimeText(p.updatedAt))
                }
                TableColumn("操作") { p in
                    HStack {
                        Button("打开") { appState.openProject(p.id) }
                        Button("复制") { appState.duplicateProject(p) }
                        Button("删除") {
                            pendingDelete = [p]
                            showDeleteConfirm = true
                        }.tint(.red)
                    }.controlSize(.small)
                }
            }
            .tableStyle(.inset)
        }
    }

    private var filteredProjects: [ProjectRecord] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = appState.db.projects.filter { q.isEmpty || $0.name.contains(q) }
        return sortProjectsRecent(list)
    }

    private func profileName(of p: ProjectRecord) -> String {
        appState.db.configurationProfiles.first { $0.id == p.profileId }?.name ?? "—"
    }

    private func exportSelected() {
        guard let dir = FilePanel.openDirectory(message: "选择批量导出预算书的保存目录") else { return }
        let projects = appState.db.projects.filter { selected.contains($0.id) }
        let result = appState.batchExportProjects(projects, to: dir)
        if result.failures.isEmpty {
            appState.showToast("已批量导出 \(result.succeeded) 个工程到 \(dir.path)")
        } else {
            let names = result.failures.map { $0.0 }.joined(separator: "、")
            appState.showToast("已导出 \(result.succeeded) 个，失败 \(result.failures.count) 个（\(names)）")
        }
    }
}

/// 新建工程向导：工程名 → 配置方案 → 模板（可选）→ 创建并进入工程信息页补全。
struct NewProjectWizard: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var profileId = ""
    @State private var templateId = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建工程").font(.title2).fontWeight(.bold)
            VStack(alignment: .leading, spacing: 6) {
                Text("① 工程名称").font(.headline)
                TextField("如：2026年信阳市FTTH改造工程", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { createIfValid() }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("② 配置方案（取费标准）").font(.headline)
                Picker("", selection: $profileId) {
                    ForEach(appState.db.configurationProfiles, id: \.id) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                .labelsHidden()
                Text("决定定额库、费率与打折规则；创建后可在工程信息页切换。")
                    .font(.caption).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("③ 套用模板（可选）").font(.headline)
                Picker("", selection: $templateId) {
                    Text("不套模板（空白）").tag("")
                    ForEach(appState.db.projects, id: \.id) { p in
                        Text("套用：\(p.name)").tag(p.id)
                    }
                }
                .labelsHidden()
                Text("套模板会复制模板的工程信息、工程量、材料调整与费率覆盖。")
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("创建并填写工程信息") { createIfValid() }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            profileId = appState.db.settings.activeProfileId.isEmpty
                ? (appState.db.configurationProfiles.first?.id ?? "")
                : appState.db.settings.activeProfileId
        }
    }

    private func createIfValid() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let tpl = appState.db.projects.first { $0.id == templateId }
        appState.createProject(name: trimmed, profileId: profileId.isEmpty ? nil : profileId,
                               template: tpl)
        dismiss()
    }
}
#endif
