import Foundation

/// 引擎类型的 Codable 实现（容错解码，与 Electron JSON 键名一一对应）。
/// 引擎文件本身不含 Codable，避免 Engine/Logic 依赖编解码细节；实现集中在此。

// MARK: - VatRates

extension VatRates: Codable {
    enum CodingKeys: String, CodingKey { case jiaTax, yiTax, outputTax, safetyVat }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jiaTax = c.decodeLenientDouble(forKey: .jiaTax)
        yiTax = c.decodeLenientDouble(forKey: .yiTax)
        outputTax = c.decodeLenientDouble(forKey: .outputTax)
        safetyVat = c.decodeLenientDouble(forKey: .safetyVat)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(jiaTax, forKey: .jiaTax)
        try c.encodeIfPresent(yiTax, forKey: .yiTax)
        try c.encodeIfPresent(outputTax, forKey: .outputTax)
        try c.encodeIfPresent(safetyVat, forKey: .safetyVat)
    }
}

// MARK: - Table5Fee

extension Table5Fee: Codable {
    enum CodingKeys: String, CodingKey {
        case key, name, basis, rate, vatRate, amount, enabled, order, note, children
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.decodeLenientString(forKey: .key)
        name = c.decodeLenientString(forKey: .name)
        basis = c.decodeLenientString(forKey: .basis, default: "manual")
        rate = c.decodeLenientDouble(forKey: .rate)
        vatRate = c.decodeLenientDouble(forKey: .vatRate)
        amount = c.decodeLenientDouble(forKey: .amount)
        enabled = c.decodeLenientBoolOptional(forKey: .enabled)
        order = c.decodeLenientDouble(forKey: .order, default: 0)
        note = c.decodeLenientString(forKey: .note)
        children = try? c.decodeIfPresent([String].self, forKey: .children)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(name, forKey: .name)
        try c.encode(basis, forKey: .basis)
        try c.encodeIfPresent(rate, forKey: .rate)
        try c.encodeIfPresent(vatRate, forKey: .vatRate)
        try c.encodeIfPresent(amount, forKey: .amount)
        try c.encodeIfPresent(enabled, forKey: .enabled)
        try c.encode(order, forKey: .order)
        try c.encode(note, forKey: .note)
        try c.encodeIfPresent(children, forKey: .children)
    }
}

// MARK: - DispatchParams

extension DispatchParams: Codable {
    enum CodingKeys: String, CodingKey {
        case priceTable, peopleEquip, peopleLine, extraPer200km, extraPeopleStep
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        priceTable = try? c.decodeIfPresent([[Double]].self, forKey: .priceTable)
        peopleEquip = try? c.decodeIfPresent([[Double]].self, forKey: .peopleEquip)
        peopleLine = try? c.decodeIfPresent([[Double]].self, forKey: .peopleLine)
        extraPer200km = c.decodeLenientDouble(forKey: .extraPer200km)
        extraPeopleStep = c.decodeLenientDouble(forKey: .extraPeopleStep)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(priceTable, forKey: .priceTable)
        try c.encodeIfPresent(peopleEquip, forKey: .peopleEquip)
        try c.encodeIfPresent(peopleLine, forKey: .peopleLine)
        try c.encodeIfPresent(extraPer200km, forKey: .extraPer200km)
        try c.encodeIfPresent(extraPeopleStep, forKey: .extraPeopleStep)
    }
}

// MARK: - ProjectInfo（中文键，与 Electron `info` 一一对应）

