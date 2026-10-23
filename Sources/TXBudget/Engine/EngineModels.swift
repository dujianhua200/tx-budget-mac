import Foundation
/// 引擎输入/输出模型（纯逻辑，不依赖 SwiftUI）。
/// 字段语义与 Electron 版 JS 引擎（src/engine/*.mjs + src/lib/profiles.js）一对一对照。
/// 注意：ProjectInfo 里施工折扣/甲供增值税/乙供增值税为可选类型——JS 的 resolveRates
/// 读的是合并前（DEFAULT_INFO 合并前）的原始 project.info，未填 = null = 落到下一级；
/// 其余字段合并默认值后恒有值，故为非可选。

public struct Quota: Decodable, Equatable {
    public var code: String
    public var name: String
    public var unit: String
    public var tech: Double
    public var labor: Double
    public init(code: String, name: String = "", unit: String = "", tech: Double = 0, labor: Double = 0) {
        self.code = code; self.name = name; self.unit = unit; self.tech = tech; self.labor = labor
    }
}

public struct Material: Decodable, Equatable {
    public var name: String
    public var spec: String
    public var unit: String
    public var priceExcl: Double
    public var supply: String
    public init(name: String, spec: String = "", unit: String = "", priceExcl: Double = 0, supply: String = "") {
        self.name = name; self.spec = spec; self.unit = unit; self.priceExcl = priceExcl; self.supply = supply
    }
}

public struct Rule: Decodable, Equatable {
    public var id: String?
    public var quota: String
    public var material: String
    public var spec: String
    public var consumption: Double
    public var supply: String
    public var kind: String
    public var variant: String
    /// 适用工程（v2.4.1 起引擎消费，语义见 docs/v2.4.1-appliesto-design.md）。
    public var appliesTo: String = "全"
    public init(id: String? = nil, quota: String, material: String, spec: String = "",
                consumption: Double = 0, supply: String = "", kind: String = "", variant: String = "",
                appliesTo: String = "全") {
        self.id = id; self.quota = quota; self.material = material; self.spec = spec
        self.consumption = consumption; self.supply = supply; self.kind = kind; self.variant = variant
        self.appliesTo = appliesTo
    }
}

public struct MachinePrice: Decodable, Equatable {
    public var code: String
    public var price: Double
    public init(code: String, price: Double = 0) { self.code = code; self.price = price }
}

public struct InstrumentPrice: Decodable, Equatable {
    public var code: String
    public var price: Double
    public init(code: String, price: Double = 0) { self.code = code; self.price = price }
}

public struct QuotaMachine: Decodable, Equatable {
    public var quota: String
    public var mcode: String
    public var mname: String
    public var unit: String
    public var qty: Double
    public init(quota: String, mcode: String, mname: String = "", unit: String = "", qty: Double = 0) {
        self.quota = quota; self.mcode = mcode; self.mname = mname; self.unit = unit; self.qty = qty
    }
}

public struct QuotaInstrument: Decodable, Equatable {
    public var quota: String
    public var mcode: String
    public var mname: String
    public var unit: String
    public var qty: Double
    public init(quota: String, mcode: String, mname: String = "", unit: String = "", qty: Double = 0) {
        self.quota = quota; self.mcode = mcode; self.mname = mname; self.unit = unit; self.qty = qty
    }
}

/// 工程信息（DEFAULT_INFO，见 calc.mjs）。未填的三个 resolveRates 字段为 nil。
public struct ProjectInfo: Equatable {
    public var 建设单位: String = ""
    public var 建设项目名称: String = ""
    public var 单项工程名称: String = ""
    public var 合同编号: String = ""
    public var 工程类型: String = "通信线路工程"
    public var 区县: String = ""
    public var 编制日期: String = ""
    public var 施工折扣: Double? = nil
    public var 段落起点: String = ""
    public var 段落终点: String = ""
    public var 监理单位: String = ""
    public var 表格编号: String = "YD-"
    public var 单段工程名称: String = ""
    public var 项目编号: String = ""
    public var 施工距离: String = "35KM以内"
    public var 施工实际里程: Double? = nil
    public var 施工调遣分类: String = "施工队伍调遣人数(线路、管道）"
    public var 施工现场海拔: Double = 0
    public var 冬雨季施工费: String = "Ⅲ类地区"
    public var 甲供增值税: Double? = nil
    public var 乙供增值税: Double? = nil
    public var 工程负责人: String = ""
    public var 审核: String = ""
    public var 编制: String = ""
    /// 新增可选字段（工程信息表单“参建单位”组；计算不读，仅展示/保存）。
    public var 施工单位: String? = nil
    public var 设计单位: String? = nil
    public init() {}

