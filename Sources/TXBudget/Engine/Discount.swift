import Foundation
/// 打折模型（v2，纯函数，无依赖，不依赖 calc）。对照 src/engine/discount.mjs。
/// - 明细项 ∈ zeroAfterDiscountKeys → 折后 = 0（Q2 裁决 b，折扣率 < 1 时生效；
///   若同时在 noDiscountKeys 中，折后=0 优先）。折扣率 = 1 时折后表 ≡ 折前表，零值不生效。
/// - 明细项 ∈ noDiscountKeys → 保持折前值，否则 × 折扣率（逐项 r2）。
/// - 合计项一律由折后明细加总，不直接乘折扣率。
/// - 销项税额 = r2((exclTax - jiaMat) × outputTaxRate + jiaMat × jiaTax)，基数取折后值。
/// - noDiscountKeys 中的合计项 key 会使其子项同样不打折（mainMat → jiaMat/yiMat；
///   regFee → sewageFee/socialFee/housingFee/accidentFee），因为合计项本身由明细加总。

/// 默认不打折清单（以参考文件实测为准）。
public let defaultNoDiscountKeys = [
    "mainMat",
    "auxMat",
    "civilFee",
    "regFee",
    "socialFee",
    "housingFee",
    "accidentFee",
    "sewageFee",
    "safetyFee",
]

/// 默认折后=0 清单（Q2 裁决 b：用户 2026-10-14 裁决，11 项措施费折后 = 0）。
/// 参考结算书折后表中这 11 项全部为空（=0），既不是打折后的值，也不是折前值。
/// 与 defaultNoDiscountKeys 无交集；若某 key 同时出现在两清单中，折后=0 优先。
public let defaultZeroAfterDiscountKeys = [
    "carryFee",
    "disturbFee",
    "tempFee",
    "nightFee",
    "winterFee",
    "utilityFee",
    "specialFee",
    "protectFee",
    "earthFee",
    "dispatchFee",
    "bigMachineFee",
]

public enum DiscountLineKind: Equatable {
    case leaf
    case total
}

/// 表二费用项定义。methodDiscounted = 被打折时的方法列；methodRestored = 不打折时的方法列。
/// 参考中打折但方法列不带 X37.9% 后缀的项（点交/车辆/工具/企管/利润/规费子项），
/// methodDiscounted = methodBefore（不统一追加后缀）。
/// 占位符：{techPrice} {laborPrice} {auxRate} {envRate} {civilRate} {carryRate} {disturbRate}
/// {handoverRate} {tempRate} {vehicleRate} {nightRate} {winterRate} {toolRate} {utilityRate}
/// {protectRate} {socialRate} {housingRate} {accidentRate} {mgmtRate} {profitRate} {discountPct}
public struct DiscountLineDef: Equatable {
    public var key: String
    public var label: String
    public var kind: DiscountLineKind
    public var methodBefore: String
    public var methodDiscounted: String
    public var methodRestored: String
    public init(key: String, label: String, kind: DiscountLineKind,
                methodBefore: String, methodDiscounted: String, methodRestored: String) {
        self.key = key; self.label = label; self.kind = kind; self.methodBefore = methodBefore
        self.methodDiscounted = methodDiscounted; self.methodRestored = methodRestored
    }
}

