import XCTest
@testable import TXBudget

/// v2.6.0 真机问题批次回归（docs/v2.6-batch-design.md）：
/// #3 光缆单位迁移 / #5 表四工程级材料层 / #6 表三甲快照 / #7 关闭工程 dirty /
/// #8 映射页面下线后数据层与生成不变 / #9 行序 / 旧格式解码迁移。
final class V26BatchTests: XCTestCase {

    // MARK: - 夹具

    /// 费率齐全的方案：TXL3-187（管道光缆，挂光缆主材）+ TXL1-001（吊线，挂钢绞线）。
    private func baseProfile(cableUnit: String = "千米", cableConsumption: Double = 1.007) -> ConfigurationProfile {
        var p = ConfigurationProfile()
        p.id = "prof_1"
        p.name = "测试方案"
        p.libraries.quotas = [
            QuotaRow(id: "q1", code: "TXL3-187", name: "敷设管道光缆", unit: "千米条", tech: 3.28, labor: 1.73, coef: 1),
            QuotaRow(id: "q2", code: "TXL1-001", name: "架设吊线", unit: "条公里", tech: 2, labor: 1, coef: 1),
        ]
        p.libraries.materials = [
            MaterialRow(id: "m1", name: "光缆", spec: "GYTS_6芯", unit: cableUnit, priceExcl: 1.5, supply: "甲供"),
            MaterialRow(id: "m2", name: "钢绞线", spec: "7/2.2", unit: "kg", priceExcl: 5, supply: "乙供"),
            MaterialRow(id: "m3", name: "水泥", spec: "P.O 42.5", unit: "kg", priceExcl: 0.5, supply: "乙供"),
        ]
        p.libraries.rules = [
            RuleRow(id: "r1", quota: "TXL3-187", material: "光缆", spec: "GYTS_6芯", unit: cableUnit,
                    consumption: cableConsumption, supply: "甲供", kind: "通用", variant: "", remark: "", appliesTo: "全"),
            RuleRow(id: "r2", quota: "TXL1-001", material: "钢绞线", spec: "7/2.2", unit: "kg",
                    consumption: 10, supply: "乙供", kind: "通用", variant: "", remark: "", appliesTo: "全"),
            RuleRow(id: "r3", quota: "TXL1-001", material: "水泥", spec: "P.O 42.5", unit: "kg",
                    consumption: 2, supply: "乙供", kind: "通用", variant: "", remark: "", appliesTo: "全"),
        ]
        var named = NamedRatesRecord()
        for def in rateFieldDefs { named.setValue(0.01, forKey: def.key) }
        p.rates.byProjectType["通信线路工程"] = named
        p.rates.winterTable = ["Ⅲ类地区": 0.018]
        p.table5Fees = defaultTable5Fees()
        return p
    }

    private func makeDb(_ profile: ConfigurationProfile, projects: [ProjectRecord] = []) -> DbFile {
        var db = DbFile()
        db.configurationProfiles = [profile]
        db.settings.activeProfileId = profile.id
        db.projects = projects
        return db
    }

    private func project(_ quantities: [QuantityRow]) -> ProjectRecord {
        var p = ProjectRecord(id: "p1", name: "测试工程", profileId: "prof_1")
        p.quantities = quantities
        return p
    }

    // MARK: - #3 光缆单位迁移

    func testCableUnitMigrationRewritesUnitAndConsumptionIdempotently() {
        var db = makeDb(baseProfile())
        let changed = migrateCableMaterialUnits(&db)
        // 1 个材料行（光缆）+ 1 条引用规则；钢绞线/水泥（kg）不动。
        XCTAssertEqual(changed, 2)
        let libs = db.configurationProfiles[0].libraries
        XCTAssertEqual(libs.materials.first { $0.name == "光缆" }?.unit, "m")
        XCTAssertEqual(libs.rules.first { $0.id == "r1" }?.consumption ?? 0, 1007, accuracy: 1e-6)
        XCTAssertEqual(libs.rules.first { $0.id == "r2" }?.consumption, 10)
        XCTAssertEqual(libs.materials.first { $0.name == "钢绞线" }?.unit, "kg")
        // 价格不动。
        XCTAssertEqual(libs.materials.first { $0.name == "光缆" }?.priceExcl, 1.5)
        // 幂等：标记已写入，二次调用零改动（用户日后自建“千米”材料不被误迁）。
        XCTAssertTrue((db.meta.appliedMigrations ?? []).contains(cableUnitMigrationId))
        var db2 = db
        db2.configurationProfiles[0].libraries.materials.append(
            MaterialRow(id: "mx", name: "用户自建缆", spec: "", unit: "千米", priceExcl: 1, supply: "甲供"))
        XCTAssertEqual(migrateCableMaterialUnits(&db2), 0)
        XCTAssertEqual(db2.configurationProfiles[0].libraries.materials.last?.unit, "千米")
    }