    /// JS `{...DEFAULT_INFO, ...info}` 合并后的值（calc 除 resolveRates 外都用合并值；
    /// resolveRates 读合并前原始值，故本函数只用于结果回填与展示）。
    public func merged() -> ProjectInfo {
        var out = self
        if out.施工折扣 == nil { out.施工折扣 = 1 }
        if out.甲供增值税 == nil { out.甲供增值税 = 0.13 }
        if out.乙供增值税 == nil { out.乙供增值税 = 0.09 }
        return out
    }
}

public struct QuantityRow: Equatable {
    public var id: String?
    public var quota: String
    public var variant: String?
    public var unit: String?
    public var qty: Double?
    public var coef: Double?
    public init(id: String? = nil, quota: String, variant: String? = nil,
                unit: String? = nil, qty: Double? = nil, coef: Double? = nil) {
        self.id = id; self.quota = quota; self.variant = variant
        self.unit = unit; self.qty = qty; self.coef = coef
    }
}

public struct MaterialAdjust: Equatable {
    public var key: String
    public var delta: Double
    public init(key: String, delta: Double = 0) { self.key = key; self.delta = delta }
}

public struct MaterialPriceOverride: Equatable {
    public var key: String
    public var priceExcl: Double
    public init(key: String, priceExcl: Double = 0) { self.key = key; self.priceExcl = priceExcl }
}

public struct RuleOverride: Equatable {
    public var ruleId: String
    public var enabled: Bool
    public init(ruleId: String, enabled: Bool) { self.ruleId = ruleId; self.enabled = enabled }
}

public struct Table5Override: Equatable {
    public var key: String
    public var enabled: Bool?
    public var amount: Double?
    public init(key: String, enabled: Bool? = nil, amount: Double? = nil) {
        self.key = key; self.enabled = enabled; self.amount = amount
    }
}

public struct RateOverrides: Equatable {
    public var discount: Double?
    public var jiaTax: Double?
    public var yiTax: Double?
    public var outputTax: Double?
    public var safetyVat: Double?
    public var taxRate: Double?
    public init(discount: Double? = nil, jiaTax: Double? = nil, yiTax: Double? = nil,
                outputTax: Double? = nil, safetyVat: Double? = nil, taxRate: Double? = nil) {
        self.discount = discount; self.jiaTax = jiaTax; self.yiTax = yiTax
        self.outputTax = outputTax; self.safetyVat = safetyVat; self.taxRate = taxRate
    }
}

public struct Project: Equatable {
    public var info: ProjectInfo
    public var quantities: [QuantityRow]
    public var materialAdjust: [MaterialAdjust]
    public var materialPriceOverrides: [MaterialPriceOverride]
    public var ruleOverrides: [RuleOverride]
    public var rateOverrides: RateOverrides?
    public var table5Overrides: [Table5Override]
    /// 工程序号（1 基）：工程在所属方案工程集合中的位置，供规则 appliesTo 过滤
    /// （v2.4.1）。由 calcFor 注入；直接构造时默认 1。
    public var projectOrdinal: Int = 1
    public init(info: ProjectInfo = ProjectInfo(), quantities: [QuantityRow] = [],
                materialAdjust: [MaterialAdjust] = [], materialPriceOverrides: [MaterialPriceOverride] = [],
                ruleOverrides: [RuleOverride] = [], rateOverrides: RateOverrides? = nil,
                table5Overrides: [Table5Override] = [], projectOrdinal: Int = 1) {
        self.info = info; self.quantities = quantities; self.materialAdjust = materialAdjust
        self.materialPriceOverrides = materialPriceOverrides; self.ruleOverrides = ruleOverrides
        self.rateOverrides = rateOverrides; self.table5Overrides = table5Overrides
        self.projectOrdinal = projectOrdinal
    }
}

