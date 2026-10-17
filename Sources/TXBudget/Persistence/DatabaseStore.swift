import Foundation

/// 数据文件层（对照 Electron `dbStore.cjs` + `main.cjs` 的 loadDb/saveDb + `profiles.js` 的 applySavePatch）。
/// 同一路径：~/Library/Application Support/通信概预算/budget-data.json（与 Electron 版同一 bundle 数据目录）。

public enum DatabaseError: Error, Equatable {
    case missingProfiles
    case versionTooHigh(Int)
    case v1NeedsElectronMigration
    case unrecognizedFormat
    case notLoaded
    case patchConflict(current: Int)
    case patchError(String)
}

public struct DatabaseStore {
    public static let appSupportDirName = "通信概预算"
    public static let dbFileName = "budget-data.json"
    public static let rollingPrefix = "budget-data.backup-"
    public static let v1BackupPrefix = "budget-data.v1-backup-"
    public static let rollingKeep = 5
    public static let backupMinInterval: TimeInterval = 3600

    public static func defaultDataURL() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support")
            .appendingPathComponent(appSupportDirName)
            .appendingPathComponent(dbFileName)
    }

    public static func defaultDirectory() -> URL {
        defaultDataURL().deletingLastPathComponent()
    }

    // MARK: - 读

    /// 加载数据文件。缺失 → 返回 nil（调用方建默认库）；v1 形状 → 抛 v1NeedsElectronMigration；
    /// version > 2 → 抛 versionTooHigh；缺 configurationProfiles → 抛 missingProfiles。
    /// 损坏 JSON → 尝试最近滚动备份恢复，仍失败则抛错（损坏文件改名为 budget-data.corrupt-<戳>.json 保留）。
    public static func load(from url: URL) throws -> DbFile? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        do {
            return repair(try decodeDb(data))
        } catch let err as DatabaseError {
            // v1 形状 / 版本过高是明确结论，不走损坏恢复分支。
            switch err {
            case .v1NeedsElectronMigration, .versionTooHigh:
                throw err
            default:
                break
            }
        } catch {
            // JSON 解析失败 → 损坏恢复分支。
        }
        // 损坏：保留损坏文件，尝试最近滚动备份。
        let stamp = isoStamp()
        let corrupt = url.deletingLastPathComponent()
            .appendingPathComponent("budget-data.corrupt-\(stamp).json")
        try? fm.moveItem(at: url, to: corrupt)
        let dir = url.deletingLastPathComponent()
        if let backs = try? fm.contentsOfDirectory(atPath: dir.path)
            .filter({ $0.hasPrefix(rollingPrefix) }).sorted(), let last = backs.last,
           let backupData = try? Data(contentsOf: dir.appendingPathComponent(last)),
           let db = try? decodeDb(backupData) {
            return repair(db)
        }
        throw DatabaseError.unrecognizedFormat
    }

    private static func decodeDb(_ data: Data) throws -> DbFile {
        // v1 形状检测：顶层 libraries 且无 configurationProfiles。
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           obj["configurationProfiles"] == nil, obj["libraries"] != nil {
            throw DatabaseError.v1NeedsElectronMigration
        }
        let decoder = JSONDecoder()
        let db = try decoder.decode(DbFile.self, from: data)
        if db.version > 2 { throw DatabaseError.versionTooHigh(db.version) }
        return db
    }

    /// v2 文件内存修复（对照 Electron `repairV2`）：补 meta / activeProfileId / 工程 profileId 与数组默认值。
    static func repair(_ db: DbFile) -> DbFile {
        var out = db
        if out.configurationProfiles.isEmpty {
            // 空方案列表属于损坏数据，由调用方按 missingProfiles 处理。
            return out
        }
        if out.settings.activeProfileId.isEmpty {
            out.settings.activeProfileId = out.configurationProfiles[0].id
        }
        for i in out.projects.indices {
            if out.projects[i].profileId.isEmpty {
                out.projects[i].profileId = out.settings.activeProfileId
            }
        }
        return out
    }

    // MARK: - 写（原子写 + 滚动备份）

    /// 原子写：写临时文件 → fsync → rename 覆盖。
    static func atomicWrite(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tmp = url.appendingPathExtension("tmp-\(ProcessInfo.processInfo.processIdentifier)")
        try data.write(to: tmp)
        if let handle = try? FileHandle(forWritingTo: tmp) {
            try? handle.synchronize()
            try? handle.close()
        }
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        try fm.moveItem(at: tmp, to: url)
    }

    static func isoStamp(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date).replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-").prefix(19).description
    }

    static func rollingBackupFileName(_ date: Date = Date()) -> String {
        "\(rollingPrefix)\(isoStamp(date)).json"
    }

    static func shouldBackup(dir: URL, major: Bool, now: Date = Date()) -> Bool {
        if major { return true }
        let fm = FileManager.default
        guard let backs = try? fm.contentsOfDirectory(atPath: dir.path)
            .filter({ $0.hasPrefix(rollingPrefix) }).sorted(), let last = backs.last else { return true }
        let latest = dir.appendingPathComponent(last)
        if let attrs = try? fm.attributesOfItem(atPath: latest.path),
           let mtime = attrs[.modificationDate] as? Date {
            return now.timeIntervalSince(mtime) >= backupMinInterval
        }
        return true
    }

    static func pruneRollingBackups(dir: URL, keep: Int = rollingKeep) {
        let fm = FileManager.default
        guard let backs = try? fm.contentsOfDirectory(atPath: dir.path)
            .filter({ $0.hasPrefix(rollingPrefix) }).sorted() else { return }
        var remaining = backs
        while remaining.count > keep {
            let victim = remaining.removeFirst()
            try? fm.removeItem(at: dir.appendingPathComponent(victim))
        }
    }

    /// 保存：备份旧文件（节流）+ 原子写新文件。调用方负责在保存前递增 meta.saveVersion。
    public static func save(_ db: DbFile, to url: URL, major: Bool = false) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path), shouldBackup(dir: dir, major: major) {
            try? fm.copyItem(at: url, to: dir.appendingPathComponent(rollingBackupFileName()))
            pruneRollingBackups(dir: dir)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(db)
        try atomicWrite(data, to: url)
    }

    // MARK: - 增量保存（对照 profiles.js applySavePatch）

    public struct SavePatch {
        public var profile: ConfigurationProfile?
        public var project: ProjectRecord?
        public var configurationProfiles: [ConfigurationProfile]?
        public var projects: [ProjectRecord]?
        public var settings: SettingsRecord?
        public var settingsPatch: SettingsPatch?
        public var profileId: String?
        public var projectId: String?
        public var baseVersion: Int?
        public init(profile: ConfigurationProfile? = nil, project: ProjectRecord? = nil,
                    configurationProfiles: [ConfigurationProfile]? = nil,
                    projects: [ProjectRecord]? = nil, settings: SettingsRecord? = nil,
                    settingsPatch: SettingsPatch? = nil, profileId: String? = nil,
                    projectId: String? = nil, baseVersion: Int? = nil) {
            self.profile = profile; self.project = project
            self.configurationProfiles = configurationProfiles; self.projects = projects
            self.settings = settings; self.settingsPatch = settingsPatch
            self.profileId = profileId; self.projectId = projectId; self.baseVersion = baseVersion
        }
    }

    /// settings 的部分补丁（settingsPatch）：只含要改的键。
    public struct SettingsPatch {
        public var activeProfileId: String?
        public var editingProfileId: String?
        public var exportSelection: [String]?
        public init(activeProfileId: String? = nil, editingProfileId: String? = nil,
                    exportSelection: [String]? = nil) {
            self.activeProfileId = activeProfileId; self.editingProfileId = editingProfileId
            self.exportSelection = exportSelection
        }
    }

    /// 应用增量补丁：baseVersion 与 meta.saveVersion 不匹配时返回冲突，不改数据。
    /// 成功时 meta.saveVersion +1，并返回新 db。
    public static func applySavePatch(_ db: DbFile, _ patch: SavePatch) -> Result<DbFile, DatabaseError> {
        let current = db.meta.saveVersion
        if let base = patch.baseVersion, base != current {
            return .failure(.patchConflict(current: current))
        }
        var next = db
        if let profile = patch.profile {
            let id = patch.profileId ?? profile.id
            guard let idx = next.configurationProfiles.firstIndex(where: { $0.id == id }) else {
                return .failure(.patchError("配置方案不存在：\(id)"))
            }
            var updated = profile
            updated.id = next.configurationProfiles[idx].id
            updated.updatedAt = nowISO()
            next.configurationProfiles[idx] = updated
        }
        if let project = patch.project {
            let id = patch.projectId ?? project.id
            guard let idx = next.projects.firstIndex(where: { $0.id == id }) else {
                return .failure(.patchError("工程不存在：\(id)"))
            }
            var updated = project
            updated.id = next.projects[idx].id
            updated.updatedAt = nowISO()
            next.projects[idx] = updated
        }
        if let profiles = patch.configurationProfiles {
            next.configurationProfiles = profiles
        }
        if let projects = patch.projects {
            next.projects = projects
        }
        if let settings = patch.settings {
            next.settings = settings
        }
        if let sp = patch.settingsPatch {
            if let v = sp.activeProfileId { next.settings.activeProfileId = v }
            if let v = sp.editingProfileId { next.settings.editingProfileId = v }
            if let v = sp.exportSelection { next.settings.exportSelection = v }
        }
        next.meta.saveVersion = current + 1
        return .success(next)
    }

    // MARK: - 默认库（首次启动，无数据文件时）

    public static func defaultDb() -> DbFile {
        var prof = createProfile(name: "默认配置")
        prof.id = "prof_default"
        var settings = SettingsRecord(activeProfileId: "prof_default")
        var defaultInfo = ProjectInfo()
        defaultInfo.工程类型 = "通信线路工程"
        defaultInfo.施工折扣 = 1
        defaultInfo.施工距离 = "35KM以内"
        defaultInfo.施工调遣分类 = "施工队伍调遣人数(线路、管道）"
        defaultInfo.冬雨季施工费 = "Ⅲ类地区"
        defaultInfo.甲供增值税 = 0.13
        defaultInfo.乙供增值税 = 0.09
        settings.defaultInfo = defaultInfo
        return DbFile(version: 2, configurationProfiles: [prof], projects: [],
                      settings: settings, meta: MetaRecord(saveVersion: 0), v1Backup: .null)
    }

    // MARK: - 配置方案导入/导出文件（profileFormat: 1）

    public struct ProfileFile: Codable {
        public var profileFormat: Int
        public var exportedAt: String
        public var profile: ConfigurationProfile
        public init(profile: ConfigurationProfile) {
            self.profileFormat = 1
            self.exportedAt = nowISO()
            self.profile = profile
        }
    }

    public static func exportProfileData(_ profile: ConfigurationProfile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ProfileFile(profile: profile))
    }

    /// 导入方案文件：校验格式 + 必备字段；成功赋新 id、source='imported'。失败抛错。
    public static func importProfileData(_ data: Data) throws -> ConfigurationProfile {
        let decoder = JSONDecoder()
        let file = try decoder.decode(ProfileFile.self, from: data)
        guard file.profileFormat == 1 else {
            throw DatabaseError.patchError("不支持的方案格式版本：\(file.profileFormat)（期望 1）")
        }
        var p = file.profile
        guard !p.name.isEmpty else { throw DatabaseError.patchError("方案缺少 name") }
        let ts = nowISO()
        p.id = newUID()
        p.source = "imported"
        p.isBuiltIn = false
        p.createdAt = ts
        p.updatedAt = ts
        return p
    }

    public static func exportBackupData(_ db: DbFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(db)
    }
}
