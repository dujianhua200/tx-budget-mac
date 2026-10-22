import Foundation

/// 定额库补全并校正（v2.2.0，见 docs/v2.2-correction-design.md §5；v2.1.0 为纯补全）。
///
/// 流程 = **先校正、后补全**：
/// - 校正：key 命中内置完整库（已按官方 451 手册重建）的 base 行，其名称/单位/工日/消耗量
///   以内置库（官方）值覆盖；key 不在内置库的用户自建行绝不触碰；价格字段
///   （machinePrices/instrumentPrices 的 price、materials 的 priceExcl）绝不校正。
///   材料改名由规则/条目改名连带：materials 条目按（归一化名, spec）改名为官方写法，
///   引用旧名的规则同步改名，价格一字不动。
/// - 补全：与 v2.1 完全相同的只增不改并集合并（判定键、孤儿跳过规则不变），
///   仅机械/仪表关联的“已存在”判定补一条防重复规则：full 行与 base 行同定额且
///   归一化名称相同即视为同一台班（校正后 full 行为空码行补上了编码，若仍按编码
///   判定会把同一台班重复追加、造成表三双计）。
/// 全程幂等：对合并结果再跑一次，补全与校正计数必为 0。

/// 名称归一化（与 scripts/diff_official.py 的 norm 同口径）：
/// 全角折半角 → 去全部空白 → ø/φ 统一 Φ → ~/～/— 统一为 -。
public func libraryMatchNorm(_ s: String) -> String {
    var t = s.folding(options: [.widthInsensitive], locale: nil)
    t = t.components(separatedBy: .whitespacesAndNewlines).joined()
    t = t.replacingOccurrences(of: "ø", with: "Φ")
        .replacingOccurrences(of: "φ", with: "Φ")
        .replacingOccurrences(of: "~", with: "-")
        .replacingOccurrences(of: "—", with: "-")
    return t
}

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
    // 校正计数（v2.2.0 新增）：被官方值覆盖的行数（每行至多计 1 次）。
    public var quotasCorrected = 0
    public var rulesCorrected = 0
    public var quotaMachinesCorrected = 0
    public var quotaInstrumentsCorrected = 0
    /// materials 条目按官方写法改名的条数（仅改名，价格不动）。
    public var materialsRenamed = 0
    public init() {}
    public var pricesAdded: Int { machinePricesAdded + instrumentPricesAdded }
    public var totalAdded: Int {
        quotasAdded + rulesAdded + materialsAdded + quotaMachinesAdded
            + quotaInstrumentsAdded + machinePricesAdded + instrumentPricesAdded
    }
    public var totalCorrected: Int {
        quotasCorrected + rulesCorrected + quotaMachinesCorrected
            + quotaInstrumentsCorrected + materialsRenamed
    }
    /// 一行补全明细（确认框与完成报告共用）：“定额 +N 条、材料关联 +N 条、……”。
    public var detailText: String {
        "定额 +\(quotasAdded) 条、材料关联 +\(rulesAdded) 条、机械关联 +\(quotaMachinesAdded) 条、"
            + "仪表关联 +\(quotaInstrumentsAdded) 条、材料 +\(materialsAdded) 条、台班价 +\(pricesAdded) 条"
    }
    /// 一行校正明细：“定额校正 N 条、材料关联校正 N 条、……、材料改名 N 条”。
    public var correctedDetailText: String {
        "定额校正 \(quotasCorrected) 条、材料关联校正 \(rulesCorrected) 条、机械关联校正 \(quotaMachinesCorrected) 条、"
            + "仪表关联校正 \(quotaInstrumentsCorrected) 条、材料改名 \(materialsRenamed) 条"
    }
}

