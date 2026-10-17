import Foundation

/// 库表行模型（带 id，与 Electron `profile.libraries` 各表一一对应）。
/// 引擎类型（Quota/Material/Rule…）不带 id；此处行模型保留全部字段（含 coef/book/alias/remark 等），
/// 转换到引擎时只取引擎需要的字段。全部容错解码。

public struct QuotaRow: Equatable, Codable {
    public var id: String
    public var code: String
    public var name: String
    public var unit: String
    public var tech: Double
    public var labor: Double
    public var coef: Double?
    public var book: String
    public var alias: String
    public init(id: String = "", code: String = "", name: String = "", unit: String = "",
                tech: Double = 0, labor: Double = 0, coef: Double? = nil, book: String = "", alias: String = "") {
        self.id = id; self.code = code; self.name = name; self.unit = unit
        self.tech = tech; self.labor = labor; self.coef = coef; self.book = book; self.alias = alias
    }
    enum CodingKeys: String, CodingKey { case id, code, name, unit, tech, labor, coef, book, alias }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientString(forKey: .id)
        code = c.decodeLenientString(forKey: .code)
        name = c.decodeLenientString(forKey: .name)
        unit = c.decodeLenientString(forKey: .unit)
        tech = c.decodeLenientDouble(forKey: .tech, default: 0)
        labor = c.decodeLenientDouble(forKey: .labor, default: 0)
        coef = c.decodeLenientDouble(forKey: .coef)
        book = c.decodeLenientString(forKey: .book)
        alias = c.decodeLenientString(forKey: .alias)
    }
    public func toEngine() -> Quota { Quota(code: code, name: name, unit: unit, tech: tech, labor: labor) }
}

public struct ShortlistRow: Equatable, Codable {
    public var id: String
    public var code: String
    public var name: String
    public var unit: String
    public var coef: Double?
    public init(id: String = "", code: String = "", name: String = "", unit: String = "", coef: Double? = nil) {
        self.id = id; self.code = code; self.name = name; self.unit = unit; self.coef = coef
    }
    enum CodingKeys: String, CodingKey { case id, code, name, unit, coef }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientString(forKey: .id)
        code = c.decodeLenientString(forKey: .code)
        name = c.decodeLenientString(forKey: .name)
        unit = c.decodeLenientString(forKey: .unit)
        coef = c.decodeLenientDouble(forKey: .coef)
    }
}

public struct MaterialRow: Equatable, Codable {
    public var id: String
    public var name: String
    public var spec: String
    public var unit: String
    public var priceExcl: Double
    public var supply: String
    public var remark: String
    public init(id: String = "", name: String = "", spec: String = "", unit: String = "",
                priceExcl: Double = 0, supply: String = "", remark: String = "") {
        self.id = id; self.name = name; self.spec = spec; self.unit = unit
        self.priceExcl = priceExcl; self.supply = supply; self.remark = remark
    }
    enum CodingKeys: String, CodingKey { case id, name, spec, unit, priceExcl, supply, remark }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientString(forKey: .id)
        name = c.decodeLenientString(forKey: .name)
        spec = c.decodeLenientString(forKey: .spec)
        unit = c.decodeLenientString(forKey: .unit)
        priceExcl = c.decodeLenientDouble(forKey: .priceExcl, default: 0)
        supply = c.decodeLenientString(forKey: .supply)
        remark = c.decodeLenientString(forKey: .remark)
    }
    public func toEngine() -> Material {
        Material(name: name, spec: spec, unit: unit, priceExcl: priceExcl, supply: supply)
    }
}

