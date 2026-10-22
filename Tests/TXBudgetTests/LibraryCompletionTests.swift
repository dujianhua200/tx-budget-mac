import XCTest
@testable import TXBudget

/// v2.1.0 定额库补全（docs/v2.1-data-completion-design.md）：
/// 合并逻辑（只增不改/去重键/孤儿跳过/报告计数/幂等）、内置完整库完整性、
/// 引擎端到端（TXL4-026 插入定额后表三乙/丙、表四自动生成）。
final class LibraryCompletionTests: XCTestCase {

    // MARK: - 合并逻辑：只增不改

    func testMergeOnlyAddsNeverModifies() {
        let base = LibrarySet(
            quotas: [QuotaRow(id: "q1", code: "Q1", name: "定额一", unit: "个", tech: 1.5, labor: 0.5)],
            materials: [MaterialRow(id: "m1", name: "钢", spec: "", unit: "kg", priceExcl: 99, supply: "乙供")],
            rules: [RuleRow(id: "r1", quota: "Q1", material: "钢", spec: "", unit: "kg",
                            consumption: 2, supply: "乙供", kind: "通用", variant: "", appliesTo: "全")],
            machinePrices: [MachinePriceRow(id: "p1", code: "TXJ001", name: "熔接机", unit: "台班", price: 111)],
            instrumentPrices: [InstrumentPriceRow(id: "p2", code: "TXY001", name: "分析仪", unit: "台班", price: 222)],
            quotaMachines: [QuotaMachineRow(id: "a1", quota: "Q1", mcode: "TXJ001", mname: "熔接机", unit: "台班", qty: 0.5)],
            quotaInstruments: [QuotaInstrumentRow(id: "a2", quota: "Q1", mcode: "TXY001", mname: "分析仪", unit: "台班", qty: 0.5)]
        )
        // full：同键冲突行（值全不同）+ 新行 + 孤儿行（GHOST 定额不存在）。
        let full = LibrarySet(
            quotas: [QuotaRow(id: "f1", code: "Q1", name: "被改了名", unit: "台", tech: 9.9, labor: 9.9),
                     QuotaRow(id: "f2", code: "Q2", name: "定额二", unit: "个", tech: 3, labor: 1)],
            materials: [MaterialRow(id: "f3", name: "钢", spec: "", unit: "t", priceExcl: 1, supply: "甲供"),
                        MaterialRow(id: "f4", name: "铜", spec: "", unit: "kg", priceExcl: 5, supply: "甲供")],
            rules: [RuleRow(id: "f5", quota: "Q1", material: "钢", spec: "", consumption: 7, supply: "甲供", kind: "通用"),
                    RuleRow(id: "f6", quota: "Q2", material: "铜", spec: "", consumption: 3, supply: "甲供", kind: "通用"),
                    RuleRow(id: "f7", quota: "GHOST", material: "铜", spec: "", consumption: 1, supply: "甲供", kind: "通用")],
            machinePrices: [MachinePriceRow(id: "f8", code: "TXJ001", name: "熔接机", unit: "台班", price: 999),
                            MachinePriceRow(id: "f9", code: "TXJ002", name: "切割机", unit: "台班", price: 50)],
            instrumentPrices: [InstrumentPriceRow(id: "f10", code: "TXY001", name: "分析仪", unit: "台班", price: 999),
                               InstrumentPriceRow(id: "f11", code: "TXY002", name: "测试仪", unit: "台班", price: 60)],
            quotaMachines: [QuotaMachineRow(id: "f12", quota: "Q1", mcode: "TXJ001", mname: "熔接机", unit: "台班", qty: 9),
                            QuotaMachineRow(id: "f13", quota: "Q2", mcode: "TXJ002", mname: "切割机", unit: "台班", qty: 1),
                            QuotaMachineRow(id: "f14", quota: "GHOST", mcode: "TXJ003", mname: "x", unit: "台班", qty: 1)],
            quotaInstruments: [QuotaInstrumentRow(id: "f15", quota: "Q1", mcode: "TXY001", mname: "分析仪", unit: "台班", qty: 9),
                               QuotaInstrumentRow(id: "f16", quota: "Q2", mcode: "TXY002", mname: "测试仪", unit: "台班", qty: 1)]
        )
        let (merged, report) = mergeLibraryCompletion(base: base, full: full)

        // base 原行逐字段不变（Equatable 全等），且仍在表头位置。
        XCTAssertEqual(merged.quotas[0], base.quotas[0])
        XCTAssertEqual(merged.materials[0], base.materials[0])
        XCTAssertEqual(merged.rules[0], base.rules[0])
        XCTAssertEqual(merged.machinePrices[0], base.machinePrices[0])
        XCTAssertEqual(merged.instrumentPrices[0], base.instrumentPrices[0])
        XCTAssertEqual(merged.quotaMachines[0], base.quotaMachines[0])
        XCTAssertEqual(merged.quotaInstruments[0], base.quotaInstruments[0])
        // 现值不被 full 的冲突值覆盖（工日/价格/消耗逐项钉死）。
        XCTAssertEqual(merged.quotas[0].tech, 1.5)
        XCTAssertEqual(merged.materials[0].priceExcl, 99)
        XCTAssertEqual(merged.machinePrices[0].price, 111)
        XCTAssertEqual(merged.quotaMachines[0].qty, 0.5)
        // 新行被追加；孤儿行（2 条：rules + quotaMachines 各 1）跳过。
        XCTAssertEqual(merged.quotas.count, 2)
        XCTAssertEqual(merged.materials.count, 2)
        XCTAssertEqual(merged.rules.count, 2)
        XCTAssertEqual(merged.quotaMachines.count, 2)
        XCTAssertEqual(merged.quotaInstruments.count, 2)
        XCTAssertEqual(merged.machinePrices.count, 2)
        XCTAssertEqual(merged.instrumentPrices.count, 2)
        XCTAssertEqual(merged.machinePrices[1].price, 50)  // 新增编码的价格取 full
        // 报告计数。
        XCTAssertEqual(report.quotasAdded, 1)
        XCTAssertEqual(report.rulesAdded, 1)
        XCTAssertEqual(report.materialsAdded, 1)
        XCTAssertEqual(report.quotaMachinesAdded, 1)
        XCTAssertEqual(report.quotaInstrumentsAdded, 1)
        XCTAssertEqual(report.machinePricesAdded, 1)
        XCTAssertEqual(report.instrumentPricesAdded, 1)
        XCTAssertEqual(report.orphansSkipped, 2)
        XCTAssertEqual(report.totalAdded, 7)
        // shortlist 永不触碰。
        XCTAssertEqual(merged.shortlist, base.shortlist)
    }

