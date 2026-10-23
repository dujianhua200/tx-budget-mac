import Foundation
/// 通信工程概预算计算引擎（纯 Swift，无任何依赖）。对照 src/engine/calc.mjs。
/// 口径：2017 451号文，宇翔表二格式。公式链：
///   工程量（填量，原量 J）—加权（AB = 量 × 系数）→ 定额（技工/普工）
///   → 表三甲（工日，含 ≤100×15% / ≤250×10% 调整）
///   → 表三乙（机械，按定额-机械对）/ 表三丙（仪表，按定额-仪表对）
///   → 定额主材关联（变体 / 变体* / 通用 / 备选）→ 甲供/乙供/设备主材数量
///   → 表四甲/表四乙（除税/增值税/含税）→ 表二（取费）→ 表一/表五/汇总表
///
/// 约定：
///   - 材料数量用原量 J（不加权），工日用加权量 AB（与母版一致）
///   - 数量为 0 的行不参与计算；备选规则默认不计（enabled=false 可开启）
///   - 金额 ROUND(x,2) 与 Excel 一致（均为非负数）

/// 打折规则默认值（discountRule）。
public func defaultDiscountRule(discountRate: Double = 1) -> DiscountRule {
    DiscountRule(discountRate: discountRate,
                 noDiscountKeys: defaultNoDiscountKeys,
                 zeroAfterDiscountKeys: defaultZeroAfterDiscountKeys)
}

/// 表五费用项默认值（16 项）。designTotal 的 basis 取 'sum'（= 5.1 + 5.2 之和，不独立取费）。
public func defaultTable5Fees() -> [Table5Fee] {
    [
        Table5Fee(key: "landFee", name: "建设用地及综合赔补费", basis: "manual", rate: 0, vatRate: 0, amount: nil, enabled: true, order: 1, note: "默认空值"),
        Table5Fee(key: "mgmt2", name: "项目建设管理费", basis: "preDiscountExclTax", rate: 0.02, vatRate: 0.06, amount: nil, enabled: true, order: 2, note: "v1 公式保留"),
        Table5Fee(key: "feasibilityFee", name: "可行性研究费", basis: "manual", rate: 0, vatRate: 0, amount: nil, enabled: true, order: 3, note: "默认空值"),
        Table5Fee(key: "researchFee", name: "研究试验费", basis: "manual", rate: 0, vatRate: 0, amount: nil, enabled: true, order: 4, note: "默认空值"),
        Table5Fee(key: "designTotal", name: "勘察设计费", basis: "sum", rate: nil, vatRate: 0.06, amount: nil, enabled: true, order: 5, note: "5.1+5.2 之和，不独立取费"),
        Table5Fee(key: "surveyFee", name: "其中：勘察费", basis: "surveyKm", rate: nil, vatRate: 0.06, amount: nil, enabled: true, order: 5.1, note: "v1 分段公式保留；勘察长度=测量类定额原量/10"),
        Table5Fee(key: "designFee", name: "其中：设计费", basis: "preDiscountExclTax", rate: 0.0495, vatRate: 0.06, amount: nil, enabled: true, order: 5.2, note: "exclTax × 0.045 × 1.1"),
        Table5Fee(key: "envEvalFee", name: "环境影响评价费", basis: "manual", rate: 0, vatRate: 0, amount: nil, enabled: true, order: 6, note: "默认空值"),
        Table5Fee(key: "supervisionFee", name: "建设工程监理费", basis: "manual", rate: 0, vatRate: 0, amount: nil, enabled: true, order: 7, note: "默认空值"),
        Table5Fee(key: "safetyFee", name: "安全生产费", basis: "preDiscountExclTax", rate: 0.02, vatRate: 0, amount: nil, enabled: true, order: 8, note: "财资〔2022〕136号，通信工程 2%，增值税 0"),
        Table5Fee(key: "importTechFee", name: "引进技术及进口设备其他费", basis: "manual", rate: 0, vatRate: 0, amount: nil, enabled: true, order: 9, note: "默认空值"),
        Table5Fee(key: "insuranceFee", name: "工程保险费", basis: "manual", rate: 0, vatRate: 0, amount: nil, enabled: true, order: 10, note: "默认空值"),
        Table5Fee(key: "tenderFee", name: "工程招标代理费", basis: "manual", rate: 0, vatRate: 0, amount: nil, enabled: true, order: 11, note: "默认空值"),
        Table5Fee(key: "patentFee", name: "专利及专利技术使用费", basis: "manual", rate: 0, vatRate: 0, amount: nil, enabled: true, order: 12, note: "默认空值"),
        Table5Fee(key: "otherFee", name: "其他费用", basis: "manual", rate: 0, vatRate: 0, amount: nil, enabled: true, order: 13, note: "默认空值"),
        Table5Fee(key: "productionPrepFee", name: "生产准备及开办费(运营费)", basis: "manual", rate: 0, vatRate: 0, amount: nil, enabled: true, order: 14, note: "总计之后单独行，不计入总计"),
    ]
}

