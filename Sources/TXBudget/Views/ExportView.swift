#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 报表导出（v2.0.0）：左勾选 11 张表（存 settings.exportSelection），
/// 右逐表迷你预览（关键数字，与导出同源同值）+ 导出按钮 + 本次导出记录。
/// 导出经 NSSavePanel 选路径，调用 PrintExport 生成 xlsx（版式与结算书一致）。
struct ExportView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "报表导出",
                       subtitle: "工程：\(project.name) · 方案：\(appState.projectProfile?.name ?? "—") · 勾选的表会导出为一个 xlsx 预算书")
            HStack(alignment: .top, spacing: 16) {
                // 左：勾选卡片
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("全部表（\(appState.exportSelection.count)/\(sheetNames.count)）",
                           isOn: allBinding)
                        .fontWeight(.semibold)
                    Divider()
                    ForEach(exportGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(group.label, isOn: groupBinding(group))
                                .fontWeight(.medium)
                            ForEach(group.sheets, id: \.self) { sheet in
                                Toggle(sheet, isOn: sheetBinding(sheet))
                                    .padding(.leading, 20)
                            }
                        }
                    }
                    Divider()
                    Button("导出勾选的表（\(appState.exportSelection.count) 张）") {
                        exportTapped()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.exportSelection.isEmpty)
                    if appState.exportSelection.isEmpty {
                        Text("至少勾选 1 张表。").foregroundColor(.secondary).font(.caption)
                    }
                }
                .cardStyle()
                .frame(width: 330)

                // 右：逐表预览 + 导出记录
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let result = appState.calcResult(for: project) {
                            ForEach(selectedSheetsInOrder, id: \.self) { sheet in
                                previewCard(sheet: sheet, result: result)
                            }
                            if selectedSheetsInOrder.isEmpty {
                                Text("勾选左侧的表后，这里会预览每张表的关键数字。")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("计算失败，无法预览。").foregroundColor(.secondary)
                        }
                        historyCard
                    }
                }
            }
        }
        .padding(Theme.pagePadding)
    }

    private var selectedSheetsInOrder: [String] {
        sheetNames.filter { appState.exportSelection.contains($0) }
    }

    private func previewCard(sheet: String, result: CalcResult) -> some View {
        SectionCard(title: sheet) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(exportSheetPreviewLines(sheet, project: project,
                                                profileName: appState.projectProfile?.name ?? "—",
                                                result: result), id: \.self) { line in
                    Text(line).font(.callout).monospacedDigit()
                }
            }
        }
    }

    private var historyCard: some View {
        SectionCard(title: "本次导出记录", subtitle: "仅本次运行内保留") {
            if appState.exportHistory.isEmpty {
                Text("还没有导出记录。").foregroundColor(.secondary).font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(appState.exportHistory.prefix(8)) { rec in
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text(rec.fileName).lineLimit(1)
                            Spacer()
                            Text(rec.projectName).foregroundColor(.secondary).lineLimit(1)
                            Text(rec.timeText).foregroundColor(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }

    private func exportTapped() {
        guard let result = appState.calcResult(for: project) else {
            appState.showToast("计算失败，无法导出")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")].compactMap { $0 }
        panel.nameFieldStringValue = "\(project.name)-预算书.xlsx"
        panel.canCreateDirectories = true
        panel.begin { response in
            Task { @MainActor in
                guard response == .OK, let url = panel.url else { return }
                do {
                    try exportBudgetBook(
                        to: url, projectName: project.name,
                        project: project.toEngineProject(), result: result,
                        profile: appState.projectProfile,
                        include: Set(appState.exportSelection))
                    appState.recordExport(projectName: project.name,
                                          fileName: url.lastPathComponent)
                    appState.showToast("已导出 \(url.lastPathComponent)")
                } catch {
                    appState.showToast("导出失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private var allBinding: Binding<Bool> {
        Binding(
            get: { appState.exportSelection.count == sheetNames.count },
            set: { v in appState.setExportSelection(v ? sheetNames : []) }
        )
    }

    private func groupBinding(_ group: ExportGroup) -> Binding<Bool> {
        Binding(
            get: { group.sheets.allSatisfy { appState.exportSelection.contains($0) } },
            set: { _ in appState.setExportSelection(toggleExportGroup(appState.exportSelection, group.sheets)) }
        )
    }

    private func sheetBinding(_ sheet: String) -> Binding<Bool> {
        Binding(
            get: { appState.exportSelection.contains(sheet) },
            set: { _ in appState.setExportSelection(toggleExportSelection(appState.exportSelection, sheet)) }
        )
    }
}
#endif