/// 校正阶段（在 base 副本上原地进行，行序不变）：见文件头说明。
private func correctLibrary(base: inout LibrarySet, full: LibrarySet, report: inout LibraryCompletionReport) {
    // 定额：按 code 校正 name/unit/tech/labor（id/book/alias/coef 不动）。
    var fullQuota: [String: QuotaRow] = [:]
    for q in full.quotas where fullQuota[q.code] == nil { fullQuota[q.code] = q }
    for i in base.quotas.indices {
        guard let f = fullQuota[base.quotas[i].code] else { continue }
        var row = base.quotas[i]
        guard row.name != f.name || row.unit != f.unit || row.tech != f.tech || row.labor != f.labor
        else { continue }
        row.name = f.name; row.unit = f.unit; row.tech = f.tech; row.labor = f.labor
        base.quotas[i] = row
        report.quotasCorrected += 1
    }

    // 材料改名：条目按（归一化名, spec）改名为官方写法（priceExcl/supply/unit/remark 不动），
    // 引用旧名的规则（含变体规则）连带改名，保持可按名查价。
    var fullMatName: [String: String] = [:]
    for m in full.materials {
        let key = "\(libraryMatchNorm(m.name))|\(m.spec)"
        if fullMatName[key] == nil { fullMatName[key] = m.name }
    }
    var renameMap: [String: String] = [:]  // "旧名|spec" -> 新名
    for i in base.materials.indices {
        let key = "\(libraryMatchNorm(base.materials[i].name))|\(base.materials[i].spec)"
        guard let newName = fullMatName[key], newName != base.materials[i].name else { continue }
        renameMap["\(base.materials[i].name)|\(base.materials[i].spec)"] = newName
        base.materials[i].name = newName
        report.materialsRenamed += 1
    }
    if !renameMap.isEmpty {
        for i in base.rules.indices {
            if let newName = renameMap["\(base.rules[i].material)|\(base.rules[i].spec)"] {
                base.rules[i].material = newName
            }
        }
    }

    // 材料关联：仅 kind == "通用" 的标准消耗规则校正 consumption/unit/material
    //（键 (quota, 归一化材料名, spec)；变体规则是用户/变体口径，绝不校正）。
    var fullRule: [String: RuleRow] = [:]
    for r in full.rules where r.kind == "通用" {
        let key = "\(r.quota)|\(libraryMatchNorm(r.material))|\(r.spec)"
        if fullRule[key] == nil { fullRule[key] = r }
    }
    for i in base.rules.indices where base.rules[i].kind == "通用" {
        let key = "\(base.rules[i].quota)|\(libraryMatchNorm(base.rules[i].material))|\(base.rules[i].spec)"
        guard let f = fullRule[key] else { continue }
        var row = base.rules[i]
        guard row.consumption != f.consumption || row.unit != f.unit || row.material != f.material
        else { continue }
        row.consumption = f.consumption; row.unit = f.unit; row.material = f.material
        base.rules[i] = row
        report.rulesCorrected += 1
    }

    // 机械/仪表关联：校正 qty/unit/mname（mcode/id 不动）。匹配先按 (quota, mcode)（mcode 非空时），
    // 再按 (quota, 归一化名称)——base 空码行靠名称命中 full 的已编码行。
    func correctAssoc<T>(_ rows: inout [T], fullRows: [T],
                         quota: (T) -> String, mcode: (T) -> String, mname: (T) -> String,
                         apply: (inout T, T) -> Bool) -> Int {
        var byCode: [String: T] = [:]
        var byName: [String: T] = [:]
        for r in fullRows {
            if !mcode(r).isEmpty {
                let k = "\(quota(r))|\(mcode(r))"
                if byCode[k] == nil { byCode[k] = r }
            }
            let nk = "\(quota(r))|\(libraryMatchNorm(mname(r)))"
            if byName[nk] == nil { byName[nk] = r }
        }
        var count = 0
        for i in rows.indices {
            let row = rows[i]
            var candidate: T?
            if !mcode(row).isEmpty {
                candidate = byCode["\(quota(row))|\(mcode(row))"]
                    ?? byName["\(quota(row))|\(libraryMatchNorm(mname(row)))"]
            } else {
                candidate = byName["\(quota(row))|\(libraryMatchNorm(mname(row)))"]
            }
            guard let f = candidate else { continue }
            var edited = row
            if apply(&edited, f) {
                rows[i] = edited
                count += 1
            }
        }
        return count
    }
    report.quotaMachinesCorrected += correctAssoc(
        &base.quotaMachines, fullRows: full.quotaMachines,
        quota: { $0.quota }, mcode: { $0.mcode }, mname: { $0.mname },
        apply: { row, f in
            guard row.qty != f.qty || row.unit != f.unit || row.mname != f.mname else { return false }
            row.qty = f.qty; row.unit = f.unit; row.mname = f.mname
            return true
        })
    report.quotaInstrumentsCorrected += correctAssoc(
        &base.quotaInstruments, fullRows: full.quotaInstruments,
        quota: { $0.quota }, mcode: { $0.mcode }, mname: { $0.mname },
        apply: { row, f in
            guard row.qty != f.qty || row.unit != f.unit || row.mname != f.mname else { return false }
            row.qty = f.qty; row.unit = f.unit; row.mname = f.mname
            return true
        })
}