extension ProjectInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case 建设单位, 建设项目名称, 单项工程名称, 合同编号, 工程类型, 区县, 编制日期,
             施工折扣, 段落起点, 段落终点, 监理单位, 表格编号, 单段工程名称, 项目编号,
             施工距离, 施工实际里程, 施工调遣分类, 施工现场海拔, 冬雨季施工费,
             甲供增值税, 乙供增值税, 工程负责人, 审核, 编制, 施工单位, 设计单位
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        建设单位 = c.decodeLenientString(forKey: .建设单位)
        建设项目名称 = c.decodeLenientString(forKey: .建设项目名称)
        单项工程名称 = c.decodeLenientString(forKey: .单项工程名称)
        合同编号 = c.decodeLenientString(forKey: .合同编号)
        工程类型 = c.decodeLenientString(forKey: .工程类型, default: "通信线路工程")
        区县 = c.decodeLenientString(forKey: .区县)
        编制日期 = c.decodeLenientString(forKey: .编制日期)
        施工折扣 = c.decodeLenientDouble(forKey: .施工折扣)
        段落起点 = c.decodeLenientString(forKey: .段落起点)
        段落终点 = c.decodeLenientString(forKey: .段落终点)
        监理单位 = c.decodeLenientString(forKey: .监理单位)
        表格编号 = c.decodeLenientString(forKey: .表格编号, default: "YD-")
        单段工程名称 = c.decodeLenientString(forKey: .单段工程名称)
        项目编号 = c.decodeLenientString(forKey: .项目编号)
        施工距离 = c.decodeLenientString(forKey: .施工距离, default: "35KM以内")
        施工实际里程 = c.decodeLenientDouble(forKey: .施工实际里程)
        施工调遣分类 = c.decodeLenientString(forKey: .施工调遣分类, default: "施工队伍调遣人数(线路、管道）")
        施工现场海拔 = c.decodeLenientDouble(forKey: .施工现场海拔, default: 0)
        冬雨季施工费 = c.decodeLenientString(forKey: .冬雨季施工费, default: "Ⅲ类地区")
        甲供增值税 = c.decodeLenientDouble(forKey: .甲供增值税)
        乙供增值税 = c.decodeLenientDouble(forKey: .乙供增值税)
        工程负责人 = c.decodeLenientString(forKey: .工程负责人)
        审核 = c.decodeLenientString(forKey: .审核)
        编制 = c.decodeLenientString(forKey: .编制)
        施工单位 = c.decodeLenientStringOptional(forKey: .施工单位)
        设计单位 = c.decodeLenientStringOptional(forKey: .设计单位)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(建设单位, forKey: .建设单位)
        try c.encode(建设项目名称, forKey: .建设项目名称)
        try c.encode(单项工程名称, forKey: .单项工程名称)
        try c.encode(合同编号, forKey: .合同编号)
        try c.encode(工程类型, forKey: .工程类型)
        try c.encode(区县, forKey: .区县)
        try c.encode(编制日期, forKey: .编制日期)
        try c.encodeIfPresent(施工折扣, forKey: .施工折扣)
        try c.encode(段落起点, forKey: .段落起点)
        try c.encode(段落终点, forKey: .段落终点)
        try c.encode(监理单位, forKey: .监理单位)
        try c.encode(表格编号, forKey: .表格编号)
        try c.encode(单段工程名称, forKey: .单段工程名称)
        try c.encode(项目编号, forKey: .项目编号)
        try c.encode(施工距离, forKey: .施工距离)
        try c.encodeIfPresent(施工实际里程, forKey: .施工实际里程)
        try c.encode(施工调遣分类, forKey: .施工调遣分类)
        try c.encode(施工现场海拔, forKey: .施工现场海拔)
        try c.encode(冬雨季施工费, forKey: .冬雨季施工费)
        try c.encodeIfPresent(甲供增值税, forKey: .甲供增值税)
        try c.encodeIfPresent(乙供增值税, forKey: .乙供增值税)
        try c.encode(工程负责人, forKey: .工程负责人)
        try c.encode(审核, forKey: .审核)
        try c.encode(编制, forKey: .编制)
        try c.encodeIfPresent(施工单位, forKey: .施工单位)
        try c.encodeIfPresent(设计单位, forKey: .设计单位)
    }
}

// MARK: - QuantityRow / overrides

extension QuantityRow: Codable {
    enum CodingKeys: String, CodingKey { case id, quota, variant, unit, qty, coef, tech, labor }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientStringOptional(forKey: .id)
        quota = c.decodeLenientString(forKey: .quota)
        variant = c.decodeLenientStringOptional(forKey: .variant)
        unit = c.decodeLenientStringOptional(forKey: .unit)
        qty = c.decodeLenientDouble(forKey: .qty)
        coef = c.decodeLenientDouble(forKey: .coef)
        // v2.6.0 工日快照：旧文件无此二键 → nil（回落定额库值）。
        tech = c.decodeLenientDouble(forKey: .tech)
        labor = c.decodeLenientDouble(forKey: .labor)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encode(quota, forKey: .quota)
        try c.encodeIfPresent(variant, forKey: .variant)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encodeIfPresent(qty, forKey: .qty)
        try c.encodeIfPresent(coef, forKey: .coef)
        try c.encodeIfPresent(tech, forKey: .tech)
        try c.encodeIfPresent(labor, forKey: .labor)
    }
}

