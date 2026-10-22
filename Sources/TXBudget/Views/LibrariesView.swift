#if os(macOS)
import SwiftUI

/// 基础库视图（v2.0.0）：编辑目标 = settings.editingProfileId，不碰 activeProfileId。
/// 统一专业表格 ProTable（搜索/排序/双击编辑/复制行/删除确认）；行字典经
/// LibraryRowCodec 提交时解析回具体行类型。Excel 导入/导出沿用 v1 组件。
struct LibrariesView: View {
    @EnvironmentObject private var appState: AppState
    var viewKey: LibraryViewKey

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: viewKey.label,
                       subtitle: "资料库 · 编辑的是指定方案的库，与其他方案完全隔离")
            // 编辑目标横幅
            HStack(spacing: 10) {
                Image(systemName: "pencil.circle.fill").foregroundColor(Theme.accent)
                Text("正在编辑方案：")
                    .font(.callout).foregroundColor(.secondary)
                Text(appState.editingProfile?.name ?? "—")
                    .font(.callout).fontWeight(.semibold)
                Text("（新建工程默认方案不受这里影响）")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("切换编辑方案") { appState.nav = .profiles }
                    .controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.accent.opacity(0.07))
            .cornerRadius(8)
            if let kind = ImportLibraryKind(libraryViewKey: viewKey) {
                ExcelImportExportButtons(
                    kind: kind,
                    profileName: appState.editingProfile?.name ?? "—",
                    existingRows: { [appState] in
                        existingImportRows(kind: kind, profile: appState.editingProfile ?? ConfigurationProfile())
                    },
                    onConfirmImport: { classification, decisions, rowsBefore in
                        applyLibraryImport(appState: appState, kind: kind,
                                           classification: classification, decisions: decisions,
                                           rowsBefore: rowsBefore)
                    },
                    exportRows: { [appState] in
                        existingImportRows(kind: kind, profile: appState.editingProfile ?? ConfigurationProfile())
                    },
                    onExported: { url in
                        appState.showToast("已导出：\(url.lastPathComponent)")
                    }
                )
            }
            ProTable(
                columns: LibraryRowCodec.columns(for: viewKey),
                rows: rowDicts,
                onCommit: commitRow,
                onAdd: addRow,
                onDelete: { ids in deleteRows(ids) },
                onDuplicate: { id in duplicateRow(id) },
                emptyTitle: "该库暂无数据",
                emptyMessage: "点“新增一行”手工添加，或用上方导入从 Excel 批量导入。"
            )
        }
        .padding(Theme.pagePadding)
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
        guard !ids.isEmpty else { return }
        appState.updateDb { d in
            guard let pIdx = editingProfileIndex(d) else { return }
            LibraryRowCodec.delete(ids: ids, viewKey: viewKey, profile: &d.configurationProfiles[pIdx])
            d.configurationProfiles[pIdx].updatedAt = nowISO()
        }
    }

    /// 复制行：先新增一行（codec 生成新 id），再把源行字段值整体提交到新行。
    private func duplicateRow(_ id: String) {
        guard let source = rowDicts.first(where: { $0["id"] == id }) else { return }
        let oldIds = Set(rowDicts.compactMap { $0["id"] })
        addRow()
        // add 后重新取字典，找到新增行的 id（不在旧集合里）。
        guard let profile = appState.editingProfile else { return }
        let after = LibraryRowCodec.dicts(for: viewKey, profile: profile)
        guard let newId = after.compactMap({ $0["id"] }).first(where: { !oldIds.contains($0) })
        else { return }
        var copy = source
        copy["id"] = newId
        commitRow(id: newId, dict: copy)
        appState.showToast("已复制一行")
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
#endif
