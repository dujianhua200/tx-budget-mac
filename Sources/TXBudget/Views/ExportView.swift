#if os(macOS)
import SwiftUI

/// 报表导出：左树勾选 11 张表，默认全选，选择存 settings.exportSelection。
/// 导出 xlsx 本身是阶段 4；本阶段只做勾选界面 + 选择持久化，导出按钮先置灰并说明。
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
                    Text("导出 xlsx 在阶段 4 实现（本阶段只做勾选界面 + 选择持久化）。")
                        .foregroundColor(.secondary).font(.caption)
                }
            }
            Button("导出勾选的表（\(appState.exportSelection.count) 张）") {
                appState.showToast("导出 xlsx 在阶段 4 实现")
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
            if appState.exportSelection.isEmpty {
                Text("至少勾选 1 张表。").foregroundColor(.secondary)
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