/// 具名费率（一类工程类型）。nil = 字段缺失（具名路径告警 + 按 0 计）；
/// winterRate 的 nil 另有“按 winterTable 查表”语义。
public struct NamedRates: Equatable {
    public var techPrice: Double?
    public var laborPrice: Double?
    public var auxRate: Double?
    public var envRate: Double?
    public var civilRate: Double?
    public var carryRate: Double?
    public var disturbRate: Double?
    public var handoverRate: Double?
    public var tempNearRate: Double?
    public var tempFarRate: Double?
    public var vehicleRate: Double?
    public var nightRate: Double?
    public var winterRate: Double?
    public var toolRate: Double?
    public var utilityRate: Double?
    public var protectRate: Double?
    public var socialRate: Double?
    public var housingRate: Double?
    public var accidentRate: Double?
    public var mgmtRate: Double?
    public var profitRate: Double?
    public init() {}

    public func value(forKey key: String) -> Double? {
        switch key {
        case "techPrice": return techPrice
        case "laborPrice": return laborPrice
        case "auxRate": return auxRate
        case "envRate": return envRate
        case "civilRate": return civilRate
        case "carryRate": return carryRate
        case "disturbRate": return disturbRate
        case "handoverRate": return handoverRate
        case "tempNearRate": return tempNearRate
        case "tempFarRate": return tempFarRate
        case "vehicleRate": return vehicleRate
        case "nightRate": return nightRate
        case "winterRate": return winterRate
        case "toolRate": return toolRate
        case "utilityRate": return utilityRate
        case "protectRate": return protectRate
        case "socialRate": return socialRate
        case "housingRate": return housingRate
        case "accidentRate": return accidentRate
        case "mgmtRate": return mgmtRate
        case "profitRate": return profitRate
        default: return nil
        }
    }

    public mutating func setValue(_ value: Double?, forKey key: String) {
        switch key {
        case "techPrice": techPrice = value
        case "laborPrice": laborPrice = value
        case "auxRate": auxRate = value
        case "envRate": envRate = value
        case "civilRate": civilRate = value
        case "carryRate": carryRate = value
        case "disturbRate": disturbRate = value
        case "handoverRate": handoverRate = value
        case "tempNearRate": tempNearRate = value
        case "tempFarRate": tempFarRate = value
        case "vehicleRate": vehicleRate = value
        case "nightRate": nightRate = value
        case "winterRate": winterRate = value
        case "toolRate": toolRate = value
        case "utilityRate": utilityRate = value
        case "protectRate": protectRate = value
        case "socialRate": socialRate = value
        case "housingRate": housingRate = value
        case "accidentRate": accidentRate = value
        case "mgmtRate": mgmtRate = value
        case "profitRate": profitRate = value
        default: break
        }
    }
}

/// 解析后费率（全部已落值，非可选）+ 增值税率。
public struct ResolvedRates: Equatable {
    public var techPrice = 0.0
    public var laborPrice = 0.0
    public var auxRate = 0.0
    public var envRate = 0.0
    public var civilRate = 0.0
    public var carryRate = 0.0
    public var disturbRate = 0.0
    public var handoverRate = 0.0
    public var tempNearRate = 0.0
    public var tempFarRate = 0.0
    public var vehicleRate = 0.0
    public var nightRate = 0.0
    public var winterRate = 0.0
    public var toolRate = 0.0
    public var utilityRate = 0.0
    public var protectRate = 0.0
    public var socialRate = 0.0
    public var housingRate = 0.0
    public var accidentRate = 0.0
    public var mgmtRate = 0.0
    public var profitRate = 0.0
    public var jiaTax = 0.0
    public var yiTax = 0.0
    public var outputTax = 0.0
    public var taxRate = 0.0
    public init() {}