public struct RuleRow: Equatable, Codable {
    public var id: String
    public var quota: String
    public var material: String
    public var spec: String
    public var unit: String
    public var consumption: Double
    public var supply: String
    public var kind: String
    public var variant: String
    public var remark: String
    public var appliesTo: String
    public init(id: String = "", quota: String = "", material: String = "", spec: String = "",
                unit: String = "", consumption: Double = 0, supply: String = "", kind: String = "",
                variant: String = "", remark: String = "", appliesTo: String = "全") {
        self.id = id; self.quota = quota; self.material = material; self.spec = spec; self.unit = unit
        self.consumption = consumption; self.supply = supply; self.kind = kind; self.variant = variant
        self.remark = remark; self.appliesTo = appliesTo
    }
    enum CodingKeys: String, CodingKey {
        case id, quota, material, spec, unit, consumption, supply, kind, variant, remark, appliesTo
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientString(forKey: .id)
        quota = c.decodeLenientString(forKey: .quota)
        material = c.decodeLenientString(forKey: .material)
        spec = c.decodeLenientString(forKey: .spec)
        unit = c.decodeLenientString(forKey: .unit)
        consumption = c.decodeLenientDouble(forKey: .consumption, default: 0)
        supply = c.decodeLenientString(forKey: .supply)
        kind = c.decodeLenientString(forKey: .kind)
        variant = c.decodeLenientString(forKey: .variant)
        remark = c.decodeLenientString(forKey: .remark)
        appliesTo = c.decodeLenientString(forKey: .appliesTo, default: "全")
    }
    public func toEngine() -> Rule {
        Rule(id: id.isEmpty ? nil : id, quota: quota, material: material, spec: spec,
             consumption: consumption, supply: supply, kind: kind, variant: variant)
    }
}

public struct MachinePriceRow: Equatable, Codable {
    public var id: String
    public var code: String
    public var name: String
    public var unit: String
    public var price: Double
    public init(id: String = "", code: String = "", name: String = "", unit: String = "", price: Double = 0) {
        self.id = id; self.code = code; self.name = name; self.unit = unit; self.price = price
    }
    enum CodingKeys: String, CodingKey { case id, code, name, unit, price }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientString(forKey: .id)
        code = c.decodeLenientString(forKey: .code)
        name = c.decodeLenientString(forKey: .name)
        unit = c.decodeLenientString(forKey: .unit)
        price = c.decodeLenientDouble(forKey: .price, default: 0)
    }
    public func toEngine() -> MachinePrice { MachinePrice(code: code, price: price) }
}

public struct InstrumentPriceRow: Equatable, Codable {
    public var id: String
    public var code: String
    public var name: String
    public var unit: String
    public var price: Double
    public init(id: String = "", code: String = "", name: String = "", unit: String = "", price: Double = 0) {
        self.id = id; self.code = code; self.name = name; self.unit = unit; self.price = price
    }
    enum CodingKeys: String, CodingKey { case id, code, name, unit, price }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientString(forKey: .id)
        code = c.decodeLenientString(forKey: .code)
        name = c.decodeLenientString(forKey: .name)
        unit = c.decodeLenientString(forKey: .unit)
        price = c.decodeLenientDouble(forKey: .price, default: 0)
    }
    public func toEngine() -> InstrumentPrice { InstrumentPrice(code: code, price: price) }
}

public struct QuotaMachineRow: Equatable, Codable {
    public var id: String
    public var quota: String
    public var mcode: String
    public var mname: String
    public var unit: String
    public var qty: Double
    public init(id: String = "", quota: String = "", mcode: String = "", mname: String = "",
                unit: String = "", qty: Double = 0) {
        self.id = id; self.quota = quota; self.mcode = mcode; self.mname = mname; self.unit = unit; self.qty = qty
    }
    enum CodingKeys: String, CodingKey { case id, quota, mcode, mname, unit, qty }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientString(forKey: .id)
        quota = c.decodeLenientString(forKey: .quota)
        mcode = c.decodeLenientString(forKey: .mcode)
        mname = c.decodeLenientString(forKey: .mname)
        unit = c.decodeLenientString(forKey: .unit)
        qty = c.decodeLenientDouble(forKey: .qty, default: 0)
    }
    public func toEngine() -> QuotaMachine {
        QuotaMachine(quota: quota, mcode: mcode, mname: mname, unit: unit, qty: qty)
    }
}

public struct QuotaInstrumentRow: Equatable, Codable {
    public var id: String
    public var quota: String
    public var mcode: String
    public var mname: String
    public var unit: String
    public var qty: Double
    public init(id: String = "", quota: String = "", mcode: String = "", mname: String = "",
                unit: String = "", qty: Double = 0) {
        self.id = id; self.quota = quota; self.mcode = mcode; self.mname = mname; self.unit = unit; self.qty = qty
    }
    enum CodingKeys: String, CodingKey { case id, quota, mcode, mname, unit, qty }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientString(forKey: .id)
        quota = c.decodeLenientString(forKey: .quota)
        mcode = c.decodeLenientString(forKey: .mcode)
        mname = c.decodeLenientString(forKey: .mname)
        unit = c.decodeLenientString(forKey: .unit)
        qty = c.decodeLenientDouble(forKey: .qty, default: 0)
    }
    public func toEngine() -> QuotaInstrument {
        QuotaInstrument(quota: quota, mcode: mcode, mname: mname, unit: unit, qty: qty)
    }
}

