import XCTest
@testable import TXBudget

/// v2.5.0（docs/v2-ui-design.md §12）：表三甲逐行工日贡献与引擎表三甲对照、
/// 可选型号（变体）清单、切换型号后端到端表四随动。
final class V25WorkloadLayoutTests: XCTestCase {

    private func libs(from set: LibrarySet) -> Libs {
        LibraryCompletionTests.libs(from: set, seed: loadSeed())
    }

    // MARK: - 表三甲逐行贡献 vs 引擎（§12.1）

    /// 受控库：QA 技 2 / 普 1；QB 技 0.46 / 普 0.3（“工日X0.5”由行系数 0.5 承载）。
    private func dayLibraries() -> LibrarySet {
        LibrarySet(
            quotas: [
                QuotaRow(id: "qa", code: "QA", name: "定额甲", unit: "个", tech: 2, labor: 1),
                QuotaRow(id: "qb", code: "QB", name: "定额乙", unit: "条", tech: 0.46, labor: 0.3),
            ],
            materials: [], rules: [], machinePrices: [], instrumentPrices: [],
            quotaMachines: [], quotaInstruments: []
        )
    }

    func testRowContributionMatchesEngineTable3A() {
        let set = dayLibraries()
        var project = Project()
        project.quantities = [
            QuantityRow(id: "1", quota: "QA", variant: "定额甲", qty: 4, coef: 2),   // 技 16 / 普 8
            QuantityRow(id: "2", quota: "QA", variant: "定额甲", qty: 6, coef: 1),   // 技 12 / 普 6
            QuantityRow(id: "3", quota: "QB", variant: "定额乙", qty: 18.748, coef: 0.5), // 技 4.31204
            QuantityRow(id: "4", quota: "QA", variant: "定额甲", qty: 0, coef: 1),    // 不参与 = 0
            QuantityRow(id: "5", quota: "QA", variant: "定额甲", qty: -3, coef: 1),   // 无效 = 0
            QuantityRow(id: "6", quota: "GHOST", variant: "", qty: 9, coef: 1),       // 孤儿 = 0
        ]
        // 逐行贡献公式：数量 × 系数 × 单位工日（含系数 0.5 的行）。
        let c3 = table3ARowContribution(row: project.quantities[2], libraries: set)
        XCTAssertEqual(c3.tech, 18.748 * 0.5 * 0.46, accuracy: 1e-9)
        XCTAssertEqual(c3.labor, 18.748 * 0.5 * 0.3, accuracy: 1e-9)
        XCTAssertEqual(table3ARowContribution(row: project.quantities[3], libraries: set).tech, 0)
        XCTAssertEqual(table3ARowContribution(row: project.quantities[4], libraries: set).tech, 0)
        XCTAssertEqual(table3ARowContribution(row: project.quantities[5], libraries: set).tech, 0)

        // 逐行贡献求和 == 引擎表三甲逐项（仅差每定额一处 r2 舍入）。
        let engine = calcProject(project, libs(from: set))
        var sumTech = 0.0, sumLabor = 0.0
        for row in project.quantities {
            let c = table3ARowContribution(row: row, libraries: set)
            sumTech += c.tech
            sumLabor += c.labor
        }
        XCTAssertEqual(sumTech, engine.techSub, accuracy: 0.01)
        XCTAssertEqual(sumLabor, engine.laborSub, accuracy: 0.01)
        // 引擎逐定额行（QA 一组）：加权量 (4×2+6)=14 → 技 r2(14×2)=28。
        let qaRows = engine.table3A.filter { $0.code == "QA" }
        XCTAssertEqual(qaRows.reduce(0.0) { $0 + $1.tech }, 28, accuracy: 0.001)
        XCTAssertEqual(qaRows.reduce(0.0) { $0 + $1.labor }, 14, accuracy: 0.001)
        // QB 组：r2(9.374 × 0.46) = 4.31（引擎舍入到 2 位）。
        let qbRows = engine.table3A.filter { $0.code == "QB" }
        XCTAssertEqual(qbRows.reduce(0.0) { $0 + $1.tech }, 4.31, accuracy: 0.001)
        // 汇总条主数字口径 = techSub/laborSub（与状态栏 techDays 的调整前小计同源）。
        XCTAssertEqual(engine.techDays, engine.techSub * (1 + engine.adjRate), accuracy: 0.001)
    }

    // MARK: - 可选型号清单（§12.4）

