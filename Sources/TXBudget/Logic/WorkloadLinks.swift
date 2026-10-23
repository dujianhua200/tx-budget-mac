import Foundation

/// 工作量底部关联区的数据组装与写回（v2.4.0，docs/v2.4-workload-design.md §3）。
///
/// “实际生效”判定与引擎 `calcProject` 逐条同口径（引擎一字不改，等价性由
/// WorkloadLinksTests 的对照测试钉死）：
/// - 参与行：定额在库中、数量非 nil 且 > 0 且非 NaN、系数（nil 按 1）> 0 且非 NaN。
/// - 机械/仪表：本行基数 = 数量 × 系数（参与时），台班贡献 = 基数 × 映射消耗量；
///   单价按 mcode 查价目库（同码后行覆盖先行），无码/无价按 0。
/// - 主材·通用：基数 = 参与行原始数量（不乘系数）；变体：variant 精确相等（nil 按 ""）；
///   变体*：引擎单独遍历全部行——定额同、数量 ≠ 0 非 NaN、variant 前缀命中即计（不查有效性）；
///   备选：variant 精确相等且规则 id 在 project.ruleOverrides 启用时才生效。
/// - 主材单价 = 材料库价（名称+规格命中，后行覆盖先行，与引擎 matByKey 一致）；
///   供货分组：材料库 supply 非空优先，否则规则 supply（与引擎 buildMatTable 一致）。
/// - appliesTo（v2.4.1）：与引擎共用 `ruleAppliesToProject` 闸门（序号取
///   project.projectOrdinal，由 calcFor / 面板按同一 projectOrdinal() 注入）；
///   被挡规则仍列出、合计按 0、灰显给原因（理由见 docs/v2.4.1-appliesto-design.md）。

// MARK: - 行状态

public enum WorkloadRowState: Equatable {
    /// 参与计算。
    case active
    /// 定额编号不在库中（孤儿行）：不参与计算，无生效关联。
    case orphan
    /// 在库中但本行不参与计算（数量为 0/未填、数量为负、系数无效），关联合计按 0 计。
    case inactive(reason: String)
}

/// 本行参与判定（引擎工程量累加循环的逐行口径）。
public func workloadRowState(row: QuantityRow, libraries: LibrarySet) -> WorkloadRowState {
    guard libraries.quotas.contains(where: { $0.code == row.quota }) else { return .orphan }
    guard let qty = row.qty, !qty.isNaN else { return .inactive(reason: "数量未填") }
    if qty < 0 { return .inactive(reason: "数量为负，无效行") }
    if qty == 0 { return .inactive(reason: "数量为 0，不参与计算") }
    let coef = row.coef ?? 1
    if !(coef > 0) { return .inactive(reason: "系数无效，不参与计算") }
    return .active
}

// MARK: - 关联条目（面板组装结果）

public struct EffectiveMaterialLink: Equatable {
    /// libraries.rules 下标（写回定位）。
    public var ruleIndex: Int
    public var rule: RuleRow
    /// 本行基数（按 kind 语义，见文件头）。
    public var basisQty: Double
    /// 本行贡献的自动数量 = 基数 × 消耗量（不含工程级手动调整）。
    public var totalQty: Double
    /// 是否实际生效（备选未启用 / 适用工程不含本工程 = false，合计按 0 计入表四——
    /// totalQty 已按 0 给出基数时为 0；注意未生效时 basisQty 亦为 0，isEffective 仅作展示标记）。
    public var isEffective: Bool
    /// 未生效原因（如“备选未启用”/“适用工程为「1,3」，本工程序号 2，未生效”）；生效时为 nil。
    public var inactiveReason: String?
    /// 材料库命中行下标（libraries.materials）；未建档为 nil。
    public var materialIndex: Int?
    /// 材料库价（未建档 = 0）。
    public var priceExcl: Double
    /// 合价 = totalQty × 材料库价（工程级覆盖价不影响面板口径，见设计文档）。
    public var amount: Double
    /// 展示单位：材料库单位优先，否则规则 unit。
    public var unit: String
    /// 表四分组口径：材料库 supply 非空优先，否则规则 supply。
    public var effectiveSupply: String
}

public struct EffectiveEquipLink: Equatable {
    /// libraries.quotaMachines / quotaInstruments 下标（写回定位）。
    public var linkIndex: Int
    public var mcode: String
    public var mname: String
    public var unit: String
    /// 映射消耗量（台班/单位工程量）。
    public var consumption: Double
    /// 本行加权工程量 = 数量 × 系数（参与时；否则 0）。
    public var basisQty: Double
    /// 本行台班贡献 = 基数 × 消耗量。
    public var totalQty: Double
    /// 价目库单价；无码或码不在价目库时为 nil（引擎按 0 计价）。
    public var price: Double?
    /// 合价 = totalQty × (price ?? 0)。
    public var amount: Double
}