public let discountLineDefs: [DiscountLineDef] = [
    DiscountLineDef(key: "techFee", label: "技工费", kind: .leaf, methodBefore: "技工总工日X{techPrice}", methodDiscounted: "技工总工日X{techPrice}X{discountPct}%", methodRestored: "技工总工日X{techPrice}/{discountPct}%"),
    DiscountLineDef(key: "laborFee", label: "普工费", kind: .leaf, methodBefore: "普工总工日X{laborPrice}", methodDiscounted: "普工总工日X{laborPrice}X{discountPct}%", methodRestored: "普工总工日X{laborPrice}/{discountPct}%"),
    DiscountLineDef(key: "laborTotal", label: "人工费", kind: .total, methodBefore: "技工费+普工费", methodDiscounted: "技工费+普工费", methodRestored: "技工费+普工费"),
    DiscountLineDef(key: "jiaMat", label: "甲供材料", kind: .leaf, methodBefore: "甲供材料费用", methodDiscounted: "甲供材料费用X{discountPct}%", methodRestored: "甲供材料费用"),
    DiscountLineDef(key: "yiMat", label: "乙供材料", kind: .leaf, methodBefore: "乙供材料费用", methodDiscounted: "乙供材料费用X{discountPct}%", methodRestored: "乙供材料费用"),
    DiscountLineDef(key: "mainMat", label: "主要材料费", kind: .total, methodBefore: "主材费用", methodDiscounted: "主材费用", methodRestored: "主材费用"),
    DiscountLineDef(key: "auxMat", label: "辅助材料费", kind: .leaf, methodBefore: "主要材料费X{auxRate}%", methodDiscounted: "主要材料费X{auxRate}%X{discountPct}%", methodRestored: "主要材料费X{auxRate}%"),
    DiscountLineDef(key: "matTotal", label: "材料费", kind: .total, methodBefore: "主要材料费+辅助材料费", methodDiscounted: "主要材料费+辅助材料费", methodRestored: "主要材料费+辅助材料费"),
    DiscountLineDef(key: "machineFee", label: "机械使用费", kind: .leaf, methodBefore: "机械费合计", methodDiscounted: "机械费合计X{discountPct}%", methodRestored: "机械费合计"),
    DiscountLineDef(key: "instrumentFee", label: "仪器仪表费", kind: .leaf, methodBefore: "仪表费合计", methodDiscounted: "仪表费合计X{discountPct}%", methodRestored: "仪表费合计"),
    DiscountLineDef(key: "directFee", label: "直接工程费", kind: .total, methodBefore: "1-4之和", methodDiscounted: "1-4之和", methodRestored: "1-4之和"),
    DiscountLineDef(key: "envFee", label: "环境保护费", kind: .leaf, methodBefore: "人工费X{envRate}%", methodDiscounted: "人工费X{envRate}%X{discountPct}%", methodRestored: "人工费X{envRate}%"),
    DiscountLineDef(key: "civilFee", label: "文明施工费", kind: .leaf, methodBefore: "人工费X{civilRate}%", methodDiscounted: "人工费X{civilRate}%X{discountPct}%", methodRestored: "人工费X{civilRate}%/{discountPct}%"),
    DiscountLineDef(key: "carryFee", label: "工地器材搬运费", kind: .leaf, methodBefore: "人工费X{carryRate}%", methodDiscounted: "人工费X{carryRate}%X{discountPct}%", methodRestored: "人工费X{carryRate}%"),
    DiscountLineDef(key: "disturbFee", label: "工程干扰费", kind: .leaf, methodBefore: "人工费X{disturbRate}%", methodDiscounted: "人工费X{disturbRate}%X{discountPct}%", methodRestored: "人工费X{disturbRate}%"),
    DiscountLineDef(key: "handoverFee", label: "工程点交、场地清理费", kind: .leaf, methodBefore: "人工费X{handoverRate}%", methodDiscounted: "人工费X{handoverRate}%", methodRestored: "人工费X{handoverRate}%"),
    DiscountLineDef(key: "tempFee", label: "临时设施费", kind: .leaf, methodBefore: "人工费X{tempRate}%", methodDiscounted: "人工费X{tempRate}%X{discountPct}%", methodRestored: "人工费X{tempRate}%/{discountPct}%"),
    DiscountLineDef(key: "vehicleFee", label: "工程车辆使用费", kind: .leaf, methodBefore: "人工费X{vehicleRate}%", methodDiscounted: "人工费X{vehicleRate}%", methodRestored: "人工费X{vehicleRate}%"),
    DiscountLineDef(key: "nightFee", label: "夜间施工增加费", kind: .leaf, methodBefore: "人工费X{nightRate}%", methodDiscounted: "人工费X{nightRate}%X{discountPct}%", methodRestored: "人工费X{nightRate}%"),
    DiscountLineDef(key: "winterFee", label: "冬雨季施工增加费", kind: .leaf, methodBefore: "人工费X{winterRate}%", methodDiscounted: "人工费X{winterRate}%X{discountPct}%", methodRestored: "人工费X{winterRate}%"),
    DiscountLineDef(key: "toolFee", label: "生产工具用具使用费", kind: .leaf, methodBefore: "人工费X{toolRate}%", methodDiscounted: "人工费X{toolRate}%", methodRestored: "人工费X{toolRate}%"),
    DiscountLineDef(key: "utilityFee", label: "施工用水电蒸汽费", kind: .leaf, methodBefore: "人工费X{utilityRate}%", methodDiscounted: "人工费X{utilityRate}%X{discountPct}%", methodRestored: "人工费X{utilityRate}%"),
    DiscountLineDef(key: "specialFee", label: "特殊地区施工增加费", kind: .leaf, methodBefore: "工日X8X0", methodDiscounted: "工日X8X0X{discountPct}%", methodRestored: "工日X8X0"),
    DiscountLineDef(key: "protectFee", label: "已完工程及设备保护费", kind: .leaf, methodBefore: "人工费X{protectRate}%", methodDiscounted: "人工费X{protectRate}%X{discountPct}%", methodRestored: "人工费X{protectRate}%"),
    DiscountLineDef(key: "earthFee", label: "运土费", kind: .leaf, methodBefore: "运土费", methodDiscounted: "运土费X{discountPct}%", methodRestored: "运土费"),
    DiscountLineDef(key: "dispatchFee", label: "施工队伍调遣费", kind: .leaf, methodBefore: "调遣单价X人数X2", methodDiscounted: "调遣单价X人数X2X{discountPct}%", methodRestored: "调遣单价X人数X2"),
    DiscountLineDef(key: "bigMachineFee", label: "大型施工机械调遣费", kind: .leaf, methodBefore: "大型施工机械调遣费", methodDiscounted: "大型施工机械调遣费X{discountPct}%", methodRestored: "大型施工机械调遣费"),
    DiscountLineDef(key: "measureFee", label: "措施项目费", kind: .total, methodBefore: "1-15之和", methodDiscounted: "1-15之和", methodRestored: "1-15之和"),
    DiscountLineDef(key: "directTotal", label: "直接费", kind: .total, methodBefore: "(一)+(二)", methodDiscounted: "(一)+(二)", methodRestored: "(一)+(二)"),
    DiscountLineDef(key: "sewageFee", label: "工程排污费", kind: .leaf, methodBefore: "工程排污费", methodDiscounted: "工程排污费X{discountPct}%", methodRestored: "工程排污费"),
    DiscountLineDef(key: "socialFee", label: "社会保障费", kind: .leaf, methodBefore: "人工费X{socialRate}%", methodDiscounted: "人工费X{socialRate}%", methodRestored: "人工费X{socialRate}%"),
    DiscountLineDef(key: "housingFee", label: "住房公积金", kind: .leaf, methodBefore: "人工费X{housingRate}%", methodDiscounted: "人工费X{housingRate}%", methodRestored: "人工费X{housingRate}%"),
    DiscountLineDef(key: "accidentFee", label: "危险作业意外伤害保险费", kind: .leaf, methodBefore: "人工费X{accidentRate}%", methodDiscounted: "人工费X{accidentRate}%", methodRestored: "人工费X{accidentRate}%"),
    DiscountLineDef(key: "regFee", label: "规费", kind: .total, methodBefore: "1-4之和", methodDiscounted: "1-4之和", methodRestored: "(1-4之和)/{discountPct}%"),
    DiscountLineDef(key: "mgmtFee", label: "企业管理费", kind: .leaf, methodBefore: "人工费X{mgmtRate}%", methodDiscounted: "人工费X{mgmtRate}%", methodRestored: "人工费X{mgmtRate}%"),
    DiscountLineDef(key: "indirectTotal", label: "间接费", kind: .total, methodBefore: "(一)+(二)", methodDiscounted: "(一)+(二)", methodRestored: "(一)+(二)"),
    DiscountLineDef(key: "profit", label: "利润", kind: .leaf, methodBefore: "人工费X{profitRate}%", methodDiscounted: "人工费X{profitRate}%", methodRestored: "人工费X{profitRate}%"),
    DiscountLineDef(key: "exclTax", label: "建筑安装工程费（除税价）", kind: .total, methodBefore: "一+二+三", methodDiscounted: "一+二+三", methodRestored: "一+二+三"),
    DiscountLineDef(key: "outputTax", label: "销项税额", kind: .total, methodBefore: "销项税额", methodDiscounted: "销项税额", methodRestored: "销项税额"),
    DiscountLineDef(key: "inclTax", label: "建筑安装工程费（含税价）", kind: .total, methodBefore: "一+二+三+四", methodDiscounted: "一+二+三+四", methodRestored: "一+二+三+四"),
]

