import XCTest
@testable import TXBudget

/// v2.4.0 工作量底部关联区（docs/v2.4-workload-design.md §3/§5）：
/// 共享判定与引擎同口径（对照钉死）、面板组装、写回后引擎随动、真实种子变体场景端到端。
final class WorkloadLinksTests: XCTestCase {

    // MARK: - 夹具

    /// 受控小库：Q1/Q2 两定额；四种规则种类各一条 + Q2 通用；机械/仪表各一条映射。
    /// M3 故意不建档（材料库无此行）。
    private func fixtureLibraries() -> LibrarySet {
        LibrarySet(
            quotas: [
                QuotaRow(id: "q1", code: "Q1", name: "定额一", unit: "个", tech: 1, labor: 1),
                QuotaRow(id: "q2", code: "Q2", name: "定额二", unit: "个", tech: 1, labor: 1),
            ],
            materials: [
                MaterialRow(id: "m1", name: "M1", spec: "", unit: "个", priceExcl: 10, supply: "甲供"),
                MaterialRow(id: "m2", name: "M2", spec: "", unit: "个", priceExcl: 20, supply: "甲供"),
                MaterialRow(id: "m4", name: "M4", spec: "", unit: "个", priceExcl: 40, supply: "甲供"),
            ],
            rules: [
                RuleRow(id: "r0", quota: "Q1", material: "M1", spec: "", unit: "个", consumption: 2, supply: "甲供", kind: "通用", variant: ""),
                RuleRow(id: "r1", quota: "Q1", material: "M2", spec: "", unit: "个", consumption: 3, supply: "甲供", kind: "变体", variant: "V1"),
                RuleRow(id: "r2", quota: "Q1", material: "M3", spec: "", unit: "个", consumption: 5, supply: "甲供", kind: "变体*", variant: "V"),
                RuleRow(id: "alt1", quota: "Q1", material: "M4", spec: "", unit: "个", consumption: 7, supply: "甲供", kind: "备选", variant: "V1"),
                RuleRow(id: "r4", quota: "Q2", material: "M1", spec: "", unit: "个", consumption: 11, supply: "甲供", kind: "通用", variant: ""),
            ],
            machinePrices: [MachinePriceRow(id: "p1", code: "TXJ001", name: "熔接机", unit: "台班", price: 100)],
            instrumentPrices: [InstrumentPriceRow(id: "p2", code: "TXY001", name: "分析仪", unit: "台班", price: 200)],
            quotaMachines: [
                QuotaMachineRow(id: "a1", quota: "Q1", mcode: "TXJ001", mname: "熔接机", unit: "台班", qty: 0.5),
                QuotaMachineRow(id: "a2", quota: "Q2", mcode: "TXJ001", mname: "熔接机", unit: "台班", qty: 1),
            ],
            quotaInstruments: [
                QuotaInstrumentRow(id: "a3", quota: "Q1", mcode: "TXY001", mname: "分析仪", unit: "台班", qty: 0.25),
            ]
        )
    }

    /// A/B 同定额同变体（系数不同）、C 变体不符、D 负数行、E 另一定额、F 孤儿行。
    private func fixtureProject(enableAlt: Bool = false) -> Project {
        var p = Project()
        p.quantities = [
            QuantityRow(id: "A", quota: "Q1", variant: "V1", qty: 4, coef: 2),
            QuantityRow(id: "B", quota: "Q1", variant: "V1", qty: 6, coef: 1),
            QuantityRow(id: "C", quota: "Q1", variant: "V2", qty: 3, coef: 1),
            QuantityRow(id: "D", quota: "Q1", variant: "V1", qty: -2, coef: 1),
            QuantityRow(id: "E", quota: "Q2", variant: "", qty: 5, coef: 1),
            QuantityRow(id: "F", quota: "GHOST", variant: "", qty: 9, coef: 1),
        ]
        if enableAlt { p.ruleOverrides = [RuleOverride(ruleId: "alt1", enabled: true)] }
        return p
    }

    private func libs(from set: LibrarySet) -> Libs {
        LibraryCompletionTests.libs(from: set, seed: loadSeed())
    }

