#if os(macOS)
import SwiftUI

/// 设置：整库备份 / 导入导出（全部写真实路径，原生文件面板）。
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "设置",
                           subtitle: "整库备份 / 方案导入导出 / 关于")
                SectionCard(title: "备份与方案文件", subtitle: "全部写真实路径（原生文件面板）") {
                    HStack(spacing: 8) {
                        Button("整库备份") { exportBackup() }
                        Button("导入方案文件") { importProfile() }
                        Button("导出当前资料库方案") { exportEditingProfile() }
                    }
                    .controlSize(.small)
                }
                SectionCard(title: "当前方案") {
                    VStack(alignment: .leading, spacing: 6) {
                        infoRow("资料库方案", appState.editingProfile?.name ?? "—")
                        infoRow("新建工程默认方案", defaultProfileName)
                        Text("资料库方案与新建默认相互独立：前者在资料库/取费规则页顶部切换，后者在配置方案页设为默认。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                SectionCard(title: "数据文件") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("数据文件：~/Library/Application Support/通信概预算/budget-data.json（与 Electron 版同一文件，可直接互通）。")
                        Text("备份：每次重大操作与每小时自动滚动备份（保留 5 份），文件为 budget-data.backup-<时间戳>.json。")
                    }
                    .font(.callout)
                    .foregroundColor(.secondary)
                }
                SectionCard(title: "关于") {
                    VStack(alignment: .leading, spacing: 6) {
                        infoRow("软件", "\(appDisplayName) v\(TXBudget.version)")
                        infoRow("保存状态", appState.saveState.text)
                    }
                }
            }
            .padding(Theme.pagePadding)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundColor(.secondary).frame(width: 130, alignment: .leading)
            Text(value)
        }
        .font(.callout)
    }

    private var defaultProfileName: String {
        appState.db.configurationProfiles.first { $0.id == appState.db.settings.activeProfileId }?.name ?? "—"
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

    private func exportEditingProfile() {
        guard let profile = appState.editingProfile else { return }
        guard let url = FilePanel.saveFile(defaultName: "\(profile.name).json", allowedTypes: ["json"]) else { return }
        do {
            let data = try DatabaseStore.exportProfileData(profile)
            try data.write(to: url)
            appState.showToast("已导出：\(url.path)")
        } catch {
            appState.showToast("导出失败：\(error.localizedDescription)")
        }
    }
}
#endif
