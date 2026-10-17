#if os(macOS)
import SwiftUI

/// 工程列表（最近置顶 + 搜索 + 按方案筛选 + 新建/复制/删除/导出选中）。
struct ProjectsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var profileFilter = ""
    @State private var newName = ""
    @State private var templateId = ""
    @State private var selected: Set<String> = []
    @State private var confirmDeleteIds: [String]?
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("搜索工程名称…", text: $query).frame(width: 260)
                Picker("全部配置方案", selection: $profileFilter) {
                    Text("全部配置方案").tag("")
                    ForEach(appState.db.configurationProfiles, id: \.id) { p in
                        Text(p.name).tag(p.id)
                    }
                }.frame(width: 200)
                TextField("新工程名称", text: $newName).frame(width: 260)
                Picker("不套模板（空白）", selection: $templateId) {
                    Text("不套模板（空白）").tag("")
                    ForEach(appState.db.projects, id: \.id) { p in
                        Text("套用模板：\(p.name)").tag(p.id)
                    }
                }.frame(width: 220)
                Button("＋ 新建工程") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let tpl = appState.db.projects.first { $0.id == templateId }
                    appState.createProject(name: name, template: tpl)
                    newName = ""
                }
                .buttonStyle(.borderedProminent)
                Button("导出选中（Excel）") { exportSelected() }
                    .disabled(selected.isEmpty)
                Button("删除选中") {
                    confirmDeleteIds = Array(selected)
                    showDeleteConfirm = true
                }
                .disabled(selected.isEmpty)
                .tint(.red)
                Button("批量生成 →") { appState.nav = .batch }
            }
            .controlSize(.small)

            Table(filteredProjects, selection: $selected) {
                TableColumn("工程名称") { p in
                    Button(p.name) { appState.openProject(p.id) }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                }
                TableColumn("配置方案") { p in
                    Text(profileName(of: p))
                }
                TableColumn("工程量行数") { p in
                    Text("\(p.quantities.count)")
                }
                TableColumn("总计（含税）") { p in
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
                            confirmDeleteIds = [p.id]
                            showDeleteConfirm = true
                        }.tint(.red)
                    }.controlSize(.small)
                }
            }
            .tableStyle(.inset)
            if filteredProjects.isEmpty {
                Text("暂无工程。先新建一个，或到“批量生成”从 Excel 导入。")
                    .foregroundColor(.secondary)
            }
        }
        .alert("删除工程？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { confirmDeleteIds = nil }
            Button("确认删除", role: .destructive) {
                if let ids = confirmDeleteIds {
                    appState.deleteProjects(ids)
                    selected.subtract(ids)
                    confirmDeleteIds = nil
                }
            }
        } message: {
            Text("将删除 \(confirmDeleteIds?.count ?? 0) 个工程（含工程量、材料调整与费率覆盖），删除前已备份。")
        }
    }

    private var filteredProjects: [ProjectRecord] {
        let list = appState.db.projects.filter { p in
            (query.isEmpty || p.name.contains(query)) &&
            (profileFilter.isEmpty || p.profileId == profileFilter)
        }
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
#endif