    private func links(_ row: QuantityRow, _ project: Project, _ set: LibrarySet) -> WorkloadRowLinks {
        effectiveLinks(row: row, project: project, libraries: set)
    }

    /// 引擎表四某材料键的自动数量（三张表合计）。
    private func engineAutoQty(_ res: CalcResult, _ name: String, _ spec: String) -> Double {
        let key = "\(name)|\(spec)"
        var sum = 0.0
        for t in [res.table4A, res.table4B, res.table4Equip] {
            for r in t.rows where r.key == key { sum += r.autoQty }
        }
        return sum
    }

    private func panelMatSum(_ project: Project, _ set: LibrarySet, _ name: String) -> Double {
        project.quantities.reduce(0.0) { acc, row in
            acc + links(row, project, set).materials
                .filter { $0.rule.material == name }.reduce(0.0) { $0 + $1.totalQty }
        }
    }

    // MARK: - 与引擎一致性（核心契约）

    func testPanelSumsMatchEngine() {
        let set = fixtureLibraries()
        let project = fixtureProject()
        let engine = calcProject(project, libs(from: set))

        // 机械：Q1 加权工程量 = 4×2+6+3 = 17（D 负数不参与）→ 台班 17×0.5 = 8.5。
        let engineB = engine.table3B.rows.filter { $0.quota == "Q1" }
            .reduce(0.0) { $0 + $1.sessions }
        XCTAssertEqual(engineB, 8.5, accuracy: 0.001)
        var panelB = 0.0
        for row in project.quantities where row.quota == "Q1" {
            panelB += links(row, project, set).machines.reduce(0.0) { $0 + $1.totalQty }
        }
        XCTAssertEqual(panelB, engineB, accuracy: 0.001)

        // 仪表：17 × 0.25 = 4.25。
        let engineC = engine.table3C.rows.filter { $0.quota == "Q1" }
            .reduce(0.0) { $0 + $1.sessions }
        XCTAssertEqual(engineC, 4.25, accuracy: 0.001)
        var panelC = 0.0
        for row in project.quantities where row.quota == "Q1" {
            panelC += links(row, project, set).instruments.reduce(0.0) { $0 + $1.totalQty }
        }
        XCTAssertEqual(panelC, engineC, accuracy: 0.001)

        // 材料逐键：M1 = Q1 通用 (4+6+3)×2 + Q2 通用 5×11 = 81；M2 变体 = (4+6)×3 = 30；
        // M3 变体* = (4+6+3−2)×5 = 55（负数行按引擎口径计入）；M4 备选未启用 = 0。
        XCTAssertEqual(engineAutoQty(engine, "M1", ""), 81, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(engine, "M2", ""), 30, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(engine, "M3", ""), 55, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(engine, "M4", ""), 0, accuracy: 0.001)
        for name in ["M1", "M2", "M3", "M4"] {
            XCTAssertEqual(panelMatSum(project, set, name), engineAutoQty(engine, name, ""),
                           accuracy: 0.001, "面板逐行合计应与引擎一致：\(name)")
        }
    }

    func testPanelSumsMatchEngineWithAltEnabled() {
        let set = fixtureLibraries()
        let project = fixtureProject(enableAlt: true)
        let engine = calcProject(project, libs(from: set))
        // 备选启用：基数 = 变体 V1 参与行原始量 4+6 = 10 → 10×7 = 70。
        XCTAssertEqual(engineAutoQty(engine, "M4", ""), 70, accuracy: 0.001)
        XCTAssertEqual(panelMatSum(project, set, "M4"), 70, accuracy: 0.001)
    }

    // MARK: - 组装正确性