extension MaterialRowEdit: Codable {
    enum CodingKeys: String, CodingKey {
        case key, code, name, spec, unit, supply, category, remark, deleted
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.decodeLenientString(forKey: .key)
        code = c.decodeLenientStringOptional(forKey: .code)
        name = c.decodeLenientStringOptional(forKey: .name)
        spec = c.decodeLenientStringOptional(forKey: .spec)
        unit = c.decodeLenientStringOptional(forKey: .unit)
        supply = c.decodeLenientStringOptional(forKey: .supply)
        category = c.decodeLenientStringOptional(forKey: .category)
        remark = c.decodeLenientStringOptional(forKey: .remark)
        deleted = c.decodeLenientBool(forKey: .deleted, default: false)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encodeIfPresent(code, forKey: .code)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(spec, forKey: .spec)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encodeIfPresent(supply, forKey: .supply)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(remark, forKey: .remark)
        try c.encode(deleted, forKey: .deleted)
    }
}

extension ManualMaterialRow: Codable {
    enum CodingKeys: String, CodingKey {
        case id, code, name, spec, unit, qty, priceExcl, supply, category, remark
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientString(forKey: .id)
        code = c.decodeLenientString(forKey: .code)
        name = c.decodeLenientString(forKey: .name)
        spec = c.decodeLenientString(forKey: .spec)
        unit = c.decodeLenientString(forKey: .unit)
        qty = c.decodeLenientDouble(forKey: .qty, default: 0)
        priceExcl = c.decodeLenientDouble(forKey: .priceExcl, default: 0)
        supply = c.decodeLenientString(forKey: .supply, default: "甲供")
        category = c.decodeLenientString(forKey: .category)
        remark = c.decodeLenientString(forKey: .remark)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(code, forKey: .code)
        try c.encode(name, forKey: .name)
        try c.encode(spec, forKey: .spec)
        try c.encode(unit, forKey: .unit)
        try c.encode(qty, forKey: .qty)
        try c.encode(priceExcl, forKey: .priceExcl)
        try c.encode(supply, forKey: .supply)
        try c.encode(category, forKey: .category)
        try c.encode(remark, forKey: .remark)
    }
}

extension MaterialAdjust: Codable {
    enum CodingKeys: String, CodingKey { case key, delta }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.decodeLenientString(forKey: .key)
        delta = c.decodeLenientDouble(forKey: .delta, default: 0)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(delta, forKey: .delta)
    }
}

extension MaterialPriceOverride: Codable {
    enum CodingKeys: String, CodingKey { case key, priceExcl }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.decodeLenientString(forKey: .key)
        priceExcl = c.decodeLenientDouble(forKey: .priceExcl, default: 0)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encode(priceExcl, forKey: .priceExcl)
    }
}

extension RuleOverride: Codable {
    enum CodingKeys: String, CodingKey { case ruleId, enabled }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ruleId = c.decodeLenientString(forKey: .ruleId)
        enabled = c.decodeLenientBool(forKey: .enabled, default: false)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ruleId, forKey: .ruleId)
        try c.encode(enabled, forKey: .enabled)
    }
}

extension Table5Override: Codable {
    enum CodingKeys: String, CodingKey { case key, enabled, amount }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.decodeLenientString(forKey: .key)
        enabled = c.decodeLenientBoolOptional(forKey: .enabled)
        amount = c.decodeLenientDouble(forKey: .amount)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(key, forKey: .key)
        try c.encodeIfPresent(enabled, forKey: .enabled)
        try c.encodeIfPresent(amount, forKey: .amount)
    }
}

extension RateOverrides: Codable {
    enum CodingKeys: String, CodingKey { case discount, jiaTax, yiTax, outputTax, safetyVat, taxRate }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        discount = c.decodeLenientDouble(forKey: .discount)
        jiaTax = c.decodeLenientDouble(forKey: .jiaTax)
        yiTax = c.decodeLenientDouble(forKey: .yiTax)
        outputTax = c.decodeLenientDouble(forKey: .outputTax)
        safetyVat = c.decodeLenientDouble(forKey: .safetyVat)
        taxRate = c.decodeLenientDouble(forKey: .taxRate)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(discount, forKey: .discount)
        try c.encodeIfPresent(jiaTax, forKey: .jiaTax)
        try c.encodeIfPresent(yiTax, forKey: .yiTax)
        try c.encodeIfPresent(outputTax, forKey: .outputTax)
        try c.encodeIfPresent(safetyVat, forKey: .safetyVat)
        try c.encodeIfPresent(taxRate, forKey: .taxRate)
    }
}
