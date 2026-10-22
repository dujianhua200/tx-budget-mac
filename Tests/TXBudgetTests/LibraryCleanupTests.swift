import XCTest
@testable import TXBudget

/// v2.3.0 按官方清理（docs/v2.3-cleanup-design.md）：
/// dry-run 不改数据、apply 只删官方域内额外关联、变体/手册外/名称命中行保留、
/// 删前备份含待删行、幂等、引擎端到端（额外机械清理后表三乙不再生成）。
final class LibraryCleanupTests: XCTestCase {

    // MARK: - 夹具

    /// full（官方口径）：定额 Q1/Q2；Q1 有材料“钢”、机械 TXJ001、仪表 TXY001。
    private func makeFull() -> LibrarySet {
        LibrarySet(
            quotas: [QuotaRow(id: "f1", code: "Q1", name: "官方定额一", unit: "个", tech: 1, labor: 1),
                     QuotaRow(id: "f2", code: "Q2", name: "官方定额二", unit: "个", tech: 1, labor: 1)],
            rules: [RuleRow(id: "fr1", quota: "Q1", material: "钢", spec: "", unit: "kg",
                            consumption: 2, supply: "甲供", kind: "通用", variant: "", appliesTo: "全")],
            quotaMachines: [QuotaMachineRow(id: "fm1", quota: "Q1", mcode: "TXJ001", mname: "熔接机", unit: "台班", qty: 0.5)],
            quotaInstruments: [QuotaInstrumentRow(id: "fi1", quota: "Q1", mcode: "TXY001", mname: "分析仪", unit: "台班", qty: 0.5)]
        )
    }

    /// base：Q1 下混有官方行、额外行、变体行、名称命中的空码行；手册外定额 USER1 的关联。
    private func makeBase() -> LibrarySet {
        LibrarySet(
            quotas: [QuotaRow(id: "q1", code: "Q1", name: "定额一", unit: "个", tech: 1, labor: 1),
                     QuotaRow(id: "u1", code: "USER1", name: "自建定额", unit: "项", tech: 3, labor: 2)],
            materials: [MaterialRow(id: "m1", name: "钢", spec: "", unit: "kg", priceExcl: 99, supply: "乙供")],
            rules: [
                RuleRow(id: "r1", quota: "Q1", material: "钢", spec: "", unit: "kg",
                        consumption: 2, supply: "乙供", kind: "通用", variant: "", appliesTo: "全"),       // 官方有 → 留
                RuleRow(id: "r2", quota: "Q1", material: "铝", spec: "", unit: "kg",
                        consumption: 1, supply: "乙供", kind: "通用", variant: "", appliesTo: "全"),       // 官方无 → 删
                RuleRow(id: "r3", quota: "Q1", material: "铝", spec: "", unit: "kg",
                        consumption: 9, supply: "乙供", kind: "变体", variant: "某变体", appliesTo: "全"),   // 变体 → 留
                RuleRow(id: "r4", quota: "USER1", material: "自建材料", spec: "", unit: "个",
                        consumption: 1, supply: "乙供", kind: "通用", variant: "", appliesTo: "全"),       // 手册外定额 → 留
            ],
            machinePrices: [MachinePriceRow(id: "p1", code: "TXJ001", name: "熔接机", unit: "台班", price: 111)],
            quotaMachines: [
                QuotaMachineRow(id: "a1", quota: "Q1", mcode: "TXJ001", mname: "熔接机", unit: "台班", qty: 0.5), // 官方有 → 留
                QuotaMachineRow(id: "a2", quota: "Q1", mcode: "TXJ999", mname: "来历不明机", unit: "台班", qty: 3), // 官方无 → 删
                QuotaMachineRow(id: "a3", quota: "Q1", mcode: "", mname: "熔接机", unit: "台班", qty: 0.5),          // 名称命中 → 留
                QuotaMachineRow(id: "a4", quota: "USER1", mcode: "TXJ999", mname: "来历不明机", unit: "台班", qty: 1), // 手册外 → 留
            ],
            quotaInstruments: [
                QuotaInstrumentRow(id: "b1", quota: "Q1", mcode: "TXY001", mname: "分析仪", unit: "台班", qty: 0.5), // 官方有 → 留
                QuotaInstrumentRow(id: "b2", quota: "Q1", mcode: "TXY999", mname: "幽灵仪表", unit: "台班", qty: 2), // 官方无 → 删
            ]
        )
    }

    // MARK: - dry-run 与 apply

