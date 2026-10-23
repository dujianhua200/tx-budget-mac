import XCTest
@testable import TXBudget

/// v2.4.1 规则「适用工程」（appliesTo）过滤（docs/v2.4.1-appliesto-design.md）：
/// 解析单测、引擎行为、calcFor 工程序号集成、面板-引擎一致性。
/// 语义：'' = 不启用，'全' = 全部工程，'1,3' = 仅序号 1、3 的工程；
/// 序号 = 工程在所属方案工程集合中的 1 基位置。
final class AppliesToTests: XCTestCase {

    // MARK: - 解析

    func testParseAll() {
        XCTAssertEqual(parseRuleAppliesTo("全"), .all)
        XCTAssertEqual(parseRuleAppliesTo(" 全 "), .all)
        XCTAssertTrue(ruleAppliesToProject("全", projectOrdinal: 1))
        XCTAssertTrue(ruleAppliesToProject("全", projectOrdinal: 9))
    }

    func testParseEmptyMeansDisabled() {
        XCTAssertEqual(parseRuleAppliesTo(""), .disabled)
        XCTAssertEqual(parseRuleAppliesTo("   "), .disabled)
        XCTAssertFalse(ruleAppliesToProject("", projectOrdinal: 1))
        XCTAssertFalse(ruleAppliesToProject("", projectOrdinal: 2))
    }

    func testParseList() {
        XCTAssertEqual(parseRuleAppliesTo("1,3"), .only([1, 3]))
        XCTAssertTrue(ruleAppliesToProject("1,3", projectOrdinal: 1))
        XCTAssertFalse(ruleAppliesToProject("1,3", projectOrdinal: 2))
        XCTAssertTrue(ruleAppliesToProject("1,3", projectOrdinal: 3))
        XCTAssertEqual(parseRuleAppliesTo("2"), .only([2]))
    }

    func testParseTolerantSeparatorsAndFullWidth() {
        // 全角逗号、顿号、分号、空格分隔与首尾空白都应等价解析。
        XCTAssertEqual(parseRuleAppliesTo("1，3"), .only([1, 3]))
        XCTAssertEqual(parseRuleAppliesTo("1、3"), .only([1, 3]))
        XCTAssertEqual(parseRuleAppliesTo("1;3"), .only([1, 3]))
        XCTAssertEqual(parseRuleAppliesTo("1 3"), .only([1, 3]))
        XCTAssertEqual(parseRuleAppliesTo(" 1 , 3 "), .only([1, 3]))
        // 全角数字归一化。
        XCTAssertEqual(parseRuleAppliesTo("１，３"), .only([1, 3]))
    }

    func testParseGarbageFailsClosed() {
        XCTAssertEqual(parseRuleAppliesTo("abc"), .disabled)
        XCTAssertEqual(parseRuleAppliesTo("0"), .disabled)       // 0 不是合法序号（1 基）
        XCTAssertEqual(parseRuleAppliesTo("1,a,3"), .only([1, 3])) // 非法 token 丢弃
        XCTAssertFalse(ruleAppliesToProject("abc", projectOrdinal: 1))
    }

    // MARK: - 引擎行为（受控夹具）

    /// Q1 一条定额；五条规则分别覆盖：通用/变体/变体*/备选 × 不同 appliesTo。
    private func fixtureLibraries() -> LibrarySet {
        LibrarySet(
            quotas: [QuotaRow(id: "q1", code: "Q1", name: "定额一", unit: "个", tech: 1, labor: 1)],
            materials: [
                MaterialRow(id: "m1", name: "M1", spec: "", unit: "个", priceExcl: 10, supply: "甲供"),
                MaterialRow(id: "m2", name: "M2", spec: "", unit: "个", priceExcl: 10, supply: "甲供"),
                MaterialRow(id: "m3", name: "M3", spec: "", unit: "个", priceExcl: 10, supply: "甲供"),
                MaterialRow(id: "m4", name: "M4", spec: "", unit: "个", priceExcl: 10, supply: "甲供"),
                MaterialRow(id: "m5", name: "M5", spec: "", unit: "个", priceExcl: 10, supply: "甲供"),
            ],
            rules: [
                RuleRow(id: "g1", quota: "Q1", material: "M1", spec: "", unit: "个", consumption: 2, supply: "甲供", kind: "通用", variant: "", appliesTo: "2"),
                RuleRow(id: "v1", quota: "Q1", material: "M2", spec: "", unit: "个", consumption: 3, supply: "甲供", kind: "变体", variant: "V1", appliesTo: "1,3"),
                RuleRow(id: "e1", quota: "Q1", material: "M3", spec: "", unit: "个", consumption: 5, supply: "甲供", kind: "通用", variant: "", appliesTo: ""),
                RuleRow(id: "a1", quota: "Q1", material: "M4", spec: "", unit: "个", consumption: 7, supply: "甲供", kind: "备选", variant: "V1", appliesTo: "2"),
                RuleRow(id: "s1", quota: "Q1", material: "M5", spec: "", unit: "个", consumption: 11, supply: "甲供", kind: "变体*", variant: "V", appliesTo: "2"),
            ]
        )
    }

