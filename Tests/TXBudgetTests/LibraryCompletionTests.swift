import XCTest
@testable import TXBudget

/// v2.2.0 定额库补全并校正（docs/v2.2-correction-design.md）：
/// 合并逻辑（先校正后补全/校正范围/自建行与价格不动/防重复/孤儿跳过/报告计数/幂等）、
/// 内置完整库完整性（官方校正版）、引擎端到端（TXL4-026 校正后表三丙按官方 0.3 台班）。
/// v2.1.0 时本文件验证“只增不改”；v2.2.0 起 key 命中行按官方校正，契约见设计文档 §5。
final class LibraryCompletionTests: XCTestCase {

    // MARK: - 合并逻辑：key 命中校正、未命中补全、价格永不校正

    func testMergeCorrectsKeyedRowsAndAddsMissing() {
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
        // full：同键行（官方值全不同）+ 新行 + 孤儿行（GHOST 定额不存在）。
        let full = LibrarySet(
            quotas: [QuotaRow(id: "f1", code: "Q1", name: "官方名", unit: "台", tech: 9.9, labor: 9.9),
                     QuotaRow(id: "f2", code: "Q2", name: "定额二", unit: "个", tech: 3, labor: 1)],
            materials: [MaterialRow(id: "f3", name: "钢", spec: "", unit: "t", priceExcl: 1, supply: "甲供"),
                        MaterialRow(id: "f4", name: "铜", spec: "", unit: "kg", priceExcl: 5, supply: "甲供")],
            rules: [RuleRow(id: "f5", quota: "Q1", material: "钢", spec: "", unit: "条", consumption: 7, supply: "甲供", kind: "通用"),
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

        // key 命中行被官方校正：定额名称/单位/工日、关联消耗量；id 与不校正字段保留。
        XCTAssertEqual(merged.quotas[0].id, "q1")
        XCTAssertEqual(merged.quotas[0].name, "官方名")
        XCTAssertEqual(merged.quotas[0].unit, "台")
        XCTAssertEqual(merged.quotas[0].tech, 9.9)
        XCTAssertEqual(merged.quotas[0].labor, 9.9)
        XCTAssertEqual(merged.rules[0].consumption, 7)
        XCTAssertEqual(merged.rules[0].unit, "条")
        XCTAssertEqual(merged.rules[0].supply, "乙供")  // supply 不在校正范围
        XCTAssertEqual(merged.quotaMachines[0].qty, 9)
        XCTAssertEqual(merged.quotaInstruments[0].qty, 9)
        // 价格绝不校正：材料价与台班价保持 base 现值。
        XCTAssertEqual(merged.materials[0], base.materials[0])
        XCTAssertEqual(merged.materials[0].priceExcl, 99)
        XCTAssertEqual(merged.machinePrices[0].price, 111)
        XCTAssertEqual(merged.instrumentPrices[0].price, 222)
        // 新行被追加；孤儿行（2 条：rules + quotaMachines 各 1）跳过。
        XCTAssertEqual(merged.quotas.count, 2)
        XCTAssertEqual(merged.materials.count, 2)
        XCTAssertEqual(merged.rules.count, 2)
        XCTAssertEqual(merged.quotaMachines.count, 2)
        XCTAssertEqual(merged.quotaInstruments.count, 2)
        XCTAssertEqual(merged.machinePrices.count, 2)
        XCTAssertEqual(merged.instrumentPrices.count, 2)
        XCTAssertEqual(merged.machinePrices[1].price, 50)  // 新增编码的价格取 full
        // 报告计数：补全与校正分开。
        XCTAssertEqual(report.quotasAdded, 1)
        XCTAssertEqual(report.rulesAdded, 1)
        XCTAssertEqual(report.materialsAdded, 1)
        XCTAssertEqual(report.quotaMachinesAdded, 1)
        XCTAssertEqual(report.quotaInstrumentsAdded, 1)
        XCTAssertEqual(report.machinePricesAdded, 1)
        XCTAssertEqual(report.instrumentPricesAdded, 1)
        XCTAssertEqual(report.orphansSkipped, 2)
        XCTAssertEqual(report.totalAdded, 7)
        XCTAssertEqual(report.quotasCorrected, 1)
        XCTAssertEqual(report.rulesCorrected, 1)
        XCTAssertEqual(report.quotaMachinesCorrected, 1)
        XCTAssertEqual(report.quotaInstrumentsCorrected, 1)
        XCTAssertEqual(report.materialsRenamed, 0)
        XCTAssertEqual(report.totalCorrected, 4)
        // shortlist 永不触碰。
        XCTAssertEqual(merged.shortlist, base.shortlist)
        // 幂等：再合并一次，补全与校正均为 0 且结果全等。
        let (merged2, report2) = mergeLibraryCompletion(base: merged, full: full)
        XCTAssertEqual(report2.totalAdded, 0)
        XCTAssertEqual(report2.totalCorrected, 0)
        XCTAssertEqual(merged2, merged)
    }

    /// 校正范围：变体规则不校正、自建定额整行不动、材料改名连带规则改名且保价。
    func testCorrectionScopeVariantUserRowsAndRename() {
        let base = LibrarySet(
            quotas: [QuotaRow(id: "q1", code: "Q1", name: "旧名", unit: "个", tech: 9, labor: 9),
                     QuotaRow(id: "u1", code: "USER1", name: "用户定额", unit: "项", tech: 3, labor: 2)],
            materials: [MaterialRow(id: "m1", name: "水泥 32.5", spec: "", unit: "t", priceExcl: 42, supply: "乙供")],
            rules: [RuleRow(id: "r1", quota: "Q1", material: "水泥 32.5", spec: "", unit: "kg",
                            consumption: 5, supply: "乙供", kind: "通用", variant: "", appliesTo: "全"),
                    RuleRow(id: "r2", quota: "Q1", material: "水泥 32.5", spec: "", unit: "kg",
                            consumption: 6, supply: "乙供", kind: "变体", variant: "石膏板墙", appliesTo: "全"),
                    RuleRow(id: "r3", quota: "USER1", material: "自建材料", spec: "", unit: "个",
                            consumption: 1, supply: "乙供", kind: "通用", variant: "", appliesTo: "全")]
        )
        let full = LibrarySet(
            quotas: [QuotaRow(id: "f1", code: "Q1", name: "官方名", unit: "台", tech: 2, labor: 1)],
            materials: [MaterialRow(id: "f2", name: "水泥32.5", spec: "", unit: "t", priceExcl: 1, supply: "甲供")],
            rules: [RuleRow(id: "f3", quota: "Q1", material: "水泥32.5", spec: "", unit: "t",
                            consumption: 0.45, supply: "甲供", kind: "通用", variant: "", appliesTo: "全")]
        )
        let (merged, report) = mergeLibraryCompletion(base: base, full: full)
        // 定额校正只命中 Q1；自建 USER1 整行逐字段不动。
        XCTAssertEqual(merged.quotas[0].name, "官方名")
        XCTAssertEqual(merged.quotas[1], base.quotas[1])
        XCTAssertEqual(report.quotasCorrected, 1)
        // 材料条目改名为官方写法，价格/供方不动。
        XCTAssertEqual(merged.materials[0].name, "水泥32.5")
        XCTAssertEqual(merged.materials[0].priceExcl, 42)
        XCTAssertEqual(merged.materials[0].supply, "乙供")
        XCTAssertEqual(report.materialsRenamed, 1)
        // 通用规则被校正（量/单位/名）；变体规则只连带改名、量不动；自建规则全不动。
        XCTAssertEqual(merged.rules[0].consumption, 0.45)
        XCTAssertEqual(merged.rules[0].unit, "t")
        XCTAssertEqual(merged.rules[0].material, "水泥32.5")
        XCTAssertEqual(merged.rules[1].material, "水泥32.5")
        XCTAssertEqual(merged.rules[1].consumption, 6)
        XCTAssertEqual(merged.rules[2], base.rules[2])
        XCTAssertEqual(report.rulesCorrected, 1)
        XCTAssertEqual(report.totalAdded, 0)
        // 幂等。
        let (merged2, report2) = mergeLibraryCompletion(base: merged, full: full)
        XCTAssertEqual(report2.totalCorrected, 0)
        XCTAssertEqual(report2.totalAdded, 0)
        XCTAssertEqual(merged2, merged)
    }

    /// 空码关联按名称校正；full 中同名异码行视为同一台班，不重复追加（防表三双计）。
    func testMergeEmptyCodeRowsCorrectedByNameNotDuplicated() {
        let base = LibrarySet(
            quotas: [QuotaRow(id: "q1", code: "Q1")],
            quotaMachines: [QuotaMachineRow(id: "a1", quota: "Q1", mcode: "", mname: "叉车", unit: "台班", qty: 1)]
        )
        let full = LibrarySet(
            quotas: [QuotaRow(id: "f1", code: "Q1")],
            quotaMachines: [
                QuotaMachineRow(id: "f2", quota: "Q1", mcode: "", mname: "叉车", unit: "台班", qty: 2),   // 同名同空码 → 按名校正
                QuotaMachineRow(id: "f3", quota: "Q1", mcode: "", mname: "吊车", unit: "台班", qty: 3),   // 空码不同名 → 新增
                QuotaMachineRow(id: "f4", quota: "Q1", mcode: "TXJ009", mname: "叉车", unit: "台班", qty: 4), // 同名异码 → 同一台班，不重复追加
            ]
        )
        let (merged, report) = mergeLibraryCompletion(base: base, full: full)
        XCTAssertEqual(report.quotaMachinesCorrected, 1)
        XCTAssertEqual(report.quotaMachinesAdded, 1)
        XCTAssertEqual(merged.quotaMachines.count, 2)
        XCTAssertEqual(merged.quotaMachines[0].qty, 2)  // base 空码行按官方量校正
        XCTAssertEqual(merged.quotaMachines[1].mname, "吊车")
    }

    func testMergeIdempotentWithRealFullLibrary() throws {
        let full = try XCTUnwrap(loadBundledFullLibrary())
        let base = Self.loadAppSeedLibrarySet()
        let (merged1, report1) = mergeLibraryCompletion(base: base, full: full)
        // 实测数（以 App 现行种子为 base，v2.2.0 首跑回填；见 docs/v2.2-correction-design.md §5）。
        XCTAssertEqual(report1.quotasAdded, 547)
        XCTAssertEqual(report1.rulesAdded, 6634)
        XCTAssertEqual(report1.materialsAdded, 666)
        XCTAssertEqual(report1.quotaMachinesAdded, 695)
        XCTAssertEqual(report1.quotaInstrumentsAdded, 327)
        XCTAssertEqual(report1.machinePricesAdded, 3)
        XCTAssertEqual(report1.instrumentPricesAdded, 3)
        XCTAssertEqual(report1.orphansSkipped, 0)
        XCTAssertEqual(report1.quotasCorrected, 2104)
        XCTAssertEqual(report1.rulesCorrected, 0)
        XCTAssertEqual(report1.quotaMachinesCorrected, 1067)
        XCTAssertEqual(report1.quotaInstrumentsCorrected, 55)
        XCTAssertEqual(report1.materialsRenamed, 0)
        XCTAssertEqual(merged1.quotas.count, 3169)
        // 幂等：再合并一次，补全与校正必为 0 且结果全等。
        let (merged2, report2) = mergeLibraryCompletion(base: merged1, full: full)
        XCTAssertEqual(report2.totalAdded, 0)
        XCTAssertEqual(report2.totalCorrected, 0)
        XCTAssertEqual(merged2, merged1)
    }

    // MARK: - 内置完整库完整性（官方校正版，与构建脚本产物一致，设计文档 §4）

    func testBundledFullLibraryIntegrity() throws {
        let full = try XCTUnwrap(loadBundledFullLibrary(), "内置完整库必须能经 Bundle.module 加载")
        XCTAssertEqual(full.quotas.count, 3092)
        XCTAssertEqual(full.shortlist.count, 0)
        XCTAssertEqual(full.materials.count, 668)
        XCTAssertEqual(full.rules.count, 6634)
        XCTAssertEqual(full.machinePrices.count, 58)
        XCTAssertEqual(full.instrumentPrices.count, 97)
        XCTAssertEqual(full.quotaMachines.count, 2107)
        XCTAssertEqual(full.quotaInstruments.count, 1887)
        // 整册 T5G 在库（App 旧种子全缺的 527 条）。
        XCTAssertEqual(full.quotas.filter { $0.code.hasPrefix("T5G") }.count, 527)
        // 手册外定额保留不删（官方 TGD2 编号自 160 跳号、无 161）。
        XCTAssertTrue(full.quotas.contains { $0.code == "TGD2-161" })
        // 规则全部按“标准消耗默认生效”转换（引擎 kind=通用、适用工程=全）。
        XCTAssertTrue(full.rules.allSatisfy { $0.kind == "通用" && $0.appliesTo == "全" && $0.variant.isEmpty })
        // 无编码条目保留空码、不臆造（构建实测数：官方有此台班但名称解析不到唯一编码）。
        XCTAssertEqual(full.quotaMachines.filter { $0.mcode.isEmpty }.count, 77)
        XCTAssertEqual(full.quotaInstruments.filter { $0.mcode.isEmpty }.count, 10)
        // 价格沿用 v2.1 来源不变（官方手册无价格，不在校正范围）。
        XCTAssertTrue(full.machinePrices.contains { $0.code == "TXJ001" && $0.price == 144 })
        XCTAssertTrue(full.instrumentPrices.contains { $0.code == "TXY100" })
        // 官方校正锚点（差异报告实证条目）：
        // 工日校正：T5G3-022 技工 5.84 → 5.48。
        XCTAssertEqual(full.quotas.first { $0.code == "T5G3-022" }?.tech ?? 0, 5.48, accuracy: 0.0001)
        // 设计选用（＊）：TXL3-187 光缆标识牌保留行、量 0、remark 注明。
        let star = full.rules.first { $0.quota == "TXL3-187" && $0.material == "光缆标识牌" }
        XCTAssertEqual(star?.consumption ?? -1, 0)
        XCTAssertEqual(star?.remark, "设计选用")
        XCTAssertEqual(full.rules.first { $0.quota == "TXL3-187" && $0.material == "架空光缆" }?.consumption ?? 0, 1007)
        // 数量校正约 30 倍：TGD2-112 镀锌钢管 100 → 3000。
        XCTAssertEqual(full.rules.first { $0.quota == "TGD2-112" && $0.material.hasPrefix("镀锌钢管") }?.consumption ?? 0, 3000)
        // 仪表校正：TXL4-026 两检测仪 0.4 → 0.3。
        XCTAssertEqual(full.quotaInstruments.first { $0.quota == "TXL4-026" && $0.mcode == "TXY094" }?.qty ?? 0, 0.3, accuracy: 0.0001)
        XCTAssertEqual(full.quotaInstruments.first { $0.quota == "TXL4-026" && $0.mcode == "TXY095" }?.qty ?? 0, 0.3, accuracy: 0.0001)
        // TXL4-026 的材料规则在库（端到端用例的数据前提）。
        XCTAssertTrue(full.rules.contains { $0.quota == "TXL4-026" && $0.material == "电缆" && $0.consumption == 1015 })
    }

    // MARK: - 引擎端到端：合并并校正后插入定额自动生成表三乙/丙、表四

    func testEndToEndTXL4026AfterCompletion() throws {
        let full = try XCTUnwrap(loadBundledFullLibrary())
        let base = Self.loadAppSeedLibrarySet()
        let seed = loadSeed()
        let project = smallProject { p in
            p.quantities = [QuantityRow(quota: "TXL4-026", variant: "", unit: "", qty: 2, coef: 1)]
        }
        // 合并前：App 种子中 TXL4-026 有机械/仪表关联、无材料关联 → 表四不出它的材料；
        // 仪表台班还是小程序的 0.4。
        let before = calcProject(project, Self.libs(from: base, seed: seed))
        XCTAssertEqual(matQty(before, "电缆", ""), 0)
        XCTAssertEqual(before.table3B.rows.first { $0.equipName == "电缆拖车" }?.sessions ?? 0, 0.8, accuracy: 0.001)
        // 合并并校正后：三张表齐全，数量 = 官方消耗量 × 工程量(2)。
        let (merged, _) = mergeLibraryCompletion(base: base, full: full)
        let after = calcProject(project, Self.libs(from: merged, seed: seed))
        let bRows = after.table3B.rows.filter { $0.quota == "TXL4-026" }
        XCTAssertEqual(bRows.first { $0.equipName == "电缆拖车" }?.sessions ?? 0, 0.8, accuracy: 0.001)   // TXJ026 0.4×2
        XCTAssertEqual(bRows.first { $0.equipName == "载重汽车(5t)" }?.sessions ?? 0, 0.8, accuracy: 0.001) // TXJ016 0.4×2（名称已按官方校正去空格）
        let cRows = after.table3C.rows.filter { $0.quota == "TXL4-026" }
        XCTAssertEqual(cRows.first { $0.equipName == "有毒有害气体检测仪" }?.sessions ?? 0, 0.6, accuracy: 0.001) // TXY094 官方 0.3×2（小程序 0.4 已校正）
        XCTAssertEqual(cRows.first { $0.equipName == "可燃气体检测仪" }?.sessions ?? 0, 0.6, accuracy: 0.001)     // TXY095 官方 0.3×2
        XCTAssertEqual(matQty(after, "电缆", ""), 2030, accuracy: 0.001)          // 1015×2
        XCTAssertEqual(matQty(after, "电缆托板", ""), 70.7, accuracy: 0.001)       // 35.35×2
        XCTAssertEqual(matQty(after, "托板塑料垫", ""), 70.7, accuracy: 0.001)     // 35.35×2（官方有此材料，小程序缺失）
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
