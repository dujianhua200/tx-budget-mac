#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 报表导出：左树勾选 11 张表，默认全选，选择存 settings.exportSelection。
/// 导出按钮经 NSSavePanel 选路径，调用 PrintExport 生成 xlsx（版式与 2024 结算书一致）。
struct ExportView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("报表导出").font(.headline)
            HStack(alignment: .top, spacing: 24) {
                // 左树勾选
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("全部表（\(appState.exportSelection.count)/\(sheetNames.count)）",
                           isOn: allBinding)
                    ForEach(exportGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Toggle(group.label, isOn: groupBinding(group))
                            ForEach(group.sheets, id: \.self) { sheet in
                                Toggle(sheet, isOn: sheetBinding(sheet))
                                    .padding(.leading, 20)
                            }
                        }
                    }
                }
                .frame(minWidth: 300, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    Text("工程：\(project.name)")
                    Text("配置方案：\(appState.projectProfile?.name ?? "—")")
                    if let result = appState.calcResult(for: project) {
                        Text("总计（含税）\(money(result.table1.grandIncl)) 元")
                    }
                    Text("导出 xlsx（版式与 2024 结算书一致，数值由计算引擎生成）。")
                        .foregroundColor(.secondary).font(.caption)
                }
            }
            Button("导出勾选的表（\(appState.exportSelection.count) 张）") {
                exportTapped()
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.exportSelection.isEmpty)
            if appState.exportSelection.isEmpty {
                Text("至少勾选 1 张表。").foregroundColor(.secondary)
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