public struct WorkloadRowLinks: Equatable {
    public var state: WorkloadRowState
    public var materials: [EffectiveMaterialLink]
    public var machines: [EffectiveEquipLink]
    public var instruments: [EffectiveEquipLink]
}

// MARK: - 组装（与引擎同口径）

/// 某条工程量行在当前工程下实际生效的关联（面板数据源）。
/// project 提供 ruleOverrides（备选启用判定）；libraries 为工程所属方案的库。
public func effectiveLinks(row: QuantityRow, project: Project, libraries: LibrarySet) -> WorkloadRowLinks {
    let state = workloadRowState(row: row, libraries: libraries)
    guard state != .orphan else {
        return WorkloadRowLinks(state: state, materials: [], machines: [], instruments: [])
    }
    let isActive = state == .active
    let qty = num(row.qty)
    let coef = row.coef ?? 1
    let rowVariant = row.variant ?? ""

    // 材料库索引（名称|规格 → 下标；后行覆盖先行，与引擎 matByKey 一致）。
    var matIndexByKey: [String: Int] = [:]
    for (i, m) in libraries.materials.enumerated() { matIndexByKey["\(m.name)|\(m.spec)"] = i }
    // 价目库（编码 → 价；后行覆盖先行，与引擎 price dict 一致）。
    var machinePrice: [String: Double] = [:]
    for p in libraries.machinePrices { machinePrice[p.code] = p.price }
    var instrumentPrice: [String: Double] = [:]
    for p in libraries.instrumentPrices { instrumentPrice[p.code] = p.price }
    var ruleEnabled: [String: Bool] = [:]
    for o in project.ruleOverrides { ruleEnabled[o.ruleId] = o.enabled }

    // ---- 主材 ----
    var materials: [EffectiveMaterialLink] = []
    for (i, rule) in libraries.rules.enumerated() where rule.quota == row.quota {
        var basis: Double? = nil
        var effective = true
        var reason: String? = nil
        switch rule.kind {
        case "通用":
            basis = isActive ? qty : 0
        case "变体":
            if rowVariant == rule.variant { basis = isActive ? qty : 0 }
        case "变体*":
            // 引擎口径：不查行有效性，仅数量 ≠ 0 非 NaN 且前缀命中（定额在库已由 state 保证非孤儿）。
            if let q = row.qty, q != 0, !q.isNaN, rowVariant.hasPrefix(rule.variant) { basis = q }
            else if rowVariant.hasPrefix(rule.variant) { basis = 0 }
        case "备选":
            if rowVariant == rule.variant {
                let enabled = !rule.id.isEmpty && ruleEnabled[rule.id] == true
                basis = enabled && isActive ? qty : 0
                effective = enabled
                if !enabled { reason = "备选未启用" }
            }
        default:
            basis = nil // 引擎对未知 kind 不计入（q 恒 0），面板同样不列。
        }
        guard let basisQty0 = basis else { continue }
        // v2.4.1：适用工程闸门（与引擎 Calc 同一纯函数）。与本行相关但被挡的规则
        // 仍列出：合计按 0、灰显、给原因；与备选未启用同时命中时优先报适用工程。
        var basisQty = basisQty0
        if !ruleAppliesToProject(rule.appliesTo, projectOrdinal: project.projectOrdinal) {
            basisQty = 0
            effective = false
            reason = ruleAppliesToInactiveReason(rule.appliesTo, projectOrdinal: project.projectOrdinal)
        }
        let matIdx = matIndexByKey["\(rule.material)|\(rule.spec)"]
        let mat = matIdx.map { libraries.materials[$0] }
        let price = num(mat?.priceExcl)
        let total = basisQty * num(rule.consumption)
        materials.append(EffectiveMaterialLink(
            ruleIndex: i, rule: rule, basisQty: basisQty, totalQty: total,
            isEffective: effective, inactiveReason: reason,
            materialIndex: matIdx, priceExcl: price, amount: total * price,
            unit: mat?.unit ?? rule.unit,
            effectiveSupply: (mat != nil && !mat!.supply.isEmpty) ? mat!.supply : rule.supply
        ))
    }

    // ---- 机械 / 仪表 ----
    func equipLink(index: Int, mcode: String, mname: String, unit: String,
                   consumption: Double, prices: [String: Double]) -> EffectiveEquipLink {
        let basis = isActive ? qty * coef : 0
        let total = basis * num(consumption)
        let price = mcode.isEmpty ? nil : prices[mcode]
        return EffectiveEquipLink(
            linkIndex: index, mcode: mcode, mname: mname, unit: unit,
            consumption: consumption, basisQty: basis, totalQty: total,
            price: price, amount: total * (price ?? 0))
    }
    var machines: [EffectiveEquipLink] = []
    for (i, m) in libraries.quotaMachines.enumerated() where m.quota == row.quota {
        machines.append(equipLink(index: i, mcode: m.mcode, mname: m.mname, unit: m.unit,
                                  consumption: m.qty, prices: machinePrice))
    }
    var instruments: [EffectiveEquipLink] = []
    for (i, m) in libraries.quotaInstruments.enumerated() where m.quota == row.quota {
        instruments.append(equipLink(index: i, mcode: m.mcode, mname: m.mname, unit: m.unit,
                                     consumption: m.qty, prices: instrumentPrice))
    }

    return WorkloadRowLinks(state: state, materials: materials, machines: machines, instruments: instruments)
}