/// 调遣费参数默认值（数值原样搬运自 v1 calc.mjs 的 DISPATCH_* 常量）。
public func defaultDispatch() -> DispatchParams {
    DispatchParams(
        priceTable: [
            [0, 0], [35.0001, 141], [100.0001, 174], [200.0001, 240], [400.0001, 295],
            [600.0001, 356], [800.0001, 372], [1000.0001, 417], [1200.0001, 565],
            [1400.0001, 598], [1600.0001, 634],
        ],
        peopleEquip: [
            [0, 5], [500.0001, 10], [1000.0001, 17], [2000.0001, 24], [3000.0001, 30], [4000.0001, 35],
        ],
        peopleLine: [
            [0, 5], [500.0001, 10], [1000.0001, 17], [2000.0001, 24], [3000.0001, 30],
            [4000.0001, 35], [5000.0001, 40], [6000.0001, 45], [7000.0001, 50],
            [8000.0001, 55], [9000.0001, 60], [10000.0001, 80], [15000.0001, 95],
            [20000.0001, 105], [25000.0001, 120],
        ],
        extraPer200km: 48,
        extraPeopleStep: 3
    )
}

/// Excel HLOOKUP 近似匹配：取 <= key 的最大阈值对应的值。
/// 偏离说明：JS 对空表会抛 TypeError；此处空表/短行返回 0（畸形输入不崩溃）。
public func approxLookup(_ key: Double, _ table: [[Double]]) -> Double {
    guard let first = table.first, first.count > 1 else { return 0 }
    var v = first[1]
    for row in table {
        guard row.count > 1 else { break }
        if key >= row[0] { v = row[1] } else { break }
    }
    return v
}

/// 勘察费：按勘察长度分段。勘察长度 = 测量类定额（TXL1-001/002/003）原量 / 10。
public func surveyFeeFor(_ surveyKm: Double) -> Double {
    if !(surveyKm > 0) { return 0 }
    if surveyKm <= 1 { return 2000 * 0.8 }
    if surveyKm <= 10 { return (2000 + (surveyKm - 1) * 1530) * 0.8 }
    if surveyKm <= 50 { return (15770 + (surveyKm - 10) * 1130) * 0.8 }
    return surveyKm * 1219.4 * 0.8
}

private struct MatQtyEntry {
    var auto: Double
    var supply: String
}

private struct Table5WorkRow {
    var fee: Table5Fee
    var override: Table5Override?
    var enabled: Bool
    var excl: Double?
    var vatRate: Double = 0
    var vat: Double = 0
    var incl: Double = 0
}