    func testCableQtyEndToEndAfterMigration() {
        let row0 = QuantityRow(id: "a", quota: "TXL3-187", qty: 2, coef: 1)
        // 迁移前：2 千米条 × 1.007 = 2.014（表四数量经 r2 显示 2.01，单位“千米”——用户投诉的错误形态）。
        let dbBefore = makeDb(baseProfile(), projects: [project([row0])])
        let before = calcFor(dbBefore, dbBefore.projects[0])
        let beforeRow = before?.table4A.rows.first { $0.key == "光缆|GYTS_6芯" }
        XCTAssertEqual(beforeRow?.qty ?? 0, 2.01, accuracy: 1e-9)
        XCTAssertEqual(beforeRow?.unit, "千米")

        // 迁移后：数量 2014、单位 m；价格（元/米口径）不动，金额 = 2014 × 1.5。
        var db = makeDb(baseProfile(), projects: [project([row0])])
        migrateCableMaterialUnits(&db)
        let after = calcFor(db, db.projects[0])
        let row = after?.table4A.rows.first { $0.key == "光缆|GYTS_6芯" }
        XCTAssertEqual(row?.qty ?? 0, 2014, accuracy: 1e-9)
        XCTAssertEqual(row?.unit, "m")
        XCTAssertEqual(row?.amtExcl ?? 0, 3021, accuracy: 1e-9)
    }

    // MARK: - 旧格式解码与加载迁移

    func testOldFormatFixtureDecodesWithEmptyNewFields() throws {
        let url = Bundle.module.url(forResource: "db-v2-sample", withExtension: "json", subdirectory: "Fixtures")!
        let db = try JSONDecoder().decode(DbFile.self, from: Data(contentsOf: url))
        let p = try XCTUnwrap(db.projects.first)
        // v2.6.0 新字段在旧文件里缺失 → 容错解码为缺省（快照 nil、材料层空、迁移标记 nil）。
        XCTAssertNil(p.quantities.first?.tech)
        XCTAssertNil(p.quantities.first?.labor)
        XCTAssertTrue(p.materialEdits.isEmpty)
        XCTAssertTrue(p.manualMaterials.isEmpty)
        XCTAssertTrue(p.materialOrder.isEmpty)
        XCTAssertNil(db.meta.appliedMigrations)
    }

    func testStoreLoadAppliesCableMigrationMarker() throws {
        let url = Bundle.module.url(forResource: "db-v2-sample", withExtension: "json", subdirectory: "Fixtures")!
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("txb-v26-load-\(UUID().uuidString).json")
        try Data(contentsOf: url).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let loaded = try DatabaseStore.load(from: tmp)
        XCTAssertTrue(((loaded?.meta.appliedMigrations ?? []).contains(cableUnitMigrationId)))
    }

