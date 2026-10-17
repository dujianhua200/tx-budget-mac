import Foundation

/// 具名费率记录（Codable，键名与 Electron `rates.byProjectType[工程类型]` 一致）。
/// winterRate 的 nil = 按 winterTable 查表，与 0（显式 0）严格区分。
public struct NamedRatesRecord: Equatable, Codable {
    public var values: [String: Double?]
    public init(values: [String: Double?] = [:]) { self.values = values }

    public func value(forKey key: String) -> Double? { values[key] ?? nil }
    public mutating func setValue(_ value: Double?, forKey key: String) { values[key] = value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode([String: JSONValue].self)) ?? [:]
        var out: [String: Double?] = [:]
        for def in rateFieldDefs {
            if let jv = raw[def.key] {
                switch jv {
                case .null: out[def.key] = nil
                case .number(let n): out[def.key] = n
                case .string(let s): out[def.key] = Double(s.trimmingCharacters(in: .whitespaces))
                default: out[def.key] = nil
                }
            } else {
                out[def.key] = nil
            }
        }
        // 保留非标准键（原样透传，不丢数据）。
        for (k, jv) in raw where !rateFieldDefs.map({ $0.key }).contains(k) {
            if case .number(let n) = jv { out[k] = n }
        }
        self.values = out
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        var dict: [String: JSONValue] = [:]
        for (k, v) in values {
            dict[k] = v.map { .number($0) } ?? .null
        }
        try c.encode(dict)
    }

    public func toEngine() -> NamedRates {
        var n = NamedRates()
        for def in rateFieldDefs {
            // values[key] 是 Double??：外层缺失 → nil；内层 nil → nil（查表/缺失语义）。
            if let v = values[def.key], let v {
                n.setValue(v, forKey: def.key)
            } else {
                n.setValue(nil, forKey: def.key)
            }
        }
        return n
    }

    public static func fromEngine(_ n: NamedRates) -> NamedRatesRecord {
        var rec = NamedRatesRecord()
        for def in rateFieldDefs {
            rec.values[def.key] = n.value(forKey: def.key)
        }
        return rec
    }
}

/// 费率记录：byProjectType（5 工程类型 × 21 字段）+ winterTable + vatRates。
public struct RatesRecord: Equatable, Codable {
    public var byProjectType: [String: NamedRatesRecord]
    public var winterTable: [String: Double]
    public var vatRates: VatRates
    public init(byProjectType: [String: NamedRatesRecord] = [:], winterTable: [String: Double] = [:],
                vatRates: VatRates = VatRates()) {
        self.byProjectType = byProjectType; self.winterTable = winterTable; self.vatRates = vatRates
    }
    enum CodingKeys: String, CodingKey { case byProjectType, winterTable, vatRates }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        byProjectType = (try? c.decodeIfPresent([String: NamedRatesRecord].self, forKey: .byProjectType)) ?? [:]
        winterTable = (try? c.decodeIfPresent([String: Double].self, forKey: .winterTable)) ?? [:]
        vatRates = (try? c.decodeIfPresent(VatRates.self, forKey: .vatRates)) ?? VatRates()
    }
    public func toEngine() -> Rates {
        var byType: [String: NamedRates] = [:]
        for (k, v) in byProjectType { byType[k] = v.toEngine() }
        return Rates(byProjectType: byType, winterTable: winterTable, vatRates: vatRates)
    }
    public static func fromEngine(_ r: Rates) -> RatesRecord {
        var byType: [String: NamedRatesRecord] = [:]
        if let b = r.byProjectType {
            for (k, v) in b { byType[k] = NamedRatesRecord.fromEngine(v) }
        }
        return RatesRecord(byProjectType: byType, winterTable: r.winterTable, vatRates: r.vatRates)
    }
}

/// 打折规则记录（methodText 原样透传，引擎不消费）。
public struct DiscountRuleRecord: Equatable, Codable {
    public var discountRate: Double?
    public var noDiscountKeys: [String]?
    public var zeroAfterDiscountKeys: [String]?
    public var methodText: [String: String]?
    public init(discountRate: Double? = nil, noDiscountKeys: [String]? = nil,
                zeroAfterDiscountKeys: [String]? = nil, methodText: [String: String]? = nil) {
        self.discountRate = discountRate; self.noDiscountKeys = noDiscountKeys
        self.zeroAfterDiscountKeys = zeroAfterDiscountKeys; self.methodText = methodText
    }
    enum CodingKeys: String, CodingKey { case discountRate, noDiscountKeys, zeroAfterDiscountKeys, methodText }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        discountRate = c.decodeLenientDouble(forKey: .discountRate)
        noDiscountKeys = try? c.decodeIfPresent([String].self, forKey: .noDiscountKeys)
        zeroAfterDiscountKeys = try? c.decodeIfPresent([String].self, forKey: .zeroAfterDiscountKeys)
        methodText = try? c.decodeIfPresent([String: String].self, forKey: .methodText)
    }
    public func toEngine() -> DiscountRule {
        DiscountRule(discountRate: discountRate, noDiscountKeys: noDiscountKeys,
                     zeroAfterDiscountKeys: zeroAfterDiscountKeys)
    }
    public static func fromEngine(_ d: DiscountRule, methodText: [String: String]? = nil) -> DiscountRuleRecord {
        DiscountRuleRecord(discountRate: d.discountRate, noDiscountKeys: d.noDiscountKeys,
                           zeroAfterDiscountKeys: d.zeroAfterDiscountKeys, methodText: methodText)
    }
}
