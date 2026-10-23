#if os(macOS)
import SwiftUI

/// 工作量 · 表四材料（v2.6.0 重做，docs/v2.6-batch-design.md §5）：表四甲（甲供）/
/// 表四乙（乙供）两组平铺清单 + 备选材料勾选。列序照宇翔表四甲：
/// 代号 / 材料名称 / 规格程式 / 单位 / 数量 / 除税价格 / 材料金额 / 类型 / 类别 / 备注。
///
/// 旧版用 SwiftUI Table 嵌在 ScrollView 里，高度塌陷——用户在表四看不到生成主材；
/// 本版改用 ProTable（自带行高与滚动），生成行确实可见。全表可编辑（材料金额 =
/// 数量 × 除税价格自动算，只读），行可插入/追加/删除/上下移动；改动落本工程级
/// 材料层（生成行覆盖 materialEdits + 既有 materialAdjust/materialPriceOverrides +
/// 手工行 manualMaterials + 行序 materialOrder），引擎取费/表一/导出消费生效表四，
/// 不回写资料库。改关联本身（哪条定额用什么材料）仍在表三甲底部关联区。
struct WorkloadMaterialsView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("本工程生效材料表：由定额关联自动生成，本页可直接改——除材料金额（数量 × 除税价格自动算）外全字段可改，行可增删、可上下移动；改动只影响本工程，不回写资料库。改关联本身请去表三甲底部关联区。")
                .foregroundColor(.secondary).font(.caption)
            if let result = appState.calcResult(for: project) {
                let keys = [result.table4A.rows.map { $0.key },
                            result.table4B.rows.map { $0.key },
                            result.table4Equip.rows.map { $0.key }]
                EffectiveMatTable(title: "甲供材料（表四甲）", tableId: "table4a",
                                  table: result.table4A, supplyGroup: "甲供",
                                  project: project, tablesKeysInOrder: keys)
                    .frame(maxHeight: .infinity)
                EffectiveMatTable(title: "乙供材料（表四乙）", tableId: "table4b",
                                  table: result.table4B, supplyGroup: "乙供",
                                  project: project, tablesKeysInOrder: keys)
                    .frame(maxHeight: .infinity)
                alternateRulesView(result: result)
            } else {
                Text("计算失败。").foregroundColor(.secondary)
            }
        }
    }

    private func alternateRulesView(result: CalcResult) -> some View {
        let libs = appState.projectProfile?.libraries ?? LibrarySet()
        let alts = libs.rules.filter { $0.kind == "备选" }
        return VStack(alignment: .leading, spacing: 8) {
            Text("备选材料（默认不计，勾选后按变体精确匹配计入）").font(.headline)
            if alts.isEmpty {
                Text("当前方案没有备选材料规则。").font(.caption).foregroundColor(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(alts, id: \.id) { r in
                            HStack(spacing: 10) {
                                Text(r.quota).frame(width: 92, alignment: .leading)
                                    .monospacedDigit()
                                Text(r.variant).frame(minWidth: 140, alignment: .leading)
                                Text(r.material).frame(minWidth: 120, alignment: .leading)
                                Text(r.spec).frame(width: 110, alignment: .leading)
                                    .foregroundColor(.secondary)
                                Text("单位消耗量 \(num2(r.consumption))")
                                    .foregroundColor(.secondary).monospacedDigit()
                                Spacer()
                                Toggle("启用", isOn: ruleEnabledBinding(r))
                                    .toggleStyle(.switch).controlSize(.small)
                            }
                            .font(.caption)
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 150)
            }
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

/// 工作量 · 安装设备（表四甲设备组，supply = 设备）。
struct WorkloadEquipView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("表四甲中的设备组（类型 = 设备），与表四材料同源生成；本页同样可直接改本工程字段、增删行、调顺序，只影响本工程。")
                .foregroundColor(.secondary).font(.caption)
            if let result = appState.calcResult(for: project) {
                let keys = [result.table4A.rows.map { $0.key },
                            result.table4B.rows.map { $0.key },
                            result.table4Equip.rows.map { $0.key }]
                EffectiveMatTable(title: "安装设备（表四甲 · 设备）", tableId: "table4equip",
                                  table: result.table4Equip, supplyGroup: "设备",
                                  project: project, tablesKeysInOrder: keys)
                    .frame(maxHeight: .infinity)
            } else {
                Text("计算失败。").foregroundColor(.secondary)
            }
        }
    }
}