    func testMergeEmptyCodeRowsKeyedByName() {
        let base = LibrarySet(
            quotas: [QuotaRow(id: "q1", code: "Q1")],
            quotaMachines: [QuotaMachineRow(id: "a1", quota: "Q1", mcode: "", mname: "叉车", unit: "台班", qty: 1)]
        )
        let full = LibrarySet(
            quotas: [QuotaRow(id: "f1", code: "Q1")],
            quotaMachines: [
                QuotaMachineRow(id: "f2", quota: "Q1", mcode: "", mname: "叉车", unit: "台班", qty: 2),   // 同名同空码 → 跳过
                QuotaMachineRow(id: "f3", quota: "Q1", mcode: "", mname: "吊车", unit: "台班", qty: 3),   // 空码不同名 → 新增
                QuotaMachineRow(id: "f4", quota: "Q1", mcode: "TXJ009", mname: "叉车", unit: "台班", qty: 4), // 有码 → 新增
            ]
        )
        let (merged, report) = mergeLibraryCompletion(base: base, full: full)
        XCTAssertEqual(report.quotaMachinesAdded, 2)
        XCTAssertEqual(merged.quotaMachines.count, 3)
        XCTAssertEqual(merged.quotaMachines[0].qty, 1)  // base 行不变
    }