/// 表五计算：按配置 table5Fees 逐项取费 + 工程级 table5Overrides 覆盖。
/// - basis: preDiscountExclTax / afterDiscountExclTax / laborTotal(折前人工费) /
///   fixed / manual / surveyKm(勘察分段) / sum（= 子项和）。
/// - enabled=false 的行不输出、不计入总计；productionPrepFee（总计之后单独行）不计入总计。
/// - 单项 vatRate 缺失时：safetyFee 回落到 rates.vatRates.safetyVat，其余回落 0。
private func calcTable5(table2Before: Table2, table2After: Table2, surveyKm: Double,
                        feesConfig: [Table5Fee]?, overrides: [Table5Override],
                        safetyVatFallback: Double, warnings: inout [CalcWarning]) -> Table5Result {
    let feeList = (feesConfig != nil && !feesConfig!.isEmpty) ? feesConfig! : defaultTable5Fees()
    var overridesByKey: [String: Table5Override] = [:]
    for o in overrides { overridesByKey[o.key] = o }

    // 启用行，按 order 稳定排序（Swift sorted 非稳定排序，需以原下标作决胜）。
    var indexed: [(Int, Table5Fee)] = []
    for (i, fee) in feeList.enumerated() {
        let ov = overridesByKey[fee.key]
        let enabled = ov?.enabled ?? fee.enabled ?? true
        if enabled { indexed.append((i, fee)) }
    }
    indexed.sort { a, b in
        if a.1.order != b.1.order { return a.1.order < b.1.order }
        return a.0 < b.0
    }
    var rows: [Table5WorkRow] = indexed.map { (_, fee) in
        Table5WorkRow(fee: fee, override: overridesByKey[fee.key], enabled: true, excl: nil)
    }

    // 除税价（sum 行留空，稍后填充）。
    for i in rows.indices {
        let row = rows[i]
        let ov = row.override
        if let amount = ov?.amount {
            rows[i].excl = r2(num(amount))
        } else if row.fee.basis == "preDiscountExclTax" {
            rows[i].excl = r2(table2Before.exclTax * num(row.fee.rate))
        } else if row.fee.basis == "afterDiscountExclTax" {
            rows[i].excl = r2(table2After.exclTax * num(row.fee.rate))
        } else if row.fee.basis == "laborTotal" {
            rows[i].excl = r2(table2Before.laborTotal * num(row.fee.rate))
        } else if row.fee.basis == "fixed" {
            rows[i].excl = r2(num(row.fee.amount))
        } else if row.fee.basis == "manual" {
            rows[i].excl = r2(num(row.fee.amount))
        } else if row.fee.basis == "surveyKm" {
            rows[i].excl = r2(surveyFeeFor(surveyKm))
        } else if row.fee.basis == "sum" {
            rows[i].excl = nil
        } else {
            warnings.append(CalcWarning(code: "unknownTable5Basis",
                                        message: "表五费用项“\(row.fee.name)”的 basis“\(row.fee.basis)”未知，按 0 计算"))
            rows[i].excl = 0
        }
    }
    // sum 行：子项和（子项被禁用按 0 计；子项为已填好的前序 sum 行时读填好的值，
    // 子项为后序 sum 行时读 nil → 0，与 JS 一致——此处必须实时查 rows，不能用快照字典，
    // 因 Swift 结构体是值类型，快照会在填充后过期）。
    func sumChildren(of fee: Table5Fee) -> [String] {
        if let children = fee.children { return children }
        if fee.key == "designTotal" { return ["surveyFee", "designFee"] }
        return []
    }
    for i in rows.indices where rows[i].fee.basis == "sum" {
        var sum = 0.0
        for k in sumChildren(of: rows[i].fee) {
            if let child = rows.last(where: { $0.fee.key == k }) {
                sum += num(child.excl)
            }
        }
        rows[i].excl = r2(sum)
    }
    // 增值税 + 含税。
    for i in rows.indices {
        let vr = rows[i].fee.vatRate ?? (rows[i].fee.key == "safetyFee" ? safetyVatFallback : 0)
        rows[i].vatRate = vr
        rows[i].vat = r2(num(rows[i].excl) * num(vr))
        rows[i].incl = r2(num(rows[i].excl) + rows[i].vat)
    }
    // 总计：排除 sum 行的子项（仅当该 sum 行启用时）与 productionPrepFee。
    var sumChildrenSet = Set<String>()
    for row in rows where row.fee.basis == "sum" {
        for k in sumChildren(of: row.fee) { sumChildrenSet.insert(k) }
    }
    let totalRows = rows.filter { !sumChildrenSet.contains($0.fee.key) && $0.fee.key != "productionPrepFee" }
    let totalExcl = r2(totalRows.reduce(0) { $0 + num($1.excl) })
    let totalVat = r2(totalRows.reduce(0) { $0 + $1.vat })
    let totalIncl = r2(totalExcl + totalVat)

    let outRows = rows.map { row in
        Table5Row(key: row.fee.key, name: row.fee.name, basis: row.fee.basis,
                  rate: row.fee.rate, vatRate: row.vatRate, order: row.fee.order,
                  note: row.fee.note, enabled: true, excl: num(row.excl), vat: row.vat,
                  incl: row.incl, amount: num(row.excl))
    }
    func field(_ key: String, _ get: (Table5WorkRow) -> Double) -> Double {
        // JS byKey 为 Map（last-wins），此处用 last 保持一致。
        guard let row = rows.last(where: { $0.fee.key == key }) else { return 0 }
        return get(row)
    }
    let pp = rows.first(where: { $0.fee.key == "productionPrepFee" })
    return Table5Result(
        rows: outRows,
        totalExcl: totalExcl, totalVat: totalVat, totalIncl: totalIncl,
        mgmt2: field("mgmt2") { num($0.excl) },
        mgmt2Vat: field("mgmt2") { $0.vat },
        mgmt2Incl: field("mgmt2") { $0.incl },
        surveyKm: r2(surveyKm),
        surveyFee: field("surveyFee") { num($0.excl) },
        surveyVat: field("surveyFee") { $0.vat },
        designFee: field("designFee") { num($0.excl) },
        designVat: field("designFee") { $0.vat },
        designTotal: field("designTotal") { num($0.excl) },
        designTotalVat: field("designTotal") { $0.vat },
        safetyFee: field("safetyFee") { num($0.excl) },
        safetyVat: field("safetyFee") { $0.vat },
        safetyIncl: field("safetyFee") { $0.incl },
        productionPrepFee: num(pp?.excl),
        productionPrepVat: pp?.vat ?? 0,
        productionPrepIncl: pp?.incl ?? 0
    )
}