/// 生效材料表（ProTable 平铺）：一组（甲供/乙供/设备）一行一材料。
/// 写回规则（v2.6.0 §5）：手工行直接改 manualMaterials；生成行——数量改走
/// materialAdjust（增量 = 新量 − 自动量）、除税价改走 materialPriceOverrides、
/// 其余字段（代号/名称/规格/单位/类型/类别/备注）只把与当前生效值不同的写入
/// materialEdits 覆盖（按身份键，后写覆盖先写；改名不改键）。
struct EffectiveMatTable: View {
    @EnvironmentObject private var appState: AppState
    var title: String
    var tableId: String
    var table: Table4Result
    var supplyGroup: String
    var project: ProjectRecord
    var tablesKeysInOrder: [[String]]

    private var columns: [LibraryColumn] {
        [
            LibraryColumn(key: "code", label: "代号", kind: .text),
            LibraryColumn(key: "name", label: "材料名称", kind: .text),
            LibraryColumn(key: "spec", label: "规格程式", kind: .text),
            LibraryColumn(key: "unit", label: "单位", kind: .text),
            LibraryColumn(key: "qty", label: "数量", kind: .number),
            LibraryColumn(key: "priceExcl", label: "除税价格", kind: .number),
            LibraryColumn(key: "amount", label: "材料金额", kind: .number),
            LibraryColumn(key: "supply", label: "类型", kind: .select,
                          options: ["甲供", "乙供", "设备"]),
            LibraryColumn(key: "category", label: "类别", kind: .text),
            LibraryColumn(key: "remark", label: "备注", kind: .text),
        ]
    }