    func testVariantOptionsFromRules() {
        let set = LibrarySet(
            quotas: [QuotaRow(id: "q1", code: "Q1", name: "定额一", unit: "个", tech: 1, labor: 1),
                     QuotaRow(id: "q2", code: "Q2", name: "定额二", unit: "个", tech: 1, labor: 1)],
            materials: [],
            rules: [
                RuleRow(id: "r0", quota: "Q1", material: "M1", consumption: 2, kind: "通用", variant: ""),
                RuleRow(id: "r1", quota: "Q1", material: "M2", consumption: 3, kind: "变体", variant: "V1"),
                RuleRow(id: "r2", quota: "Q1", material: "M3", consumption: 5, kind: "变体*", variant: "V"),
                RuleRow(id: "r3", quota: "Q1", material: "M2", consumption: 9, kind: "变体", variant: "V1"),
                RuleRow(id: "r4", quota: "Q1", material: "M4", consumption: 7, kind: "备选", variant: "V1"),
            ],
            machinePrices: [], instrumentPrices: [], quotaMachines: [], quotaInstruments: []
        )
        // 基准项（定额库原名）打头 + 变体/变体* distinct（首现顺序、去重；备选不算型号）。
        XCTAssertEqual(variantOptions(quota: "Q1", libraries: set), ["定额一", "V1", "V"])
        // 无变体规则 → 只有基准项（界面据此判定“无可选型号”不弹）。
        XCTAssertEqual(variantOptions(quota: "Q2", libraries: set), ["定额二"])
        // 孤儿编码 → 空。
        XCTAssertEqual(variantOptions(quota: "GHOST", libraries: set), [])
    }

    func testVariantOptionsSeedTXL3() {
        let set = LibraryCompletionTests.loadAppSeedLibrarySet()
        let options187 = variantOptions(quota: "TXL3-187", libraries: set)
        XCTAssertEqual(options187.count, 4)
        XCTAssertEqual(options187.first, firstQuota(code: "TXL3-187", libraries: set)?.name)
        XCTAssertTrue(options187.contains("挂钩法架设架空光缆 平原 6芯"))
        XCTAssertTrue(options187.contains("挂钩法架设架空光缆 平原 12芯"))
        XCTAssertTrue(options187.contains("挂钩法架设架空光缆 平原 24芯"))
        let options192 = variantOptions(quota: "TXL3-192", libraries: set)
        XCTAssertEqual(options192.count, 4)
        XCTAssertTrue(options192.contains("挂钩法架设架空光缆 丘陵、城区、水田 12芯"))
    }

    // MARK: - 切换型号端到端（§12.4：表四主材规格/用量随动）

    func testVariantSwitchChangesTable4EndToEnd() {
        let set = LibraryCompletionTests.loadAppSeedLibrarySet()
        var project = smallProject { p in
            p.quantities = [QuantityRow(quota: "TXL3-187", variant: "挂钩法架设架空光缆 平原 6芯",
                                        unit: "千米条", qty: 2, coef: 1)]
        }
        let engineLibs = LibraryCompletionTests.libs(from: set, seed: loadSeed())
        var engine = calcProject(project, engineLibs)
        XCTAssertEqual(matQty(engine, "光缆", "GYTS_6芯"), 2.014, accuracy: 0.01)
        XCTAssertEqual(matQty(engine, "光缆", "GYTS_12芯"), 0, accuracy: 0.001)

        // 切换为 12 芯（只改 variant，工程量/系数不动）→ 表四规格与用量随动。
        project.quantities[0].variant = "挂钩法架设架空光缆 平原 12芯"
        engine = calcProject(project, engineLibs)
        XCTAssertEqual(matQty(engine, "光缆", "GYTS_6芯"), 0, accuracy: 0.001)
        XCTAssertEqual(matQty(engine, "光缆", "GYTS_12芯"), 2.014, accuracy: 0.01)
        // 通用主材不随型号变。
        XCTAssertEqual(matQty(engine, "铸塑光缆挂钩", "45mm"), 4000, accuracy: 0.001)
        // 关联区（同一 Logic）同步：本行生效变体主材改为 GYTS_12芯。
        let links = effectiveLinks(row: project.quantities[0], project: project, libraries: set)
        let fiber = links.materials.first { $0.rule.material == "光缆" }
        XCTAssertEqual(fiber?.rule.spec, "GYTS_12芯")
        XCTAssertEqual(fiber?.totalQty ?? -1, 2.014, accuracy: 0.001)
        // 切回基准项（定额库原名）→ 只剩通用规则：变体光缆消失，挂钩仍在。
        project.quantities[0].variant = firstQuota(code: "TXL3-187", libraries: set)?.name
        engine = calcProject(project, engineLibs)
        XCTAssertEqual(matQty(engine, "光缆", "GYTS_12芯"), 0, accuracy: 0.001)
        XCTAssertEqual(matQty(engine, "铸塑光缆挂钩", "45mm"), 4000, accuracy: 0.001)
    }
}
