import XCTest
@testable import TXBudget

/// 表五公式列（basis + rate → 公式文本）。
final class Table5LogicTests: XCTestCase {

    private func fee(key: String, basis: String, rate: Double? = nil, amount: Double? = nil) -> Table5Fee {
        Table5Fee(key: key, name: key, basis: basis, rate: rate, vatRate: nil, amount: amount, enabled: true, order: 1, note: "")
    }

    func testManualFormula() {
        XCTAssertEqual(table5Formula(fee(key: "x", basis: "manual")), "手动输入")
    }

    func testSafetyFeeFormula() {
        // 安全生产费口径：折前建安工程费除税价 × 2%（与 basis 无关，key 兜底）。
        XCTAssertEqual(table5Formula(fee(key: "safetyFee", basis: "preDiscountExclTax", rate: 0.02)),
                       "折前建安工程费除税价 × 2%")
    }

    func testBasisFormulas() {
        XCTAssertEqual(table5Formula(fee(key: "a", basis: "preDiscountExclTax", rate: 0.01)),
                       "折前建安工程费除税价 × 1%")
        XCTAssertEqual(table5Formula(fee(key: "b", basis: "afterDiscountExclTax", rate: 0.05)),
                       "折后建安工程费除税价 × 5%")
        XCTAssertEqual(table5Formula(fee(key: "c", basis: "laborTotal", rate: 0.1)),
                       "人工费 × 10%")
        XCTAssertEqual(table5Formula(fee(key: "d", basis: "fixed", amount: 123.45)),
                       "固定金额 123.45")
        XCTAssertEqual(table5Formula(fee(key: "e", basis: "surveyKm")), "按勘察长度分段计取")
        XCTAssertEqual(table5Formula(fee(key: "f", basis: "sum")), "子项之和")
    }

    func testBuildRowsStableSortAndOverrides() {
        var profile = ConfigurationProfile()
        profile.table5Fees = [
            fee(key: "b", basis: "manual"),
            fee(key: "a", basis: "manual"),
        ]
        profile.table5Fees[0].order = 2
        profile.table5Fees[1].order = 1
        var project = ProjectRecord(id: "p", name: "P", profileId: "prof")
        project.table5Overrides = [Table5Override(key: "a", enabled: false, amount: 77)]
        let rows = buildTable5ViewRows(profile: profile, project: project, result: nil)
        // 按 order 排序：a(1) 在前。
        XCTAssertEqual(rows.map { $0.key }, ["a", "b"])
        // 覆盖生效：a 被禁用；金额来自引擎结果（无结果时为 nil，覆盖的 amount 不直接进视图行）。
        XCTAssertEqual(rows.first?.enabled, false)
        XCTAssertNil(rows.first?.amount)
    }
}
