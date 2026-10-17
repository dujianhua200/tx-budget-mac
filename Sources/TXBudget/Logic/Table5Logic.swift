import Foundation

/// 表五公式列与视图行（对照 Electron `v3.js` 的 table5Formula / buildTable5ViewRows）。

public let table5BasisLabels: [String: String] = [
    "manual": "手动输入",
    "preDiscountExclTax": "折前建安工程费除税价",
    "afterDiscountExclTax": "折后建安工程费除税价",
    "laborTotal": "人工费（折前）",
    "fixed": "固定金额",
    "surveyKm": "勘察长度",
    "sum": "子项之和",
]

private func pctText(_ rate: Double?) -> String {
    guard let rate else { return "" }
    let v = (rate * 100 * 10000).rounded() / 10000
    return "\(jsNumberString(v))%"
}

/// 表五公式列：由 table5Fees 的 basis + rate 生成。
/// manual → “手动输入”；safetyFee → “折前建安工程费除税价 × {rate}%”。
public func table5Formula(_ fee: Table5Fee) -> String {
    if fee.basis == "manual" { return "手动输入" }
    if fee.key == "safetyFee" { return "折前建安工程费除税价 × \(pctText(fee.rate))" }
    switch fee.basis {
    case "preDiscountExclTax": return "折前建安工程费除税价 × \(pctText(fee.rate))"
    case "afterDiscountExclTax": return "折后建安工程费除税价 × \(pctText(fee.rate))"
    case "laborTotal": return "人工费 × \(pctText(fee.rate))"
    case "fixed": return fee.amount != nil ? "固定金额 \(jsNumberString(fee.amount!))" : "固定金额"
    case "surveyKm": return "按勘察长度分段计取"
    case "sum": return "子项之和"
    default: return fee.note
    }
}

public struct Table5ViewRow: Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var basis: String
    public var rate: Double?
    public var amount: Double?
    public var formula: String
    public var enabled: Bool
    public init(key: String, name: String, basis: String, rate: Double?, amount: Double?,
                formula: String, enabled: Bool) {
        self.key = key; self.name = name; self.basis = basis; self.rate = rate
        self.amount = amount; self.formula = formula; self.enabled = enabled
    }
}

/// 表五视图行：全量费用项。金额取 result.table5.rows（引擎已含 overrides 覆盖）；
/// 启用 = override.enabled ?? fee.enabled。引擎不输出 enabled=false 的行，此处以配置项为准补回停用行。
public func buildTable5ViewRows(profile: ConfigurationProfile?, project: ProjectRecord?,
                                 result: CalcResult?) -> [Table5ViewRow] {
    // 按 order 稳定排序（Swift sorted 非稳定排序，以原下标作决胜）。
    let fees = (profile?.table5Fees ?? []).enumerated().sorted {
        if $0.element.order != $1.element.order { return $0.element.order < $1.element.order }
        return $0.offset < $1.offset
    }.map { $0.element }
    var byKey: [String: Table5Row] = [:]
    for r in result?.table5.rows ?? [] { byKey[r.key] = r }
    var overrides: [String: Table5Override] = [:]
    for o in project?.table5Overrides ?? [] { overrides[o.key] = o }
    return fees.map { fee in
        let ov = overrides[fee.key]
        let enabled = ov?.enabled ?? fee.enabled ?? true
        let row = byKey[fee.key]
        return Table5ViewRow(
            key: fee.key, name: fee.name, basis: fee.basis, rate: fee.rate,
            amount: enabled && row != nil ? (row!.excl) : nil,
            formula: table5Formula(fee), enabled: enabled
        )
    }
}
