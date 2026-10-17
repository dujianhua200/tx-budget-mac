import Foundation
/// 费率模型（v2，纯函数，无依赖）。对照 src/engine/rates.mjs。
/// 具名字段替代 v1 rateGrid 魔法下标；PROJECT_TYPES 顺序与 calc.mjs 一致。

public let projectTypes = [
    "无线通信设备安装工程",
    "通信电源设备安装工程",
    "有线通信设备安装工程",
    "通信线路工程",
    "通信管道工程",
]

public struct RateFieldDef: Equatable {
    public var key: String
    public var name: String
    public var unit: String
    public var gridN: Int
    public init(key: String, name: String, unit: String, gridN: Int) {
        self.key = key; self.name = name; self.unit = unit; self.gridN = gridN
    }
}

/// 具名费率字段定义。gridN = v1 RATE_ITEMS 的 HLOOKUP 行号 n（rateGrid 行下标 = n + 1）。
/// taxRate（n=26）不在 defs 中：增值税率由 rates.vatRates 承载。
public let rateFieldDefs: [RateFieldDef] = [
    RateFieldDef(key: "techPrice", name: "技工费", unit: "元/工日", gridN: 3),
    RateFieldDef(key: "laborPrice", name: "普工费", unit: "元/工日", gridN: 4),
    RateFieldDef(key: "auxRate", name: "辅材费率", unit: "费率", gridN: 5),
    RateFieldDef(key: "envRate", name: "环境保护费费", unit: "费率", gridN: 6),
    RateFieldDef(key: "civilRate", name: "文明施工费", unit: "费率", gridN: 7),
    RateFieldDef(key: "carryRate", name: "工地器材搬运费", unit: "费率", gridN: 8),
    RateFieldDef(key: "disturbRate", name: "工程干扰费", unit: "费率", gridN: 9),
    RateFieldDef(key: "handoverRate", name: "工程点交、场地清理费", unit: "费率", gridN: 10),
    RateFieldDef(key: "tempNearRate", name: "临时设施费(35km以内)", unit: "费率", gridN: 11),
    RateFieldDef(key: "tempFarRate", name: "临时设施费(35km以上)", unit: "费率", gridN: 12),
    RateFieldDef(key: "vehicleRate", name: "工程车辆使用费", unit: "费率", gridN: 13),
    RateFieldDef(key: "nightRate", name: "夜间施工增加费", unit: "费率", gridN: 14),
    RateFieldDef(key: "winterRate", name: "冬雨季施工增加费", unit: "费率（null=按地区查表）", gridN: 15),
    RateFieldDef(key: "toolRate", name: "生产工具用具使用费", unit: "费率", gridN: 16),
    RateFieldDef(key: "utilityRate", name: "施工用水电蒸汽费", unit: "费率", gridN: 17),
    RateFieldDef(key: "protectRate", name: "已完成工程及设备保护费", unit: "费率", gridN: 19),
    RateFieldDef(key: "socialRate", name: "社会保障金", unit: "费率", gridN: 21),
    RateFieldDef(key: "housingRate", name: "住房公积金", unit: "费率", gridN: 22),
    RateFieldDef(key: "accidentRate", name: "危险作业意外伤害保险费", unit: "费率", gridN: 23),
    RateFieldDef(key: "mgmtRate", name: "企业管理费", unit: "费率", gridN: 24),
    RateFieldDef(key: "profitRate", name: "利润率", unit: "费率", gridN: 25),
]

/// HLOOKUP 行号 n -> 具名字段 key。
public let rateGridNToKey: [Int: String] = Dictionary(
    uniqueKeysWithValues: rateFieldDefs.map { ($0.gridN, $0.key) })

/// v1 rateGrid -> 具名费率 byProjectType。
/// 冬雨季行（gridN=15）在 rateGrid 中恒为 null，迁移为 winterRate: nil（= 按 winterTable 查表）；
/// 施工用水电蒸汽费（gridN=17）null 迁移为 0。
public func rateGridToRates(_ rateGrid: [[Double?]]?) -> [String: NamedRates] {
    var byProjectType: [String: NamedRates] = [:]
    for col in 0..<projectTypes.count {
        var row = NamedRates()
        for def in rateFieldDefs {
            if def.key == "winterRate" {
                row.setValue(nil, forKey: "winterRate")
                continue
            }
            var v: Double? = nil
            if let grid = rateGrid, def.gridN + 1 < grid.count {
                let gridRow = grid[def.gridN + 1]
                if 6 + col < gridRow.count {
                    v = gridRow[6 + col]
                }
            }
            row.setValue(v ?? 0, forKey: def.key)
        }
        byProjectType[projectTypes[col]] = row
    }
    return byProjectType
}

/// 具名费率读取：缺失返回 nil（与 0 区分；winterRate 的 nil 另有“查表”语义）。
public func rateForNamed(_ rates: Rates?, _ projectType: String, _ key: String) -> Double? {
    guard let rates, let named = rates.byProjectType?[projectType] else { return nil }
    return named.value(forKey: key)
}

