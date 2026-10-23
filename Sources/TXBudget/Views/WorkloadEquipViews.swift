#if os(macOS)
import SwiftUI

/// 工作量 · 机械（表三乙）：由定额—机械关联自动汇总。
struct WorkloadMachinesView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result = appState.calcResult(for: project) {
                Text("表三乙 · 机械（合计 \(money(result.table3B.total))）").font(.headline)
                Table(indexed(result.table3B.rows)) {
                    TableColumn("定额编号") { r in Text(r.row.quota) }
                    TableColumn("定额名称") { r in Text(r.row.quotaName) }
                    TableColumn("数量") { r in Num2Text(value: r.row.qty) }
                    TableColumn("机械名称") { r in Text(r.row.equipName) }
                    TableColumn("单位") { r in Text(r.row.equipUnit) }
                    TableColumn("消耗量") { r in Num2Text(value: r.row.consumption) }
                    TableColumn("单价") { r in MoneyText(value: r.row.price) }
                    TableColumn("台班数") { r in Num2Text(value: r.row.sessions) }
                    TableColumn("金额") { r in MoneyText(value: r.row.amount) }
                }
                .tableStyle(.inset)
                if result.table3B.rows.isEmpty {
                    Text("无机械费。").foregroundColor(.secondary)
                }
            } else {
                Text("计算失败。").foregroundColor(.secondary)
            }
        }
    }
}

/// 工作量 · 仪器仪表（表三丙统一大表，不拆碎）。
/// 列：定额编号 / 项目名称 / 单位 / 数量 | 仪器仪表名称 | 单位定额值 数量 / 单价 | 合计值 数量 / 合计。
struct WorkloadInstrumentsView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result = appState.calcResult(for: project) {
                Text("表三丙 · 仪器仪表（合计 \(money(result.table3C.total))）").font(.headline)
                Table(indexed(result.table3C.rows)) {
                    TableColumn("定额编号") { r in Text(r.row.quota) }
                    TableColumn("项目名称") { r in Text(r.row.quotaName) }
                    TableColumn("单位") { r in Text(r.row.unit) }
                    TableColumn("数量") { r in Num2Text(value: r.row.qty) }
                    TableColumn("仪器仪表名称") { r in Text(r.row.equipName) }
                    TableColumn("单位定额值 · 数量") { r in Num2Text(value: r.row.consumption) }
                    TableColumn("单位定额值 · 单价") { r in MoneyText(value: r.row.price) }
                    TableColumn("合计值 · 数量") { r in Num2Text(value: r.row.sessions) }
                    TableColumn("合计值 · 合计") { r in MoneyText(value: r.row.amount) }
                }
                .tableStyle(.inset)
                if result.table3C.rows.isEmpty {
                    Text("无仪表费。").foregroundColor(.secondary)
                }
            } else {
                Text("计算失败。").foregroundColor(.secondary)
            }
        }
    }
}
#endif
