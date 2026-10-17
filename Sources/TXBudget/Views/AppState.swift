#if os(macOS)
import SwiftUI
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

    init(dataURL: URL = DatabaseStore.defaultDataURL()) {
        self.dataURL = dataURL
        do {
            if let loaded = try DatabaseStore.load(from: dataURL) {
                if loaded.configurationProfiles.isEmpty {
                    self.db = DatabaseStore.defaultDb()
                    self.loadError = "数据文件缺少配置方案，已载入空白默认库（原文件未改动）。"
                } else {
                    self.db = loaded
                }
            } else {
                self.db = DatabaseStore.defaultDb()
            }
        } catch let err as DatabaseError {
            self.db = DatabaseStore.defaultDb()
            switch err {
            case .v1NeedsElectronMigration:
                self.loadError = "检测到 v1 数据文件，请先用 Electron 版打开一次完成迁移，再用原生版打开。"
            case .versionTooHigh(let v):
                self.loadError = "数据版本高于本软件版本（v\(v)），请升级软件后再打开。"
            default:
                self.loadError = "数据文件无法识别或已损坏且无可用备份，请从备份恢复。"
            }
        } catch {
            self.db = DatabaseStore.defaultDb()
            self.loadError = "数据加载失败：\(error.localizedDescription)"
        }
        self.exportSelection = resolveExportSelection(self.db.settings)
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
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            await self?.performSave(auto: true, major: major)
        }
    }

    /// 显式保存：排空队列，立即写盘。
    func flushSaves() {
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
            saveState = SaveStatus(status: .saved, at: saveState.at, auto: false)
            showToast("保存失败：\(error.localizedDescription}，已重拉磁盘数据")
        }
    }

    func reloadFromDisk() {
        do {
            if let loaded = try DatabaseStore.load(from: dataURL) {
                db = loaded
                loadError = nil
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

    func newProject(name: String, template: ProjectRecord? = nil) {
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
}
#endif
