#if os(macOS)
import SwiftUI

/// 工作量 · 材料汇总（表四甲：甲供 / 乙供 / 设备三组）+ 备选材料勾选。
/// 数量 = 自动计算 ＋ 手动调整；单价为本工程单价（改这里只影响本工程）。
struct WorkloadMaterialsView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("数量 = 自动计算 ＋ 手动调整；单价为本工程单价（改这里只影响本工程，到“基础库 → 材料库”改全局默认价）。备选材料默认不计，在下方勾选启用。")
                    .foregroundColor(.secondary).font(.caption)
                if let result = appState.calcResult(for: project) {
                    MatTableView(title: "甲供主材（表四甲）", table: result.table4A, project: project)
                    MatTableView(title: "乙供主材（表四乙）", table: result.table4B, project: project)
                    MatTableView(title: "设备（表四甲设备）", table: result.table4Equip, project: project)
                    alternateRulesView(result: result)
                } else {
                    Text("计算失败。").foregroundColor(.secondary)
                }
            }
        }
    }

    private func alternateRulesView(result: CalcResult) -> some View {
        let libs = appState.projectProfile?.libraries ?? LibrarySet()
        let alts = libs.rules.filter { $0.kind == "备选" }
        return VStack(alignment: .leading, spacing: 8) {
            Text("备选材料（默认不计，勾选后按变体精确匹配计入）").font(.headline)
            Table(alts, id: \.id) {
                TableColumn("定额编号") { r in Text(r.quota) }
                TableColumn("变体项目名称") { r in Text(r.variant) }
                TableColumn("材料") { r in Text(r.material) }
                TableColumn("规格") { r in Text(r.spec) }
                TableColumn("单位消耗量") { r in Num2Text(value: r.consumption) }
                TableColumn("启用") { r in
                    Toggle("", isOn: ruleEnabledBinding(r))
                        .labelsHidden()
                }
            }
            .tableStyle(.inset)
        }
    }

    private func ruleEnabledBinding(_ rule: RuleRow) -> Binding<Bool> {
        Binding(
            get: { project.ruleOverrides.first { $0.ruleId == rule.id }?.enabled ?? false },
            set: { v in appState.updateProject(project.id) { p in
                if let i = p.ruleOverrides.firstIndex(where: { $0.ruleId == rule.id }) {
                    p.ruleOverrides[i].enabled = v
                } else {
                    p.ruleOverrides.append(RuleOverride(ruleId: rule.id, enabled: v))
                }
            } }
        )
    }
}

/// 工作量 · 安装设备（表四甲：supply = '设备' 子集，即 table4Equip，不新增字段）。
struct WorkloadEquipView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("仅显示 supply = “设备” 的材料行（即表四甲设备组），不新增字段。")
                    .foregroundColor(.secondary).font(.caption)
                if let result = appState.calcResult(for: project) {
                    MatTableView(title: "安装设备（表四甲 · 设备）", table: result.table4Equip, project: project)
                } else {
                    Text("计算失败。").foregroundColor(.secondary)
                }
            }
        }
    }
}

/// 材料表（表四甲结构，复用于材料汇总三组 / 安装设备子集）。
/// 列：名称 / 规格 / 单位 / 自动数量 / 手动调整 / 数量 / 除税单价 / 增值税/单位 / 含税单价 / 除税合计 / 增值税合计。
struct MatTableView: View {
    @EnvironmentObject private var appState: AppState
    var title: String
    var table: Table4Result
    var project: ProjectRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title)（合计除税 \(money(table.totalExcl))，增值税 \(money(table.totalVat))，含税 \(money(table.totalIncl))）")
                .font(.headline)
            Table(table.rows, id: \.key) {
                TableColumn("名称") { r in Text(r.name + (r.unmatched ? "（未建档）" : "")) }
                TableColumn("规格") { r in Text(r.spec) }
                TableColumn("单位") { r in Text(r.unit) }
                TableColumn("自动数量") { r in Num2Text(value: r.autoQty) }
                TableColumn("手动调整") { r in
                    DoubleField(label: "", value: deltaBinding(r.key))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                }
                TableColumn("数量") { r in Num2Text(value: r.qty) }
                TableColumn("除税单价") { r in
                    DoubleField(label: "", value: priceBinding(r.key, defaultValue: r.priceExcl))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }
                TableColumn("增值税/单位") { r in MoneyText(value: r.priceVat) }
                TableColumn("含税单价") { r in MoneyText(value: r.priceIncl) }
                TableColumn("除税合计") { r in MoneyText(value: r.amtExcl) }
                TableColumn("增值税合计") { r in MoneyText(value: r.amtVat) }
            }
            .tableStyle(.inset)
            if table.rows.isEmpty {
                Text("无材料。").foregroundColor(.secondary)
            }
        }
    }

    private func deltaBinding(_ key: String) -> Binding<Double> {
        Binding(
            get: { project.materialAdjust.first { $0.key == key }?.delta ?? 0 },
            set: { v in appState.updateProject(project.id) { p in
                if let i = p.materialAdjust.firstIndex(where: { $0.key == key }) {
                    p.materialAdjust[i].delta = v
                } else {
                    p.materialAdjust.append(MaterialAdjust(key: key, delta: v))
                }
            } }
        )
    }

    private func priceBinding(_ key: String, defaultValue: Double) -> Binding<Double> {
        Binding(
            get: { project.materialPriceOverrides.first { $0.key == key }?.priceExcl ?? defaultValue },
            set: { v in appState.updateProject(project.id) { p in
                if let i = p.materialPriceOverrides.firstIndex(where: { $0.key == key }) {
                    p.materialPriceOverrides[i].priceExcl = v
                } else {
                    p.materialPriceOverrides.append(MaterialPriceOverride(key: key, priceExcl: v))
                }
            } }
        )
    }
}
#endif