    func testMergeIdempotentWithRealFullLibrary() throws {
        let full = try XCTUnwrap(loadBundledFullLibrary())
        let base = Self.loadAppSeedLibrarySet()
        let (merged1, report1) = mergeLibraryCompletion(base: base, full: full)
        // 与设计文档 §5 的实测数一致（以 App 现行种子为 base）。
        XCTAssertEqual(report1.quotasAdded, 547)
        XCTAssertEqual(report1.rulesAdded, 6116)
        XCTAssertEqual(report1.materialsAdded, 590)
        XCTAssertEqual(report1.quotaMachinesAdded, 667)
        XCTAssertEqual(report1.quotaInstrumentsAdded, 496)
        XCTAssertEqual(report1.machinePricesAdded, 3)
        XCTAssertEqual(report1.instrumentPricesAdded, 3)
        XCTAssertEqual(report1.orphansSkipped, 0)
        XCTAssertEqual(merged1.quotas.count, 3169)
        // 幂等：再合并一次，新增必为 0 且结果全等。
        let (merged2, report2) = mergeLibraryCompletion(base: merged1, full: full)
        XCTAssertEqual(report2.totalAdded, 0)
        XCTAssertEqual(merged2, merged1)
    }

    // MARK: - 内置完整库完整性（与转换脚本产物一致，设计文档 §4.7）

    func testBundledFullLibraryIntegrity() throws {
        let full = try XCTUnwrap(loadBundledFullLibrary(), "内置完整库必须能经 Bundle.module 加载")
        XCTAssertEqual(full.quotas.count, 3092)
        XCTAssertEqual(full.shortlist.count, 0)
        XCTAssertEqual(full.materials.count, 591)
        XCTAssertEqual(full.rules.count, 6116)
        XCTAssertEqual(full.machinePrices.count, 58)
        XCTAssertEqual(full.instrumentPrices.count, 97)
        XCTAssertEqual(full.quotaMachines.count, 2156)
        XCTAssertEqual(full.quotaInstruments.count, 1876)
        // 整册 T5G 在库（App 旧种子全缺的 527 条）。
        XCTAssertEqual(full.quotas.filter { $0.code.hasPrefix("T5G") }.count, 527)
        // 规则全部按“标准消耗默认生效”转换（引擎 kind=通用、适用工程=全）。
        XCTAssertTrue(full.rules.allSatisfy { $0.kind == "通用" && $0.appliesTo == "全" && $0.variant.isEmpty })
        // 无编码条目保留空码、不臆造（转换报告实测数）。
        XCTAssertEqual(full.quotaMachines.filter { $0.mcode.isEmpty }.count, 426)
        XCTAssertEqual(full.quotaInstruments.filter { $0.mcode.isEmpty }.count, 172)
        // 小程序独有台班价编码在库（合并时将补给 App）。
        XCTAssertTrue(full.machinePrices.contains { $0.code == "TXJ001" && $0.price == 144 })
        XCTAssertTrue(full.instrumentPrices.contains { $0.code == "TXY100" })
        // TXL4-026 的材料规则在库（端到端用例的数据前提）。
        XCTAssertTrue(full.rules.contains { $0.quota == "TXL4-026" && $0.material == "电缆" && $0.consumption == 1015 })
    }

    // MARK: - 引擎端到端：合并后插入定额自动生成表三乙/丙、表四

