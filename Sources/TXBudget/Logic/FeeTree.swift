import Foundation

/// 取费左树（对照 Electron `v3.js` 的 FEE_TREE：由表二费用结构派生，DISCOUNT_LINE_DEFS 全覆盖）。

public enum FeeNodeKind: Equatable {
    case group
    case leaf
}

public struct FeeNode: Equatable, Identifiable {
    public var id: String
    public var label: String
    public var kind: FeeNodeKind
    public var key: String?
    public var children: [FeeNode]?
    public init(id: String, label: String, kind: FeeNodeKind, key: String? = nil, children: [FeeNode]? = nil) {
        self.id = id; self.label = label; self.kind = kind; self.key = key; self.children = children
    }
}

private func feeLeaf(_ key: String) -> FeeNode {
    let def = discountLineDefs.first { $0.key == key }
    return FeeNode(id: "leaf:\(key)", label: def?.label ?? key, kind: .leaf, key: key)
}

private func feeGroup(_ id: String, _ label: String, _ children: [FeeNode]) -> FeeNode {
    FeeNode(id: id, label: label, kind: .group, children: children)
}

public let feeTree = feeGroup("root:all", "建筑安装工程费", [
    feeGroup("g:direct", "直接费", [
        feeGroup("g:labor", "人工费", [feeLeaf("techFee"), feeLeaf("laborFee"), feeLeaf("laborTotal")]),
        feeGroup("g:material", "材料费", [feeLeaf("jiaMat"), feeLeaf("yiMat"), feeLeaf("mainMat"), feeLeaf("auxMat"), feeLeaf("matTotal")]),
        feeGroup("g:machine", "机械使用费", [feeLeaf("machineFee")]),
        feeGroup("g:instrument", "仪器仪表费", [feeLeaf("instrumentFee")]),
        feeGroup("g:directFee", "直接工程费", [feeLeaf("directFee")]),
    ]),
    feeGroup("g:measure", "措施费", [
        feeLeaf("envFee"), feeLeaf("civilFee"), feeLeaf("carryFee"), feeLeaf("disturbFee"), feeLeaf("handoverFee"),
        feeLeaf("tempFee"), feeLeaf("vehicleFee"), feeLeaf("nightFee"), feeLeaf("winterFee"), feeLeaf("toolFee"),
        feeLeaf("utilityFee"), feeLeaf("specialFee"), feeLeaf("protectFee"), feeLeaf("earthFee"), feeLeaf("dispatchFee"),
        feeLeaf("bigMachineFee"), feeLeaf("measureFee"),
    ]),
    feeGroup("g:directTotal", "直接费合计", [feeLeaf("directTotal")]),
    feeGroup("g:reg", "规费", [feeLeaf("sewageFee"), feeLeaf("socialFee"), feeLeaf("housingFee"), feeLeaf("accidentFee"), feeLeaf("regFee")]),
    feeGroup("g:mgmt", "企业管理费", [feeLeaf("mgmtFee")]),
    feeGroup("g:indirect", "间接费", [feeLeaf("indirectTotal")]),
    feeGroup("g:profit", "利润", [feeLeaf("profit")]),
    feeGroup("g:tax", "税金", [feeLeaf("outputTax")]),
    feeGroup("g:total", "合计", [feeLeaf("exclTax"), feeLeaf("inclTax")]),
])

public func findFeeNode(_ node: FeeNode?, _ id: String) -> FeeNode? {
    guard let node else { return nil }
    if node.id == id { return node }
    for c in node.children ?? [] {
        if let hit = findFeeNode(c, id) { return hit }
    }
    return nil
}

public func feeLeavesOf(_ node: FeeNode?) -> [String] {
    guard let node else { return [] }
    if node.kind == .leaf, let key = node.key { return [key] }
    return (node.children ?? []).flatMap { feeLeavesOf($0) }
}

/// 费率 key → 费率字段（rates.byProjectType[工程类型] 内）；无对应费率的项为 nil。
public let feeRateField: [String: String] = [
    "techFee": "techPrice", "laborFee": "laborPrice", "auxMat": "auxRate",
    "envFee": "envRate", "civilFee": "civilRate", "carryFee": "carryRate", "disturbFee": "disturbRate",
    "handoverFee": "handoverRate", "tempFee": "tempNearRate", "vehicleFee": "vehicleRate",
    "nightFee": "nightRate", "winterFee": "winterRate", "toolFee": "toolRate", "utilityFee": "utilityRate",
    "protectFee": "protectRate", "socialFee": "socialRate", "housingFee": "housingRate",
    "accidentFee": "accidentRate", "mgmtFee": "mgmtRate", "profit": "profitRate",
]

/// 计算式（依据）文本：取 DISCOUNT_LINE_DEFS 的 methodBefore，用费率占位符填充。
/// 费率占位符显示为百分比数字（如 auxRate 0.003 → 0.3），价格占位符原样显示。
public func feeBasisText(_ key: String, _ vars: [String: Double]) -> String {
    guard let def = discountLineDefs.first(where: { $0.key == key }) else { return "" }
    var basisVars: [String: Double] = [:]
    for (k, v) in vars {
        if k.hasSuffix("Rate"), k != "discountRate" { basisVars[k] = v * 100 } else { basisVars[k] = v }
    }
    return renderMethodText(def, mode: .before, vars: basisVars)
}

public struct FeeRow: Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var basis: String
    public var base: String
    public var rate: Double?
    public var rateField: String?
    public var amount: Double?
    public init(key: String, name: String, basis: String, base: String,
                rate: Double?, rateField: String?, amount: Double?) {
        self.key = key; self.name = name; self.basis = basis; self.base = base
        self.rate = rate; self.rateField = rateField; self.amount = amount
    }
}

/// 右表行：点树节点 → 该组费用项。金额取 result.table2Before（折前）；
/// 费率取 profile.rates.byProjectType[projectType]。tempRate 展示取 tempNearRate；
/// winterRate null = 按 winterTable 查（以 Ⅲ类地区为默认展示口径）。
public func feeRowsForNode(_ nodeId: String, profile: ConfigurationProfile?,
                            result: CalcResult?, projectType: String) -> [FeeRow] {
    guard let node = findFeeNode(feeTree, nodeId) else { return [] }
    let rates = profile?.rates.byProjectType[projectType] ?? NamedRatesRecord()
    let winterTable = profile?.rates.winterTable ?? [:]
    var vars: [String: Double] = [:]
    for def in rateFieldDefs {
        if let v = rates.value(forKey: def.key) { vars[def.key] = v }
    }
    if vars["tempRate"] == nil { vars["tempRate"] = rates.value(forKey: "tempNearRate") ?? 0 }
    if vars["winterRate"] == nil { vars["winterRate"] = winterTable["Ⅲ类地区"] ?? 0 }
    vars["discountRate"] = profile?.discountRule.discountRate ?? 1
    return feeLeavesOf(node).map { key in
        let def = discountLineDefs.first { $0.key == key }
        let rateField = feeRateField[key]
        var rate: Double? = rateField.flatMap { rates.value(forKey: $0) }
        if key == "winterFee" { rate = vars["winterRate"] }
        let basis = feeBasisText(key, vars)
        let base = basis.contains("X") ? String(basis.split(separator: "X", maxSplits: 1).first ?? Substring(basis)) : basis
        return FeeRow(key: key, name: def?.label ?? key, basis: basis, base: base,
                      rate: rate, rateField: rateField,
                      amount: result?.table2Before.values[key])
    }
}

public func rateFieldDef(_ key: String) -> RateFieldDef? {
    rateFieldDefs.first { $0.key == key }
}
