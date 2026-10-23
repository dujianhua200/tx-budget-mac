#if os(macOS)
import SwiftUI

/// 工作量（v2.4.0）：顶部报表分页一排——表三甲（录入）/ 表三乙 / 表三丙 / 表四材料 / 安装设备。
/// 表三甲 = 工程量清单（唯一录入页）+ 底部关联区；其余四页为引擎自动生成的只读报表
/// （工程级修正除外，见 docs/v2.4-workload-design.md）。预览与导出同源同值。
struct WorkloadView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord
    @State private var page = "3a"
    @State private var selectedRowKey: String?
    @State private var showVariantPicker = false
    @State private var variantTarget: QuantityRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "工作量",
                       subtitle: "工作量就是表三：在表三甲录入工程量，表三乙 / 表三丙 / 表四材料自动生成；在表三甲点选一行，可在底部关联区查看并修改它要用到的主材、机械、仪器仪表")
            statsStrip
            QuotaAddBar(project: project)
            warningBanners
            Picker("", selection: $page) {
                Text("表三甲").tag("3a")
                Text("表三乙").tag("3b")
                Text("表三丙").tag("3c")
                Text("表四材料").tag("mat")
                Text("安装设备").tag("equip")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            pageContent
        }
        .padding(Theme.pagePadding)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case "3a":
            VStack(alignment: .leading, spacing: 6) {
                VSplitView {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("表三甲 · 工程量清单（\(project.quantities.count) 行）")
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
                            onSelectionChange: { ids in
                                selectedRowKey = ids.count == 1 ? ids.first : nil
                            },
                            onRowDoubleClick: handleRowDoubleClick,
                            tableId: "workload-3a",
                            flexibleKey: "variant",
                            flexibleMinWidth: 260,
                            readOnlyKeys: ["quota", "variant", "unit", "tech", "labor",
                                           "techTotal", "laborTotal", "status"],
                            totalsKeys: [],
                            emptyTitle: "尚未录入工程量",
                            emptyMessage: "在上方搜索定额编号或名称，输数量后回车添加第一行。",
                            columnWidths: ["quota": 92, "variant": 260, "unit": 56, "qty": 84,
                                           "coef": 64, "tech": 64, "labor": 64,
                                           "techTotal": 88, "laborTotal": 88, "status": 92]
                        )
                    }
                    .frame(minHeight: 180)
                    WorkloadLinksPanel(project: project, selectedRow: selectedQuantityRow)
                        .frame(minHeight: 200, idealHeight: 260)
                }
                table3ASummaryBar
            }
            .sheet(isPresented: $showVariantPicker) {
                if let target = variantTarget {
                    VariantPickerSheet(quota: target.quota,
                                       options: variantPickerOptions,
                                       current: target.variant ?? "") { picked in
                        switchVariant(of: target, to: picked)
                    }
                }
            }
        case "3b":
            VStack(alignment: .leading, spacing: 6) {
                generatedNote("数据来自定额的机械关联（定额—机械映射 × 工程量）。修改请在表三甲点选工作量后用底部关联区，或去资料库维护。")
                WorkloadMachinesView(project: project)
            }
        case "3c":
            VStack(alignment: .leading, spacing: 6) {
                generatedNote("数据来自定额的仪器仪表关联（定额—仪表映射 × 工程量）。修改请在表三甲点选工作量后用底部关联区，或去资料库维护。")
                WorkloadInstrumentsView(project: project)
            }
        case "mat":
            WorkloadMaterialsView(project: project)
        default:
            VStack(alignment: .leading, spacing: 6) {
                generatedNote("表四甲中的设备组（supply = 设备），与表四材料同源生成；改关联在表三甲底部关联区，改本工程数量/单价在本页。")
                WorkloadEquipView(project: project)
            }
        }
    }

    private func generatedNote(_ text: String) -> some View {
        Text("自动生成，只读。\(text)")
            .font(.caption).foregroundColor(.secondary)
    }

    // MARK: - 表三甲汇总条（v2.5.0 §12.1：数字一律取引擎结果）

    private var table3ASummaryBar: some View {
        HStack(spacing: 20) {
            Text("汇总").fontWeight(.bold)
            Text("总技工合计 \(num2(result?.techSub)) 工日").monospacedDigit()
            Text("总普工合计 \(num2(result?.laborSub)) 工日").monospacedDigit()
            if let r = result, r.adjRate != 0 {
                Text("含工日调整 +\(jsNumberString(r.adjRate * 100))%：调整后 技 \(num2(r.techDays)) / 普 \(num2(r.laborDays)) 工日（与导出表三甲合计行一致）")
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    // MARK: - 双击选型号（v2.5.0 §12.4）

    /// 本次弹出的型号清单：Logic 清单 + 当前行变体（不在清单内时追加，保证当前状态可见）。
    private var variantPickerOptions: [String] {
        guard let target = variantTarget else { return [] }
        var options = variantOptions(quota: target.quota, libraries: libraries)
        let current = target.variant ?? ""
        if !current.isEmpty && !options.contains(current) { options.append(current) }
        return options
    }

    private func handleRowDoubleClick(_ dictId: String) {
        guard let row = project.quantities.enumerated()
            .first(where: { quantityDictId($0.element, at: $0.offset) == dictId })?.element
        else { return }
        selectedRowKey = dictId
        var options = variantOptions(quota: row.quota, libraries: libraries)
        let current = row.variant ?? ""
        if !current.isEmpty && !options.contains(current) { options.append(current) }
        guard options.count >= 2 else {
            appState.showToast("该定额无可选型号")
            return
        }
        variantTarget = row
        showVariantPicker = true
    }

    private func switchVariant(of row: QuantityRow, to picked: String) {
        guard let id = row.id, (row.variant ?? "") != picked else { return }
        appState.updateProject(project.id) { p in
            guard let i = p.quantities.firstIndex(where: { $0.id == id }) else { return }
            p.quantities[i].variant = picked
        }
        appState.showToast("已切换型号：\(picked)")
    }

    /// 当前在清单中单选的工程量行（按清单字典 id 解析，含无 id 行的行序回退 id）。
    private var selectedQuantityRow: QuantityRow? {
        guard let key = selectedRowKey else { return nil }
        return project.quantities.enumerated()
            .first { quantityDictId($0.element, at: $0.offset) == key }?.element
    }

    private func quantityDictId(_ row: QuantityRow, at index: Int) -> String {
        row.id ?? "rowidx_\(index)"
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
            LibraryColumn(key: "tech", label: "技工", kind: .number),
            LibraryColumn(key: "labor", label: "普工", kind: .number),
            LibraryColumn(key: "techTotal", label: "技工合计", kind: .number),
            LibraryColumn(key: "laborTotal", label: "普工合计", kind: .number),
            LibraryColumn(key: "status", label: "状态", kind: .text),
        ]
    }

    private var quantityDicts: [[String: String]] {
        project.quantities.enumerated().map { i, row in
            let status = quantityRowStatus(row, orphanIds: orphanIds, invalidIds: invalidIds,
                                           duplicateCodes: duplicateCodes)
            let quota = firstQuota(code: row.quota, libraries: libraries)
            let contribution = table3ARowContribution(row: row, libraries: libraries)
            return [
                "id": quantityDictId(row, at: i),
                "quota": row.quota,
                "variant": row.variant ?? "",
                "unit": row.unit ?? "",
                "qty": row.qty.map { jsNumberString($0) } ?? "",
                "coef": row.coef.map { jsNumberString($0) } ?? "",
                "tech": quota.map { num2($0.tech) } ?? "",
                "labor": quota.map { num2($0.labor) } ?? "",
                "techTotal": quota == nil ? "" : num2(contribution.tech),
                "laborTotal": quota == nil ? "" : num2(contribution.labor),
                "status": quantityRowStatusText(status),
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
            Text("选定额 → 输数量 → 回车添加；双击数量/系数可改，双击行可选型号。")
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
/// 双击选型号（v2.5.0 §12.4）：仿宇翔“请选择”列表——变体全名列项、当前打勾、点选即切换。
struct VariantPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var quota: String
    var options: [String]
    var current: String
    var onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("请选择型号").font(.title3).fontWeight(.bold)
            Text("定额 \(quota)：切换型号只改本行项目名称，工程量与系数不变；主材规格与用量随型号重算。")
                .font(.caption).foregroundColor(.secondary)
            List(options, id: \.self) { option in
                Button {
                    onPick(option)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Text(option)
                        Spacer()
                        if option == current {
                            Image(systemName: "checkmark").foregroundColor(Theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(width: 460, height: min(CGFloat(options.count) * 30 + 16, 420))
            HStack {
                Spacer()
                Button("取消") { dismiss() }
            }
        }
        .padding(20)
    }
}
#endif
