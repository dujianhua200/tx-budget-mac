#if os(macOS)
import SwiftUI

/// 资料库维护 · 对话框宿主（v2.5.0，docs/v2-ui-design.md §12.5）。
/// 「补全并校正定额库」（v2.2.0）与「按官方清理」（v2.3.0）的完整流程——试算 →
/// 确认 alert / dry-run 预览 sheet → 备份 → 执行 → 完成报告——原在 LibrariesView
/// 内呈现；v2.5.0 起抽到此处单点呈现：资料库页按钮与菜单栏「方案」菜单都只置位
/// `appState.libraryMaintenanceRequest`，本组件由 ContentView 根部常驻挂载观察，
/// 保证全软件只有一份确认/预览，避免菜单与页面双份弹窗。流程与口径一字未改。
struct LibraryMaintenanceControls: View {
    @EnvironmentObject private var appState: AppState
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
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: appState.libraryMaintenanceRequest) { action in
                guard let action else { return }
                appState.libraryMaintenanceRequest = nil
                switch action {
                case .completion: prepareCompletion()
                case .cleanup: prepareCleanup()
                }
            }
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
}
#endif
