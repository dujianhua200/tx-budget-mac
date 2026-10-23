#if os(macOS)
import SwiftUI
import AppKit

/// 统一专业表格（v2.0.0，docs/v2-ui-design.md §4）：工作量与全部资料库共用。
/// 行 = [String: String] 字典（须含 "id"），列定义复用 LibraryColumn。
/// 特性：冻结表头、斑马纹、行号、合计行、数字列右对齐 + 等宽数字、双击行内编辑
/// （回车提交跳下一行、Esc 取消、失焦提交）、列头点击排序、顶部搜索过滤、
/// 右键菜单（编辑/复制行/删除）、Delete 删除（确认）、空状态引导。
/// 过滤/排序/合计的纯逻辑在 Logic/TableData.swift。
struct ProTable: View {
    var columns: [LibraryColumn]
    var rows: [[String: String]]
    var onCommit: (String, [String: String]) -> Void = { _, _ in }
    var onAdd: (() -> Void)? = nil
    /// 删除回调（按行 id，已在本组件内确认）。
    var onDelete: ((Set<String>) -> Void)? = nil
    /// 复制行回调（按行 id）。
    var onDuplicate: ((String) -> Void)? = nil
    /// 选择变化回调（v2.4.0 工作量关联区用；默认 nil，其他使用方不受影响）。
    var onSelectionChange: ((Set<String>) -> Void)? = nil
    /// 行双击回调（v2.5.0，docs/v2-ui-design.md §12.4）：仅非编辑列的双击触发
    /// （可编辑列双击仍进编辑）；默认 nil，其他使用方不受影响。
    var onRowDoubleClick: ((String) -> Void)? = nil
    /// 行上移/下移回调（v2.6.0 §9）：(行 id, 方向 -1 上移 / +1 下移)，右键菜单呈现；
    /// 默认 nil，其他使用方不受影响。数据顺序的交换与边界判定在回调方（Logic 纯函数）。
    var onMoveRow: ((String, Int) -> Void)? = nil
    /// “切换型号…”回调（v2.6.0 §6）：右键菜单呈现（双击名称列已改为进编辑，
    /// 选型号改走右键）；默认 nil，其他使用方不受影响。
    var onVariantPick: ((String) -> Void)? = nil
    /// 表格标识（v2.5.0 §12.2）：非空才启用列宽拖动改宽 + UserDefaults 持久化；
    /// nil 时列宽行为与旧版完全一致。
    var tableId: String? = nil
    /// 弹性列 key（v2.5.0 §12.2）：该列吃掉剩余宽度，minWidth = 解析宽与
    /// flexibleMinWidth 的较大者；默认 nil（无弹性列）。
    var flexibleKey: String? = nil
    var flexibleMinWidth: CGFloat = 200
    /// 不可编辑的列 key（显示为纯文本）。
    var readOnlyKeys: Set<String> = []
    /// 整体只读（预览模式：无新增/删除/编辑，仅搜索与排序）。
    var readOnly: Bool = false
    var showSearch: Bool = true
    /// 合计列（数字列 key 集合），对全部行求和（非过滤子集）。
    var totalsKeys: Set<String> = []
    var emptyTitle: String = "暂无数据"
    var emptyMessage: String = ""
    var addTitle: String = "＋ 新增一行"
    /// 列宽覆盖（key → 宽）；未覆盖按 kind 取默认宽。
    var columnWidths: [String: CGFloat] = [:]

    @State private var query = ""
    @State private var sort: TableSort?
    @State private var selection: Set<String> = []
    @State private var editing: EditingCell?
    @State private var pendingDelete: Set<String> = []
    @State private var showDeleteConfirm = false
    /// 用户拖定的列宽（v2.5.0：优先于 columnWidths 与 kind 默认；tableId 非空时持久化）。
    @State private var userWidths: [String: CGFloat] = [:]
    @State private var dragStartWidths: [String: CGFloat] = [:]
    @FocusState private var searchFocused: Bool

    struct EditingCell: Equatable {
        var rowId: String
        var key: String
    }

    private struct RowWrap: Identifiable {
        var id: String
        var dict: [String: String]
        var visibleIndex: Int
    }

    // MARK: - 派生

    private var numericKeys: Set<String> {
        Set(columns.filter { $0.kind == .number }.map { $0.key })
    }

