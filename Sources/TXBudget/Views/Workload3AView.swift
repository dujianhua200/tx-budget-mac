#if os(macOS)
import SwiftUI

/// 工作量 · 表三甲：定额编号联想 + 数量回车下一行 + 右侧常驻小计（建安费/除税价）。
/// 孤儿行（定额编号不在库中）/ 无效行记警告、不参与计算；可删除孤儿行或忽略警告。
struct Workload3AView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    @State private var keyword = ""
    @State private var picked: QuotaRow?
    @State private var addQty = ""
    @State private var showSuggestions = false
    @FocusState private var focusedQtyId: String?
    @FocusState private var keywordFocused: Bool
    @State private var deleteRowId: String?
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 常驻小计
            HStack(spacing: 24) {
                Text("建安费（除税价）").foregroundColor(.secondary)
                MoneyText(value: result?.table2After.exclTax, bold: true)
                Text("元").foregroundColor(.secondary)
                Text("建安费（含税）").foregroundColor(.secondary)
                MoneyText(value: result?.table2After.inclTax, bold: true)
                Text("元").foregroundColor(.secondary)
                Text("总计（含税）").foregroundColor(.secondary)
                MoneyText(value: result?.table1.grandIncl, bold: true)
                Text("元").foregroundColor(.secondary)
            }
            .font(.system(size: 14))

            // 添加行：定额联想 + 数量
            HStack(spacing: 8) {
                TextField("输入定额编号 / 项目名称，回车选第一条…", text: $keyword)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 380)
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
                    .frame(width: 140)
                    .onSubmit { doAdd() }
                Button("添加") { doAdd() }
                    .buttonStyle(.borderedProminent)
                    .disabled(picked == nil)
                Text("选定额 → 输数量 → 回车添加；工程量表内数量回车跳下一行。")
                    .foregroundColor(.secondary).font(.caption)
            }

            // 警告条
            if let warn = orphanWarning, !dismissed.contains("orphanQty"), orphanCount > 0 {
                HStack {
                    Text(warn.message).foregroundColor(.orange)
                    Button("删除孤儿行") { deleteOrphans() }
                    Button("忽略此警告") { dismissWarning("orphanQty") }
                }.font(.caption)
            }
            if let warn = invalidWarning, !dismissed.contains("invalidQty") {
                HStack {
                    Text(warn.message).foregroundColor(.orange)
                    Button("忽略此警告") { dismissWarning("invalidQty") }
                }.font(.caption)
            }

            // 工程量表
            List {
                ForEach(project.quantities, id: \.id) { row in
                    quantityRow(row)
                }
            }
            .listStyle(.inset)
            Text("共 \(project.quantities.count) 行，其中孤儿 \(orphanCount) 行。\(subtotalText)")
                .foregroundColor(.secondary).font(.caption)
        }
        .alert("删除该工程量行？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { deleteRowId = nil }
            Button("删除", role: .destructive) {
                if let id = deleteRowId {
                    appState.updateProject(project.id) { p in
                        p.quantities.removeAll { $0.id == id }
                    }
                    deleteRowId = nil
                }
            }
        } message: {
            Text("定额编号：\(project.quantities.first { $0.id == deleteRowId }?.quota ?? "")")
        }
    }

    // MARK: - 派生

    private var libraries: LibrarySet {
        appState.projectProfile?.libraries ?? LibrarySet()
    }

    private var result: CalcResult? {
        appState.calcResult(for: project)
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

    private var subtotalText: String {
        guard let r = result else { return "" }
        return " · 工日小计 \(num2(r.techSub)) / \(num2(r.laborSub))，调整 \(jsNumberString(r.adjRate * 100))%，合计 \(num2(r.techDays)) / \(num2(r.laborDays))"
    }

    // MARK: - 行

    private func quantityRow(_ row: QuantityRow) -> some View {
        let status = quantityRowStatus(row, orphanIds: orphanIds, invalidIds: invalidIds,
                                       duplicateCodes: duplicateCodes)
        return HStack(spacing: 8) {
            Text(row.quota).frame(width: 110, alignment: .leading).fontWeight(.semibold)
            Text(row.variant ?? "").frame(width: 200, alignment: .leading)
            Text(row.unit ?? "").frame(width: 50, alignment: .leading)
            OptionalDoubleField(label: "", value: qtyBinding(row))
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .focused($focusedQtyId, equals: row.id)
                .onSubmit { focusNextQty(after: row.id) }
            OptionalDoubleField(label: "", value: coefBinding(row))
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
            Text(quantityRowStatusText(status))
                .foregroundColor(.orange).font(.caption)
                .frame(width: 80, alignment: .leading)
            Spacer()
            Button("删除") {
                deleteRowId = row.id
                showDeleteConfirm = true
            }
            .tint(.red).controlSize(.small)
        }
    }

    private func qtyBinding(_ row: QuantityRow) -> Binding<Double?> {
        Binding(
            get: { row.qty },
            set: { v in appState.updateProject(project.id) { p in
                if let i = p.quantities.firstIndex(where: { $0.id == row.id }) {
                    p.quantities[i].qty = v
                }
            } }
        )
    }

    private func coefBinding(_ row: QuantityRow) -> Binding<Double?> {
        Binding(
            get: { row.coef },
            set: { v in appState.updateProject(project.id) { p in
                if let i = p.quantities.firstIndex(where: { $0.id == row.id }) {
                    p.quantities[i].coef = v
                }
            } }
        )
    }

    private func focusNextQty(after id: String?) {
        let ids = project.quantities.map { $0.id }
        guard let id, let idx = ids.firstIndex(of: id), idx + 1 < ids.count else { return }
        focusedQtyId = ids[idx + 1]
    }

    // MARK: - 操作

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
#endif