    private var rowDicts: [[String: String]] {
        table.rows.map { r in
            [
                "id": r.key,
                "code": r.code,
                "name": r.name,
                // 未建档生成行在备注位提示（写回时 commit 对此显示值做了防污染处理）。
                "spec": r.spec,
                "unit": r.unit,
                "qty": jsNumberString(r.qty),
                "priceExcl": jsNumberString(r.priceExcl),
                "amount": money(r.amtExcl),
                "supply": r.supply,
                "category": r.category,
                "remark": r.unmatched && r.remark.isEmpty ? "未建档" : r.remark,
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(title)（合计除税 \(money(table.totalExcl))，增值税 \(money(table.totalVat))，含税 \(money(table.totalIncl))）")
                .font(.headline)
            ProTable(
                columns: columns,
                rows: rowDicts,
                onCommit: commitRow,
                onAdd: addRow,
                onDelete: deleteRows,
                onMoveRow: { id, delta in moveRow(id: id, delta: delta) },
                tableId: tableId,
                flexibleKey: "name",
                flexibleMinWidth: 200,
                readOnlyKeys: ["amount"],
                totalsKeys: [],
                emptyTitle: "无材料",
                emptyMessage: "本组暂无材料行；点右上“新增行”可手工添加一行本工程材料。",
                columnWidths: ["code": 76, "name": 200, "spec": 110, "unit": 52,
                               "qty": 84, "priceExcl": 92, "amount": 96,
                               "supply": 64, "category": 76, "remark": 110]
            )
        }
    }

    // MARK: - 写回

    private func commitRow(id: String, dict: [String: String]) {
        guard let baseline = table.rows.first(where: { $0.key == id }) else { return }
        appState.updateProject(project.id) { p in
            if baseline.isManual {
                guard let i = p.manualMaterials.firstIndex(where: { $0.id == id }) else { return }
                var m = p.manualMaterials[i]
                if let v = dict["code"] { m.code = v }
                if let v = dict["name"] { m.name = v }
                if let v = dict["spec"] { m.spec = v }
                if let v = dict["unit"] { m.unit = v }
                if let v = dict["qty"], let n = Double(v.trimmingCharacters(in: .whitespaces)) { m.qty = n }
                if let v = dict["priceExcl"], let n = Double(v.trimmingCharacters(in: .whitespaces)) { m.priceExcl = n }
                if let v = dict["supply"], ["甲供", "乙供", "设备"].contains(v) { m.supply = v }
                if let v = dict["category"] { m.category = v }
                if let v = dict["remark"] { m.remark = v }
                p.manualMaterials[i] = m
                return
            }
            // 生成行：数量 → 增量调整；单价 → 本工程单价（仅在确实改动时落记录）。
            if let v = dict["qty"], let n = Double(v.trimmingCharacters(in: .whitespaces)),
               abs(n - baseline.qty) > 1e-9 {
                let delta = n - baseline.autoQty
                if let i = p.materialAdjust.firstIndex(where: { $0.key == id }) {
                    p.materialAdjust[i].delta = delta
                } else {
                    p.materialAdjust.append(MaterialAdjust(key: id, delta: delta))
                }
            }
            if let v = dict["priceExcl"], let n = Double(v.trimmingCharacters(in: .whitespaces)),
               abs(n - baseline.priceExcl) > 1e-9 {
                if let i = p.materialPriceOverrides.firstIndex(where: { $0.key == id }) {
                    p.materialPriceOverrides[i].priceExcl = n
                } else {
                    p.materialPriceOverrides.append(MaterialPriceOverride(key: id, priceExcl: n))
                }
            }
            // 其余字段 → 工程级覆盖（只记与生效值不同的字段，避免普通编辑冻结库值）。
            var edit = p.materialEdits.first { $0.key == id } ?? MaterialRowEdit(key: id)
            var touched = p.materialEdits.contains { $0.key == id }
            func apply(_ dictKey: String, _ baselineValue: String, _ set: (inout MaterialRowEdit, String) -> Void) {
                guard let v = dict[dictKey], v != baselineValue else { return }
                set(&edit, v)
                touched = true
            }
            apply("code", baseline.code) { $0.code = $1 }
            apply("name", baseline.name) { $0.name = $1 }
            apply("spec", baseline.spec) { $0.spec = $1 }
            apply("unit", baseline.unit) { $0.unit = $1 }
            apply("supply", baseline.supply) { $0.supply = $1 }
            apply("category", baseline.category) { $0.category = $1 }
            // 备注基线用引擎原值（未建档行的显示“未建档”不是数据，不写回）。
            apply("remark", baseline.remark) { $0.remark = $1 }
            if touched {
                if let i = p.materialEdits.firstIndex(where: { $0.key == id }) {
                    p.materialEdits[i] = edit
                } else {
                    p.materialEdits.append(edit)
                }
            }
        }
    }

    private func addRow() {
        appState.updateProject(project.id) { p in
            p.manualMaterials.append(ManualMaterialRow(id: newUID(), supply: supplyGroup))
        }
    }

    private func deleteRows(ids: Set<String>) {
        appState.updateProject(project.id) { p in
            for id in ids {
                if p.manualMaterials.contains(where: { $0.id == id }) {
                    p.manualMaterials.removeAll { $0.id == id }
                } else {
                    // 生成行：工程级删除标记（数据仍在库里，其他工程不受影响）。
                    if let i = p.materialEdits.firstIndex(where: { $0.key == id }) {
                        p.materialEdits[i].deleted = true
                    } else {
                        p.materialEdits.append(MaterialRowEdit(key: id, deleted: true))
                    }
                }
            }
        }
    }

    private func moveRow(id: String, delta: Int) {
        appState.updateProject(project.id) { p in
            p.materialOrder = movedMaterialOrder(currentOrder: p.materialOrder,
                                                 tablesKeysInOrder: tablesKeysInOrder,
                                                 movingKey: id, delta: delta)
        }
    }
}
#endif