    private var visibleRows: [RowWrap] {
        var list = tableRowsFiltered(rows, query: query)
        if let sort { list = tableRowsSorted(list, sort: sort, numericKeys: numericKeys) }
        return list.enumerated().map { i, dict in
            RowWrap(id: dict["id"] ?? "row-\(i)", dict: dict, visibleIndex: i)
        }
    }

    private func columnWidth(_ col: LibraryColumn) -> CGFloat {
        if let w = userWidths[col.key] { return w }
        if let w = columnWidths[col.key] { return w }
        switch col.kind {
        case .number: return 88
        case .select: return 116
        case .checkbox: return 44
        case .text: return 150
        }
    }

    /// 单元格框架：弹性列吃掉剩余宽度（minWidth 兜底），其余列固定解析宽。
    @ViewBuilder
    private func framedCell<Content: View>(_ col: LibraryColumn,
                                           alignment: Alignment,
                                           @ViewBuilder content: () -> Content) -> some View {
        if col.key == flexibleKey {
            content().frame(minWidth: max(columnWidth(col), flexibleMinWidth),
                            maxWidth: .infinity, alignment: alignment)
        } else {
            content().frame(width: columnWidth(col), alignment: alignment)
        }
    }

    // MARK: - 列宽持久化（v2.5.0 §12.2）

    private var widthsDefaultsKey: String? {
        tableId.map { "protable.widths.\($0)" }
    }

