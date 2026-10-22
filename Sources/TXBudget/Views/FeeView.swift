#if os(macOS)
import SwiftUI

/// 费用（v2.0.0）：表一总表预览 / 表二取费 / 表五其他费 三标签。
/// 表二折前 = 左树 + 右表（费率可编辑，写回资料库当前方案，同 v1）；
/// 表二折后 = 同结构只读（金额取 table2After，计算式为折前口径，页面已注明）。
struct FeesView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord
    @State private var tab = "t1"
    @State private var t2Mode = "before"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "费用",
                       subtitle: "表一总表 · 表二取费 · 表五其他费，均与导出同源同值")
            Picker("", selection: $tab) {
                Text("表一 · 总表").tag("t1")
                Text("表二 · 取费").tag("t2")
                Text("表五 · 其他费").tag("t5")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 360)
            switch tab {
            case "t1":
                table1Preview
            case "t2":
                table2Tab
            default:
                Table5ContentView(project: project)
            }
        }
        .padding(Theme.pagePadding)
    }

    // MARK: - 表一（报表式预览）

    private var table1Preview: some View {
        Group {
            if let r = appState.calcResult(for: project) {
                SectionCard(title: "工程总表（表一）", subtitle: "金额单位：元；与导出表一同源同值") {
                    VStack(spacing: 0) {
                        reportRow("建筑安装工程费（除税，折前）", r.table1.beforeDiscount, level: 0)
                        reportRow("建筑安装工程费（除税，折后）", r.table1.afterDiscount, level: 0)
                        reportRow("增值税（折后）", r.table1.taxAfter, level: 1)
                        reportRow("建筑安装工程费（含税，折后）", r.table1.totalAfter, level: 0, bold: true)
                        Divider().padding(.vertical, 4)
                        reportRow("需要安装的设备费（除税）", r.table1.equipFee, level: 0)
                        reportRow("设备增值税", r.table1.equipVat, level: 1)
                        reportRow("设备费（含税）", r.table1.equipIncl, level: 0, bold: true)
                        Divider().padding(.vertical, 4)
                        reportRow("工程建设其他费（除税）", r.table1.otherFee, level: 0)
                        reportRow("其他费增值税", r.table1.otherVat, level: 1)
                        reportRow("工程建设其他费（含税）", r.table1.otherIncl, level: 0, bold: true)
                        Divider().padding(.vertical, 4)
                        HStack {
                            Text("工程总费用（含税）").font(.headline)
                            Spacer()
                            Text(money(r.table1.grandIncl))
                                .font(.title3).fontWeight(.bold).monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else {
                Text("计算失败。").foregroundColor(.secondary)
            }
        }
    }

    private func reportRow(_ label: String, _ amount: Double, level: Int, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .fontWeight(bold ? .semibold : .regular)
                .padding(.leading, CGFloat(level) * 22)
            Spacer()
            Text(money(amount))
                .fontWeight(bold ? .semibold : .regular)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
    }

    // MARK: - 表二（折前可编辑 / 折后只读）

    private var table2Tab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker("", selection: $t2Mode) {
                    Text("折前").tag("before")
                    Text("折后").tag("after")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                Text(t2Mode == "before"
                     ? "费率将写入资料库方案“\(appState.editingProfile?.name ?? "—")”；金额为折前表二。"
                     : "折后金额由折前按打折规则计算（只读）；计算式列为折前口径。费率编辑请切回折前。")
                    .foregroundColor(.secondary).font(.caption)
            }
            if t2Mode == "before" {
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
            } else {
                FeeTreeTableView(
                    profile: appState.editingProfile,
                    result: afterResult,
                    projectType: .constant(project.info.工程类型),
                    showProjectTypePicker: false,
                    ratesEditable: false,
                    onRateChange: { _, _, _ in }
                )
            }
        }
    }

    /// 折后展示：把 table2After 换进 table2Before 的位置喂给既有 feeRowsForNode
    /// （该函数固定读 table2Before）；引擎本身不动，口径不变。
    private var afterResult: CalcResult? {
        guard var r = appState.calcResult(for: project) else { return nil }
        r.table2Before = r.table2After
        return r
    }
}

/// 取费左树 + 右表复用组件（当前工程·费用 / 取费规则·费率 共用）。
struct FeeTreeTableView: View {
    var profile: ConfigurationProfile?
    var result: CalcResult?
    var projectType: Binding<String>
    var showProjectTypePicker: Bool
    /// 费率是否可编辑（表二折后只读模式为 false，费率列显示数值）。
    var ratesEditable: Bool = true
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
                    Text("\(selectedNode?.label ?? "")（\(rows.count) 项，金额为\(ratesEditable ? "折前" : "折后")）")
                        .font(.headline)
                    Table(rows) {
                        TableColumn("费用名称") { r in Text(r.name) }
                        TableColumn("计算基数") { r in Text(r.base).foregroundColor(.secondary) }
                        TableColumn("费率") { r in
                            if ratesEditable, let field = r.rateField {
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
