#if os(macOS)
import SwiftUI

/// 当前工程 · 表五：完整表格，列：费用名称 / 计算基数 / 费率 / 金额 / 公式 / 启用勾选。
/// 金额取 result.table5；手动项可覆盖（table5Overrides.amount）。
struct Table5View: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("表五 · 工程建设其他费").font(.headline)
            if let result = appState.calcResult(for: project) {
                let rows = buildTable5ViewRows(profile: appState.projectProfile,
                                               project: project, result: result)
                Table(rows) {
                    TableColumn("费用名称") { r in Text(r.name) }
                    TableColumn("计算基数") { r in
                        Text(table5BasisLabels[r.basis] ?? r.basis).foregroundColor(.secondary)
                    }
                    TableColumn("费率") { r in Text(ratePercentText(r.rate)) }
                    TableColumn("金额（元）") { r in
                        if r.basis == "manual" {
                            OptionalDoubleField(label: "", value: amountBinding(r.key))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)
                        } else {
                            MoneyText(value: r.amount)
                        }
                    }
                    TableColumn("公式") { r in Text(r.formula).foregroundColor(.secondary) }
                    TableColumn("启用") { r in
                        Toggle("", isOn: enabledBinding(r.key))
                            .labelsHidden()
                    }
                }
                .tableStyle(.inset)
                Text("总计（除税）\(money(result.table5.totalExcl)) · 增值税 \(money(result.table5.totalVat)) · 含税 \(money(result.table5.totalIncl))")
                    .foregroundColor(.secondary)
            } else {
                Text("计算失败。").foregroundColor(.secondary)
            }
        }
    }

    private func amountBinding(_ key: String) -> Binding<Double?> {
        Binding(
            get: { project.table5Overrides.first { $0.key == key }.flatMap { $0.amount } },
            set: { v in appState.updateProject(project.id) { p in
                if let i = p.table5Overrides.firstIndex(where: { $0.key == key }) {
                    p.table5Overrides[i].amount = v
                } else {
                    p.table5Overrides.append(Table5Override(key: key, enabled: nil, amount: v))
                }
            } }
        )
    }

    private func enabledBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { project.table5Overrides.first { $0.key == key }?.enabled ?? true },
            set: { v in appState.updateProject(project.id) { p in
                if let i = p.table5Overrides.firstIndex(where: { $0.key == key }) {
                    p.table5Overrides[i].enabled = v
                } else {
                    p.table5Overrides.append(Table5Override(key: key, enabled: v, amount: nil))
                }
            } }
        )
    }
}
#endif
