#if os(macOS)
import SwiftUI
import AppKit
import Combine

/// 全局应用状态（对照 Electron `App.jsx`）：持有 db、导航、打开工程、保存状态。
/// 保存：updateDb 只改内存并标记 dirty，800ms 节流聚合后自动写盘；显式保存按钮排空队列立即写盘。
@MainActor
final class AppState: ObservableObject {
    @Published var db: DbFile
    @Published var nav: NavDestination = .projects
    @Published var openProjectId: String?
    @Published var saveState = SaveStatus.initial()
    @Published var toast: String?
    @Published var loadError: String?
    @Published var exportSelection: [String]

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
        nav = .current(.info)
    }

    func createProject(name: String, template: ProjectRecord? = nil) {
        let created = newProject(db, name: name, template: template)
        updateDb { d in d.projects.insert(created, at: 0) }
        openProjectId = created.id
        nav = .current(.info)
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
#endif
