#if os(macOS)
import SwiftUI

/// 配置方案（v2.0.0 卡片呈现）：新建 / 复制 / 重命名 / 删除（占用检查）/ 导出方案文件 /
/// 导入方案文件 / 设为新建默认 / 整库备份。
/// 编辑目标与新建默认彻底分离：【编辑内容】只置 editingProfileId 并跳资料库页；
/// 【设为默认】只影响新建工程（逻辑与 v1 一致，仅呈现重做）。
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
            PageHeader(title: "配置方案",
                       subtitle: "每套方案拥有独立完整的一套库、费率、规则，不同方案之间数据完全隔离")
            Text("点「编辑内容」后，资料库与取费规则编辑的就是该方案（也可在资料库/取费规则页顶部的“当前方案”下拉直接切换）；「设为默认」只影响新建工程。")
                .font(.caption).foregroundColor(.secondary)
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

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(appState.db.configurationProfiles, id: \.id) { p in
                        profileCard(p)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(Theme.pagePadding)
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
        .sheet(isPresented: Binding(
            get: { blockedProfile != nil },
            set: { if !$0 { blockedProfile = nil } }
        )) {
            if let p = blockedProfile {
                VStack(alignment: .leading, spacing: 12) {
                    Text("删除方案“\(p.name)”").font(.headline)
                    Text("仍有 \(projectsOf(p.id).count) 个工程使用该方案：\(projectsOf(p.id).map { $0.name }.joined(separator: "、"))。请选择这些工程要切换到的方案，切换后本方案将被删除。")
                        .foregroundColor(.secondary)
                    Picker("切换到方案", selection: $switchTarget) {
                        ForEach(blockedOthers, id: \.id) { other in
                            Text(other.name).tag(other.id)
                        }
                    }
                    HStack {
                        Button("取消", role: .cancel) { blockedProfile = nil }
                        Button("切换工程并删除", role: .destructive) {
                            guard !switchTarget.isEmpty else { return }
                            appState.updateDb { d in
                                for i in d.projects.indices where d.projects[i].profileId == p.id {
                                    d.projects[i].profileId = switchTarget
                                }
                            }
                            appState.deleteProfile(p.id)
                            appState.showToast("已删除配置方案“\(p.name)”")
                            blockedProfile = nil
                        }
                        .disabled(switchTarget.isEmpty)
                    }
                }
                .padding()
                .frame(width: 420)
            }
        }
    }

    private func profileCard(_ p: ConfigurationProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if renameId == p.id {
                    TextField("方案名", text: $renameValue)
                        .textFieldStyle(.roundedBorder).frame(width: 220)
                    Button("保存") { rename(p) }.controlSize(.small)
                    Button("取消") { renameId = nil }.controlSize(.small)
                } else {
                    Text(p.name).font(.headline)
                    Button("重命名") {
                        renameId = p.id
                        renameValue = p.name
                    }.controlSize(.small)
                }
                Spacer()
                ForEach(statusBadges(p), id: \.self) { badge in
                    Text(badge)
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Theme.accent)
                        .cornerRadius(7)
                }
            }
            HStack(spacing: 14) {
                Text("来源：\(p.source.isEmpty ? "—" : p.source)")
                Text("工程数：\(projectsOf(p.id).count)")
                Text("定额 \(p.libraries.quotas.count) 条 · 材料 \(p.libraries.materials.count) 条")
                Text("更新：\(dateTimeText(p.updatedAt))")
            }
            .font(.caption).foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button("编辑内容") {
                    appState.setEditingProfile(p.id)
                    appState.nav = .libraries(.quotas)
                    appState.showToast("资料库与取费规则现在编辑方案“\(p.name)”")
                }
                .buttonStyle(.borderedProminent)
                Button("设为默认") { appState.setDefaultProfile(p.id) }
                    .disabled(appState.db.settings.activeProfileId == p.id)
                Button("复制") { duplicate(p) }
                Button("导出") { exportProfile(p) }
                Spacer()
                Button("删除") { askDelete(p) }
                    .tint(.red)
            }
            .controlSize(.small)
        }
        .cardStyle()
    }

    private func statusBadges(_ p: ConfigurationProfile) -> [String] {
        // v2.0.1：删除“正在编辑”徽标——它按 (editingProfileId ?? activeProfileId)
        // 恒有一家显示、无法消除且无处解释，是隐藏全局模式；编辑目标改由
        // 资料库/取费规则页顶部的“当前方案”下拉直接呈现与切换。
        var badges: [String] = []
        if appState.db.settings.activeProfileId == p.id { badges.append("新建默认") }
        return badges
    }

    private var blockedOthers: [ConfigurationProfile] {
        guard let p = blockedProfile else { return [] }
        return appState.db.configurationProfiles.filter { $0.id != p.id }
    }

    private func projectsOf(_ pid: String) -> [ProjectRecord] {
        appState.db.projects.filter { $0.profileId == pid }
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