    private func fixtureProject(ordinal: Int, enableAlt: Bool = true) -> Project {
        var p = Project()
        p.quantities = [QuantityRow(id: "A", quota: "Q1", variant: "V1", qty: 10, coef: 1)]
        p.projectOrdinal = ordinal
        if enableAlt { p.ruleOverrides = [RuleOverride(ruleId: "a1", enabled: true)] }
        return p
    }

    private func libs(from set: LibrarySet) -> Libs {
        LibraryCompletionTests.libs(from: set, seed: loadSeed())
    }

    private func engineAutoQty(_ res: CalcResult, _ name: String) -> Double {
        var sum = 0.0
        for t in [res.table4A, res.table4B, res.table4Equip] {
            for r in t.rows where r.key == "\(name)|" { sum += r.autoQty }
        }
        return sum
    }

    func testEngineFiltersByOrdinal() {
        let set = fixtureLibraries()
        // 序号 1：变体（1,3）生效 10×3=30；通用（2）/备选（2）/变体*（2）被挡；空永不生效。
        let r1 = calcProject(fixtureProject(ordinal: 1), libs(from: set))
        XCTAssertEqual(engineAutoQty(r1, "M1"), 0, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r1, "M2"), 30, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r1, "M3"), 0, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r1, "M4"), 0, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r1, "M5"), 0, accuracy: 0.001)
        // 序号 2：通用 10×2=20；变体（1,3）被挡；备选已启用且序号命中 10×7=70；变体* 10×11=110。
        let r2 = calcProject(fixtureProject(ordinal: 2), libs(from: set))
        XCTAssertEqual(engineAutoQty(r2, "M1"), 20, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r2, "M2"), 0, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r2, "M3"), 0, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r2, "M4"), 70, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r2, "M5"), 110, accuracy: 0.001)
        // 序号 3：仅变体（1,3）生效。
        let r3 = calcProject(fixtureProject(ordinal: 3), libs(from: set))
        XCTAssertEqual(engineAutoQty(r3, "M2"), 30, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r3, "M1"), 0, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r3, "M4"), 0, accuracy: 0.001)
    }

    func testEngineAltStillNeedsOverrideWhenOrdinalMatches() {
        let set = fixtureLibraries()
        // 序号命中但备选未启用 → 两道闸门取交集，仍不出量。
        let r = calcProject(fixtureProject(ordinal: 2, enableAlt: false), libs(from: set))
        XCTAssertEqual(engineAutoQty(r, "M4"), 0, accuracy: 0.001)
    }

    // MARK: - 面板-引擎一致性

    func testPanelGrayedWithReasonWhenBlocked() {
        let set = fixtureLibraries()
        let row = QuantityRow(id: "A", quota: "Q1", variant: "V1", qty: 10, coef: 1)

        let p1 = fixtureProject(ordinal: 1)
        let links1 = effectiveLinks(row: row, project: p1, libraries: set)
        let m1 = links1.materials.first { $0.rule.material == "M1" }
        XCTAssertNotNil(m1)
        XCTAssertEqual(m1?.isEffective, false)
        XCTAssertEqual(m1?.totalQty ?? -1, 0, accuracy: 0.001)
        XCTAssertTrue(m1?.inactiveReason?.contains("适用工程为「2」") ?? false)
        XCTAssertTrue(m1?.inactiveReason?.contains("序号 1") ?? false)
        // 空 appliesTo：灰显原因不同。
        let m3 = links1.materials.first { $0.rule.material == "M3" }
        XCTAssertEqual(m3?.isEffective, false)
        XCTAssertTrue(m3?.inactiveReason?.contains("适用工程为空") ?? false)
        // 序号 1 面板逐材合计 == 引擎（M2=30，其余 0）。
        let engine1 = calcProject(p1, libs(from: set))
        for name in ["M1", "M2", "M3", "M4", "M5"] {
            let panel = links1.materials.filter { $0.rule.material == name }
                .reduce(0.0) { $0 + $1.totalQty }
            XCTAssertEqual(panel, engineAutoQty(engine1, name), accuracy: 0.001,
                           "序号 1 面板与引擎应一致：\(name)")
        }

        // 序号 2：M1 生效且数值与引擎一致（20）。
        let p2 = fixtureProject(ordinal: 2)
        let links2 = effectiveLinks(row: row, project: p2, libraries: set)
        let m1b = links2.materials.first { $0.rule.material == "M1" }
        XCTAssertEqual(m1b?.isEffective, true)
        XCTAssertEqual(m1b?.totalQty ?? -1, 20, accuracy: 0.001)
        let engine2 = calcProject(p2, libs(from: set))
        for name in ["M1", "M2", "M3", "M4", "M5"] {
            let panel = links2.materials.filter { $0.rule.material == name }
                .reduce(0.0) { $0 + $1.totalQty }
            XCTAssertEqual(panel, engineAutoQty(engine2, name), accuracy: 0.001,
                           "序号 2 面板与引擎应一致：\(name)")
        }
    }

    // MARK: - calcFor 工程序号集成

    func testCalcForInjectsOrdinalWithinProfile() {
        var profile = ConfigurationProfile()
        profile.id = "prof_A"
        profile.name = "方案A"
        profile.libraries = fixtureLibraries()
        var other = ConfigurationProfile()
        other.id = "prof_B"
        other.name = "方案B"
        other.libraries = fixtureLibraries()

        let qty = [QuantityRow(id: "A", quota: "Q1", variant: "V1", qty: 10, coef: 1)]
        // db.projects 顺序：X（方案B，不占 A 的序号）、P1、P2、P3（方案A）。
        let x = ProjectRecord(id: "X", name: "X", profileId: "prof_B", quantities: qty)
        let p1 = ProjectRecord(id: "P1", name: "P1", profileId: "prof_A", quantities: qty)
        let p2 = ProjectRecord(id: "P2", name: "P2", profileId: "prof_A", quantities: qty)
        let p3 = ProjectRecord(id: "P3", name: "P3", profileId: "prof_A", quantities: qty)

        var db = DbFile()
        db.configurationProfiles = [profile, other]
        db.settings.activeProfileId = "prof_A"
        db.projects = [x, p1, p2, p3]

        XCTAssertEqual(projectOrdinal(db, x), 1)   // 方案B 内第 1 个
        XCTAssertEqual(projectOrdinal(db, p1), 1)  // 方案A 内第 1 个（X 不占位）
        XCTAssertEqual(projectOrdinal(db, p2), 2)
        XCTAssertEqual(projectOrdinal(db, p3), 3)
        // 不在 db 中的工程（示例工程）回落 1。
        XCTAssertEqual(projectOrdinal(db, ProjectRecord(id: "ghost", profileId: "prof_A")), 1)

        // 变体规则 appliesTo="1,3"：P1/P3 出 M2=30，P2 不出；通用规则 appliesTo="2"：仅 P2 出 M1=20。
        let r1 = calcFor(db, p1)!
        XCTAssertEqual(engineAutoQty(r1, "M2"), 30, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r1, "M1"), 0, accuracy: 0.001)
        let r2 = calcFor(db, p2)!
        XCTAssertEqual(engineAutoQty(r2, "M2"), 0, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r2, "M1"), 20, accuracy: 0.001)
        let r3 = calcFor(db, p3)!
        XCTAssertEqual(engineAutoQty(r3, "M2"), 30, accuracy: 0.001)
        XCTAssertEqual(engineAutoQty(r3, "M1"), 0, accuracy: 0.001)
    }
}
