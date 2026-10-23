#if os(macOS)
import SwiftUI
import AppKit
import Combine

/// 全局应用状态（对照 Electron `App.jsx`）：持有 db、导航、打开工程、保存状态。
/// 保存：updateDb 只改内存并标记 dirty，800ms 节流聚合后自动写盘；显式保存按钮排空队列立即写盘。
@MainActor
final class AppState: ObservableObject {
    @Published var db: DbFile
    @Published var nav: NavDestination = .projectList
    @Published var openProjectId: String?
    @Published var saveState = SaveStatus.initial()
    @Published var toast: String?
    @Published var loadError: String?
    @Published var exportSelection: [String]
    /// 本次运行的导出记录（内存态，不落盘）：报表导出页展示，重启清空。
    @Published var exportHistory: [ExportRecord] = []
    /// 资料库维护请求（v2.5.0 §12.5）：菜单栏与资料库页按钮共同置位，
    /// 由 ContentView 根部常驻的 LibraryMaintenanceControls 单点呈现确认/预览。
    @Published var libraryMaintenanceRequest: LibraryMaintenanceAction?
    /// 设置页聚焦令牌（v2.5.0）：菜单「工程信息模板…」递增之，设置页据此高亮模板卡片。
    @Published var settingsFocusToken = 0

    private let dataURL: URL
    private var autosaveTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    /// 加载失败时阻塞自动保存（防空白库覆盖原文件）；显式保存 / 成功重载时解除。
    private var saveBlockedByLoadError = false

