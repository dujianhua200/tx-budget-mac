#if os(macOS)
import SwiftUI

/// 基础库视图（编辑目标 = settings.editingProfileId，不碰 activeProfileId）。
/// 库表行以 [String: String] 字典编辑，提交时解析回具体行类型（见 LibraryRowCodec）。
struct LibrariesView: View {
    @EnvironmentObject private var appState: AppState
    var viewKey: LibraryViewKey
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteIds: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("基础库 · \(viewKey.label)")
                .font(.headline)
            Text("正在编辑方案：\(appState.editingProfile?.name ?? "—")（编辑目标）；新建工程默认方案不受这里影响。")
                .foregroundColor(.secondary).font(.caption)
            Text("Excel 导入/导出在后续阶段实现（需 xlsx 读写）。")
                .foregroundColor(.secondary).font(.caption)
            DictTableView(
                columns: LibraryRowCodec.columns(for: viewKey),
                rowDicts: rowDicts,
                onCommit: commitRow,
                onAdd: addRow,
                onDelete: { indices in
                    pendingDeleteIds = Set(indices.compactMap { idx in
                        guard idx < rowDicts.count else { return nil }
                        return rowDicts[idx]["id"]
                    }.filter { !$0.isEmpty })
                    showDeleteConfirm = true
                }
            )
        }
        .alert("删除选中的 \(pendingDeleteIds.count) 条？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { pendingDeleteIds.removeAll() }
            Button("确认删除", role: .destructive) {
                deleteRows(pendingDeleteIds)
                pendingDeleteIds.removeAll()
            }
        } message: {
            Text("删除后不可恢复（本阶段无撤销）。")
        }
    }

    private var rowDicts: [[String: String]] {
        guard let profile = appState.editingProfile else { return [] }
        return LibraryRowCodec.dicts(for: viewKey, profile: profile)
    }

    private func commitRow(id: String, dict: [String: String]) {
        appState.updateDb { d in
            guard let pIdx = editingProfileIndex(d) else { return }
            LibraryRowCodec.commit(id: id, dict: dict, viewKey: viewKey, profile: &d.configurationProfiles[pIdx])
            d.configurationProfiles[pIdx].updatedAt = nowISO()
        }
    }

    private func addRow() {
        appState.updateDb { d in
            guard let pIdx = editingProfileIndex(d) else { return }
            LibraryRowCodec.add(viewKey: viewKey, profile: &d.configurationProfiles[pIdx])
            d.configurationProfiles[pIdx].updatedAt = nowISO()
        }
    }

    private func deleteRows(_ ids: Set<String>) {
        appState.updateDb { d in
            guard let pIdx = editingProfileIndex(d) else { return }
            LibraryRowCodec.delete(ids: ids, viewKey: viewKey, profile: &d.configurationProfiles[pIdx])
            d.configurationProfiles[pIdx].updatedAt = nowISO()
        }
    }

    private func editingProfileIndex(_ d: DbFile) -> Int? {
        if let id = d.settings.editingProfileId, let i = d.configurationProfiles.firstIndex(where: { $0.id == id }) {
            return i
        }
        if let i = d.configurationProfiles.firstIndex(where: { $0.id == d.settings.activeProfileId }) {
            return i
        }
        return d.configurationProfiles.indices.first
    }
}

/// 通用字典表格：行 = [String: String]，列由 LibraryColumn 定义。
/// 文本/数字单元格本地编辑、提交（回车/失焦）时写回；下拉/勾选即时写回。
/// 注：不用 SwiftUI Table——TableBuilder 内 ForEach 生成 TableColumn 会报 init 歧义；
/// 改用 List + HStack 网格，列宽与 Table 版一致。
struct DictTableView: View {
    var columns: [LibraryColumn]
    var rowDicts: [[String: String]]
    var onCommit: (String, [String: String]) -> Void
    var onAdd: () -> Void
    /// 删除：传选中行的序号（调用方按当前 rowDicts 映射回行内 id）。
    var onDelete: (Set<Int>) -> Void

    @State private var selected: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("＋ 新增一行") { onAdd() }
                Button("删除选中") { onDelete(selected); selected.removeAll() }
                    .disabled(selected.isEmpty)
                    .tint(.red)
                Spacer()
                Text("\(rowDicts.count) 条").foregroundColor(.secondary)
            }
            .controlSize(.small)
            HStack(spacing: 8) {
                ForEach(columns, id: \.key) { col in
                    Text(col.label).font(.caption).foregroundColor(.secondary)
                        .frame(width: columnWidth(col), alignment: .leading)
                }
                Spacer()
            }
            List(indexedRows) { indexed in
                HStack(spacing: 8) {
                    ForEach(columns, id: \.key) { col in
                        cell(col, indexed.row, indexed.id)
                            .frame(width: columnWidth(col), alignment: .leading)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { toggleSelect(indexed.id) }
                .listRowBackground(selected.contains(indexed.id) ? Color.accentColor.opacity(0.15) : Color.clear)
            }
            .listStyle(.inset)
        }
    }

    private var indexedRows: [IndexedRow<[String: String]>] {
        rowDicts.enumerated().map { i, d in
            IndexedRow(id: i, row: d)
        }
    }

    private func toggleSelect(_ index: Int) {
        if selected.contains(index) {
            selected.remove(index)
        } else {
            selected.insert(index)
        }
    }

    private func columnWidth(_ col: LibraryColumn) -> CGFloat {
        switch col.kind {
        case .number: return 90
        case .select: return 110
        case .checkbox: return 40
        case .text: return 140
        }
    }

    // 注意：List 的选中是序号，删除时映射回行内 id。
    private func cell(_ col: LibraryColumn, _ dict: [String: String], _ index: Int) -> some View {
        let rowId = dict["id"] ?? "\(index)"
        let current = dict[col.key] ?? ""
        switch col.kind {
        case .select:
            return AnyView(
                Picker("", selection: Binding(
                    get: { current },
                    set: { v in
                        var d = dict; d[col.key] = v
                        onCommit(rowId, d)
                    }
                )) {
                    ForEach(col.options, id: \.self) { o in Text(o).tag(o) }
                }
                .labelsHidden()
                .frame(width: 110)
            )
        case .checkbox:
            return AnyView(
                Toggle("", isOn: Binding(
                    get: { current == "true" },
                    set: { v in
                        var d = dict; d[col.key] = v ? "true" : "false"
                        onCommit(rowId, d)
                    }
                ))
                .labelsHidden()
            )
        default:
            return AnyView(
                LibraryCellField(initial: current) { newValue in
                    var d = dict; d[col.key] = newValue
                    onCommit(rowId, d)
                }
                .frame(width: col.kind == .number ? 90 : 140)
            )
        }
    }
}

/// 文本/数字单元格：本地编辑，提交（回车/失焦）时写回，避免每敲一键就重渲染丢焦点。
struct LibraryCellField: View {
    var initial: String
    var onCommit: (String) -> Void
    @State private var text: String = ""
    @State private var initialized = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear {
                if !initialized { text = initial; initialized = true }
            }
            .onChange(of: initial) { v in
                if !focused { text = v }
            }
            .onSubmit { commit() }
            .onChange(of: focused) { f in
                if !f { commit() }
            }
    }

    private func commit() {
        if text != initial { onCommit(text) }
    }
}
#endif