/// noDiscountKeys 中合计项 key → 其子项（合计项不打折时子项同样不打折）。
public let discountParentChildren: [String: [String]] = [
    "mainMat": ["jiaMat", "yiMat"],
    "regFee": ["sewageFee", "socialFee", "housingFee", "accidentFee"],
]

/// 措施费明细项（measureFee 的加总来源）。
public let measureLeaves = [
    "envFee", "civilFee", "carryFee", "disturbFee", "handoverFee", "tempFee",
    "vehicleFee", "nightFee", "winterFee", "toolFee", "utilityFee", "specialFee",
    "protectFee", "earthFee", "dispatchFee", "bigMachineFee",
]

public enum MethodMode {
    case before
    case discounted
    case restored
}

/// 渲染一条方法列模板：替换 {占位符}。discountPct = discountRate×100（去浮点噪声，
/// JS：`String(Number((r * 100).toFixed(4)))`）。
public func renderMethodText(_ def: DiscountLineDef, mode: MethodMode, vars: [String: Double] = [:]) -> String {
    let tpl: String
    switch mode {
    case .restored: tpl = def.methodRestored
    case .before: tpl = def.methodBefore
    case .discounted: tpl = def.methodDiscounted
    }
    var out = ""
    var i = tpl.startIndex
    while i < tpl.endIndex {
        if tpl[i] == "{", let close = tpl[i...].firstIndex(of: "}") {
            let key = String(tpl[tpl.index(after: i)..<close])
            if key == "discountPct" {
                if let r = vars["discountRate"] {
                    var s = String(format: "%.4f", r * 100)
                    while s.last == "0" { s.removeLast() }
                    if s.last == "." { s.removeLast() }
                    out += s
                } else {
                    out += "{discountPct}"
                }
            } else if let v = vars[key] {
                out += jsNumberString(v)
            } else {
                out += "{\(key)}"
            }
            i = tpl.index(after: close)
            continue
        }
        out.append(tpl[i])
        i = tpl.index(after: i)
    }
    return out
}