// MARK: - 写回（纯函数，视图取到工程所属方案后调用；下标越界即无操作）

public func setRuleConsumption(in libraries: inout LibrarySet, ruleIndex: Int, _ value: Double) {
    guard libraries.rules.indices.contains(ruleIndex) else { return }
    libraries.rules[ruleIndex].consumption = value
}

public func removeRule(in libraries: inout LibrarySet, ruleIndex: Int) {
    guard libraries.rules.indices.contains(ruleIndex) else { return }
    libraries.rules.remove(at: ruleIndex)
}

public func setQuotaMachineQty(in libraries: inout LibrarySet, index: Int, _ value: Double) {
    guard libraries.quotaMachines.indices.contains(index) else { return }
    libraries.quotaMachines[index].qty = value
}

public func removeQuotaMachine(in libraries: inout LibrarySet, index: Int) {
    guard libraries.quotaMachines.indices.contains(index) else { return }
    libraries.quotaMachines.remove(at: index)
}

public func setQuotaInstrumentQty(in libraries: inout LibrarySet, index: Int, _ value: Double) {
    guard libraries.quotaInstruments.indices.contains(index) else { return }
    libraries.quotaInstruments[index].qty = value
}

public func removeQuotaInstrument(in libraries: inout LibrarySet, index: Int) {
    guard libraries.quotaInstruments.indices.contains(index) else { return }
    libraries.quotaInstruments.remove(at: index)
}

/// 新增主材关联：材料取自材料库一行；kind 为“通用”或“变体”（variant 传本行项目名称）。
public func addMaterialRule(in libraries: inout LibrarySet, quota: String,
                            material: MaterialRow, kind: String, variant: String,
                            consumption: Double) {
    libraries.rules.append(RuleRow(
        id: newUID(), quota: quota, material: material.name, spec: material.spec,
        unit: material.unit, consumption: consumption, supply: material.supply,
        kind: kind, variant: variant, remark: "", appliesTo: "全"))
}

public func addQuotaMachine(in libraries: inout LibrarySet, quota: String,
                            priceRow: MachinePriceRow, qty: Double) {
    libraries.quotaMachines.append(QuotaMachineRow(
        id: newUID(), quota: quota, mcode: priceRow.code, mname: priceRow.name,
        unit: priceRow.unit, qty: qty))
}

public func addQuotaInstrument(in libraries: inout LibrarySet, quota: String,
                               priceRow: InstrumentPriceRow, qty: Double) {
    libraries.quotaInstruments.append(QuotaInstrumentRow(
        id: newUID(), quota: quota, mcode: priceRow.code, mname: priceRow.name,
        unit: priceRow.unit, qty: qty))
}

/// 改材料库单价（名称+规格命中行）；未命中返回 false（未建档，需先 ensureMaterial）。
@discardableResult
public func setMaterialPrice(in libraries: inout LibrarySet, name: String, spec: String,
                             _ value: Double) -> Bool {
    // 与引擎 matByKey 一致：命中最后一行。
    guard let i = libraries.materials.lastIndex(where: { $0.name == name && $0.spec == spec }) else {
        return false
    }
    libraries.materials[i].priceExcl = value
    return true
}

/// 材料建档：材料库无（名称+规格）时追加一行；已存在则不重复建。返回行下标。
@discardableResult
public func ensureMaterial(in libraries: inout LibrarySet, name: String, spec: String,
                           unit: String, supply: String, priceExcl: Double) -> Int {
    if let i = libraries.materials.lastIndex(where: { $0.name == name && $0.spec == spec }) {
        return i
    }
    libraries.materials.append(MaterialRow(
        id: newUID(), name: name, spec: spec, unit: unit,
        priceExcl: priceExcl, supply: supply, remark: ""))
    return libraries.materials.count - 1
}