/// 补全并校正：把 full（内置完整库，官方校正版）合并进 base，返回合并结果与报告。
/// 先对 base 做官方校正，再做 v2.1 的只增不改补全；用户自建行与全部价格永不被改。
/// full 的关联行若其 quota 不在合并后的定额集合中，视为孤儿跳过并计数；
/// base 自身的行（包括 base 原有的孤儿行）一律原样保留（校正命中者除外）。shortlist 不触碰。
public func mergeLibraryCompletion(base: LibrarySet, full: LibrarySet)
    -> (merged: LibrarySet, report: LibraryCompletionReport) {
    var report = LibraryCompletionReport()
    var merged = base

    // 第一段：校正（base 副本上原地改，行序不变）。
    correctLibrary(base: &merged, full: full, report: &report)

    // 第二段：补全（与 v2.1 判定一致；校正已把 base 行名对齐官方，精确键可直接命中）。
    var quotaCodes = Set(merged.quotas.map { $0.code })
    for row in full.quotas where !quotaCodes.contains(row.code) {
        quotaCodes.insert(row.code)
        merged.quotas.append(row)
        report.quotasAdded += 1
    }

    // 材料：按 (name, spec) 只增。
    var materialKeys = Set(merged.materials.map { "\($0.name)|\($0.spec)" })
    for row in full.materials {
        let key = "\(row.name)|\(row.spec)"
        guard !materialKeys.contains(key) else { continue }
        materialKeys.insert(key)
        merged.materials.append(row)
        report.materialsAdded += 1
    }

    // 材料关联：按 (quota, material, spec) 只增；孤儿（定额不存在）跳过。
    var ruleKeys = Set(merged.rules.map { "\($0.quota)|\($0.material)|\($0.spec)" })
    for row in full.rules {
        guard quotaCodes.contains(row.quota) else { report.orphansSkipped += 1; continue }
        let key = "\(row.quota)|\(row.material)|\(row.spec)"
        guard !ruleKeys.contains(key) else { continue }
        ruleKeys.insert(key)
        merged.rules.append(row)
        report.rulesAdded += 1
    }

    // 机械/仪表关联：编码键 (quota, mcode) 或名称键 (quota, 归一化名称) 任一命中即视为已存在
    //（防重复，见文件头）；孤儿跳过。
    func assocPresent(codeKeys: Set<String>, nameKeys: Set<String>, quota: String, mcode: String, mname: String) -> Bool {
        (!mcode.isEmpty && codeKeys.contains("\(quota)|\(mcode)"))
            || nameKeys.contains("\(quota)|\(libraryMatchNorm(mname))")
    }
    var qmCodeKeys = Set(merged.quotaMachines.filter { !$0.mcode.isEmpty }.map { "\($0.quota)|\($0.mcode)" })
    var qmNameKeys = Set(merged.quotaMachines.map { "\($0.quota)|\(libraryMatchNorm($0.mname))" })
    for row in full.quotaMachines {
        guard quotaCodes.contains(row.quota) else { report.orphansSkipped += 1; continue }
        guard !assocPresent(codeKeys: qmCodeKeys, nameKeys: qmNameKeys,
                            quota: row.quota, mcode: row.mcode, mname: row.mname) else { continue }
        if !row.mcode.isEmpty { qmCodeKeys.insert("\(row.quota)|\(row.mcode)") }
        qmNameKeys.insert("\(row.quota)|\(libraryMatchNorm(row.mname))")
        merged.quotaMachines.append(row)
        report.quotaMachinesAdded += 1
    }
    var qiCodeKeys = Set(merged.quotaInstruments.filter { !$0.mcode.isEmpty }.map { "\($0.quota)|\($0.mcode)" })
    var qiNameKeys = Set(merged.quotaInstruments.map { "\($0.quota)|\(libraryMatchNorm($0.mname))" })
    for row in full.quotaInstruments {
        guard quotaCodes.contains(row.quota) else { report.orphansSkipped += 1; continue }
        guard !assocPresent(codeKeys: qiCodeKeys, nameKeys: qiNameKeys,
                            quota: row.quota, mcode: row.mcode, mname: row.mname) else { continue }
        if !row.mcode.isEmpty { qiCodeKeys.insert("\(row.quota)|\(row.mcode)") }
        qiNameKeys.insert("\(row.quota)|\(libraryMatchNorm(row.mname))")
        merged.quotaInstruments.append(row)
        report.quotaInstrumentsAdded += 1
    }

    // 台班价：按 code 只补缺失（价格取 full），已有编码的价格一字不动。
    var mpCodes = Set(merged.machinePrices.map { $0.code })
    for row in full.machinePrices where !mpCodes.contains(row.code) {
        mpCodes.insert(row.code)
        merged.machinePrices.append(row)
        report.machinePricesAdded += 1
    }
    var ipCodes = Set(merged.instrumentPrices.map { $0.code })
    for row in full.instrumentPrices where !ipCodes.contains(row.code) {
        ipCodes.insert(row.code)
        merged.instrumentPrices.append(row)
        report.instrumentPricesAdded += 1
    }

    return (merged, report)
}
