import Foundation

/// 定额库补全合并（v2.1.0，见 docs/v2.1-data-completion-design.md §5）。
///
/// 总原则：**只增不改**。base 中任何一行、任何字段（工日、价格、消耗量）都不修改；
/// 只把 full 中 base 没有的行按 full 内顺序追加到表尾，base 原行顺序不变。
/// 共同编码的工日/台班价小程序与 App 不同源，一律以 base（App 现值，经结算书验证）为准——
/// 靠“只增不改”天然保证，不做字段级调和。合并幂等：对合并结果再合并，新增必为 0。

public struct LibraryCompletionReport: Equatable {
    public var quotasAdded = 0
    public var rulesAdded = 0
    public var materialsAdded = 0
    public var quotaMachinesAdded = 0
    public var quotaInstrumentsAdded = 0
    public var machinePricesAdded = 0
    public var instrumentPricesAdded = 0
    /// full 中指向不存在定额的关联行（rules/机械/仪表）被跳过的条数。
    public var orphansSkipped = 0
    public init() {}
    public var pricesAdded: Int { machinePricesAdded + instrumentPricesAdded }
    public var totalAdded: Int {
        quotasAdded + rulesAdded + materialsAdded + quotaMachinesAdded
            + quotaInstrumentsAdded + machinePricesAdded + instrumentPricesAdded
    }
    /// 一行明细（确认框与完成报告共用）：“定额 +N 条、材料关联 +N 条、……”。
    public var detailText: String {
        "定额 +\(quotasAdded) 条、材料关联 +\(rulesAdded) 条、机械关联 +\(quotaMachinesAdded) 条、"
            + "仪表关联 +\(quotaInstrumentsAdded) 条、材料 +\(materialsAdded) 条、台班价 +\(pricesAdded) 条"
    }
}

/// 并集合并：把 full（内置完整库）中 base 缺失的行补进 base，返回合并结果与报告。
/// 判定键：quotas 按 code；rules 按 (quota, material, spec)；materials 按 (name, spec)；
/// quotaMachines/quotaInstruments 按 (quota, mcode)，mcode 为空的行以 (quota, mname) 为键
/// （源数据少量条目无编码，保留空码不臆造，以名称区分避免互相折叠）；
/// 台班价按 code——新增行价格取 full，仅限 base 缺失的编码。
/// full 的关联行若其 quota 不在合并后的定额集合中，视为孤儿跳过并计数；
/// base 自身的行（包括 base 原有的孤儿行）一律原样保留。shortlist 不触碰。
public func mergeLibraryCompletion(base: LibrarySet, full: LibrarySet)
    -> (merged: LibrarySet, report: LibraryCompletionReport) {
    var report = LibraryCompletionReport()
    var merged = base

    // 定额：按 code 只增。
    var quotaCodes = Set(base.quotas.map { $0.code })
    for row in full.quotas where !quotaCodes.contains(row.code) {
        quotaCodes.insert(row.code)
        merged.quotas.append(row)
        report.quotasAdded += 1
    }

    // 材料：按 (name, spec) 只增。
    var materialKeys = Set(base.materials.map { "\($0.name)|\($0.spec)" })
    for row in full.materials {
        let key = "\(row.name)|\(row.spec)"
        guard !materialKeys.contains(key) else { continue }
        materialKeys.insert(key)
        merged.materials.append(row)
        report.materialsAdded += 1
    }

    // 材料关联：按 (quota, material, spec) 只增；孤儿（定额不存在）跳过。
    var ruleKeys = Set(base.rules.map { "\($0.quota)|\($0.material)|\($0.spec)" })
    for row in full.rules {
        guard quotaCodes.contains(row.quota) else { report.orphansSkipped += 1; continue }
        let key = "\(row.quota)|\(row.material)|\(row.spec)"
        guard !ruleKeys.contains(key) else { continue }
        ruleKeys.insert(key)
        merged.rules.append(row)
        report.rulesAdded += 1
    }

    // 机械/仪表关联：按 (quota, mcode) 只增，空码以 (quota, mname) 为键；孤儿跳过。
    func assocKey(quota: String, mcode: String, mname: String) -> String {
        mcode.isEmpty ? "\(quota)|name:\(mname)" : "\(quota)|\(mcode)"
    }
    var qmKeys = Set(base.quotaMachines.map { assocKey(quota: $0.quota, mcode: $0.mcode, mname: $0.mname) })
    for row in full.quotaMachines {
        guard quotaCodes.contains(row.quota) else { report.orphansSkipped += 1; continue }
        let key = assocKey(quota: row.quota, mcode: row.mcode, mname: row.mname)
        guard !qmKeys.contains(key) else { continue }
        qmKeys.insert(key)
        merged.quotaMachines.append(row)
        report.quotaMachinesAdded += 1
    }
    var qiKeys = Set(base.quotaInstruments.map { assocKey(quota: $0.quota, mcode: $0.mcode, mname: $0.mname) })
    for row in full.quotaInstruments {
        guard quotaCodes.contains(row.quota) else { report.orphansSkipped += 1; continue }
        let key = assocKey(quota: row.quota, mcode: row.mcode, mname: row.mname)
        guard !qiKeys.contains(key) else { continue }
        qiKeys.insert(key)
        merged.quotaInstruments.append(row)
        report.quotaInstrumentsAdded += 1
    }

    // 台班价：按 code 只补缺失（价格取 full），已有编码的价格一字不动。
    var mpCodes = Set(base.machinePrices.map { $0.code })
    for row in full.machinePrices where !mpCodes.contains(row.code) {
        mpCodes.insert(row.code)
        merged.machinePrices.append(row)
        report.machinePricesAdded += 1
    }
    var ipCodes = Set(base.instrumentPrices.map { $0.code })
    for row in full.instrumentPrices where !ipCodes.contains(row.code) {
        ipCodes.insert(row.code)
        merged.instrumentPrices.append(row)
        report.instrumentPricesAdded += 1
    }

    return (merged, report)
}
