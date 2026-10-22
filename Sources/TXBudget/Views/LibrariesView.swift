#if os(macOS)
import SwiftUI

/// 基础库视图（v2.0.0）：编辑目标 = settings.editingProfileId，不碰 activeProfileId。
/// v2.0.1：页首横幅改为“当前方案”下拉选择器（ProfilePickerBanner），现场可切换。
/// v2.1.0：横幅下加“补全定额库”——把内置完整库并集合并进当前方案（只增不改，
/// 见 Logic/LibraryCompletion.swift 与 docs/v2.1-data-completion-design.md §6）。
/// v2.2.0：升级为“补全并校正”——内置库已按官方 451 手册重建，合并先校正
/// （工日/单位/名称/消耗量以官方为准）后补全；自建行与全部价格不动
/// （docs/v2.2-correction-design.md §5/§6）。
/// v2.3.0：并列加“按官方清理”——删除官方手册没有的错误关联；三重保险 =
/// dry-run 预览清单确认 + 删前自动备份方案文件 + 幂等
/// （Logic/LibraryCleanup.swift，docs/v2.3-cleanup-design.md）。
/// 统一专业表格 ProTable（搜索/排序/双击编辑/复制行/删除确认）；行字典经
/// LibraryRowCodec 提交时解析回具体行类型。Excel 导入/导出沿用 v1 组件。
struct LibrariesView: View {
    @EnvironmentObject private var appState: AppState
    var viewKey: LibraryViewKey
    @State private var cachedFull: LibrarySet?
    @State private var previewReport: LibraryCompletionReport?
    @State private var showCompletionConfirm = false
    @State private var doneReport: LibraryCompletionReport?
    @State private var showCompletionDone = false
    @State private var cleanupPlan: LibraryCleanupPlan?
    @State private var showCleanupPreview = false
    @State private var cleanupDoneReport: LibraryCleanupReport?
    @State private var cleanupBackupPath = ""
    @State private var showCleanupDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: viewKey.label,
                       subtitle: "资料库 · 编辑的是指定方案的库，与其他方案完全隔离")
            // 当前方案选择器（v2.0.1：原静态横幅改真下拉，现场可切换编辑目标）
            ProfilePickerBanner()
            // 定额库补全并校正（v2.2.0）：作用于当前方案，先试算弹确认，完成后分开报补全与校正数。
            HStack(spacing: 8) {
                Button("补全并校正定额库") { prepareCompletion() }
                    .controlSize(.small)
                Text("把内置完整库中缺少的定额与关联补进来，并按官方 451 手册校正已有定额的工日与消耗量；你自建的定额和全部价格不动。")
                    .font(.caption).foregroundColor(.secondary)
            }
            // 按官方清理（v2.3.0）：删除官方没有的错误关联，先预览清单确认，执行前自动备份。
            HStack(spacing: 8) {
                Button("按官方清理") { prepareCleanup() }
                    .controlSize(.small)
                    .tint(.red)
                Text("删除当前方案里官方 451 手册没有的材料/机械/仪表错误关联；先预览清单确认才删，删前自动备份方案（可用“导入方案文件”恢复）。")
                    .font(.caption).foregroundColor(.secondary)
            }
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
        .alert("补全并校正定额库", isPresented: $showCompletionConfirm) {
            Button("取消", role: .cancel) {}
            Button("补全并校正") { applyCompletion() }
        } message: {
            Text("将为当前方案“\(appState.editingProfile?.name ?? "—")”补全：\(previewReport?.detailText ?? "")；校正：\(previewReport?.correctedDetailText ?? "")。将按官方 451 手册校正定额工日与消耗量，你自建的定额和全部价格不动。")
        }
        .alert("补全校正完成", isPresented: $showCompletionDone) {
            Button("好") {}
        } message: {
            Text("已补全：\(doneReport?.detailText ?? "")；已校正：\(doneReport?.correctedDetailText ?? "")。新增定额插入后将自动带出材料、机械与仪表。")
        }
        .sheet(isPresented: $showCleanupPreview) {
            cleanupPreviewSheet
        }
        .alert("清理完成", isPresented: $showCleanupDone) {
            Button("好") {}
        } message: {
            Text("已删除：\(cleanupDoneReport?.detailText ?? "")。\n备份文件：\(cleanupBackupPath)\n（如需恢复，在配置方案页用“导入方案文件”导入该备份。）")
        }
    }

    /// 清理预览（dry-run 清单）：三张表分组列出全部待删行，看清后才确认。
    private var cleanupPreviewSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("按官方清理 · 预览").font(.headline)
            Text("当前方案“\(appState.editingProfile?.name ?? "—")”中，以下关联在官方 451 手册中不存在，将被删除（合计 \(cleanupPlan?.total ?? 0) 条）：")
                .font(.callout).foregroundColor(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    cleanupGroup(title: "材料关联", items: cleanupPlan?.rules ?? [])
                    cleanupGroup(title: "机械关联", items: cleanupPlan?.quotaMachines ?? [])
                    cleanupGroup(title: "仪表关联", items: cleanupPlan?.quotaInstruments ?? [])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("执行前会自动把当前方案备份到数据目录，备份文件可用“导入方案文件”恢复。手册外定额与变体规则不在清理范围内。")
                .font(.caption).foregroundColor(.secondary)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { showCleanupPreview = false }
                Button("确认清理", role: .destructive) { confirmCleanup() }
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 520)
    }

    private func cleanupGroup(title: String, items: [LibraryCleanupItem]) -> some View {
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(title)（\(items.count) 条）").font(.subheadline).fontWeight(.semibold)
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 8) {
                            Text(item.displayText).font(.callout)
                            if !item.spec.isEmpty {
                                Text(item.spec).font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    /// dry-run 清理预览（不写数据）：对待删清单非空才弹预览；为 0 只提示。
    private func prepareCleanup() {
        guard let profile = appState.editingProfile else { return }
        if cachedFull == nil { cachedFull = loadBundledFullLibrary() }
        guard let full = cachedFull else {
            appState.showToast("内置完整库加载失败，无法清理（资源缺失）")
            return
        }
        let plan = planLibraryCleanup(base: profile.libraries, full: full)
        if plan.total == 0 {
            appState.showToast("当前方案没有官方 451 手册之外的错误关联，无需清理")
            return
        }
        cleanupPlan = plan
        showCleanupPreview = true
    }

    /// 确认清理：先备份当前方案（失败则中止，绝不无备份删数据），再按预览清单逐行删除。
    private func confirmCleanup() {
        guard let plan = cleanupPlan, let profile = appState.editingProfile else { return }
        let profileId = profile.id
        let backupURL: URL
        do {
            backupURL = try writeLibraryCleanupBackup(
                profile: profile, directory: DatabaseStore.defaultDirectory())
        } catch {
            showCleanupPreview = false
            appState.showToast("备份失败，已取消清理：\(error.localizedDescription)")
            return
        }
        var applied: LibraryCleanupReport?
        appState.updateDb { d in
            guard let i = d.configurationProfiles.firstIndex(where: { $0.id == profileId }) else { return }
            let (cleaned, report) = applyLibraryCleanup(
                base: d.configurationProfiles[i].libraries, plan: plan)
            d.configurationProfiles[i].libraries = cleaned
            d.configurationProfiles[i].updatedAt = nowISO()
            applied = report
        }
        showCleanupPreview = false
        if let applied {
            cleanupDoneReport = applied
            cleanupBackupPath = backupURL.path
            showCleanupDone = true
        }
    }

    /// 试算补全并校正（不写数据）：加载内置完整库并对当前方案跑一次合并，得到预计补全/校正数。
    private func prepareCompletion() {
        guard let profile = appState.editingProfile else { return }
        if cachedFull == nil { cachedFull = loadBundledFullLibrary() }
        guard let full = cachedFull else {
            appState.showToast("内置完整库加载失败，无法补全（资源缺失）")
            return
        }
        let (_, report) = mergeLibraryCompletion(base: profile.libraries, full: full)
        if report.totalAdded == 0 && report.totalCorrected == 0 {
            appState.showToast("当前方案已与官方 451 手册一致，无需补全校正")
            return
        }
        previewReport = report
        showCompletionConfirm = true
    }

    /// 正式补全并校正：在 updateDb 内对实时方案数据再跑一次合并（与试算同一纯函数，结果一致）。
    private func applyCompletion() {
        guard let full = cachedFull, let profileId = appState.editingProfile?.id else { return }
        var applied: LibraryCompletionReport?
        appState.updateDb { d in
            guard let i = d.configurationProfiles.firstIndex(where: { $0.id == profileId }) else { return }
            let (merged, report) = mergeLibraryCompletion(base: d.configurationProfiles[i].libraries, full: full)
            d.configurationProfiles[i].libraries = merged
            d.configurationProfiles[i].updatedAt = nowISO()
            applied = report
        }
        if let applied {
            doneReport = applied
            showCompletionDone = true
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
