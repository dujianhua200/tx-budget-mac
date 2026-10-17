#if os(macOS)
import SwiftUI

/// 取费左树 + 右表（费用名称 / 计算基数 / 费率 / 金额 / 计算式，费率可编辑）。
/// 左树由表二费用结构派生；点节点切换右表分组；金额取当前工程折前表二。
/// 费率编辑写回“正在编辑方案”的费率（与 Electron 一致：库/费率编辑走 editingProfileId）。
struct FeeView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("费率编辑写回正在编辑的方案“\(appState.editingProfile?.name ?? "—")”；金额列为当前工程折前表二。")
                .foregroundColor(.secondary).font(.caption)
            FeeTreeTableView(
                profile: appState.editingProfile,
                result: appState.calcResult(for: project),
                projectType: .constant(project.info.工程类型),
                showProjectTypePicker: false,
                onRateChange: { _, rateField, value in
                    appState.updateDb { d in
                        guard let idx = d.configurationProfiles.firstIndex(where: { $0.id == d.settings.editingProfileId ?? "" })
                            ?? d.configurationProfiles.firstIndex(where: { $0.id == d.settings.activeProfileId }) else { return }
                        if d.configurationProfiles[idx].rates.byProjectType[project.info.工程类型] == nil {
                            d.configurationProfiles[idx].rates.byProjectType[project.info.工程类型] = NamedRatesRecord()
                        }
                        d.configurationProfiles[idx].rates.byProjectType[project.info.工程类型]?.setValue(value, forKey: rateField)
                        d.configurationProfiles[idx].updatedAt = nowISO()
                    }
                }
            )
        }
    }
}

/// 取费左树 + 右表复用组件（当前工程·费用 / 取费规则·费率 共用）。
struct FeeTreeTableView: View {
    var profile: ConfigurationProfile?
    var result: CalcResult?
    var projectType: Binding<String>
    var showProjectTypePicker: Bool
    var onRateChange: (String, String, Double?) -> Void

    @State private var selectedId = "root:all"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showProjectTypePicker {
                HStack {
                    Text("工程类别")
                    Picker("", selection: projectType) {
                        ForEach(projectTypes, id: \.self) { t in Text(t).tag(t) }
                    }.labelsHidden()
                    Text("金额列取自该方案下首个工程的折前表二；无工程时金额为空。")
                        .foregroundColor(.secondary).font(.caption)
                }
            }
            HSplitView {
                // 左树
                ScrollView {
                    FeeTreeNodeView(node: feeTree, depth: 0, selectedId: $selectedId)
                        .frame(minWidth: 220, alignment: .leading)
                }
                // 右表
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(selectedNode?.label ?? "")（\(rows.count) 项，金额为折前）")
                        .font(.headline)
                    Table(rows) {
                        TableColumn("费用名称") { r in Text(r.name) }
                        TableColumn("计算基数") { r in Text(r.base).foregroundColor(.secondary) }
                        TableColumn("费率") { r in
                            if let field = r.rateField {
                                OptionalDoubleField(label: "", value: rateBinding(r, field: field))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 110)
                            } else {
                                Text(r.rate.map { jsNumberString($0) } ?? "—")
                            }
                        }
                        TableColumn("金额（元）") { r in MoneyText(value: r.amount) }
                        TableColumn("计算式") { r in Text(r.basis).foregroundColor(.secondary) }
                    }
                    .tableStyle(.inset)
                    if rows.isEmpty {
                        Text("该组无费用项。").foregroundColor(.secondary)
                    }
                    Text("费率编辑直接写回当前编辑方案的费率；冬雨季费率 null = 按地区查表。")
                        .foregroundColor(.secondary).font(.caption)
                }
                .frame(minWidth: 400)
            }
        }
    }

    private var effectiveType: String { projectType.wrappedValue }

    private var selectedNode: FeeNode? { findFeeNode(feeTree, selectedId) }

    private var rows: [FeeRow] {
        feeRowsForNode(selectedId, profile: profile, result: result, projectType: effectiveType)
    }

    private func rateBinding(_ row: FeeRow, field: String) -> Binding<Double?> {
        Binding(
            get: { row.rate },
            set: { v in onRateChange(row.key, field, v) }
        )
    }
}

/// 左树节点（递归）。
struct FeeTreeNodeView: View {
    var node: FeeNode
    var depth: Int
    @Binding var selectedId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                selectedId = node.id
            } label: {
                HStack {
                    Text(node.kind == .group ? "▸ " : "· ")
                    Text(node.label)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(selectedId == node.id ? .accentColor : .primary)
            .fontWeight(selectedId == node.id ? .semibold : .regular)
            .padding(.leading, CGFloat(depth) * 16)
            if let children = node.children {
                ForEach(children) { child in
                    FeeTreeNodeView(node: child, depth: depth + 1, selectedId: $selectedId)
                }
            }
        }
    }
}
#endif
