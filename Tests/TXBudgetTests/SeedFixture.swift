/// 测试夹具：Electron 版 data/seed.json（原样复制）+ tests/fixtures/lo_values.json（原样复制）。
/// Seed 的 materials 按 jia/yi/equip 三数组分供，rules 无 id（测试里按序补 r0…，与 JS 测试一致）。

import Foundation
@testable import TXBudget

struct SeedMaterialJSON: Decodable {
    var name: String
    var spec: String
    var unit: String
    var priceExcl: Double
}

struct SeedRuleJSON: Decodable {
    var quota: String
    var material: String
    var spec: String
    var consumption: Double
    var supply: String
    var kind: String
    var variant: String
}

/// rateGrid 单元格：数值 / 字符串（表头/标签）/ null。
/// JS 的 rateGridToRates 对非数值单元格走 numOr(v, 0) 回落为 0，此处字符串 → nil → 0，与之一致。
enum SeedCell: Decodable {
    case number(Double)
    case text(String)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let d = try? c.decode(Double.self) {
            self = .number(d)
        } else if let s = try? c.decode(String.self) {
            self = .text(s)
        } else {
            self = .null
        }
    }

    var doubleValue: Double? {
        if case .number(let d) = self { return d }
        return nil
    }
}

struct SeedFixture: Decodable {
    var quotas: [Quota]
    var materials_jia: [SeedMaterialJSON]
    var materials_yi: [SeedMaterialJSON]
    var materials_equip: [SeedMaterialJSON]
    var rateGrid: [[SeedCell]]
    var winterTable: [String: Double]
    var machinePrices: [MachinePrice]
    var instrumentPrices: [InstrumentPrice]
    var quotaMachines: [QuotaMachine]
    var quotaInstruments: [QuotaInstrument]
    var rules: [SeedRuleJSON]

    /// rateGrid 转 [[Double?]]（字符串/null → nil，消费方再按 JS numOr 回落为 0）。
    var rateGridNumbers: [[Double?]] {
        rateGrid.map { row in row.map { $0.doubleValue } }
    }
}

func loadSeed() -> SeedFixture {
    let url = Bundle.module.url(forResource: "seed", withExtension: "json", subdirectory: "Fixtures")!
    let data = try! Data(contentsOf: url)
    return try! JSONDecoder().decode(SeedFixture.self, from: data)
}

func loadLOValues() -> [String: Double] {
    let url = Bundle.module.url(forResource: "lo_values", withExtension: "json", subdirectory: "Fixtures")!
    let data = try! Data(contentsOf: url)
    return try! JSONDecoder().decode([String: Double].self, from: data)
}

func seedMaterials(_ seed: SeedFixture) -> [Material] {
    seed.materials_jia.map { Material(name: $0.name, spec: $0.spec, unit: $0.unit, priceExcl: $0.priceExcl, supply: "甲供") }
        + seed.materials_yi.map { Material(name: $0.name, spec: $0.spec, unit: $0.unit, priceExcl: $0.priceExcl, supply: "乙供") }
        + seed.materials_equip.map { Material(name: $0.name, spec: $0.spec, unit: $0.unit, priceExcl: $0.priceExcl, supply: "设备") }
}

func seedRules(_ seed: SeedFixture) -> [Rule] {
    seed.rules.enumerated().map { i, r in
        Rule(id: "r\(i)", quota: r.quota, material: r.material, spec: r.spec,
             consumption: r.consumption, supply: r.supply, kind: r.kind, variant: r.variant)
    }
}

/// JS engine.test.mjs 的 libs：只有 rateGrid（无 winterTable、无 rates）→ 冬雨季费率 0。
func engineLibs(from seed: SeedFixture) -> Libs {
    Libs(quotas: seed.quotas, materials: seedMaterials(seed), rules: seedRules(seed),
         rateGrid: seed.rateGridNumbers,
         machinePrices: seed.machinePrices, instrumentPrices: seed.instrumentPrices,
         quotaMachines: seed.quotaMachines, quotaInstruments: seed.quotaInstruments)
}

/// JS discount.test.mjs / crosscheck.test.mjs 的 libsGrid：rateGrid + winterTable。
func gridLibs(from seed: SeedFixture) -> Libs {
    Libs(quotas: seed.quotas, materials: seedMaterials(seed), rules: seedRules(seed),
         winterTable: seed.winterTable, rateGrid: seed.rateGridNumbers,
         machinePrices: seed.machinePrices, instrumentPrices: seed.instrumentPrices,
         quotaMachines: seed.quotaMachines, quotaInstruments: seed.quotaInstruments)
}

/// JS profileToLibs(seedToProfile(seed)) 的形状：具名费率（由 rateGrid 转换）+ winterTable + 增值税率。
func namedLibs(from seed: SeedFixture, discountRule: DiscountRule? = nil) -> Libs {
    var libs = gridLibs(from: seed)
    libs.rates = Rates(byProjectType: rateGridToRates(seed.rateGridNumbers),
                       winterTable: seed.winterTable,
                       vatRates: VatRates(jiaTax: 0.13, yiTax: 0.09, outputTax: 0.09, safetyVat: 0))
    libs.discountRule = discountRule
    return libs
}

/// JS discount.test.mjs 的 setWinter：把指定工程类型的 winterRate 置为给定值（nil = 查表）。
func withWinterRate(_ libs: Libs, _ value: Double?, projectType: String = "通信线路工程") -> Libs {
    var out = libs
    var rates = out.rates ?? Rates()
    var byType = rates.byProjectType ?? [:]
    var named = byType[projectType] ?? NamedRates()
    named.winterRate = value
    byType[projectType] = named
    rates.byProjectType = byType
    out.rates = rates
    return out
}

/// JS discount.test.mjs 的 smallProject。
func smallProject(over: (inout Project) -> Void = { _ in }) -> Project {
    var info = ProjectInfo()
    info.工程类型 = "通信线路工程"
    info.施工折扣 = 1
    info.施工距离 = "35KM以内"
    info.施工调遣分类 = "施工队伍调遣人数(线路、管道）"
    info.冬雨季施工费 = "Ⅲ类地区"
    info.甲供增值税 = 0.13
    info.乙供增值税 = 0.09
    var project = Project(info: info, quantities: [
        QuantityRow(quota: "TXL1-008", variant: "", unit: "", qty: 7, coef: 1),
    ])
    over(&project)
    return project
}

func matQty(_ res: CalcResult, _ name: String, _ spec: String) -> Double {
    for t in [res.table4A, res.table4B, res.table4Equip] {
        if let row = t.rows.first(where: { $0.name == name && $0.spec == spec }) { return row.qty }
    }
    return 0
}