public struct DiscountRuleInput: Equatable {
    public var discountRate: Double
    public var noDiscountKeys: [String]?
    public var zeroAfterDiscountKeys: [String]?
    public var outputTaxRate: Double?
    public var jiaTax: Double?
    public init(discountRate: Double, noDiscountKeys: [String]? = nil,
                zeroAfterDiscountKeys: [String]? = nil, outputTaxRate: Double? = nil,
                jiaTax: Double? = nil) {
        self.discountRate = discountRate; self.noDiscountKeys = noDiscountKeys
        self.zeroAfterDiscountKeys = zeroAfterDiscountKeys; self.outputTaxRate = outputTaxRate
        self.jiaTax = jiaTax
    }
}

public enum DiscountError: Error, Equatable {
    case invalidRate(String)
}

/// 逐项打折：table2Before → table2After。
/// - outputTaxRate/jiaTax 用于折后销项税额公式；缺失时销项税额保持折前值（calc 恒提供税率）。
/// - zeroAfterDiscountKeys：折后=0 清单（Q2 裁决 b），仅 discountRate < 1 时生效；缺失时用默认值。
/// - throws: discountRate 非法（<=0 / >1 / 非数字）时抛错。
public func applyDiscount(_ before: Table2, rule: DiscountRuleInput) throws -> Table2 {
    let rate = rule.discountRate
    guard rate.isFinite, rate > 0, rate <= 1 else {
        throw DiscountError.invalidRate("折扣率非法：\(jsNumberString(rate))（取值范围 (0,1]）")
    }
    var noDisc = Set(rule.noDiscountKeys ?? defaultNoDiscountKeys)
    let zeroDisc = Set(rule.zeroAfterDiscountKeys ?? defaultZeroAfterDiscountKeys)
    // 合计项 key 联动子项。
    for (parent, children) in discountParentChildren where noDisc.contains(parent) {
        for c in children { noDisc.insert(c) }
    }
    var after = Table2()

    // 明细项：折扣率 < 1 且 ∈ zeroAfterDiscountKeys 则折后 = 0（优先于不打折）；
    // ∈ noDiscountKeys 则保持；否则 × 折扣率。未在 DEFS 中的额外数值 key 同规则处理
    //（如某配置表二内含 safetyFee 行；合计项 key 不在此列，由下文加总覆盖）。
    let defKeys = Set(discountLineDefs.map { $0.key })
    var leafKeys = Set(discountLineDefs.filter { $0.kind == .leaf }.map { $0.key })
    for k in before.values.keys where !defKeys.contains(k) && k != "dispatchUnit" && k != "dispatchPeople" {
        leafKeys.insert(k)
    }
    for k in leafKeys {
        let v = num(before.values[k])
        if rate < 1, zeroDisc.contains(k) {
            after.values[k] = 0
        } else if noDisc.contains(k) {
            after.values[k] = r2(v)
        } else {
            after.values[k] = r2(v * rate)
        }
    }

    // 合计项：由折后明细加总（不直接乘折扣率）。
    after.laborTotal = r2(after.techFee + after.laborFee)
    after.mainMat = r2(after.jiaMat + after.yiMat)
    after.matTotal = r2(after.mainMat + after.auxMat)
    after.directFee = r2(after.laborTotal + after.matTotal + after.machineFee + after.instrumentFee)
    after.measureFee = r2(measureLeaves.reduce(0) { $0 + (after.values[$1] ?? 0) })
    after.directTotal = r2(after.directFee + after.measureFee)
    after.regFee = r2(after.sewageFee + after.socialFee + after.housingFee + after.accidentFee)
    after.indirectTotal = r2(after.regFee + after.mgmtFee)
    after.exclTax = r2(after.directTotal + after.indirectTotal + after.profit)

    // 销项税额：基数取折后值；未提供税率时保持折前值。
    if let ot = rule.outputTaxRate, let jt = rule.jiaTax {
        after.outputTax = r2((after.exclTax - after.jiaMat) * ot + after.jiaMat * jt)
    } else {
        after.outputTax = r2(num(before.values["outputTax"]))
    }
    after.inclTax = r2(after.exclTax + after.outputTax)

    // 信息项原样透传。
    after.dispatchUnit = before.values["dispatchUnit"] ?? 0
    after.dispatchPeople = before.values["dispatchPeople"] ?? 0
    return after
}