    func testEndToEndTXL4026AfterCompletion() throws {
        let full = try XCTUnwrap(loadBundledFullLibrary())
        let base = Self.loadAppSeedLibrarySet()
        let seed = loadSeed()
        let project = smallProject { p in
            p.quantities = [QuantityRow(quota: "TXL4-026", variant: "", unit: "", qty: 2, coef: 1)]
        }
        // 合并前：App 种子中 TXL4-026 有机械/仪表关联、无材料关联 → 表四不出它的材料。
        let before = calcProject(project, Self.libs(from: base, seed: seed))
        XCTAssertEqual(matQty(before, "电缆", ""), 0)
        XCTAssertEqual(before.table3B.rows.first { $0.equipName == "电缆拖车" }?.sessions ?? 0, 0.8, accuracy: 0.001)
        // 合并后：三张表齐全，数量 = 消耗量 × 工程量(2)。
        let (merged, _) = mergeLibraryCompletion(base: base, full: full)
        let after = calcProject(project, Self.libs(from: merged, seed: seed))
        let bRows = after.table3B.rows.filter { $0.quota == "TXL4-026" }
        XCTAssertEqual(bRows.first { $0.equipName == "电缆拖车" }?.sessions ?? 0, 0.8, accuracy: 0.001)   // TXJ026 0.4×2
        XCTAssertEqual(bRows.first { $0.equipName == "载重汽车 (5t)" }?.sessions ?? 0, 0.8, accuracy: 0.001) // TXJ016 0.4×2
        let cRows = after.table3C.rows.filter { $0.quota == "TXL4-026" }
        XCTAssertEqual(cRows.first { $0.equipName == "有毒有害气体检测仪" }?.sessions ?? 0, 0.8, accuracy: 0.001) // TXY094 0.4×2
        XCTAssertEqual(cRows.first { $0.equipName == "可燃气体检测仪" }?.sessions ?? 0, 0.8, accuracy: 0.001)     // TXY095 0.4×2
        XCTAssertEqual(matQty(after, "电缆", ""), 2030, accuracy: 0.001)          // 1015×2
        XCTAssertEqual(matQty(after, "电缆托板", ""), 70.7, accuracy: 0.001)       // 35.35×2
        XCTAssertEqual(matQty(after, "热缩端帽(带气门)", ""), 10.1, accuracy: 0.001) // 5.05×2
    }

    // MARK: - 辅助

    /// App 现行种子（Fixtures/seed.json，Electron 格式）→ LibrarySet（材料按甲/乙/设备三分）。
    static func loadAppSeedLibrarySet() -> LibrarySet {
        struct SeedFile: Decodable {
            var quotas: [QuotaRow]
            var materials_jia: [SeedMat]
            var materials_yi: [SeedMat]
            var materials_equip: [SeedMat]
            var rules: [RuleRow]
            var machinePrices: [MachinePriceRow]
            var instrumentPrices: [InstrumentPriceRow]
            var quotaMachines: [QuotaMachineRow]
            var quotaInstruments: [QuotaInstrumentRow]
            struct SeedMat: Decodable { var name: String; var spec: String; var unit: String; var priceExcl: Double }
        }
        let url = Bundle.module.url(forResource: "seed", withExtension: "json", subdirectory: "Fixtures")!
        let f = try! JSONDecoder().decode(SeedFile.self, from: Data(contentsOf: url))
        func mats(_ rows: [SeedFile.SeedMat], _ supply: String) -> [MaterialRow] {
            rows.map { MaterialRow(name: $0.name, spec: $0.spec, unit: $0.unit, priceExcl: $0.priceExcl, supply: supply) }
        }
        return LibrarySet(
            quotas: f.quotas,
            materials: mats(f.materials_jia, "甲供") + mats(f.materials_yi, "乙供") + mats(f.materials_equip, "设备"),
            rules: f.rules,
            machinePrices: f.machinePrices,
            instrumentPrices: f.instrumentPrices,
            quotaMachines: f.quotaMachines,
            quotaInstruments: f.quotaInstruments
        )
    }

    /// LibrarySet → 引擎 Libs（费率沿用种子具名费率，与 ProfileLibs 的透传一致）。
    static func libs(from set: LibrarySet, seed: SeedFixture) -> Libs {
        var l = namedLibs(from: seed)
        l.quotas = set.quotas.map { $0.toEngine() }
        l.materials = set.materials.map { $0.toEngine() }
        l.rules = set.rules.map { $0.toEngine() }
        l.machinePrices = set.machinePrices.map { $0.toEngine() }
        l.instrumentPrices = set.instrumentPrices.map { $0.toEngine() }
        l.quotaMachines = set.quotaMachines.map { $0.toEngine() }
        l.quotaInstruments = set.quotaInstruments.map { $0.toEngine() }
        return l
    }
}