    func testProjectRecordRoundTripWithNewMaterialLayer() throws {
        var p = project([QuantityRow(id: "a", quota: "TXL1-001", qty: 1, tech: 2.5, labor: 1.5)])
        p.materialEdits = [MaterialRowEdit(key: "钢绞线|7/2.2", name: "改名绞线")]
        p.manualMaterials = [ManualMaterialRow(id: "mm1", name: "接头盒", qty: 3, priceExcl: 100, supply: "乙供")]
        p.materialOrder = ["水泥|P.O 42.5", "钢绞线|7/2.2"]
        let back = try JSONDecoder().decode(ProjectRecord.self,
                                            from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        XCTAssertEqual(back.quantities.first?.tech, 2.5)
    }

    // MARK: - #6 表三甲快照

    func testTable3ASnapshotSplitsGroupsAndTotalsFollowRowValues() {
        let profile = baseProfile()
        // 两行同编号：一行用库值（技工 2），一行改了行技工快照（5）。
        let edited = project([
            QuantityRow(id: "a", quota: "TXL1-001", qty: 10, coef: 1),
            QuantityRow(id: "b", quota: "TXL1-001", qty: 10, coef: 1, tech: 5),
        ])
        let db = makeDb(profile, projects: [edited])
        let result = calcFor(db, edited)
        let rows = result?.table3A.filter { $0.code == "TXL1-001" } ?? []
        XCTAssertEqual(rows.count, 2, "工日不同应分两行，实际：\(rows)")
        XCTAssertEqual(Set(rows.map { $0.tech }), [20, 50])
        XCTAssertEqual(result?.techSub ?? 0, 70, accuracy: 1e-9)
        XCTAssertEqual(result?.laborSub ?? 0, 20, accuracy: 1e-9)
        // 定额库不变（改的只是本工程条目）。
        XCTAssertEqual(db.configurationProfiles[0].libraries.quotas.first { $0.code == "TXL1-001" }?.tech, 2)

        // 对照：都无快照 → 合并一行，合计 = 20 × 2 = 40（与旧口径一致）。
        let plain = project([
            QuantityRow(id: "a", quota: "TXL1-001", qty: 10, coef: 1),
            QuantityRow(id: "b", quota: "TXL1-001", qty: 10, coef: 1),
        ])
        let plainResult = calcFor(makeDb(profile, projects: [plain]), plain)
        let plainRows = plainResult?.table3A.filter { $0.code == "TXL1-001" } ?? []
        XCTAssertEqual(plainRows.count, 1)
        XCTAssertEqual(plainResult?.techSub ?? 0, 40, accuracy: 1e-9)
    }

    func testFillQuantitySnapshotsBackfillsMissingOnly() {
        let libs = baseProfile().libraries
        let rows = [
            QuantityRow(id: "a", quota: "TXL1-001", qty: 1),                       // 全缺 → 回填
            QuantityRow(id: "b", quota: "TXL1-001", qty: 1, tech: 9),              // 已有 tech 不覆盖
            QuantityRow(id: "c", quota: "NOPE-999", qty: 1),                       // 孤儿行原样
        ]
        let filled = fillQuantitySnapshots(rows, libraries: libs)
        XCTAssertEqual(filled[0].tech, 2)
        XCTAssertEqual(filled[0].labor, 1)
        XCTAssertEqual(filled[0].unit, "条公里")
        XCTAssertEqual(filled[1].tech, 9)
        XCTAssertEqual(filled[1].labor, 1)
        XCTAssertNil(filled[2].tech)
        XCTAssertNil(filled[2].unit)
        // 变体（名称/型号匹配键）绝不被回填改动。
        XCTAssertEqual(filled[0].variant, rows[0].variant)
    }

    // MARK: - #5 表四工程级材料层

    /// 基线工程：TXL1-001 × 10 → 钢绞线 auto 100kg（乙供，价 5）、水泥 auto 20kg（乙供，价 0.5）。
    private func matProject() -> ProjectRecord {
        project([QuantityRow(id: "a", quota: "TXL1-001", qty: 10, coef: 1)])
    }

    func testTable4GeneratedRowsVisibleWithAmounts() {
        let db = makeDb(baseProfile(), projects: [matProject()])
        let result = calcFor(db, matProject())
        let steel = result?.table4B.rows.first { $0.key == "钢绞线|7/2.2" }
        XCTAssertEqual(steel?.qty ?? 0, 100, accuracy: 1e-9)
        XCTAssertEqual(steel?.amtExcl ?? 0, 500, accuracy: 1e-9)
        XCTAssertEqual(steel?.supply, "乙供")
        XCTAssertFalse(steel?.isManual ?? true)
        // 表二乙供主材费消费生效表四。
        XCTAssertEqual(result?.table2After.yiMat ?? 0, 510, accuracy: 1e-9)
    }

    func testTable4QtyAndPriceEditsFlowToTotals() {
        var p = matProject()
        p.materialAdjust = [MaterialAdjust(key: "钢绞线|7/2.2", delta: 50)]
        var db = makeDb(baseProfile(), projects: [p])
        var result = calcFor(db, p)
        XCTAssertEqual(result?.table4B.rows.first { $0.key == "钢绞线|7/2.2" }?.qty ?? 0, 150, accuracy: 1e-9)
        XCTAssertEqual(result?.table4B.rows.first { $0.key == "钢绞线|7/2.2" }?.amtExcl ?? 0, 750, accuracy: 1e-9)

        p.materialAdjust = []
        p.materialPriceOverrides = [MaterialPriceOverride(key: "钢绞线|7/2.2", priceExcl: 6)]
        db = makeDb(baseProfile(), projects: [p])
        result = calcFor(db, p)
        XCTAssertEqual(result?.table4B.rows.first { $0.key == "钢绞线|7/2.2" }?.amtExcl ?? 0, 600, accuracy: 1e-9)
        XCTAssertEqual(result?.table2After.yiMat ?? 0, 610, accuracy: 1e-9)
        // 资料库价格不变。
        XCTAssertEqual(db.configurationProfiles[0].libraries.materials.first { $0.name == "钢绞线" }?.priceExcl, 5)
    }

    func testTable4SupplyEditMovesRowBetweenTables() {
        var p = matProject()
        p.materialEdits = [MaterialRowEdit(key: "钢绞线|7/2.2", supply: "甲供")]
        let result = calcFor(makeDb(baseProfile(), projects: [p]), p)
        XCTAssertNil(result?.table4B.rows.first { $0.key == "钢绞线|7/2.2" })
        let moved = result?.table4A.rows.first { $0.key == "钢绞线|7/2.2" }
        XCTAssertEqual(moved?.supply, "甲供")
        XCTAssertEqual(moved?.amtExcl ?? 0, 500, accuracy: 1e-9)
        XCTAssertEqual(result?.table4A.totalExcl ?? 0, 500, accuracy: 1e-9)
    }

    func testTable4DeleteAndRenameAndManualRow() {
        var p = matProject()
        p.materialEdits = [
            MaterialRowEdit(key: "钢绞线|7/2.2", deleted: true),
            MaterialRowEdit(key: "水泥|P.O 42.5", name: "水泥（本工程改名）"),
        ]
        p.manualMaterials = [ManualMaterialRow(id: "mm1", code: "CL001", name: "接头盒", spec: "12芯",
                                               unit: "个", qty: 3, priceExcl: 100, supply: "乙供",
                                               category: "材料", remark: "手工录入")]
        let result = calcFor(makeDb(baseProfile(), projects: [p]), p)
        // 删除的生成行消失；改名行键不变、金额不变、名称生效。
        XCTAssertNil(result?.table4B.rows.first { $0.key == "钢绞线|7/2.2" })
        let cement = result?.table4B.rows.first { $0.key == "水泥|P.O 42.5" }
        XCTAssertEqual(cement?.name, "水泥（本工程改名）")
        XCTAssertEqual(cement?.amtExcl ?? 0, 10, accuracy: 1e-9)
        // 手工行出现并计入合计。
        let manual = result?.table4B.rows.first { $0.key == "mm1" }
        XCTAssertEqual(manual?.isManual, true)
        XCTAssertEqual(manual?.code, "CL001")
        XCTAssertEqual(manual?.category, "材料")
        XCTAssertEqual(manual?.remark, "手工录入")
        XCTAssertEqual(manual?.amtExcl ?? 0, 300, accuracy: 1e-9)
        XCTAssertEqual(result?.table4B.totalExcl ?? 0, 310, accuracy: 1e-9)
    }

    func testTable4MaterialOrderFollowedAndNewRowsAppend() {
        var p = matProject()
        // 生成序为 钢绞线 → 水泥；显式序反转后行序跟随。
        p.materialOrder = ["水泥|P.O 42.5", "钢绞线|7/2.2"]
        p.manualMaterials = [ManualMaterialRow(id: "mm1", name: "接头盒", qty: 1, priceExcl: 10, supply: "乙供")]
        let result = calcFor(makeDb(baseProfile(), projects: [p]), p)
        XCTAssertEqual(result?.table4B.rows.map { $0.key },
                       ["水泥|P.O 42.5", "钢绞线|7/2.2", "mm1"],
                       "未入序的手工行接本组末尾，不冲已调顺序")
    }

    // MARK: - #9 行移动纯函数

    func testMoveQuantityRowBounds() {
        let rows = [QuantityRow(id: "a", quota: "Q", qty: 1),
                    QuantityRow(id: "b", quota: "Q", qty: 1),
                    QuantityRow(id: "c", quota: "Q", qty: 1)]
        XCTAssertEqual(moveQuantityRow(rows, at: 0, delta: 1).map { $0.id }, ["b", "a", "c"])
        XCTAssertEqual(moveQuantityRow(rows, at: 0, delta: -1).map { $0.id }, ["a", "b", "c"])
        XCTAssertEqual(moveQuantityRow(rows, at: 2, delta: 1).map { $0.id }, ["a", "b", "c"])
        XCTAssertEqual(moveQuantityRow(rows, at: 9, delta: 1).map { $0.id }, ["a", "b", "c"])
    }

    func testMovedMaterialOrderSwapsWithinOwnTableOnly() {
        let tables = [["a1", "a2"], ["b1", "b2", "b3"], [String]()]
        XCTAssertEqual(movedMaterialOrder(currentOrder: [], tablesKeysInOrder: tables,
                                          movingKey: "b1", delta: 1),
                       ["a1", "a2", "b2", "b1", "b3"])
        // 到组边界 / 未知 key / 非法 delta → 原样返回 currentOrder。
        XCTAssertEqual(movedMaterialOrder(currentOrder: ["x"], tablesKeysInOrder: tables,
                                          movingKey: "a2", delta: 1), ["x"])
        XCTAssertEqual(movedMaterialOrder(currentOrder: ["x"], tablesKeysInOrder: tables,
                                          movingKey: "b3", delta: 1), ["x"])
        XCTAssertEqual(movedMaterialOrder(currentOrder: ["x"], tablesKeysInOrder: tables,
                                          movingKey: "zz", delta: 1), ["x"])
        XCTAssertEqual(movedMaterialOrder(currentOrder: ["x"], tablesKeysInOrder: tables,
                                          movingKey: "b1", delta: 2), ["x"])
    }

    // MARK: - #7 关闭工程 dirty

    func testProjectSessionDirty() {
        let base = project([QuantityRow(id: "a", quota: "TXL1-001", qty: 1)])
        XCTAssertFalse(projectSessionDirty(baseline: base, current: base))
        XCTAssertFalse(projectSessionDirty(baseline: nil, current: base))
        // 仅打开戳与更新时间不同 → 不算改动。
        var stamped = base
        stamped.lastOpenedAt = 1_700_000_000_000
        stamped.updatedAt = "2026-10-23T00:00:00Z"
        XCTAssertFalse(projectSessionDirty(baseline: base, current: stamped))
        // 内容变更 → dirty。
        var edited = base
        edited.quantities[0].qty = 2
        XCTAssertTrue(projectSessionDirty(baseline: base, current: edited))
        var renamed = base
        renamed.name = "改名工程"
        XCTAssertTrue(projectSessionDirty(baseline: base, current: renamed))
    }

    // MARK: - #8 映射下线：数据层与生成不变

    func testMappingDataLayerIntactAfterPagesRemoved() {
        var profile = baseProfile()
        profile.libraries.quotaMachines = [
            QuotaMachineRow(id: "qm1", quota: "TXL1-001", mcode: "TXJ001", mname: "熔接机", unit: "台班", qty: 0.5)]
        profile.libraries.quotaInstruments = [
            QuotaInstrumentRow(id: "qi1", quota: "TXL1-001", mcode: "TXY001", mname: "分析仪", unit: "台班", qty: 0.5)]
        // 导入数据层三个 kind 仍可读（文件格式兼容不变）：变体切片含三条“通用”规则。
        XCTAssertEqual(existingImportRows(kind: .rulesVariant, profile: profile).map { $0.id },
                       ["r1", "r2", "r3"])
        XCTAssertEqual(existingImportRows(kind: .quotaMachines, profile: profile).map { $0.id }, ["qm1"])
        XCTAssertEqual(existingImportRows(kind: .quotaInstruments, profile: profile).map { $0.id }, ["qi1"])
        // 三个 kind 不再对应资料库页面。
        XCTAssertNil(ImportLibraryKind.rulesVariant.libraryViewKey)
        XCTAssertNil(ImportLibraryKind.quotaMachines.libraryViewKey)
        XCTAssertNil(ImportLibraryKind.quotaInstruments.libraryViewKey)
        // 用户可见标签无“映射”字样。
        for kind in ImportLibraryKind.allCases {
            XCTAssertFalse(kind.label.contains("映射"), "\(kind) 标签仍含映射：\(kind.label)")
        }
        // 引擎生成不依赖页面：表三乙仍由定额—机械关联生成（10 × 0.5 台班 × 100 元）。
        profile.libraries.machinePrices = [
            MachinePriceRow(id: "mp1", code: "TXJ001", name: "熔接机", unit: "台班", price: 100)]
        let result = calcFor(makeDb(profile, projects: [matProject()]), matProject())
        let machineRow = result?.table3B.rows.first { $0.equipName == "熔接机" }
        XCTAssertEqual(machineRow?.sessions ?? 0, 5, accuracy: 1e-9)
        XCTAssertEqual(machineRow?.amount ?? 0, 500, accuracy: 1e-9)
    }
}