    func testPlanDryRunListsExtrasAndDoesNotMutate() {
        let base = makeBase()
        let plan = planLibraryCleanup(base: base, full: makeFull())
        XCTAssertEqual(plan.rules.map { $0.id }, ["r2"])
        XCTAssertEqual(plan.quotaMachines.map { $0.id }, ["a2"])
        XCTAssertEqual(plan.quotaInstruments.map { $0.id }, ["b2"])
        XCTAssertEqual(plan.total, 3)
        // dry-run 不改数据：base 与原值全等（值类型，再比一次构造结果）。
        XCTAssertEqual(base, makeBase())
        // 清单内容供预览：定额编码 + 名称 + 消耗量齐全。
        XCTAssertEqual(plan.rules[0].quota, "Q1")
        XCTAssertEqual(plan.rules[0].name, "铝")
        XCTAssertEqual(plan.rules[0].qty, 1)
        XCTAssertEqual(plan.quotaMachines[0].name, "来历不明机")
    }

    func testApplyDeletesOnlyOfficialDomainExtras() {
        let base = makeBase()
        let plan = planLibraryCleanup(base: base, full: makeFull())
        let (cleaned, report) = applyLibraryCleanup(base: base, plan: plan)
        XCTAssertEqual(report.rulesRemoved, 1)
        XCTAssertEqual(report.quotaMachinesRemoved, 1)
        XCTAssertEqual(report.quotaInstrumentsRemoved, 1)
        XCTAssertEqual(report.total, 3)
        // 只删三行：其余关联（官方行/变体/手册外/名称命中）逐行保留、行序不变。
        XCTAssertEqual(cleaned.rules.map { $0.id }, ["r1", "r3", "r4"])
        XCTAssertEqual(cleaned.quotaMachines.map { $0.id }, ["a1", "a3", "a4"])
        XCTAssertEqual(cleaned.quotaInstruments.map { $0.id }, ["b1"])
        // 不在范围内的表逐字不动：定额本体、材料、台班价。
        XCTAssertEqual(cleaned.quotas, base.quotas)
        XCTAssertEqual(cleaned.materials, base.materials)
        XCTAssertEqual(cleaned.machinePrices, base.machinePrices)
        XCTAssertEqual(cleaned.instrumentPrices, base.instrumentPrices)
        XCTAssertEqual(cleaned.shortlist, base.shortlist)
    }

    /// 用户在官方定额下自加的关联：数据上与错误关联不可区分，必须进预览清单靠用户把关。
    func testUserAddedAssocUnderOfficialQuotaAppearsInPlan() {
        var base = makeBase()
        base.quotaMachines.append(QuotaMachineRow(
            id: "u9", quota: "Q1", mcode: "TXJ555", mname: "用户自加机", unit: "台班", qty: 1))
        let plan = planLibraryCleanup(base: base, full: makeFull())
        XCTAssertTrue(plan.quotaMachines.contains { $0.id == "u9" && $0.name == "用户自加机" })
    }

    /// 回归：行 id 全为空（Electron 时代真实数据形状）时，apply 只删清单行、不误删整表。
    func testApplyWithEmptyRowIdsDeletesOnlyListedRows() {
        var base = makeBase()
        // 把所有行 id 清空，模拟无 id 数据。
        base.rules = base.rules.map { var r = $0; r.id = ""; return r }
        base.quotaMachines = base.quotaMachines.map { var r = $0; r.id = ""; return r }
        base.quotaInstruments = base.quotaInstruments.map { var r = $0; r.id = ""; return r }
        let plan = planLibraryCleanup(base: base, full: makeFull())
        XCTAssertEqual(plan.total, 3)
        let (cleaned, report) = applyLibraryCleanup(base: base, plan: plan)
        XCTAssertEqual(report.total, 3)
        XCTAssertEqual(cleaned.rules.count, base.rules.count - 1)
        XCTAssertEqual(cleaned.quotaMachines.count, base.quotaMachines.count - 1)
        XCTAssertEqual(cleaned.quotaInstruments.count, base.quotaInstruments.count - 1)
        XCTAssertFalse(cleaned.rules.contains { $0.material == "铝" && $0.kind == "通用" })
        XCTAssertTrue(cleaned.rules.contains { $0.material == "铝" && $0.kind == "变体" })
    }

    func testCleanupIdempotent() {
        let base = makeBase()
        let full = makeFull()
        let (cleaned, _) = applyLibraryCleanup(base: base, plan: planLibraryCleanup(base: base, full: full))
        let plan2 = planLibraryCleanup(base: cleaned, full: full)
        XCTAssertEqual(plan2.total, 0)
    }

    // MARK: - 删前备份

