#if os(macOS)
import SwiftUI

/// 设置：整库备份 / 导入导出（全部写真实路径，原生文件面板）。
/// v2.5.0：新增「工程信息模板」卡片（编辑 settings.defaultInfo，菜单栏「模板」直达）；
/// 方案导入/导出收敛到 AppState 的 importProfileViaPanel / exportEditingProfileViaPanel
/// （与菜单栏「方案」共用同一实现）。
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var highlightTemplate = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "设置",
                           subtitle: "整库备份 / 方案导入导出 / 工程信息模板 / 关于")
                SectionCard(title: "备份与方案文件", subtitle: "全部写真实路径（原生文件面板）") {
                    HStack(spacing: 8) {
                        Button("整库备份") { exportBackup() }
                        Button("导入方案文件") { appState.importProfileViaPanel() }
                        Button("导出当前资料库方案") { appState.exportEditingProfileViaPanel() }
                    }
                    .controlSize(.small)
                }
                SectionCard(title: "工程信息模板",
                            subtitle: "新建工程时预填的默认工程信息；只影响之后新建的工程，已建工程在各自的工程信息页改") {
                    templateEditors
                }
                .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .stroke(highlightTemplate ? Theme.accent : Color.clear, lineWidth: 2))
                .onChange(of: appState.settingsFocusToken) { _ in
                    highlightTemplate = true
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        highlightTemplate = false
                    }
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

    // MARK: - 工程信息模板（settings.defaultInfo，选项与工程信息表单同源）

    private func infoBinding<T>(_ keyPath: WritableKeyPath<ProjectInfo, T>) -> Binding<T> {
        Binding(get: { appState.db.settings.defaultInfo[keyPath: keyPath] },
                set: { v in appState.updateDb { $0.settings.defaultInfo[keyPath: keyPath] = v } })
    }

    private var templateEditors: some View {
        VStack(alignment: .leading, spacing: 8) {
            templateRow("工程类型") {
                Picker("", selection: infoBinding(\.工程类型)) {
                    ForEach(projectTypes, id: \.self) { Text($0).tag($0) }
                }.labelsHidden()
            }
            templateRow("施工折扣") {
                OptionalDoubleField(label: "", value: infoBinding(\.施工折扣))
                    .textFieldStyle(.roundedBorder)
                Text("1 = 不打折；0.379 = 打 37.9%").font(.caption).foregroundColor(.secondary)
            }
            templateRow("施工距离") {
                Picker("", selection: infoBinding(\.施工距离)) {
                    Text("35KM以内").tag("35KM以内")
                    Text("35KM以上").tag("35KM以上")
                }.labelsHidden()
            }
            templateRow("施工调遣分类") {
                Picker("", selection: infoBinding(\.施工调遣分类)) {
                    Text("施工队伍调遣人数(线路、管道）").tag("施工队伍调遣人数(线路、管道）")
                    Text("施工队伍调遣人数(无线、电源、设备）").tag("施工队伍调遣人数(无线、电源、设备）")
                }.labelsHidden()
            }
            templateRow("冬雨季施工费") {
                Picker("", selection: infoBinding(\.冬雨季施工费)) {
                    Text("Ⅰ类地区").tag("Ⅰ类地区")
                    Text("Ⅱ类地区").tag("Ⅱ类地区")
                    Text("Ⅲ类地区").tag("Ⅲ类地区")
                }.labelsHidden()
            }
            templateRow("甲供增值税") {
                OptionalDoubleField(label: "", value: infoBinding(\.甲供增值税))
                    .textFieldStyle(.roundedBorder)
                Text("如 0.13").font(.caption).foregroundColor(.secondary)
            }
            templateRow("乙供增值税") {
                OptionalDoubleField(label: "", value: infoBinding(\.乙供增值税))
                    .textFieldStyle(.roundedBorder)
                Text("如 0.09").font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func templateRow<Content: View>(_ label: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 130, alignment: .leading)
            content()
            Spacer()
        }
        .font(.callout)
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