    public mutating func setValue(_ value: Double, forKey key: String) {
        switch key {
        case "techPrice": techPrice = value
        case "laborPrice": laborPrice = value
        case "auxRate": auxRate = value
        case "envRate": envRate = value
        case "civilRate": civilRate = value
        case "carryRate": carryRate = value
        case "disturbRate": disturbRate = value
        case "handoverRate": handoverRate = value
        case "tempNearRate": tempNearRate = value
        case "tempFarRate": tempFarRate = value
        case "vehicleRate": vehicleRate = value
        case "nightRate": nightRate = value
        case "winterRate": winterRate = value
        case "toolRate": toolRate = value
        case "utilityRate": utilityRate = value
        case "protectRate": protectRate = value
        case "socialRate": socialRate = value
        case "housingRate": housingRate = value
        case "accidentRate": accidentRate = value
        case "mgmtRate": mgmtRate = value
        case "profitRate": profitRate = value
        default: break
        }
    }
}

public struct VatRates: Equatable {
    public var jiaTax: Double?
    public var yiTax: Double?
    public var outputTax: Double?
    public var safetyVat: Double?
    public init(jiaTax: Double? = nil, yiTax: Double? = nil,
                outputTax: Double? = nil, safetyVat: Double? = nil) {
        self.jiaTax = jiaTax; self.yiTax = yiTax; self.outputTax = outputTax; self.safetyVat = safetyVat
    }
}

public struct Rates: Equatable {
    public var byProjectType: [String: NamedRates]?
    public var winterTable: [String: Double]
    public var vatRates: VatRates
    public init(byProjectType: [String: NamedRates]? = nil, winterTable: [String: Double] = [:],
                vatRates: VatRates = VatRates()) {
        self.byProjectType = byProjectType; self.winterTable = winterTable; self.vatRates = vatRates
    }
}

public struct DiscountRule: Equatable {
    public var discountRate: Double?
    public var noDiscountKeys: [String]?
    public var zeroAfterDiscountKeys: [String]?
    public init(discountRate: Double? = nil, noDiscountKeys: [String]? = nil,
                zeroAfterDiscountKeys: [String]? = nil) {
        self.discountRate = discountRate; self.noDiscountKeys = noDiscountKeys
        self.zeroAfterDiscountKeys = zeroAfterDiscountKeys
    }
}

public struct Table5Fee: Equatable {
    public var key: String
    public var name: String
    public var basis: String
    public var rate: Double?
    public var vatRate: Double?
    public var amount: Double?
    public var enabled: Bool?
    public var order: Double
    public var note: String
    public var children: [String]?
    public init(key: String, name: String, basis: String, rate: Double? = nil, vatRate: Double? = nil,
                amount: Double? = nil, enabled: Bool? = nil, order: Double = 0, note: String = "",
                children: [String]? = nil) {
        self.key = key; self.name = name; self.basis = basis; self.rate = rate; self.vatRate = vatRate
        self.amount = amount; self.enabled = enabled; self.order = order; self.note = note; self.children = children
    }
}

public struct DispatchParams: Equatable {
    public var priceTable: [[Double]]?
    public var peopleEquip: [[Double]]?
    public var peopleLine: [[Double]]?
    public var extraPer200km: Double?
    public var extraPeopleStep: Double?
    public init(priceTable: [[Double]]? = nil, peopleEquip: [[Double]]? = nil,
                peopleLine: [[Double]]? = nil, extraPer200km: Double? = nil,
                extraPeopleStep: Double? = nil) {
        self.priceTable = priceTable; self.peopleEquip = peopleEquip; self.peopleLine = peopleLine
        self.extraPer200km = extraPer200km; self.extraPeopleStep = extraPeopleStep
    }
}