/// 8 张库表（与 Electron `profile.libraries` 一一对应）。
public struct LibrarySet: Equatable, Codable {
    public var quotas: [QuotaRow]
    public var shortlist: [ShortlistRow]
    public var materials: [MaterialRow]
    public var rules: [RuleRow]
    public var machinePrices: [MachinePriceRow]
    public var instrumentPrices: [InstrumentPriceRow]
    public var quotaMachines: [QuotaMachineRow]
    public var quotaInstruments: [QuotaInstrumentRow]
    public init(quotas: [QuotaRow] = [], shortlist: [ShortlistRow] = [], materials: [MaterialRow] = [],
                rules: [RuleRow] = [], machinePrices: [MachinePriceRow] = [],
                instrumentPrices: [InstrumentPriceRow] = [], quotaMachines: [QuotaMachineRow] = [],
                quotaInstruments: [QuotaInstrumentRow] = []) {
        self.quotas = quotas; self.shortlist = shortlist; self.materials = materials; self.rules = rules
        self.machinePrices = machinePrices; self.instrumentPrices = instrumentPrices
        self.quotaMachines = quotaMachines; self.quotaInstruments = quotaInstruments
    }
    enum CodingKeys: String, CodingKey {
        case quotas, shortlist, materials, rules, machinePrices, instrumentPrices, quotaMachines, quotaInstruments
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quotas = (try? c.decodeIfPresent([QuotaRow].self, forKey: .quotas)) ?? []
        shortlist = (try? c.decodeIfPresent([ShortlistRow].self, forKey: .shortlist)) ?? []
        materials = (try? c.decodeIfPresent([MaterialRow].self, forKey: .materials)) ?? []
        rules = (try? c.decodeIfPresent([RuleRow].self, forKey: .rules)) ?? []
        machinePrices = (try? c.decodeIfPresent([MachinePriceRow].self, forKey: .machinePrices)) ?? []
        instrumentPrices = (try? c.decodeIfPresent([InstrumentPriceRow].self, forKey: .instrumentPrices)) ?? []
        quotaMachines = (try? c.decodeIfPresent([QuotaMachineRow].self, forKey: .quotaMachines)) ?? []
        quotaInstruments = (try? c.decodeIfPresent([QuotaInstrumentRow].self, forKey: .quotaInstruments)) ?? []
    }
    /// 缺 id 的行补确定性 id（与 Electron `withIds` 一致：<前缀>_<序号>）。
    public func withIds() -> LibrarySet {
        var out = self
        func fix<T>(_ rows: [T], prefix: String, setId: (inout T, String) -> Void, getId: (T) -> String) -> [T] {
            rows.enumerated().map { i, r in
                var row = r
                if getId(row).isEmpty { setId(&row, "\(prefix)_\(i)") }
                return row
            }
        }
        out.quotas = fix(quotas, prefix: "quota", setId: { $0.id = $1 }, getId: { $0.id })
        out.shortlist = fix(shortlist, prefix: "short", setId: { $0.id = $1 }, getId: { $0.id })
        out.materials = fix(materials, prefix: "mat", setId: { $0.id = $1 }, getId: { $0.id })
        out.rules = fix(rules, prefix: "rule", setId: { $0.id = $1 }, getId: { $0.id })
        out.machinePrices = fix(machinePrices, prefix: "mach", setId: { $0.id = $1 }, getId: { $0.id })
        out.instrumentPrices = fix(instrumentPrices, prefix: "inst", setId: { $0.id = $1 }, getId: { $0.id })
        out.quotaMachines = fix(quotaMachines, prefix: "qm", setId: { $0.id = $1 }, getId: { $0.id })
        out.quotaInstruments = fix(quotaInstruments, prefix: "qi", setId: { $0.id = $1 }, getId: { $0.id })
        return out
    }
}