    private func loadUserWidths() {
        guard let key = widthsDefaultsKey,
              let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return }
        userWidths = decoded.mapValues { CGFloat($0) }
    }

    private func saveUserWidths() {
        guard let key = widthsDefaultsKey,
              let data = try? JSONEncoder().encode(userWidths.mapValues { Double($0) })
        else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    /// 列头右缘拖动手柄：拖动改宽（36–640），双击恢复默认（清用户宽）。
    private func resizeHandle(_ col: LibraryColumn) -> some View {
        Color.clear
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidths[col.key] == nil {
                            dragStartWidths[col.key] = columnWidth(col)
                        }
                        let start = dragStartWidths[col.key] ?? columnWidth(col)
                        userWidths[col.key] = min(640, max(36, start + value.translation.width))
                    }
                    .onEnded { _ in
                        dragStartWidths[col.key] = nil
                        saveUserWidths()
                    }
            )
            .onTapGesture(count: 2) {
                userWidths[col.key] = nil
                saveUserWidths()
            }
    }

    private func isEditable(_ col: LibraryColumn) -> Bool {
        !readOnly && !readOnlyKeys.contains(col.key)
    }

    private var firstEditableKey: String? {
        // 只考虑有行内编辑器的列（文本/数字）；select/checkbox 是即时提交，不进编辑态。
        columns.first { isEditable($0) && ($0.kind == .text || $0.kind == .number) }?.key
    }

    // MARK: - 主体

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            headerRow
            Divider()
            if visibleRows.isEmpty {
                EmptyStateView(
                    systemImage: "tablecells",
                    title: rows.isEmpty ? emptyTitle : "没有匹配的行",
                    message: rows.isEmpty ? emptyMessage : "换个关键词试试，或清空搜索。",
                    actionTitle: (!readOnly && onAdd != nil && rows.isEmpty) ? addTitle : nil,
                    action: onAdd
                )
            } else {
                List(visibleRows, selection: $selection) { wrap in
                    rowView(wrap)
                        .listRowBackground(rowBackground(wrap))
                        .contextMenu { rowMenu(wrap) }
                }
                .listStyle(.inset)
                .onDeleteCommand {
                    if !readOnly, onDelete != nil, !selection.isEmpty {
                        pendingDelete = selection
                        showDeleteConfirm = true
                    }
                }
            }
            if !totalsKeys.isEmpty {
                totalsRow
            }
        }
        .onAppear { loadUserWidths() }
        .onChange(of: selection) { newValue in onSelectionChange?(newValue) }
        .alert("删除选中的 \(pendingDelete.count) 条？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { pendingDelete.removeAll() }
            Button("确认删除", role: .destructive) {
                onDelete?(pendingDelete)
                selection.subtract(pendingDelete)
                pendingDelete.removeAll()
            }
        } message: {
            Text("删除后不可恢复（本软件无全局撤销；数据文件有自动备份）。")
        }
        .modifier(EnterKeyCatcher(enabled: !readOnly && editing == nil) {
            // Enter 编辑：恰选中一行且不在编辑中 → 编辑其首个可编辑列。
            guard selection.count == 1, let id = selection.first,
                  let key = firstEditableKey else { return }
            editing = EditingCell(rowId: id, key: key)
        })
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 8) {
            if showSearch {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("搜索", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .frame(width: 160)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
                // ⌘F 聚焦页内搜索（隐形按钮承载快捷键）。
                Button("") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0)
            }
            Text(query.isEmpty ? "共 \(rows.count) 条" : "显示 \(visibleRows.count) / 共 \(rows.count) 条")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
            if !readOnly {
                if let onAdd {
                    Button(addTitle) { onAdd() }
                }
                if onDelete != nil {
                    Button("删除选中") {
                        pendingDelete = selection
                        showDeleteConfirm = true
                    }
                    .disabled(selection.isEmpty)
                    .tint(.red)
                }
            }
        }
        .controlSize(.small)
        .padding(.vertical, 6)
    }

    // MARK: - 表头（冻结：位于滚动区之外）

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("#")
                .font(.caption).foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
            ForEach(columns, id: \.key) { col in
                Button {
                    toggleSort(col)
                } label: {
                    framedCell(col, alignment: col.kind == .number ? .trailing : .leading) {
                        HStack(spacing: 2) {
                            if col.kind == .number { Spacer() }
                            Text(col.label)
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            if sort?.key == col.key {
                                Text(sort?.ascending == true ? "▲" : "▼")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .overlay(alignment: .trailing) {
                    if tableId != nil { resizeHandle(col) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func toggleSort(_ col: LibraryColumn) {
        if sort?.key == col.key {
            if sort?.ascending == true {
                sort = TableSort(key: col.key, ascending: false)
            } else {
                sort = nil
            }
        } else {
            sort = TableSort(key: col.key, ascending: true)
        }
    }

    // MARK: - 行

    private func rowBackground(_ wrap: RowWrap) -> Color {
        if selection.contains(wrap.id) { return Theme.accent.opacity(0.15) }
        return wrap.visibleIndex.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.03)
    }

    private func rowView(_ wrap: RowWrap) -> some View {
        HStack(spacing: 8) {
            Text("\(wrap.visibleIndex + 1)")
                .font(.caption).foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
            ForEach(columns, id: \.key) { col in
                framedCell(col, alignment: col.kind == .number ? .trailing : .leading) {
                    cellView(wrap: wrap, col: col)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func cellView(wrap: RowWrap, col: LibraryColumn) -> some View {
        let value = wrap.dict[col.key] ?? ""
        if isEditable(col), editing == EditingCell(rowId: wrap.id, key: col.key),
           col.kind == .text || col.kind == .number {
            ProCellField(
                initial: value,
                isNumber: col.kind == .number,
                onCommit: { newValue in commitEdit(wrap: wrap, col: col, newValue: newValue) },
                onCancel: { editing = nil }
            )
        } else {
            switch col.kind {
            case .checkbox:
                Toggle("", isOn: Binding(
                    get: { value == "true" },
                    set: { v in
                        guard isEditable(col) else { return }
                        var d = wrap.dict; d[col.key] = v ? "true" : "false"
                        onCommit(wrap.id, d)
                    }
                ))
                .labelsHidden()
                .disabled(!isEditable(col))
            case .select:
                if isEditable(col) {
                    Picker("", selection: Binding(
                        get: { value },
                        set: { v in
                            var d = wrap.dict; d[col.key] = v
                            onCommit(wrap.id, d)
                        }
                    )) {
                        ForEach(col.options, id: \.self) { o in Text(o).tag(o) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                } else {
                    Text(value)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { handleCellDoubleTap(wrap: wrap, col: col) }
                }
            case .number:
                Text(value.isEmpty ? "—" : value)
                    .monospacedDigit()
                    .foregroundColor(value.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { handleCellDoubleTap(wrap: wrap, col: col) }
            case .text:
                Text(value)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { handleCellDoubleTap(wrap: wrap, col: col) }
            }
        }
    }

    /// 单元格双击：可编辑列进编辑；只读列在设了 onRowDoubleClick 时回调（v2.5.0 选型号）。
    private func handleCellDoubleTap(wrap: RowWrap, col: LibraryColumn) {
        if isEditable(col) {
            startEdit(wrap: wrap, col: col)
        } else if let onRowDoubleClick {
            selection = [wrap.id]
            onRowDoubleClick(wrap.id)
        }
    }

    private func startEdit(wrap: RowWrap, col: LibraryColumn) {
        guard isEditable(col) else { return }
        selection = [wrap.id]
        editing = EditingCell(rowId: wrap.id, key: col.key)
    }

    private func commitEdit(wrap: RowWrap, col: LibraryColumn, newValue: String) {
        if newValue != (wrap.dict[col.key] ?? "") {
            var d = wrap.dict
            d[col.key] = newValue
            onCommit(wrap.id, d)
        }
        // 回车提交后跳下一行同列继续编辑（快速录入）；没有下一行则收起。
        let list = visibleRows
        if let idx = list.firstIndex(where: { $0.id == wrap.id }), idx + 1 < list.count {
            editing = EditingCell(rowId: list[idx + 1].id, key: col.key)
        } else {
            editing = nil
        }
    }

    @ViewBuilder
    private func rowMenu(_ wrap: RowWrap) -> some View {
        if !readOnly {
            if let key = firstEditableKey {
                Button("编辑") {
                    selection = [wrap.id]
                    editing = EditingCell(rowId: wrap.id, key: key)
                }
            }
            if let onVariantPick {
                Button("切换型号…") {
                    selection = [wrap.id]
                    onVariantPick(wrap.id)
                }
            }
            if let onMoveRow {
                Button("上移") { onMoveRow(wrap.id, -1) }
                Button("下移") { onMoveRow(wrap.id, 1) }
            }
            if let onDuplicate {
                Button("复制行") { onDuplicate(wrap.id) }
            }
            if onDelete != nil {
                Divider()
                Button("删除", role: .destructive) {
                    pendingDelete = [wrap.id]
                    showDeleteConfirm = true
                }
            }
        }
    }

    // MARK: - 合计行（加粗 + 顶边框，对全部行求和）

    private var totalsRow: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Text("")
                    .frame(width: 30)
                ForEach(columns, id: \.key) { col in
                    if totalsKeys.contains(col.key) {
                        framedCell(col, alignment: .trailing) {
                            Text(num2(tableColumnTotal(rows, key: col.key)))
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    } else if col.key == columns.first?.key {
                        framedCell(col, alignment: .leading) {
                            Text("合计")
                                .fontWeight(.bold)
                        }
                    } else {
                        framedCell(col, alignment: .leading) {
                            Text("")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }
}

/// 单元格编辑器：本地文本，回车提交、Esc 取消、失焦提交（只提交一次）。
struct ProCellField: View {
    var initial: String
    var isNumber: Bool
    var onCommit: (String) -> Void
    var onCancel: () -> Void

    @State private var text = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(isNumber ? .system(.body, design: .monospaced) : .body)
            .multilineTextAlignment(isNumber ? .trailing : .leading)
            .focused($focused)
            .onAppear {
                text = initial
                focused = true
            }
            .onSubmit { finish(commit: true) }
            .onExitCommand { finish(commit: false) }
            .onChange(of: focused) { f in
                if !f { finish(commit: true) }
            }
    }

    private func finish(commit: Bool) {
        guard !finished else { return }
        finished = true
        if commit { onCommit(text) } else { onCancel() }
    }
}

/// Enter 键捕获（macOS 13 无 onKeyPress，用本地事件监视实现）：
/// 仅当窗口为 key、第一响应者不是文本编辑器、且 enabled 时触发；触发后消费事件。
/// 文本字段聚焦时不拦截，保证输入框内的回车语义（提交/下一行）不受影响。
/// enabled 经引用盒同步最新值，避免监视器闭包捕获安装时的旧值。
struct EnterKeyCatcher: ViewModifier {
    var enabled: Bool
    var action: () -> Void

    final class Box {
        var enabled = true
    }

    @State private var box = Box()
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                box.enabled = enabled
                guard monitor == nil else { return }
                let box = self.box
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard box.enabled,
                          event.keyCode == 36 || event.keyCode == 76,
                          !event.modifierFlags.contains(.command),
                          !event.modifierFlags.contains(.option),
                          !event.modifierFlags.contains(.control)
                    else { return event }
                    if let responder = NSApp.keyWindow?.firstResponder,
                       responder is NSTextView || responder is NSTextField {
                        return event
                    }
                    action()
                    return nil
                }
            }
            .onChange(of: enabled) { box.enabled = $0 }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}
#endif