/// calcProject 的 libs 输入（对应 JS calcProject(project, libs) 的 libs 形参）。
public struct Libs: Equatable {
    public var quotas: [Quota]
    public var materials: [Material]
    public var rules: [Rule]
    public var rates: Rates?
    public var winterTable: [String: Double]?
    public var rateGrid: [[Double?]]?
    public var discountRule: DiscountRule?
    public var table5Fees: [Table5Fee]?
    public var dispatch: DispatchParams?
    public var machinePrices: [MachinePrice]
    public var instrumentPrices: [InstrumentPrice]
    public var quotaMachines: [QuotaMachine]
    public var quotaInstruments: [QuotaInstrument]
    public init(quotas: [Quota] = [], materials: [Material] = [], rules: [Rule] = [],
                rates: Rates? = nil, winterTable: [String: Double]? = nil, rateGrid: [[Double?]]? = nil,
                discountRule: DiscountRule? = nil, table5Fees: [Table5Fee]? = nil,
                dispatch: DispatchParams? = nil, machinePrices: [MachinePrice] = [],
                instrumentPrices: [InstrumentPrice] = [], quotaMachines: [QuotaMachine] = [],
                quotaInstruments: [QuotaInstrument] = []) {
        self.quotas = quotas; self.materials = materials; self.rules = rules; self.rates = rates
        self.winterTable = winterTable; self.rateGrid = rateGrid; self.discountRule = discountRule
        self.table5Fees = table5Fees; self.dispatch = dispatch; self.machinePrices = machinePrices
        self.instrumentPrices = instrumentPrices; self.quotaMachines = quotaMachines
        self.quotaInstruments = quotaInstruments
    }
}

public struct CalcWarning: Equatable {
    public var code: String
    public var message: String
    public var rowIds: [String]?
    public init(code: String, message: String, rowIds: [String]? = nil) {
        self.code = code; self.message = message; self.rowIds = rowIds
    }
}

/// 表二（折前/折后）。以字典为底：applyDiscount 需像 JS 一样处理表二内的额外数值键
///（如某配置表二内含 safetyFee 行）；40 个具名字段以计算属性读写。
public struct Table2: Equatable {
    public var values: [String: Double] = [:]
    public init(values: [String: Double] = [:]) { self.values = values }
    private func read(_ key: String) -> Double { values[key] ?? 0 }
    private mutating func write(_ key: String, _ v: Double) { values[key] = v }