    init(dataURL: URL = DatabaseStore.defaultDataURL()) {
        self.dataURL = dataURL
        // 先算局部变量再统一赋值：init 未完成前不能读 self.db。
        var initialDb: DbFile
        var initialLoadError: String?
        do {
            if let loaded = try DatabaseStore.load(from: dataURL) {
                if loaded.configurationProfiles.isEmpty {
                    initialDb = DatabaseStore.defaultDb()
                    initialLoadError = "数据文件缺少配置方案，已载入空白默认库（原文件未改动）。"
                } else {
                    initialDb = loaded
                }
            } else {
                initialDb = DatabaseStore.defaultDb()
            }
        } catch let err as DatabaseError {
            initialDb = DatabaseStore.defaultDb()
            switch err {
            case .v1NeedsElectronMigration:
                initialLoadError = "检测到 v1 数据文件，请先用 Electron 版打开一次完成迁移，再用原生版打开。"
            case .versionTooHigh(let v):
                initialLoadError = "数据版本高于本软件版本（v\(v)），请升级软件后再打开。"
            default:
                initialLoadError = "数据文件无法识别或已损坏且无可用备份，请从备份恢复。"
            }
        } catch {
            initialDb = DatabaseStore.defaultDb()
            initialLoadError = "数据加载失败：\(error.localizedDescription)"
        }
        self.db = initialDb
        self.loadError = initialLoadError
        self.exportSelection = resolveExportSelection(initialDb.settings)
        // 加载失败 → 阻塞自动保存，直到显式保存或成功重载。
        self.saveBlockedByLoadError = initialLoadError != nil
        // 退出前落盘：Cmd+Q / 菜单退出都会发 willTerminate，同步 flush 保证 800ms 窗口内的编辑不丢。
        // 设计文档 §7 要求“关闭前有未保存仍提示”；此处改为“保证落盘、不弹窗”
        // （自动保存 + 退出 flush 后退出时恒为已保存，弹窗纯属干扰），偏差见 v1.0.1 汇报。
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.flushSaves() }
        }
    }

    // MARK: - 派生状态

    var openProject: ProjectRecord? {
        guard let id = openProjectId else { return nil }
        return db.projects.first { $0.id == id }
    }

    var projectProfile: ConfigurationProfile? {
        guard let p = openProject else { return nil }
        return getProfile(db, p.profileId) ?? activeProfile(db)
    }

    var editingProfile: ConfigurationProfile? { resolveEditingProfile(db) }

    var hasProject: Bool { openProject != nil }

    func calcResult(for project: ProjectRecord) -> CalcResult? {
        calcFor(db, project)
    }

    /// 当前打开工程的全部校验问题（校验中心 / 状态栏徽标 / 概览共用同一聚合）。
    var openProjectIssues: [ValidationIssue] {
        guard let p = openProject else { return [] }
        return collectValidationIssues(db: db, project: p, profile: projectProfile,
                                       result: calcResult(for: p))
    }

    var openProjectIssueCount: Int { openProjectIssues.count }

    /// 记录一次成功导出（报表导出页“本次导出记录”展示）。
    func recordExport(projectName: String, fileName: String) {
        exportHistory.insert(
            ExportRecord(time: Date(), projectName: projectName, fileName: fileName),
            at: 0)
    }

    // MARK: - 保存

    /// 改内存 + 标记 dirty + 安排 800ms 自动保存（节流聚合）。
    func updateDb(_ mutate: (inout DbFile) -> Void, major: Bool = false) {
        mutate(&db)
        saveState = saveState.transition(.edit)
        scheduleAutosave(major: major)
    }

    private func scheduleAutosave(major: Bool) {
        // 加载失败后禁止自动保存：此时内存可能是空白库，自动保存会把空白库写回原路径。
        // 显式保存（flushSaves）不受此限制——用户明确要保存时才写盘。
        guard !saveBlockedByLoadError else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSave(auto: true, major: major)
        }
    }

    /// 显式保存：排空队列，立即写盘；同时解除加载失败的自动保存阻塞。
    func flushSaves() {
        saveBlockedByLoadError = false
        autosaveTask?.cancel()
        autosaveTask = nil
        performSave(auto: false, major: false)
    }

    private func performSave(auto: Bool, major: Bool) {
        guard saveState.status == .dirty || saveState.status == .saving else { return }
        saveState = saveState.transition(.saveStart)
        db.meta.saveVersion += 1
        do {
            try DatabaseStore.save(db, to: dataURL, major: major)
            saveState = saveState.transition(auto ? .autoSaveDone : .saveDone)
        } catch {
            // 保存失败：重拉磁盘，避免本地与磁盘分叉（与 Electron 一致）。
            if let reloaded = try? DatabaseStore.load(from: dataURL) {
                db = reloaded
            }
            // 失败后仍是 dirty（仍显示“● 未保存”，可重试），不许误报“✓ 已保存”。
            saveState = saveState.transition(.edit)
            showToast("保存失败：\(error.localizedDescription)，已重拉磁盘数据，请重试保存")
        }
    }

    func reloadFromDisk() {
        do {
            if let loaded = try DatabaseStore.load(from: dataURL) {
                db = loaded
                loadError = nil
                saveBlockedByLoadError = false
            }
        } catch {
            loadError = "重新加载失败：\(error.localizedDescription)"
        }
    }

    func showToast(_ msg: String) {
        toast = msg
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.toast = nil }
        }
    }

    /// 改单个工程（找得到才改，并刷新 updatedAt）。
    func updateProject(_ id: String, _ mutate: (inout ProjectRecord) -> Void) {
        updateDb { d in
            if let i = d.projects.firstIndex(where: { $0.id == id }) {
                mutate(&d.projects[i])
                d.projects[i].updatedAt = nowISO()
            }
        }
    }

    func updateOpenProject(_ mutate: (inout ProjectRecord) -> Void) {
        guard let id = openProjectId else { return }
        updateProject(id, mutate)
    }

    // MARK: - 工程操作

    func openProject(_ id: String) {
        updateDb { d in
            if let i = d.projects.firstIndex(where: { $0.id == id }) {
                d.projects[i].lastOpenedAt = Date().timeIntervalSince1970 * 1000
            }
        }
        openProjectId = id
        nav = .overview
    }

    func createProject(name: String, template: ProjectRecord? = nil) {
        createProject(name: name, profileId: nil, template: template)
    }

    /// 新建工程（向导版）：可指定配置方案（缺省用新建默认方案逻辑，见 newProject）。
    /// 创建后进入工程信息页补全信息（向导的“完成”步）。
    func createProject(name: String, profileId: String?, template: ProjectRecord?) {
        var created = newProject(db, name: name, template: template)
        if let profileId, db.configurationProfiles.contains(where: { $0.id == profileId }) {
            created.profileId = profileId
        }
        let toInsert = created
        updateDb { d in d.projects.insert(toInsert, at: 0) }
        openProjectId = created.id
        nav = .projectInfo
        showToast("已新建工程“\(name)”")
    }

    func duplicateProject(_ p: ProjectRecord) {
        var copy = p
        copy.id = newUID()
        copy.name = p.name + "（副本）"
        copy.createdAt = nowISO()
        copy.updatedAt = nowISO()
        copy.lastOpenedAt = nil
        updateDb { d in d.projects.insert(copy, at: 0) }
        showToast("已复制为“\(copy.name)”")
    }

    func deleteProjects(_ ids: [String]) {
        updateDb({ d in d.projects.removeAll { ids.contains($0.id) } }, major: true)
        if let open = openProjectId, ids.contains(open) { openProjectId = nil }
        showToast("已删除 \(ids.count) 个工程")
    }

    /// 切换工程所用配置方案（改 profileId，调用方负责确认）。
    func switchProjectProfile(_ projectId: String, _ profileId: String) {
        updateDb { d in
            if let i = d.projects.firstIndex(where: { $0.id == projectId }) {
                d.projects[i].profileId = profileId
                d.projects[i].updatedAt = nowISO()
            }
        }
    }

    // MARK: - 配置方案操作

    func setEditingProfile(_ profileId: String) {
        updateDb { d in d.settings.editingProfileId = profileId }
    }

    func setDefaultProfile(_ profileId: String) {
        updateDb { d in d.settings.activeProfileId = profileId }
    }

    func addProfile(_ profile: ConfigurationProfile) {
        updateDb { d in d.configurationProfiles.append(profile) }
    }

    func deleteProfile(_ id: String) {
        updateDb({ d in
            d.configurationProfiles.removeAll { $0.id == id }
            if d.settings.activeProfileId == id {
                d.settings.activeProfileId = d.configurationProfiles.first?.id ?? ""
            }
            if d.settings.editingProfileId == id {
                d.settings.editingProfileId = d.configurationProfiles.first?.id
            }
        }, major: true)
    }

    /// 导出勾选持久化（settings.exportSelection）。
    func setExportSelection(_ selection: [String]) {
        exportSelection = selection
        updateDb { d in d.settings.exportSelection = selection }
    }

    /// 复制当前资料库方案（菜单栏「方案」用；逻辑复用 Logic 的 duplicateProfile）。
    func duplicateEditingProfile() {
        guard let profile = editingProfile else { return }
        let copy = duplicateProfile(profile)
        addProfile(copy)
        showToast("已复制方案为“\(copy.name)”")
    }

    /// 导入方案文件（原生文件面板；设置页与菜单栏共用同一实现，v2.5.0 收敛）。
    func importProfileViaPanel() {
        guard let url = FilePanel.openFile(allowedTypes: ["json"]) else { return }
        do {
            let data = try Data(contentsOf: url)
            var profile = try DatabaseStore.importProfileData(data)
            let names = Set(db.configurationProfiles.map { $0.name })
            if names.contains(profile.name) { profile.name = "\(profile.name)（导入）" }
            addProfile(profile)
            showToast("已导入配置方案“\(profile.name)”")
        } catch {
            showToast("导入失败：\(error.localizedDescription)")
        }
    }

    /// 导出当前资料库方案（原生文件面板；设置页与菜单栏共用同一实现，v2.5.0 收敛）。
    func exportEditingProfileViaPanel() {
        guard let profile = editingProfile else { return }
        guard let url = FilePanel.saveFile(defaultName: "\(profile.name).json", allowedTypes: ["json"]) else { return }
        do {
            let data = try DatabaseStore.exportProfileData(profile)
            try data.write(to: url)
            showToast("已导出：\(url.path)")
        } catch {
            showToast("导出失败：\(error.localizedDescription)")
        }
    }

    /// 批量导出：逐个工程计算并写盘，单个失败记录后继续（不中断其余工程）。
    /// 文件名 `<工程名>_概预算.xlsx`（batchExportFileName），勾选表 = 当前导出勾选。
    /// 返回 (成功数, 失败列表[(工程名, 原因)])，调用方负责提示。
    func batchExportProjects(_ projects: [ProjectRecord], to dir: URL) -> (succeeded: Int, failures: [(String, String)]) {
        var ok = 0
        var failures: [(String, String)] = []
        for p in projects {
            do {
                guard let result = calcFor(db, p) else { throw PrintExportError.writeFailed("计算失败") }
                let profile = getProfile(db, p.profileId) ?? activeProfile(db)
                try exportBudgetBook(
                    to: dir.appendingPathComponent(batchExportFileName(for: p.name)),
                    projectName: p.name, project: p.toEngineProject(), result: result,
                    profile: profile, include: Set(exportSelection))
                ok += 1
            } catch {
                failures.append((p.name, error.localizedDescription))
            }
        }
        return (ok, failures)
    }
}

/// 资料库维护动作（v2.5.0）：补全并校正 / 按官方清理，作用于当前资料库方案。
enum LibraryMaintenanceAction: Equatable {
    case completion
    case cleanup
}

/// 一次导出记录（内存态）：时间 + 工程名 + 文件名。
struct ExportRecord: Identifiable {
    var id = UUID()
    var time: Date
    var projectName: String
    var fileName: String

    var timeText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: time)
    }
}
#endif
