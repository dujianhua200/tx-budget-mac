#if os(macOS)
import SwiftUI

/// 工作量（一处录入，v2.0.0）：左 = 工程量清单（ProTable），右 = 自动生成结果预览标签。
/// 用户只做“录工程量”一个动作：表三甲/乙/丙、材料汇总、安装设备全部由引擎自动联动，
/// 预览与导出同源同值（docs/v2-ui-design.md §3）。
struct WorkloadView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord
    @State private var previewTab = "3a"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "工作量",
                       subtitle: "录入工程量后，表三甲 / 表三乙 / 表三丙 / 材料汇总自动生成（与导出一致）")
            statsStrip
            QuotaAddBar(project: project)
            warningBanners
            HSplitView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("工程量清单（\(project.quantities.count) 行）")
                        .font(.headline)
                    ProTable(
                        columns: quantityColumns,
                        rows: quantityDicts,
                        onCommit: commitQuantity,
                        onDelete: { ids in
                            appState.updateProject(project.id) { p in
                                p.quantities.removeAll { $0.id.map { ids.contains($0) } ?? false }
                            }
                        },
                        readOnlyKeys: ["quota", "variant", "unit", "status"],
                        totalsKeys: [],
                        emptyTitle: "尚未录入工程量",
                        emptyMessage: "在上方搜索定额编号或名称，输数量后回车添加第一行。",
                        columnWidths: ["quota": 104, "variant": 200, "unit": 52, "status": 92]
                    )
                }
                .frame(minWidth: 440)
                previewPane
                    .frame(minWidth: 380)
            }
        }
        .padding(Theme.pagePadding)
    }

    // MARK: - 顶部统计条

    private var statsStrip: some View {
        HStack(spacing: 22) {
            statItem("建安费（除税）", money(result?.table2After.exclTax) + " 元")
            statItem("建安费（含税）", money(result?.table2After.inclTax) + " 元")
            statItem("总造价（含税）", money(result?.table1.grandIncl) + " 元")
            statItem("工日 技/普", "\(num2(result?.techDays)) / \(num2(result?.laborDays))")
            Spacer()
        }
        .font(.callout)
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundColor(.secondary)
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
    }

    // MARK: - 警告条（孤儿行 / 无效行，与校验中心同源：result.warnings）

    @ViewBuilder
    private var warningBanners: some View {
        if let warn = orphanWarning, !dismissed.contains("orphanQty"), orphanCount > 0 {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(warn.message).foregroundColor(.orange)
                Button("删除孤儿行") { deleteOrphans() }
                Button("忽略") { dismissWarning("orphanQty") }
                Spacer()
            }.font(.caption)
        }
        if let warn = invalidWarning, !dismissed.contains("invalidQty") {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(warn.message).foregroundColor(.orange)
                Button("忽略") { dismissWarning("invalidQty") }
                Spacer()
            }.font(.caption)
        }
    }

    // MARK: - 右侧预览

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("自动生成预览").font(.headline)
                Spacer()
                Picker("", selection: $previewTab) {
                    Text("表三甲").tag("3a")
                    Text("表三乙").tag("3b")
                    Text("表三丙").tag("3c")
                    Text("材料汇总").tag("mat")
                    Text("安装设备").tag("equip")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 340)
            }
            switch previewTab {
            case "3a":
                ProTable(
                    columns: table3AColumns,
                    rows: table3ADicts,
                    readOnly: true,
                    totalsKeys: ["tech", "labor"],
                    emptyTitle: "暂无表三甲数据",
                    emptyMessage: "录入工程量后自动生成。",
                    columnWidths: ["code": 100, "name": 190, "unit": 50]
                )
            case "3b":
                WorkloadMachinesView(project: project)
            case "3c":
                WorkloadInstrumentsView(project: project)
            case "mat":
                WorkloadMaterialsView(project: project)
            default:
                WorkloadEquipView(project: project)
            }
        }
    }

    // MARK: - 派生数据

    private var result: CalcResult? { appState.calcResult(for: project) }

    private var libraries: LibrarySet {
        appState.projectProfile?.libraries ?? LibrarySet()
    }

    private var dismissed: [String] { project.warningsDismissed }

    private var orphanIds: Set<String> {
        Set((result?.warnings ?? []).filter { $0.code == "orphanQty" }.flatMap { $0.rowIds ?? [] })
    }

    private var invalidIds: Set<String> {
        Set((result?.warnings ?? []).filter { $0.code == "invalidQty" }.flatMap { $0.rowIds ?? [] })
    }

    private var orphanWarning: CalcWarning? {
        result?.warnings.first { $0.code == "orphanQty" }
    }

    private var invalidWarning: CalcWarning? {
        result?.warnings.first { $0.code == "invalidQty" }
    }

    private var orphanCount: Int { orphanIds.count }

    private var duplicateCodes: Set<String> {
        var seen = Set<String>()
        var dup = Set<String>()
        for q in libraries.quotas {
            if seen.contains(q.code) { dup.insert(q.code) } else { seen.insert(q.code) }
        }
        return dup
    }

    private var quantityColumns: [LibraryColumn] {
        [
            LibraryColumn(key: "quota", label: "定额编号", kind: .text),
            LibraryColumn(key: "variant", label: "项目名称", kind: .text),
            LibraryColumn(key: "unit", label: "单位", kind: .text),
            LibraryColumn(key: "qty", label: "数量", kind: .number),
            LibraryColumn(key: "coef", label: "系数", kind: .number),
            LibraryColumn(key: "status", label: "状态", kind: .text),
        ]
    }

    private var quantityDicts: [[String: String]] {
        project.quantities.map { row in
            let status = quantityRowStatus(row, orphanIds: orphanIds, invalidIds: invalidIds,
                                           duplicateCodes: duplicateCodes)
            return [
                "id": row.id ?? "",
                "quota": row.quota,
                "variant": row.variant ?? "",
                "unit": row.unit ?? "",
                "qty": row.qty.map { jsNumberString($0) } ?? "",
                "coef": row.coef.map { jsNumberString($0) } ?? "",
                "status": quantityRowStatusText(status),
            ]
        }
    }

    private var table3AColumns: [LibraryColumn] {
        [
            LibraryColumn(key: "code", label: "定额编号", kind: .text),
            LibraryColumn(key: "name", label: "项目名称", kind: .text),
            LibraryColumn(key: "unit", label: "单位", kind: .text),
            LibraryColumn(key: "qty", label: "数量", kind: .number),
            LibraryColumn(key: "tech", label: "技工工日", kind: .number),
            LibraryColumn(key: "labor", label: "普工工日", kind: .number),
        ]
    }

    private var table3ADicts: [[String: String]] {
        (result?.table3A ?? []).enumerated().map { i, r in
            [
                "id": "t3a-\(i)",
                "code": r.code,
                "name": r.name,
                "unit": r.unit,
                "qty": jsNumberString(r.qty),
                "tech": jsNumberString(r.tech),
                "labor": jsNumberString(r.labor),
            ]
        }
    }

    // MARK: - 操作

    private func commitQuantity(id: String, dict: [String: String]) {
        appState.updateProject(project.id) { p in
            guard let i = p.quantities.firstIndex(where: { $0.id == id }) else { return }
            if let v = Double((dict["qty"] ?? "").trimmingCharacters(in: .whitespaces)) {
                p.quantities[i].qty = v
            }
            if let v = Double((dict["coef"] ?? "").trimmingCharacters(in: .whitespaces)) {
                p.quantities[i].coef = v
            }
        }
    }

    private func deleteOrphans() {
        appState.updateProject(project.id) { p in
            p.quantities.removeAll { $0.id.map { orphanIds.contains($0) } ?? false }
        }
    }

    private func dismissWarning(_ code: String) {
        appState.updateProject(project.id) { p in
            if !p.warningsDismissed.contains(code) { p.warningsDismissed.append(code) }
        }
    }
}