    public var techFee: Double { get { read("techFee") } set { write("techFee", newValue) } }
    public var laborFee: Double { get { read("laborFee") } set { write("laborFee", newValue) } }
    public var laborTotal: Double { get { read("laborTotal") } set { write("laborTotal", newValue) } }
    public var jiaMat: Double { get { read("jiaMat") } set { write("jiaMat", newValue) } }
    public var yiMat: Double { get { read("yiMat") } set { write("yiMat", newValue) } }
    public var mainMat: Double { get { read("mainMat") } set { write("mainMat", newValue) } }
    public var auxMat: Double { get { read("auxMat") } set { write("auxMat", newValue) } }
    public var matTotal: Double { get { read("matTotal") } set { write("matTotal", newValue) } }
    public var machineFee: Double { get { read("machineFee") } set { write("machineFee", newValue) } }
    public var instrumentFee: Double { get { read("instrumentFee") } set { write("instrumentFee", newValue) } }
    public var directFee: Double { get { read("directFee") } set { write("directFee", newValue) } }
    public var envFee: Double { get { read("envFee") } set { write("envFee", newValue) } }
    public var civilFee: Double { get { read("civilFee") } set { write("civilFee", newValue) } }
    public var carryFee: Double { get { read("carryFee") } set { write("carryFee", newValue) } }
    public var disturbFee: Double { get { read("disturbFee") } set { write("disturbFee", newValue) } }
    public var handoverFee: Double { get { read("handoverFee") } set { write("handoverFee", newValue) } }
    public var tempFee: Double { get { read("tempFee") } set { write("tempFee", newValue) } }
    public var vehicleFee: Double { get { read("vehicleFee") } set { write("vehicleFee", newValue) } }
    public var nightFee: Double { get { read("nightFee") } set { write("nightFee", newValue) } }
    public var winterFee: Double { get { read("winterFee") } set { write("winterFee", newValue) } }
    public var toolFee: Double { get { read("toolFee") } set { write("toolFee", newValue) } }
    public var utilityFee: Double { get { read("utilityFee") } set { write("utilityFee", newValue) } }
    public var specialFee: Double { get { read("specialFee") } set { write("specialFee", newValue) } }
    public var protectFee: Double { get { read("protectFee") } set { write("protectFee", newValue) } }
    public var earthFee: Double { get { read("earthFee") } set { write("earthFee", newValue) } }
    public var dispatchFee: Double { get { read("dispatchFee") } set { write("dispatchFee", newValue) } }
    public var bigMachineFee: Double { get { read("bigMachineFee") } set { write("bigMachineFee", newValue) } }
    public var measureFee: Double { get { read("measureFee") } set { write("measureFee", newValue) } }
    public var directTotal: Double { get { read("directTotal") } set { write("directTotal", newValue) } }
    public var sewageFee: Double { get { read("sewageFee") } set { write("sewageFee", newValue) } }
    public var socialFee: Double { get { read("socialFee") } set { write("socialFee", newValue) } }
    public var housingFee: Double { get { read("housingFee") } set { write("housingFee", newValue) } }
    public var accidentFee: Double { get { read("accidentFee") } set { write("accidentFee", newValue) } }
    public var regFee: Double { get { read("regFee") } set { write("regFee", newValue) } }
    public var mgmtFee: Double { get { read("mgmtFee") } set { write("mgmtFee", newValue) } }
    public var indirectTotal: Double { get { read("indirectTotal") } set { write("indirectTotal", newValue) } }
    public var profit: Double { get { read("profit") } set { write("profit", newValue) } }
    public var exclTax: Double { get { read("exclTax") } set { write("exclTax", newValue) } }
    public var outputTax: Double { get { read("outputTax") } set { write("outputTax", newValue) } }
    public var inclTax: Double { get { read("inclTax") } set { write("inclTax", newValue) } }
    public var dispatchUnit: Double { get { read("dispatchUnit") } set { write("dispatchUnit", newValue) } }
    public var dispatchPeople: Double { get { read("dispatchPeople") } set { write("dispatchPeople", newValue) } }
}

public struct Table3ARow: Equatable {
    public var code: String
    public var name: String
    public var unit: String
    public var qty: Double
    public var techUnit: Double
    public var laborUnit: Double
    public var tech: Double
    public var labor: Double
    public init(code: String, name: String, unit: String, qty: Double,
                techUnit: Double, laborUnit: Double, tech: Double, labor: Double) {
        self.code = code; self.name = name; self.unit = unit; self.qty = qty
        self.techUnit = techUnit; self.laborUnit = laborUnit; self.tech = tech; self.labor = labor
    }
}

public struct Table3EquipRow: Equatable {
    public var quota: String
    public var quotaName: String
    public var unit: String
    public var qty: Double
    public var equipName: String
    public var equipUnit: String
    public var consumption: Double
    public var price: Double
    public var sessions: Double
    public var amount: Double
    public init(quota: String, quotaName: String, unit: String, qty: Double, equipName: String,
                equipUnit: String, consumption: Double, price: Double, sessions: Double, amount: Double) {
        self.quota = quota; self.quotaName = quotaName; self.unit = unit; self.qty = qty
        self.equipName = equipName; self.equipUnit = equipUnit; self.consumption = consumption
        self.price = price; self.sessions = sessions; self.amount = amount
    }
}

public struct Table3EquipResult: Equatable {
    public var rows: [Table3EquipRow]
    public var total: Double
    public init(rows: [Table3EquipRow] = [], total: Double = 0) { self.rows = rows; self.total = total }
}