    func testPanelAssemblyForSingleRow() {
        let set = fixtureLibraries()
        let project = fixtureProject()
        let rowA = project.quantities[0]
        let l = links(rowA, project, set)
        XCTAssertEqual(l.state, .active)

        let m1 = l.materials.first { $0.rule.material == "M1" }
        XCTAssertEqual(m1?.basisQty ?? -1, 4, accuracy: 0.001)   // 主材通用基数 = 原始数量，不乘系数 2
        XCTAssertEqual(m1?.totalQty ?? -1, 8, accuracy: 0.001)
        XCTAssertEqual(m1?.priceExcl ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(m1?.amount ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(m1?.effectiveSupply, "甲供")

        let m2 = l.materials.first { $0.rule.material == "M2" }
        XCTAssertEqual(m2?.totalQty ?? -1, 12, accuracy: 0.001)  // 变体精确匹配 4×3

        let m3 = l.materials.first { $0.rule.material == "M3" }
        XCTAssertEqual(m3?.totalQty ?? -1, 20, accuracy: 0.001)  // 变体* 前缀匹配 4×5
        XCTAssertNil(m3?.materialIndex)                          // 未建档
        XCTAssertEqual(m3?.priceExcl ?? -1, 0, accuracy: 0.001)

        let m4 = l.materials.first { $0.rule.material == "M4" }
        XCTAssertEqual(m4?.isEffective, false)                   // 备选未启用
        XCTAssertEqual(m4?.inactiveReason, "备选未启用")
        XCTAssertEqual(m4?.totalQty ?? -1, 0, accuracy: 0.001)

        let mach = l.machines.first
        XCTAssertEqual(mach?.basisQty ?? -1, 8, accuracy: 0.001) // 机械基数含系数 4×2
        XCTAssertEqual(mach?.totalQty ?? -1, 4, accuracy: 0.001) // 8×0.5 台班
        XCTAssertEqual(mach?.price ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(mach?.amount ?? -1, 400, accuracy: 0.001)

        let inst = l.instruments.first
        XCTAssertEqual(inst?.totalQty ?? -1, 2, accuracy: 0.001) // 8×0.25
        XCTAssertEqual(inst?.amount ?? -1, 400, accuracy: 0.001)
    }

    func testPanelRowStates() {
        let set = fixtureLibraries()
        let project = fixtureProject()
        // C：变体 V2——变体/备选规则不命中（不列），通用与变体* 命中。
        let c = links(project.quantities[2], project, set)
        XCTAssertEqual(c.state, .active)
        XCTAssertNil(c.materials.first { $0.rule.material == "M2" })
        XCTAssertNil(c.materials.first { $0.rule.material == "M4" })
        XCTAssertEqual(c.materials.first { $0.rule.material == "M3" }?.totalQty ?? -1, 15, accuracy: 0.001)
        // D：负数行——状态 inactive；通用/变体基数 0；变体* 按引擎口径以 −2 计入。
        let d = links(project.quantities[3], project, set)
        XCTAssertEqual(d.state, .inactive(reason: "数量为负，无效行"))
        XCTAssertEqual(d.materials.first { $0.rule.material == "M1" }?.totalQty ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(d.materials.first { $0.rule.material == "M3" }?.totalQty ?? 99, -10, accuracy: 0.001)
        XCTAssertEqual(d.machines.first?.totalQty ?? -1, 0, accuracy: 0.001)
        // F：孤儿行——无任何关联。
        let f = links(project.quantities[5], project, set)
        XCTAssertEqual(f.state, .orphan)
        XCTAssertTrue(f.materials.isEmpty && f.machines.isEmpty && f.instruments.isEmpty)
        // 数量为 0 的行：inactive。
        let zero = QuantityRow(quota: "Q1", variant: "V1", qty: 0, coef: 1)
        XCTAssertEqual(workloadRowState(row: zero, libraries: set), .inactive(reason: "数量为 0，不参与计算"))
    }

    // MARK: - 写回（改库后引擎随动）

    func testWriteBackConsumptionAndDelete() {
        var set = fixtureLibraries()
        let project = fixtureProject()
        // 改主材消耗量：M1 通用 2 → 4 → 引擎 M1 = 13×4 + 55 = 107。
        let m1Idx = set.rules.firstIndex { $0.quota == "Q1" && $0.material == "M1" }!
        setRuleConsumption(in: &set, ruleIndex: m1Idx, 4)
        var engine = calcProject(project, libs(from: set))
        XCTAssertEqual(engineAutoQty(engine, "M1", ""), 107, accuracy: 0.001)
        // 删变体规则：M2 归零。
        let m2Idx = set.rules.firstIndex { $0.material == "M2" }!
        removeRule(in: &set, ruleIndex: m2Idx)
        engine = calcProject(project, libs(from: set))
        XCTAssertEqual(engineAutoQty(engine, "M2", ""), 0, accuracy: 0.001)
        // 改机械消耗量：0.5 → 1 → 表三乙 Q1 台班 = 17。
        setQuotaMachineQty(in: &set, index: 0, 1)
        engine = calcProject(project, libs(from: set))
        XCTAssertEqual(engine.table3B.rows.filter { $0.quota == "Q1" }
            .reduce(0.0) { $0 + $1.sessions }, 17, accuracy: 0.001)
        // 删仪表关联：表三丙 Q1 无行。
        removeQuotaInstrument(in: &set, index: 0)
        engine = calcProject(project, libs(from: set))
        XCTAssertTrue(engine.table3C.rows.filter { $0.quota == "Q1" }.isEmpty)
    }

    func testWriteBackAddLinks() {
        var set = fixtureLibraries()
        let project = fixtureProject()
        // 新增主材关联（先建档 M5，再加通用规则 1.5）：引擎 M5 = 13×1.5 = 19.5。
        let m5 = MaterialRow(id: "m5", name: "M5", spec: "", unit: "个", priceExcl: 3, supply: "甲供")
        set.materials.append(m5)
        addMaterialRule(in: &set, quota: "Q1", material: m5, kind: "通用", variant: "", consumption: 1.5)
        var engine = calcProject(project, libs(from: set))
        XCTAssertEqual(engineAutoQty(engine, "M5", ""), 19.5, accuracy: 0.001)
        // 新增机械关联（价目行 TXJ002 价 50，消耗 2）：表三乙新增台班 17×2 = 34。
        set.machinePrices.append(MachinePriceRow(id: "p9", code: "TXJ002", name: "切割机", unit: "台班", price: 50))
        addQuotaMachine(in: &set, quota: "Q1",
                        priceRow: set.machinePrices.last!, qty: 2)
        engine = calcProject(project, libs(from: set))
        let added = engine.table3B.rows.filter { $0.quota == "Q1" && $0.equipName == "切割机" }
        XCTAssertEqual(added.reduce(0.0) { $0 + $1.sessions }, 34, accuracy: 0.001)
        XCTAssertEqual(added.reduce(0.0) { $0 + $1.amount }, 1700, accuracy: 0.001)
        // 新增仪表关联同理。
        set.instrumentPrices.append(InstrumentPriceRow(id: "p10", code: "TXY002", name: "测试仪", unit: "台班", price: 10))
        addQuotaInstrument(in: &set, quota: "Q1",
                           priceRow: set.instrumentPrices.last!, qty: 1)
        engine = calcProject(project, libs(from: set))
        XCTAssertEqual(engine.table3C.rows.filter { $0.quota == "Q1" && $0.equipName == "测试仪" }
            .reduce(0.0) { $0 + $1.sessions }, 17, accuracy: 0.001)
    }

    func testWriteBackMaterialPriceAndEnsure() {
        var set = fixtureLibraries()
        let project = fixtureProject()
        // 改材料库价：M1 10 → 15 → 表四 M1 行合价 = 81×15（数量不变）。
        XCTAssertTrue(setMaterialPrice(in: &set, name: "M1", spec: "", 15))
        var engine = calcProject(project, libs(from: set))
        let m1Row = (engine.table4A.rows + engine.table4B.rows + engine.table4Equip.rows)
            .first { $0.key == "M1|" }
        XCTAssertEqual(m1Row?.amtExcl ?? -1, 81 * 15, accuracy: 0.001)
        // 未建档改价返回 false；建档后表四行不再 unmatched 且按价计金额。
        XCTAssertFalse(setMaterialPrice(in: &set, name: "M3", spec: "", 6))
        ensureMaterial(in: &set, name: "M3", spec: "", unit: "套", supply: "甲供", priceExcl: 6)
        engine = calcProject(project, libs(from: set))
        let m3Row = (engine.table4A.rows + engine.table4B.rows + engine.table4Equip.rows)
            .first { $0.key == "M3|" }
        XCTAssertEqual(m3Row?.unmatched, false)
        XCTAssertEqual(m3Row?.amtExcl ?? -1, 55 * 6, accuracy: 0.001)
        // 面板同步：M3 已建档、单价 6。
        let l = links(project.quantities[0], project, set)
        let m3 = l.materials.first { $0.rule.material == "M3" }
        XCTAssertNotNil(m3?.materialIndex)
        XCTAssertEqual(m3?.priceExcl ?? -1, 6, accuracy: 0.001)
    }

    // MARK: - 真实种子端到端（TXL3-187 变体材料场景）

    func testEndToEndTXL3187VariantLinks() {
        let set = LibraryCompletionTests.loadAppSeedLibrarySet()
        let project = smallProject { p in
            p.quantities = [QuantityRow(quota: "TXL3-187", variant: "挂钩法架设架空光缆 平原 6芯",
                                        unit: "千米条", qty: 2, coef: 1)]
        }
        let row = project.quantities[0]
        let l = effectiveLinks(row: row, project: project, libraries: set)
        XCTAssertEqual(l.state, .active)
        // 变体主材：光缆 GYTS_6芯，合计 = 1.007 × 2；已建档（种子材料库有此行）。
        let fiber = l.materials.first { $0.rule.material == "光缆" && $0.rule.spec == "GYTS_6芯" }
        XCTAssertNotNil(fiber)
        XCTAssertEqual(fiber?.rule.kind, "变体")
        XCTAssertEqual(fiber?.totalQty ?? -1, 2.014, accuracy: 0.001)
        XCTAssertNotNil(fiber?.materialIndex)
        // 通用主材：铸塑光缆挂钩 2000 × 2。
        let hook = l.materials.first { $0.rule.material == "铸塑光缆挂钩" }
        XCTAssertEqual(hook?.totalQty ?? -1, 4000, accuracy: 0.001)
        // 与引擎逐键一致（引擎表四数量经 r2 两位舍入，2.014 → 2.01，容差取 0.01；
        // 铸塑光缆挂钩规格为 45mm）。
        let engine = calcProject(project, LibraryCompletionTests.libs(from: set, seed: loadSeed()))
        XCTAssertEqual(matQty(engine, "光缆", "GYTS_6芯"), 2.014, accuracy: 0.01)
        XCTAssertEqual(matQty(engine, "铸塑光缆挂钩", "45mm"), 4000, accuracy: 0.001)
    }

    func testEndToEndTXL3187WriteBackChangesEngine() {
        var set = LibraryCompletionTests.loadAppSeedLibrarySet()
        let project = smallProject { p in
            p.quantities = [QuantityRow(quota: "TXL3-187", variant: "挂钩法架设架空光缆 平原 6芯",
                                        unit: "千米条", qty: 2, coef: 1)]
        }
        // 在面板里把变体规则消耗量 1.007 → 2：引擎表四光缆量应变为 2×2 = 4。
        let row = project.quantities[0]
        let l = effectiveLinks(row: row, project: project, libraries: set)
        let fiber = l.materials.first { $0.rule.material == "光缆" && $0.rule.spec == "GYTS_6芯" }!
        setRuleConsumption(in: &set, ruleIndex: fiber.ruleIndex, 2)
        let engine = calcProject(project, LibraryCompletionTests.libs(from: set, seed: loadSeed()))
        XCTAssertEqual(matQty(engine, "光缆", "GYTS_6芯"), 4, accuracy: 0.001)
        // 面板重算同步。
        let l2 = effectiveLinks(row: row, project: project, libraries: set)
        XCTAssertEqual(l2.materials.first { $0.rule.spec == "GYTS_6芯" }?.totalQty ?? -1, 4, accuracy: 0.001)
    }
}
