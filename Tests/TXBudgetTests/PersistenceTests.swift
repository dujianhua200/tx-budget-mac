import XCTest
@testable import TXBudget

/// 持久化：Electron 形状 v2 JSON 往返 / applySavePatch 白名单与冲突 / 备份清理 / 原子写。
final class PersistenceTests: XCTestCase {

    private func loadFixture() -> DbFile {
        let url = Bundle.module.url(forResource: "db-v2-sample", withExtension: "json", subdirectory: "Fixtures")!
        let data = try! Data(contentsOf: url)
        let db = try! JSONDecoder().decode(DbFile.self, from: data)
        return db
    }

    func testElectronV2FixtureDecodes() {
        let db = loadFixture()
        XCTAssertEqual(db.version, 2)
        XCTAssertEqual(db.configurationProfiles.count, 1)
        XCTAssertEqual(db.configurationProfiles.first?.id, "prof_default")
        XCTAssertEqual(db.configurationProfiles.first?.name, "默认配置")
        XCTAssertEqual(db.projects.count, 1)
        XCTAssertEqual(db.projects.first?.name, "夹具工程")
        // 中文键解码：工程信息中文键 + 参建单位。
        XCTAssertEqual(db.projects.first?.info.建设单位, "某联通分公司")
        XCTAssertEqual(db.projects.first?.info.施工单位, "某施工队")
        XCTAssertEqual(db.projects.first?.info.设计单位, "某设计院")
        XCTAssertEqual(db.projects.first?.info.施工折扣, 1)
        XCTAssertEqual(db.settings.activeProfileId, "prof_default")
        XCTAssertEqual(db.settings.editingProfileId, "prof_default")
        XCTAssertEqual(db.meta.saveVersion, 3)
        // 费率 winterRate null 与 0 严格区分：夹具里 winterRate = null。
        XCTAssertNil(db.configurationProfiles.first?.rates.byProjectType["通信线路工程"]?.value(forKey: "winterRate"))
        // 打折规则：安全生产费不打折。
        XCTAssertEqual(db.configurationProfiles.first?.discountRule.noDiscountKeys, ["safetyFee"])
    }

    func testDbRoundTripPreservesValues() throws {
        let db = loadFixture()
        let data = try JSONEncoder().encode(db)
        let back = try JSONDecoder().decode(DbFile.self, from: data)
        XCTAssertEqual(back, db)
    }

    func testApplySavePatchConflict() {
        var db = loadFixture()
        db.meta.saveVersion = 3
        let patch = DatabaseStore.SavePatch(settingsPatch: DatabaseStore.SettingsPatch(activeProfileId: "prof_y"), baseVersion: 2)
        // baseVersion 不匹配 → 冲突，不改数据。
        let result = DatabaseStore.applySavePatch(db, patch)
        if case .failure(let err) = result {
            XCTAssertEqual(err, .patchConflict(current: 3))
        } else {
            XCTFail("应返回版本冲突")
        }
    }

    func testApplySavePatchSettingsPatch() {
        let db = loadFixture()
        let patch = DatabaseStore.SavePatch(
            settingsPatch: DatabaseStore.SettingsPatch(activeProfileId: "prof_x", exportSelection: ["汇总表"]),
            baseVersion: 3)
        let result = DatabaseStore.applySavePatch(db, patch)
        if case .success(let next) = result {
            XCTAssertEqual(next.settings.activeProfileId, "prof_x")
            XCTAssertEqual(next.settings.exportSelection, ["汇总表"])
            // 其余字段不动。
            XCTAssertEqual(next.projects, db.projects)
        } else {
            XCTFail("应成功应用补丁")
        }
    }

    func testApplySavePatchUnknownKeysIgnored() {
        // SavePatch 只有白名单字段，构造上就无法传入未知键；空补丁 = 只递增 saveVersion。
        let db = loadFixture()
        let result = DatabaseStore.applySavePatch(db, DatabaseStore.SavePatch(baseVersion: 3))
        if case .success(let next) = result {
            XCTAssertEqual(next.meta.saveVersion, 4)
            XCTAssertEqual(next.projects, db.projects)
            XCTAssertEqual(next.configurationProfiles, db.configurationProfiles)
            XCTAssertEqual(next.settings, db.settings)
        } else {
            XCTFail("空补丁应成功")
        }
    }

    func testPruneRollingBackupsKeepsFive() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("txbudget-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<8 {
            let url = dir.appendingPathComponent("budget-data.backup-20260101-00000\(i).json")
            try "{}".write(to: url, atomically: true, encoding: .utf8)
        }
        DatabaseStore.pruneRollingBackups(dir: dir, keep: 5)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(remaining.count, 5)
        // 保留最新的 5 份（按文件名排序取后 5）。
        XCTAssertTrue(remaining.contains("budget-data.backup-20260101-000007.json"))
        XCTAssertFalse(remaining.contains("budget-data.backup-20260101-000000.json"))
    }

    func testAtomicWriteRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("txbudget-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = loadFixture()
        let url = dir.appendingPathComponent("budget-data.json")
        try DatabaseStore.save(db, to: url)
        let loaded = try DatabaseStore.load(from: url)
        // v2.6.0：load 走 repair 会给旧格式文件打上一次性迁移标记
        // （meta.appliedMigrations），除此之外往返逐项一致。
        // v2.6.1：repair 另跑基准补齐 + 零快照迁移，期望值同步补齐三标记。
        var expected = db
        _ = migrateCableMaterialUnits(&expected)
        _ = migrateBaselineVariantRules(&expected)
        _ = migrateZeroSnapshots(&expected)
        XCTAssertEqual(loaded, expected)
        // 无 tmp 残留。
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(files.contains { $0.hasSuffix(".tmp") })
        // 覆盖写：rename 原子替换，第二次保存的内容完整胜出；旧文件只进滚动备份，无 tmp 残留。
        var db2 = db
        db2.meta.saveVersion = 99
        try DatabaseStore.save(db2, to: url)
        XCTAssertEqual(try DatabaseStore.load(from: url)?.meta.saveVersion, 99)
        let files2 = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertFalse(files2.contains { $0.hasSuffix(".tmp") })
        XCTAssertEqual(files2.filter { $0.hasPrefix("budget-data.backup-") }.count, 1, "旧文件应进 1 份滚动备份")
    }

    func testProfileExportImportRoundTrip() throws {
        let db = loadFixture()
        let profile = db.configurationProfiles[0]
        let data = try DatabaseStore.exportProfileData(profile)
        // 方案文件格式：profileFormat: 1。
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["profileFormat"] as? Int, 1)
        let back = try DatabaseStore.importProfileData(data)
        // 导入赋新 id、source='imported'、isBuiltIn=false；其余内容一致。
        XCTAssertNotEqual(back.id, profile.id)
        XCTAssertEqual(back.source, "imported")
        XCTAssertEqual(back.isBuiltIn, false)
        var normalized = back
        normalized.id = profile.id
        normalized.source = profile.source
        normalized.isBuiltIn = profile.isBuiltIn
        normalized.createdAt = profile.createdAt
        normalized.updatedAt = profile.updatedAt
        XCTAssertEqual(normalized, profile)
    }

    func testLoadMissingFileReturnsNil() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("txbudget-missing-\(UUID().uuidString).json")
        XCTAssertNil(try DatabaseStore.load(from: url))
    }
}