public struct Table4Row: Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var name: String
    public var spec: String
    public var unit: String
    public var qty: Double
    public var autoQty: Double
    public var delta: Double
    public var priceExcl: Double
    public var priceVat: Double
    public var priceIncl: Double
    public var amtExcl: Double
    public var amtVat: Double
    public var amtIncl: Double
    public var unmatched: Bool
    public init(key: String, name: String, spec: String, unit: String, qty: Double, autoQty: Double,
                delta: Double, priceExcl: Double, priceVat: Double, priceIncl: Double,
                amtExcl: Double, amtVat: Double, amtIncl: Double, unmatched: Bool) {
        self.key = key; self.name = name; self.spec = spec; self.unit = unit; self.qty = qty
        self.autoQty = autoQty; self.delta = delta; self.priceExcl = priceExcl; self.priceVat = priceVat
        self.priceIncl = priceIncl; self.amtExcl = amtExcl; self.amtVat = amtVat; self.amtIncl = amtIncl
        self.unmatched = unmatched
    }
}

public struct Table4Result: Equatable {
    public var rows: [Table4Row]
    public var totalExcl: Double
    public var totalVat: Double
    public var totalIncl: Double
    public init(rows: [Table4Row] = [], totalExcl: Double = 0, totalVat: Double = 0, totalIncl: Double = 0) {
        self.rows = rows; self.totalExcl = totalExcl; self.totalVat = totalVat; self.totalIncl = totalIncl
    }
}

public struct Table5Row: Equatable {
    public var key: String
    public var name: String
    public var basis: String
    public var rate: Double?
    public var vatRate: Double
    public var order: Double
    public var note: String
    public var enabled: Bool
    public var excl: Double
    public var vat: Double
    public var incl: Double
    public var amount: Double
    public init(key: String, name: String, basis: String, rate: Double?, vatRate: Double,
                order: Double, note: String, enabled: Bool, excl: Double, vat: Double,
                incl: Double, amount: Double) {
        self.key = key; self.name = name; self.basis = basis; self.rate = rate; self.vatRate = vatRate
        self.order = order; self.note = note; self.enabled = enabled; self.excl = excl; self.vat = vat
        self.incl = incl; self.amount = amount
    }
}

public struct Table5Result: Equatable {
    public var rows: [Table5Row]
    public var totalExcl: Double
    public var totalVat: Double
    public var totalIncl: Double
    public var mgmt2: Double
    public var mgmt2Vat: Double
    public var mgmt2Incl: Double
    public var surveyKm: Double
    public var surveyFee: Double
    public var surveyVat: Double
    public var designFee: Double
    public var designVat: Double
    public var designTotal: Double
    public var designTotalVat: Double
    public var safetyFee: Double
    public var safetyVat: Double
    public var safetyIncl: Double
    public var productionPrepFee: Double
    public var productionPrepVat: Double
    public var productionPrepIncl: Double
    public init(rows: [Table5Row] = [], totalExcl: Double = 0, totalVat: Double = 0, totalIncl: Double = 0,
                mgmt2: Double = 0, mgmt2Vat: Double = 0, mgmt2Incl: Double = 0, surveyKm: Double = 0,
                surveyFee: Double = 0, surveyVat: Double = 0, designFee: Double = 0, designVat: Double = 0,
                designTotal: Double = 0, designTotalVat: Double = 0, safetyFee: Double = 0,
                safetyVat: Double = 0, safetyIncl: Double = 0, productionPrepFee: Double = 0,
                productionPrepVat: Double = 0, productionPrepIncl: Double = 0) {
        self.rows = rows; self.totalExcl = totalExcl; self.totalVat = totalVat; self.totalIncl = totalIncl
        self.mgmt2 = mgmt2; self.mgmt2Vat = mgmt2Vat; self.mgmt2Incl = mgmt2Incl; self.surveyKm = surveyKm
        self.surveyFee = surveyFee; self.surveyVat = surveyVat; self.designFee = designFee
        self.designVat = designVat; self.designTotal = designTotal; self.designTotalVat = designTotalVat
        self.safetyFee = safetyFee; self.safetyVat = safetyVat; self.safetyIncl = safetyIncl
        self.productionPrepFee = productionPrepFee; self.productionPrepVat = productionPrepVat
        self.productionPrepIncl = productionPrepIncl
    }
}

