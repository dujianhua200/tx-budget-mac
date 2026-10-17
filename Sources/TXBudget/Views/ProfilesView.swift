#if os(macOS)
import SwiftUI

/// 配置方案：列表 / 新建 / 复制 / 重命名 / 删除（占用检查）/ 导出方案文件 / 导入方案文件 / 设为新建默认 / 整库备份。
/// 编辑目标与新建默认彻底分离：【编辑内容】只置 editingProfileId 并跳基础库页；【设为默认】只影响新建工程。
struct ProfilesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var newName = ""
    @State private var templateId = ""
    @State private var renameId: String?
    @State private var renameValue = ""
    @State private var deleteProfile: ConfigurationProfile?
    @State private var showDeleteConfirm = false
    @State private var blockedProfile: ConfigurationProfile?
    @State private var switchTarget = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("配置方案").font(.headline)
            Text("每套方案拥有独立完整的一套库、费率、规则，不同方案之间数据完全隔离。")
                .foregroundColor(.secondary).font(.caption)
            HStack(spacing: 8) {
                TextField("新方案名称", text: $newName).frame(width: 220)
                Picker("以…为模板", selection: $templateId) {
                    Text("（空白方案）").tag("")
                    ForEach(appState.db.configurationProfiles, id: \.id) { p in
                        Text(p.name).tag(p.id)
                    }
                }.frame(width: 200)
                Button("＋ 新建方案") { createNewProfile() }
                    .buttonStyle(.borderedProminent)
                Button("导入方案文件") { importProfile() }
                Button("整库备份") { exportBackup() }
            }
            .controlSize(.small)
            Table(appState.db.configurationProfiles) {
                TableColumn("方案名") { p in
                    if renameId == p.id {
                        HStack {
                            TextField("方案名", text: $renameValue)
                                .textFieldStyle(.roundedBorder).frame(width: 180)
                            Button("保存") { rename(p) }.controlSize(.small)
                            Button("取消") { renameId = nil }.controlSize(.small)
                        }
                    } else {
                        HStack {
                            Text(p.name)
                            Button("重命名") {
                                renameId = p.id
                                renameValue = p.name
                            }.controlSize(.small)
                        }
                    }
                }
                TableColumn("来源") { p in Text(p.source) }
                TableColumn("工程数") { p in Text("\(projectsOf(p.id).count)") }
                TableColumn("状态") { p in Text(statusText(p)) }
                TableColumn("操作") { p in
                    HStack {
                        Button("编辑内容") {
                            appState.setEditingProfile(p.id)
                            appState.nav = .libraries(.quotas)
                            appState.showToast("正在编辑方案“\(p.name)”")
                        }
                        .buttonStyle(.borderedProminent)
                        Button("设为默认") { appState.setDefaultProfile(p.id) }
                            .disabled(appState.db.settings.activeProfileId == p.id)
                        Button("复制") { duplicate(p) }
                        Button("导出") { exportProfile(p) }
                        Button("删除") { askDelete(p) }
                            .tint(.red)
                    }.controlSize(.small)
                }
            }
            .tableStyle(.inset)
        }
        .alert("删除配置方案“\(deleteProfile?.name ?? "")”？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { deleteProfile = nil }
            Button("确认删除", role: .destructive) {
                if let p = deleteProfile {
                    appState.deleteProfile(p.id)
                    appState.showToast("已删除配置方案“\(p.name)”")
                    deleteProfile = nil
                }
            }
        } message: {
            Text("将删除配置方案“\(deleteProfile?.name ?? "")”（含其全部库、费率、规则），该方案无工程引用。删除前已备份。")
        }
        .alert("无法删除“\(blockedProfile?.name ?? "")”", isPresented: Binding(
            get: { blockedProfile != nil },
            set: { if !$0 { blockedProfile = nil } }
        )) {
            Button("取消", role: .cancel) { blockedProfile = nil }
            Button("切换工程") {
                if let p = blockedProfile, !switchTarget.isEmpty {
                    appState.updateDb { d in
                        for i in d.projects.indices where d.projects[i].profileId == p.id {
                            d.projects[i].profileId = switchTarget
                        }
                    }
                    blockedProfile = nil
                }
            }
        } message: {
            if let p = blockedProfile {
                let using = projectsOf(p.id)
                let targetName = appState.db.configurationProfiles.first { $0.id == switchTarget }?.name ?? "—"
                Text("仍有 \(using.count) 个工程使用该方案，无法直接删除。\n工程：\(using.map { $0.name }.joined(separator: "、"))\n点“切换工程”会把这些工程切换到方案“\(targetName)”，之后可再删除本方案。")
            }
        }
    }

    private func projectsOf(_ pid: String) -> [ProjectRecord] {
        appState.db.projects.filter { $0.profileId == pid }
    }

    private func statusText(_ p: ConfigurationProfile) -> String {
        var parts: [String] = []
        if appState.db.settings.activeProfileId == p.id { parts.append("新建默认") }
        if (appState.db.settings.editingProfileId ?? appState.db.settings.activeProfileId) == p.id {
            parts.append("正在编辑")
        }
        return parts.joined(separator: " · ")
    }

    private func createNewProfile() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        let name = trimmed.isEmpty ? "新配置方案" : trimmed
        if let template = appState.db.configurationProfiles.first(where: { $0.id == templateId }) {
            var copy = duplicateProfile(template)
            copy.name = name
            appState.addProfile(copy)
        } else {
            appState.addProfile(createProfile(name: name))
        }
        newName = ""
        appState.showToast("已新建配置方案“\(name)”")
    }

    private func duplicate(_ p: ConfigurationProfile) {
        appState.addProfile(duplicateProfile(p))
        appState.showToast("已复制为“\(p.name)（副本）”")
    }

    private func rename(_ p: ConfigurationProfile) {
        let name = renameValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { renameId = nil; return }
        appState.updateDb { d in
            if let i = d.configurationProfiles.firstIndex(where: { $0.id == p.id }) {
                d.configurationProfiles[i].name = name
                d.configurationProfiles[i].updatedAt = nowISO()
            }
        }
        renameId = nil
        appState.showToast("已重命名为“\(name)”")
    }

    private func askDelete(_ p: ConfigurationProfile) {
        if appState.db.configurationProfiles.count <= 1 {
            appState.showToast("至少保留一个配置方案，无法删除最后一个方案。")
            return
        }
        if !projectsOf(p.id).isEmpty {
            blockedProfile = p
            switchTarget = appState.db.configurationProfiles.first { $0.id != p.id }?.id ?? ""
            return
        }
        deleteProfile = p
        showDeleteConfirm = true
    }

    private func exportProfile(_ p: ConfigurationProfile) {
        guard let url = FilePanel.saveFile(defaultName: "\(p.name).json", allowedTypes: ["json"]) else { return }
        do {
            let data = try DatabaseStore.exportProfileData(p)
            try data.write(to: url)
            appState.showToast("已导出：\(url.path)")
        } catch {
            appState.showToast("导出失败：\(error.localizedDescription)")
        }
    }

    private func importProfile() {
        guard let url = FilePanel.openFile(allowedTypes: ["json"]) else { return }
        do {
            let data = try Data(contentsOf: url)
            var profile = try DatabaseStore.importProfileData(data)
            let names = Set(appState.db.configurationProfiles.map { $0.name })
            if names.contains(profile.name) { profile.name = "\(profile.name)（导入）" }
            appState.addProfile(profile)
            appState.showToast("已导入配置方案“\(profile.name)”")
        } catch {
            appState.showToast("导入失败：\(error.localizedDescription)")
        }
    }

    private func exportBackup() {
        guard let url = FilePanel.saveFile(defaultName: "概预算整库备份.json", allowedTypes: ["json"]) else { return }
        do {
            let data = try DatabaseStore.exportBackupData(appState.db)
            try data.write(to: url)
            appState.showToast("整库已备份：\(url.path)")
        } catch {
            appState.showToast("备份失败：\(error.localizedDescription)")
        }
    }
}
#endif