/// 冬雨季费率：该工程类型的 winterRate 非 nil 则直接用它；nil 则按地区查 winterTable。
/// winterRate == 0 是显式“费率为 0”，与 nil（查表）不同。
public func winterRateForNamed(_ rates: Rates?, _ projectType: String, _ region: String) -> Double {
    if let w = rates?.byProjectType?[projectType]?.winterRate {
        return w
    }
    if let table = rates?.winterTable, let v = table[region] {
        return v
    }
    return 0
}

public struct ResolvedRateInputs: Equatable {
    public var discount: Double
    public var jiaTax: Double
    public var yiTax: Double
    public var outputTax: Double
    public var safetyVat: Double
    public init(discount: Double, jiaTax: Double, yiTax: Double, outputTax: Double, safetyVat: Double) {
        self.discount = discount; self.jiaTax = jiaTax; self.yiTax = yiTax
        self.outputTax = outputTax; self.safetyVat = safetyVat
    }
}

/// 解析具名费率。对照 calc.mjs 的 resolveNamedRates。
/// - returns: rate 含全部具名字段 + winterRate（生效值）；warnings 含缺失/未知类型告警。
public func resolveNamedRates(libs: Libs, projectType: String, region: String) -> (rate: ResolvedRates, warnings: [CalcWarning]) {
    var warnings: [CalcWarning] = []
    var rate = ResolvedRates()
    guard projectTypes.contains(projectType) else {
        warnings.append(CalcWarning(code: "unknownProjectType",
                                    message: "未知工程类型“\(projectType)”，费率按 0 计算"))
        return (rate, warnings)
    }

    let named: NamedRates
    let winterTable: [String: Double]
    let source: String
    if let byType = libs.rates?.byProjectType {
        named = byType[projectType] ?? NamedRates()
        winterTable = libs.rates?.winterTable ?? [:]
        source = "named"
    } else if let grid = libs.rateGrid {
        named = rateGridToRates(grid)[projectType] ?? NamedRates()
        winterTable = libs.winterTable ?? [:]
        source = "grid"
    } else {
        warnings.append(CalcWarning(code: "missingRate",
                                    message: "未提供费率（既无 rates 也无 rateGrid），费率按 0 计算"))
        return (rate, warnings)
    }

    for def in rateFieldDefs where def.key != "winterRate" {
        if let v = named.value(forKey: def.key) {
            rate.setValue(v, forKey: def.key)
        } else {
            // rateGrid 转换路径：nil 已转为 0，不告警（沿用 v1 静默行为）；具名路径缺失字段才告警。
            if source == "named" {
                warnings.append(CalcWarning(code: "missingRate:\(def.key)",
                                            message: "费率缺失：\(projectType) / \(def.name)，按 0 计算"))
            }
            rate.setValue(0, forKey: def.key)
        }
    }
    // 冬雨季：具名 winterRate 非 nil 直接用（0 是显式 0）；nil 则按地区查 winterTable。
    if let w = named.winterRate {
        rate.winterRate = w
    } else if let v = winterTable[region] {
        rate.winterRate = v
    } else {
        rate.winterRate = 0
    }
    if named.winterRate == nil, winterTable[region] == nil {
        warnings.append(CalcWarning(code: "missingRate:winterTable",
                                    message: "冬雨季费率缺失：地区“\(region)”不在 winterTable 中，按 0 计算"))
    }
    return (rate, warnings)
}

/// 取值优先级（§2.4）：工程 rateOverrides（非 nil）> 工程 info（合并前原始值）> 配置方案 rates/discountRule > 兜底。
/// 注意：project.info 必须传合并前原始值——JS 的 resolveRates 读的是 project.info 本身，
/// 而非 DEFAULT_INFO 合并后的 info（info 缺施工折扣时应落到配置方案折扣率，而非默认值 1）。
public func resolveRates(rates: Rates?, discountRule: DiscountRule?, project: Project) -> ResolvedRateInputs {
    let info = project.info
    let ro = project.rateOverrides ?? RateOverrides()
    let vat = rates?.vatRates ?? VatRates()
    func pick(_ roVal: Double?, _ infoVal: Double?, _ profileVal: Double?, _ fallback: Double) -> Double {
        roVal ?? infoVal ?? profileVal ?? fallback
    }
    return ResolvedRateInputs(
        discount: pick(ro.discount, info.施工折扣, discountRule?.discountRate, 1),
        jiaTax: pick(ro.jiaTax, info.甲供增值税, vat.jiaTax, 0.13),
        yiTax: pick(ro.yiTax ?? ro.taxRate, info.乙供增值税, vat.yiTax, 0.09),
        outputTax: pick(ro.outputTax ?? ro.taxRate, info.乙供增值税, vat.outputTax ?? vat.yiTax, 0.09),
        safetyVat: pick(ro.safetyVat, nil, vat.safetyVat, 0)
    )
}