public struct Table1Result: Equatable {
    public var beforeDiscount: Double
    public var afterDiscount: Double
    public var taxBefore: Double
    public var taxAfter: Double
    public var totalBefore: Double
    public var totalAfter: Double
    public var otherFee: Double
    public var otherVat: Double
    public var otherIncl: Double
    public var sumExcl: Double
    public var sumVat: Double
    public var sumIncl: Double
    public var equipFee: Double
    public var equipVat: Double
    public var equipIncl: Double
    public var grandExcl: Double
    public var grandVat: Double
    public var grandIncl: Double
    public init(beforeDiscount: Double = 0, afterDiscount: Double = 0, taxBefore: Double = 0,
                taxAfter: Double = 0, totalBefore: Double = 0, totalAfter: Double = 0,
                otherFee: Double = 0, otherVat: Double = 0, otherIncl: Double = 0,
                sumExcl: Double = 0, sumVat: Double = 0, sumIncl: Double = 0,
                equipFee: Double = 0, equipVat: Double = 0, equipIncl: Double = 0,
                grandExcl: Double = 0, grandVat: Double = 0, grandIncl: Double = 0) {
        self.beforeDiscount = beforeDiscount; self.afterDiscount = afterDiscount
        self.taxBefore = taxBefore; self.taxAfter = taxAfter; self.totalBefore = totalBefore
        self.totalAfter = totalAfter; self.otherFee = otherFee; self.otherVat = otherVat
        self.otherIncl = otherIncl; self.sumExcl = sumExcl; self.sumVat = sumVat; self.sumIncl = sumIncl
        self.equipFee = equipFee; self.equipVat = equipVat; self.equipIncl = equipIncl
        self.grandExcl = grandExcl; self.grandVat = grandVat; self.grandIncl = grandIncl
    }
}

public struct SummaryResult: Equatable {
    public var constructionExcl: Double
    public var constructionVat: Double
    public var constructionIncl: Double
    public var other: Double
    public var otherVat: Double
    public var otherIncl: Double
    public var totalExcl: Double
    public var totalVat: Double
    public var totalIncl: Double
    public init(constructionExcl: Double = 0, constructionVat: Double = 0, constructionIncl: Double = 0,
                other: Double = 0, otherVat: Double = 0, otherIncl: Double = 0,
                totalExcl: Double = 0, totalVat: Double = 0, totalIncl: Double = 0) {
        self.constructionExcl = constructionExcl; self.constructionVat = constructionVat
        self.constructionIncl = constructionIncl; self.other = other; self.otherVat = otherVat
        self.otherIncl = otherIncl; self.totalExcl = totalExcl; self.totalVat = totalVat
        self.totalIncl = totalIncl
    }
}

public struct EffectiveDiscountRule: Equatable {
    public var discountRate: Double
    public var noDiscountKeys: [String]
    public var zeroAfterDiscountKeys: [String]
    public init(discountRate: Double, noDiscountKeys: [String], zeroAfterDiscountKeys: [String]) {
        self.discountRate = discountRate; self.noDiscountKeys = noDiscountKeys
        self.zeroAfterDiscountKeys = zeroAfterDiscountKeys
    }
}

public struct CalcResult: Equatable {
    public var info: ProjectInfo
    public var rate: ResolvedRates
    public var techSub: Double
    public var laborSub: Double
    public var adjRate: Double
    public var techDays: Double
    public var laborDays: Double
    public var table3A: [Table3ARow]
    public var table3B: Table3EquipResult
    public var table3C: Table3EquipResult
    public var table4A: Table4Result
    public var table4B: Table4Result
    public var table4Equip: Table4Result
    public var table2Before: Table2
    public var table2After: Table2
    /// JS 返回的 table2 即折后表（table2After 的别名）。
    public var table2: Table2 { table2After }
    public var table5: Table5Result
    public var table1: Table1Result
    public var summary: SummaryResult
    public var warnings: [CalcWarning]
    public var discount: Double
    public var discountRule: EffectiveDiscountRule
    public var surveyKm: Double
    public var surveyRaw: Double
}