    func testBackupContainsRowsToBeDeleted() throws {
        let base = makeBase()
        var profile = ConfigurationProfile()
        profile.id = "prof_cleanup_test"
        profile.name = "清理测试方案"
        profile.libraries = base
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cleanup-backup-test-\(UUID().uuidString)")
        let url = try writeLibraryCleanupBackup(profile: profile, directory: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(url.lastPathComponent.hasPrefix("cleanup-backup-prof_cleanup_test-"))
        XCTAssertTrue(url.pathExtension == "json")
        // 备份内容 = 删前完整方案：解码后含待删行 r2/a2/b2，可经导入恢复。
        let file = try JSONDecoder().decode(
            DatabaseStore.ProfileFile.self, from: Data(contentsOf: url))
        XCTAssertEqual(file.profile.id, "prof_cleanup_test")
        XCTAssertTrue(file.profile.libraries.rules.contains { $0.id == "r2" })
        XCTAssertTrue(file.profile.libraries.quotaMachines.contains { $0.id == "a2" })
        XCTAssertTrue(file.profile.libraries.quotaInstruments.contains { $0.id == "b2" })
        XCTAssertEqual(file.profile.libraries, base)
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: - 引擎端到端：额外机械清理后表三乙不再生成

    func testEndToEndExtraMachineRemovedFromTable3B() throws {
        let full = LibrarySet(
            quotas: [QuotaRow(id: "f1", code: "TXL4-026", name: "官方定额", unit: "处", tech: 1, labor: 1)],
            machinePrices: [MachinePriceRow(id: "fp1", code: "TXJ026", name: "电缆拖车", unit: "台班", price: 100),
                            MachinePriceRow(id: "fp2", code: "TXJ999", name: "假机械", unit: "台班", price: 100)],
            quotaMachines: [QuotaMachineRow(id: "fm1", quota: "TXL4-026", mcode: "TXJ026", mname: "电缆拖车", unit: "台班", qty: 0.4)]
        )
        var base = full
        base.quotaMachines.append(QuotaMachineRow(
            id: "x1", quota: "TXL4-026", mcode: "TXJ999", mname: "假机械", unit: "台班", qty: 1.5))
        let seed = loadSeed()
        let project = smallProject { p in
            p.quantities = [QuantityRow(quota: "TXL4-026", variant: "", unit: "", qty: 2, coef: 1)]
        }
        // 清理前：额外机械进表三乙（1.5 × 2 = 3 台班）。
        let before = calcProject(project, LibraryCompletionTests.libs(from: base, seed: seed))
        let bBefore = before.table3B.rows.filter { $0.quota == "TXL4-026" }
        XCTAssertEqual(bBefore.first { $0.equipName == "假机械" }?.sessions ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(bBefore.first { $0.equipName == "电缆拖车" }?.sessions ?? 0, 0.8, accuracy: 0.001)
        // 清理后：额外机械消失，官方机械仍在。
        let plan = planLibraryCleanup(base: base, full: full)
        XCTAssertEqual(plan.quotaMachines.map { $0.id }, ["x1"])
        let (cleaned, report) = applyLibraryCleanup(base: base, plan: plan)
        XCTAssertEqual(report.quotaMachinesRemoved, 1)
        let after = calcProject(project, LibraryCompletionTests.libs(from: cleaned, seed: seed))
        let bAfter = after.table3B.rows.filter { $0.quota == "TXL4-026" }
        XCTAssertNil(bAfter.first { $0.equipName == "假机械" })
        XCTAssertEqual(bAfter.first { $0.equipName == "电缆拖车" }?.sessions ?? 0, 0.8, accuracy: 0.001)
    }

    // MARK: - 真实数据：种子经 v2.2 补全并校正后的清理量级

    func testRealDataCleanupAfterV22Completion() throws {
        let full = try XCTUnwrap(loadBundledFullLibrary())
        let seedBase = LibraryCompletionTests.loadAppSeedLibrarySet()
        let (merged, _) = mergeLibraryCompletion(base: seedBase, full: full)
        let plan = planLibraryCleanup(base: merged, full: full)
        // 实测回填（种子自带、补全校正保留下来的额外关联；见设计文档 §6）。
        // 种子 rules 共 117 条，其中 kind=通用 34 条的键不在官方内（其余为变体/备选，不在范围）。
        XCTAssertEqual(plan.rules.count, 34)
        XCTAssertEqual(plan.quotaMachines.count, 109)
        XCTAssertEqual(plan.quotaInstruments.count, 30)
        let (cleaned, report) = applyLibraryCleanup(base: merged, plan: plan)
        XCTAssertEqual(report.total, plan.total)
        // 幂等：清理后再 plan 为 0。
        XCTAssertEqual(planLibraryCleanup(base: cleaned, full: full).total, 0)
    }
}