/// 定额添加栏：输编号/名称联想（短单在前、全库在后）→ 选定 → 输数量 → 回车添加。
struct QuotaAddBar: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    @State private var keyword = ""
    @State private var picked: QuotaRow?
    @State private var addQty = ""
    @State private var showSuggestions = false
    @FocusState private var keywordFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill").foregroundColor(Theme.accent)
            TextField("输入定额编号 / 项目名称，回车选第一条…", text: $keyword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
                .focused($keywordFocused)
                .onChange(of: keyword) { _ in
                    if picked != nil, keyword != picked?.code { picked = nil }
                    showSuggestions = !keyword.trimmingCharacters(in: .whitespaces).isEmpty
                }
                .onSubmit {
                    if let first = suggestions.first {
                        picked = first
                        keyword = first.code
                        showSuggestions = false
                    }
                }
                .popover(isPresented: $showSuggestions, arrowEdge: .bottom) {
                    suggestionsList
                }
            TextField("数量，回车添加", text: $addQty)
                .textFieldStyle(.roundedBorder)
                .frame(width: 130)
                .onSubmit { doAdd() }
            Button("添加") { doAdd() }
                .buttonStyle(.borderedProminent)
                .disabled(picked == nil)
            Text("选定额 → 输数量 → 回车添加；表内双击数量/系数可改。")
                .foregroundColor(.secondary).font(.caption)
            Spacer()
        }
    }

    private var libraries: LibrarySet {
        appState.projectProfile?.libraries ?? LibrarySet()
    }

    private var suggestions: [QuotaRow] {
        quotaSuggestions(libraries, keyword)
    }

    private var suggestionsList: some View {
        List(suggestions, id: \.id) { s in
            Button {
                picked = s
                keyword = s.code
                showSuggestions = false
            } label: {
                HStack {
                    Text(s.code).fontWeight(.semibold)
                    Text(s.name)
                    Text(s.unit).foregroundColor(.secondary)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .frame(width: 380, height: min(CGFloat(suggestions.count) * 28 + 10, 300))
    }

    private func doAdd() {
        guard let picked else { return }
        let qty = Double(addQty.trimmingCharacters(in: .whitespaces)) ?? 0
        appState.updateProject(project.id) { p in
            p.quantities.append(QuantityRow(id: newUID(), quota: picked.code, variant: picked.name,
                                            unit: picked.unit, qty: qty, coef: picked.coef ?? 1))
        }
        keyword = ""
        self.picked = nil
        addQty = ""
        keywordFocused = true
    }
}

/// 全局定额搜索（工具栏）：按当前工程方案的库搜索；选中 + 输数量 → 加入工程量并跳工作量页。
/// 未打开工程时仅供浏览（加入按钮禁用）。
struct QuotaPickerSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var keyword = ""
    @State private var picked: QuotaRow?
    @State private var qtyText = "1"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("定额搜索").font(.title3).fontWeight(.bold)
            Text(appState.openProject == nil
                 ? "未打开工程：仅浏览定额库（编辑目标方案）。打开工程后可直接加入工程量。"
                 : "工程“\(appState.openProject?.name ?? "")”· 方案“\(appState.projectProfile?.name ?? "—")”的定额库")
                .font(.caption).foregroundColor(.secondary)
            TextField("输入定额编号 / 项目名称…", text: $keyword)
                .textFieldStyle(.roundedBorder)
                .onSubmit { if let first = suggestions.first { picked = first } }
            List(suggestions, id: \.id) { s in
                Button {
                    picked = s
                } label: {
                    HStack {
                        Text(s.code).fontWeight(.semibold)
                        Text(s.name)
                        Text(s.unit).foregroundColor(.secondary)
                        Spacer()
                        if picked?.id == s.id {
                            Image(systemName: "checkmark").foregroundColor(Theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 240)
            HStack(spacing: 8) {
                Text("数量")
                TextField("数量", text: $qtyText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Spacer()
                Button("关闭") { dismiss() }
                Button("加入工程量") { addPicked() }
                    .buttonStyle(.borderedProminent)
                    .disabled(picked == nil || appState.openProject == nil)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var libraries: LibrarySet {
        (appState.openProject != nil ? appState.projectProfile : appState.editingProfile)?.libraries
            ?? LibrarySet()
    }

    private var suggestions: [QuotaRow] {
        quotaSuggestions(libraries, keyword)
    }

    private func addPicked() {
        guard let picked, let project = appState.openProject else { return }
        let qty = Double(qtyText.trimmingCharacters(in: .whitespaces)) ?? 1
        appState.updateProject(project.id) { p in
            p.quantities.append(QuantityRow(id: newUID(), quota: picked.code, variant: picked.name,
                                            unit: picked.unit, qty: qty, coef: picked.coef ?? 1))
        }
        appState.nav = .workload
        appState.showToast("已加入工程量：\(picked.code) × \(jsNumberString(qty))")
        dismiss()
    }
}
#endif