/// 计算一个工程的全部预算表。对照 calc.mjs 的 calcProject。
public func calcProject(_ project: Project, _ libs: Libs) -> CalcResult {
    let info = project.info
    var warnings: [CalcWarning] = []

    // ---- 0. 费率 + 折扣/增值税率（优先级：rateOverrides > info（合并前原始值）> 配置方案 > 兜底）----
    let (namedRate, rateWarnings) = resolveNamedRates(libs: libs, projectType: info.工程类型, region: info.冬雨季施工费)
    warnings.append(contentsOf: rateWarnings)
    var rate = namedRate
    let resolved = resolveRates(rates: libs.rates, discountRule: libs.discountRule, project: project)
    var discount = resolved.discount
    if !(discount.isFinite && discount > 0 && discount <= 1) {
        warnings.append(CalcWarning(code: "invalidDiscount",
                                    message: "折扣率非法：\(jsNumberString(discount))，按 1 计算"))
        discount = 1
    }
    let jiaTax = resolved.jiaTax
    let yiTax = resolved.yiTax
    let outputTaxRate = resolved.outputTax
    let safetyVatFallback = resolved.safetyVat
    rate.jiaTax = jiaTax
    rate.yiTax = yiTax
    rate.outputTax = outputTaxRate
    rate.taxRate = outputTaxRate // 兼容旧 rate.taxRate 语义（= 销项税额税率）

    let quotas = libs.quotas
    let materials = libs.materials
    let rules = libs.rules
    var quotaByCode: [String: Quota] = [:]
    var duplicateCodes: [String] = []
    var seenCodes = Set<String>()
    for q in quotas {
        if seenCodes.contains(q.code) {
            if !duplicateCodes.contains(q.code) { duplicateCodes.append(q.code) }
        } else {
            seenCodes.insert(q.code)
            quotaByCode[q.code] = q
        }
    }
    var matByKey: [String: Material] = [:]
    for m in materials { matByKey["\(m.name)|\(m.spec)"] = m }
    var machinePrice: [String: Double] = [:]
    for m in libs.machinePrices { machinePrice[m.code] = m.price }
    var instrumentPrice: [String: Double] = [:]
    for m in libs.instrumentPrices { instrumentPrice[m.code] = m.price }
    var ruleEnabled: [String: Bool] = [:]
    for o in project.ruleOverrides { ruleEnabled[o.ruleId] = o.enabled }

    // ---- 1. 工程量汇总：按定额编号汇总原量 J / 加权量 AB；按 (编号,变体) 汇总原量 ----
    // 孤儿行（编号不在库中）、无效行（数量<0 / 系数<=0）记警告且不参与计算。
    var byQuota: [String: (raw: Double, weighted: Double)] = [:]
    var byVariant: [String: Double] = [:]
    let surveyCodes = ["TXL1-001", "TXL1-002", "TXL1-003"]
    var surveyRaw = 0.0
    var orphanRowIds: [String] = []
    var orphanCodes: [String] = []
    var orphanCodeSet = Set<String>()
    var invalidRowIds: [String] = []
    for (qi, q) in project.quantities.enumerated() {
        let rowId = q.id ?? "qty_\(qi)"
        guard quotaByCode[q.quota] != nil else {
            orphanRowIds.append(rowId)
            if !orphanCodeSet.contains(q.quota) {
                orphanCodeSet.insert(q.quota)
                orphanCodes.append(q.quota)
            }
            continue
        }
        let qty = num(q.qty)
        if let qQty = q.qty, qQty < 0 {
            invalidRowIds.append(rowId)
            continue
        }
        if qty == 0 || qty.isNaN { continue } // 数量为 0 / 非数字 → 不参与计算
        let coef = q.coef ?? 1
        if let c = q.coef, !(c > 0) {
            invalidRowIds.append(rowId)
            continue
        }
        if !(coef > 0) { continue } // 非数字系数 → 按 JS 视为 0，不参与计算
        var a = byQuota[q.quota] ?? (raw: 0, weighted: 0)
        a.raw += qty
        a.weighted += qty * coef
        byQuota[q.quota] = a
        let vk = "\(q.quota)|\(q.variant ?? "")"
        byVariant[vk] = (byVariant[vk] ?? 0) + qty
        if surveyCodes.contains(q.quota) { surveyRaw += qty }
    }
    let surveyKm = surveyRaw / 10
    if !orphanRowIds.isEmpty {
        warnings.append(CalcWarning(code: "orphanQty",
                                    message: "\(orphanRowIds.count) 行工程量引用了库中不存在的定额编号，将不参与计算：\(orphanCodes.joined(separator: "、"))",
                                    rowIds: orphanRowIds))
    }
    if !invalidRowIds.isEmpty {
        warnings.append(CalcWarning(code: "invalidQty",
                                    message: "\(invalidRowIds.count) 行工程量数量/系数无效（数量<0 或系数<=0），将不参与计算",
                                    rowIds: invalidRowIds))
    }
    for code in duplicateCodes {
        warnings.append(CalcWarning(code: "duplicateCode",
                                    message: "定额库中编号“\(code)”重复，计算按首条匹配，请去重"))
    }

    // ---- 2. 表三甲：工日 ----
    var table3A: [Table3ARow] = []
    var techSub = 0.0, laborSub = 0.0
    for quota in quotas {
        guard let agg = byQuota[quota.code], agg.weighted != 0, !agg.weighted.isNaN else { continue }
        let tech = r2(agg.weighted * num(quota.tech))
        let labor = r2(agg.weighted * num(quota.labor))
        techSub += tech
        laborSub += labor
        table3A.append(Table3ARow(code: quota.code, name: quota.name, unit: quota.unit,
                                   qty: r2(agg.weighted), techUnit: num(quota.tech),
                                   laborUnit: num(quota.labor), tech: tech, labor: labor))
    }
    let totalDays = techSub + laborSub
    let adjRate: Double = totalDays <= 100 ? 0.15 : totalDays <= 250 ? 0.1 : 0
    let techDays = techSub + techSub * adjRate
    let laborDays = laborSub + laborSub * adjRate

    // ---- 3. 表三乙 / 表三丙：机械 / 仪表（按定额-机械对，定额顺序）----
    func calcEquip(_ mappings: [(quota: String, mcode: String, mname: String, unit: String, qty: Double)],
                   _ priceMap: [String: Double]) -> Table3EquipResult {
        var byQuotaMap: [String: [(mcode: String, mname: String, unit: String, qty: Double)]] = [:]
        for m in mappings {
            byQuotaMap[m.quota, default: []].append((mcode: m.mcode, mname: m.mname, unit: m.unit, qty: m.qty))
        }
        var rows: [Table3EquipRow] = []
        var total = 0.0
        for quota in quotas {
            guard let agg = byQuota[quota.code], agg.weighted != 0, !agg.weighted.isNaN else { continue }
            guard let ms = byQuotaMap[quota.code] else { continue }
            for m in ms {
                let sessions = agg.weighted * num(m.qty)
                let price = num(priceMap[m.mcode])
                let amount = sessions * price
                total += amount
                rows.append(Table3EquipRow(quota: quota.code, quotaName: quota.name, unit: quota.unit,
                                            qty: r2(agg.weighted), equipName: m.mname, equipUnit: m.unit,
                                            consumption: num(m.qty), price: price,
                                            sessions: r2(sessions), amount: r2(amount)))
            }
        }
        return Table3EquipResult(rows: rows, total: r2(total))
    }
    let table3B = calcEquip(libs.quotaMachines.map { ($0.quota, $0.mcode, $0.mname, $0.unit, $0.qty) }, machinePrice)
    let table3C = calcEquip(libs.quotaInstruments.map { ($0.quota, $0.mcode, $0.mname, $0.unit, $0.qty) }, instrumentPrice)

    // ---- 4. 材料数量：定额主材关联 ----
    var matQty: [String: MatQtyEntry] = [:]
    var matQtyOrder: [String] = []
    for rule in rules {
        // 孤儿定额的规则不参与计算（其工程量行已排除）。
        guard quotaByCode[rule.quota] != nil else { continue }
        // v2.4.1：适用工程过滤（'' = 不启用，'全' = 全部，'1,3' = 仅对应序号工程；
        // 序号 = 工程在所属方案工程集合中的 1 基位置，由 calcFor 注入 projectOrdinal）。
        guard ruleAppliesToProject(rule.appliesTo, projectOrdinal: project.projectOrdinal) else { continue }
        var q = 0.0
        if rule.kind == "变体" {
            q = num(byVariant["\(rule.quota)|\(rule.variant)"])
        } else if rule.kind == "变体*" {
            // 母版公式：SUMIFS(变体项目名称 & "*") —— 前缀匹配。
            // 注意：此处按 JS 原样遍历全部工程量行（不校验系数/有效性），仅要求数量非 0。
            let prefix = rule.variant
            var sum = 0.0
            for qq in project.quantities where qq.quota == rule.quota {
                if let qqQty = qq.qty, qqQty != 0, !qqQty.isNaN, (qq.variant ?? "").hasPrefix(prefix) {
                    sum += qqQty
                }
            }
            q = sum
        } else if rule.kind == "通用" {
            q = num(byQuota[rule.quota]?.raw)
        } else if rule.kind == "备选" {
            if let rid = rule.id, ruleEnabled[rid] == true {
                q = num(byVariant["\(rule.quota)|\(rule.variant)"])
            }
        }
        if q == 0 || q.isNaN { continue }
        let key = "\(rule.material)|\(rule.spec)"
        if matQty[key] == nil {
            matQty[key] = MatQtyEntry(auto: 0, supply: rule.supply)
            matQtyOrder.append(key)
        }
        matQty[key]!.auto += q * num(rule.consumption)
    }
    // 手动调整
    var adjustByKey: [String: Double] = [:]
    for a in project.materialAdjust { adjustByKey[a.key] = num(a.delta) }
    var priceOverride: [String: Double] = [:]
    for p in project.materialPriceOverrides { priceOverride[p.key] = num(p.priceExcl) }

    func buildMatTable(_ supply: String) -> Table4Result {
        var rows: [Table4Row] = []
        var totalExcl = 0.0, totalVat = 0.0
        for key in matQtyOrder {
            guard let v = matQty[key] else { continue }
            let lib = matByKey[key]
            let libSupply: String
            if let lib, !lib.supply.isEmpty {
                libSupply = lib.supply
            } else {
                libSupply = v.supply
            }
            guard libSupply == supply else { continue }
            // JS：key.split('|') 解构取前两段（spec 含 '|' 时多余部分丢弃）。
            let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let name = parts.count > 0 ? parts[0] : ""
            let spec = parts.count > 1 ? parts[1] : ""
            let qty = v.auto + (adjustByKey[key] ?? 0)
            if qty == 0 || qty.isNaN { continue }
            let taxRate = supply == "甲供" ? jiaTax : supply == "乙供" ? yiTax : jiaTax
            let priceExcl = priceOverride[key] ?? num(lib?.priceExcl)
            let priceVat = priceExcl * taxRate
            let priceIncl = priceExcl + priceVat
            let amtExcl = qty * priceExcl
            let amtVat = qty * priceVat
            totalExcl += amtExcl
            totalVat += amtVat
            rows.append(Table4Row(key: key, name: name, spec: spec, unit: lib?.unit ?? "",
                                  qty: r2(qty), autoQty: r2(v.auto), delta: adjustByKey[key] ?? 0,
                                  priceExcl: r2(priceExcl), priceVat: r2(priceVat),
                                  priceIncl: r2(priceIncl), amtExcl: r2(amtExcl), amtVat: r2(amtVat),
                                  amtIncl: r2(amtExcl + amtVat), unmatched: lib == nil))
        }
        return Table4Result(rows: rows, totalExcl: r2(totalExcl), totalVat: r2(totalVat),
                            totalIncl: r2(totalExcl + totalVat))
    }
    let table4A = buildMatTable("甲供")   // 表四甲（主材）
    let table4B = buildMatTable("乙供")   // 表四乙
    let table4Equip = buildMatTable("设备") // 表四甲（设备）

    // ---- 5. 表二（折前）----
    var t2 = Table2()
    t2.techFee = r2(techDays * rate.techPrice)
    t2.laborFee = r2(laborDays * rate.laborPrice)
    t2.laborTotal = r2(t2.techFee + t2.laborFee)
    t2.jiaMat = table4A.totalExcl
    t2.yiMat = table4B.totalExcl
    t2.mainMat = r2(t2.jiaMat + t2.yiMat)
    t2.auxMat = r2(t2.mainMat * rate.auxRate)
    t2.matTotal = r2(t2.mainMat + t2.auxMat)
    t2.machineFee = table3B.total
    t2.instrumentFee = table3C.total
    t2.directFee = r2(t2.laborTotal + t2.matTotal + t2.machineFee + t2.instrumentFee)
    // 措施费
    t2.envFee = r2(t2.laborTotal * rate.envRate)
    t2.civilFee = r2(t2.laborTotal * rate.civilRate)
    t2.carryFee = r2(t2.laborTotal * rate.carryRate)
    t2.disturbFee = r2(t2.laborTotal * rate.disturbRate)
    t2.handoverFee = r2(t2.laborTotal * rate.handoverRate)
    let tempRate = info.施工距离 == "35KM以内" ? rate.tempNearRate : rate.tempFarRate
    t2.tempFee = r2(t2.laborTotal * tempRate)
    t2.vehicleFee = r2(t2.laborTotal * rate.vehicleRate)
    t2.nightFee = r2(t2.laborTotal * rate.nightRate)
    t2.winterFee = r2(t2.laborTotal * rate.winterRate)
    t2.toolFee = r2(t2.laborTotal * rate.toolRate)
    t2.utilityFee = r2(t2.laborTotal * rate.utilityRate)
    t2.specialFee = 0
    t2.protectFee = r2(t2.laborTotal * rate.protectRate)
    t2.earthFee = 0
    // 调遣费（参数来自 libs.dispatch，缺失时用内置默认表）
    let dsp = libs.dispatch ?? defaultDispatch()
    let defaults = defaultDispatch()
    let priceTable = dsp.priceTable ?? defaults.priceTable ?? []
    let peopleEquip = dsp.peopleEquip ?? defaults.peopleEquip ?? []
    let peopleLine = dsp.peopleLine ?? defaults.peopleLine ?? []
    let extraPer200km = dsp.extraPer200km ?? 48
    let extraPeopleStep = dsp.extraPeopleStep ?? 3
    let mileage = num(info.施工实际里程)
    let dispatchUnit = techDays == 0 ? 0
        : approxLookup(mileage, priceTable) + (mileage > 4400 ? ceil((mileage - 4400) / 200) * extraPer200km : 0)
    let isEquipDispatch = info.施工调遣分类 == "施工队伍调遣人数(无线、电源、设备）"
    let dispatchPeople = techDays == 0 ? 0
        : approxLookup(techDays, isEquipDispatch ? peopleEquip : peopleLine)
            + (isEquipDispatch ? ceil(max(0, techDays - 5000) / 1000) * extraPeopleStep
                               : ceil(max(0, techDays - 30000) / 5000) * extraPeopleStep)
    t2.dispatchUnit = dispatchUnit
    t2.dispatchPeople = dispatchPeople
    t2.dispatchFee = r2(dispatchUnit * dispatchPeople * 2)
    t2.bigMachineFee = 0
    t2.measureFee = r2(t2.envFee + t2.civilFee + t2.carryFee + t2.disturbFee + t2.handoverFee
        + t2.tempFee + t2.vehicleFee + t2.nightFee + t2.winterFee + t2.toolFee + t2.utilityFee
        + t2.specialFee + t2.protectFee + t2.earthFee + t2.dispatchFee + t2.bigMachineFee)
    t2.directTotal = r2(t2.directFee + t2.measureFee)
    // 间接费
    t2.sewageFee = 0
    t2.socialFee = r2(t2.laborTotal * rate.socialRate)
    t2.housingFee = r2(t2.laborTotal * rate.housingRate)
    t2.accidentFee = r2(t2.laborTotal * rate.accidentRate)
    t2.regFee = r2(t2.sewageFee + t2.socialFee + t2.housingFee + t2.accidentFee)
    t2.mgmtFee = r2(t2.laborTotal * rate.mgmtRate)
    t2.indirectTotal = r2(t2.regFee + t2.mgmtFee)
    t2.profit = r2(t2.laborTotal * rate.profitRate)
    t2.exclTax = r2(t2.directTotal + t2.indirectTotal + t2.profit)
    t2.outputTax = r2((t2.exclTax - t2.jiaMat) * outputTaxRate + table4A.totalExcl * jiaTax)
    t2.inclTax = r2(t2.exclTax + t2.outputTax)
    let table2Before = t2

    // ---- 6. 表二（折后）：逐项打折，不再用 v1 快捷公式 ----
    let noDiscountKeys = libs.discountRule?.noDiscountKeys ?? defaultNoDiscountKeys
    let zeroAfterDiscountKeys = libs.discountRule?.zeroAfterDiscountKeys ?? defaultZeroAfterDiscountKeys
    // discount 已在步骤 0 校验过合法，此处不会抛错。
    let table2After = (try? applyDiscount(table2Before, rule: DiscountRuleInput(
        discountRate: discount, noDiscountKeys: noDiscountKeys,
        zeroAfterDiscountKeys: zeroAfterDiscountKeys,
        outputTaxRate: outputTaxRate, jiaTax: jiaTax))) ?? table2Before

    // ---- 7. 表五（可配置）----
    let table5 = calcTable5(table2Before: table2Before, table2After: table2After, surveyKm: surveyKm,
                            feesConfig: libs.table5Fees, overrides: project.table5Overrides,
                            safetyVatFallback: safetyVatFallback, warnings: &warnings)

    // ---- 8. 表一 ----
    var t1 = Table1Result()
    t1.beforeDiscount = table2Before.exclTax
    t1.afterDiscount = table2After.exclTax
    t1.taxBefore = table2Before.outputTax
    t1.taxAfter = table2After.outputTax
    t1.totalBefore = r2(t1.beforeDiscount + t1.taxBefore)
    t1.totalAfter = r2(t1.afterDiscount + t1.taxAfter)
    t1.otherFee = table5.totalExcl
    t1.otherVat = table5.totalVat
    t1.otherIncl = table5.totalIncl
    t1.sumExcl = r2(t1.afterDiscount + t1.otherFee)
    t1.sumVat = r2(t1.taxAfter + t1.otherVat)
    t1.sumIncl = r2(t1.sumExcl + t1.sumVat)
    t1.equipFee = table4Equip.totalExcl
    t1.equipVat = table4Equip.totalVat
    t1.equipIncl = table4Equip.totalIncl
    t1.grandExcl = r2(t1.sumExcl + t1.equipFee)
    t1.grandVat = r2(t1.sumVat + t1.equipVat)
    t1.grandIncl = r2(t1.sumIncl + t1.equipIncl)

    // ---- 9. 汇总表（建安费 = 表一折后建安费；其他费用 = 表五总计；无自购物资行）----
    var hz = SummaryResult()
    hz.constructionExcl = t1.afterDiscount
    hz.constructionVat = t1.taxAfter
    hz.constructionIncl = r2(hz.constructionExcl + hz.constructionVat)
    hz.other = table5.totalExcl
    hz.otherVat = table5.totalVat
    hz.otherIncl = table5.totalIncl
    hz.totalExcl = r2(hz.constructionExcl + hz.other)
    hz.totalVat = r2(hz.constructionVat + hz.otherVat)
    hz.totalIncl = r2(hz.totalExcl + hz.totalVat)

    return CalcResult(
        info: info.merged(), rate: rate,
        techSub: techSub, laborSub: laborSub, adjRate: adjRate, techDays: techDays, laborDays: laborDays,
        table3A: table3A, table3B: table3B, table3C: table3C,
        table4A: table4A, table4B: table4B, table4Equip: table4Equip,
        table2Before: table2Before, table2After: table2After,
        table5: table5, table1: t1, summary: hz,
        warnings: warnings,
        discount: discount,
        discountRule: EffectiveDiscountRule(discountRate: discount,
                                            noDiscountKeys: noDiscountKeys,
                                            zeroAfterDiscountKeys: zeroAfterDiscountKeys),
        surveyKm: surveyKm, surveyRaw: surveyRaw
    )
}
