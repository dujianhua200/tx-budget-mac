import XCTest
@testable import TXBudget

/// 取费左树 / 右表逻辑（对照 Electron `v3.js` FEE_TREE 与 DISCOUNT_LINE_DEFS）。
final class FeeTreeTests: XCTestCase {

    func testLeavesCoverAllDiscountLineDefs() {
        let leaves = feeLeavesOf(feeTree)
        // 树叶子覆盖全部打折行定义（合计项同样以叶子形式挂在树上；FeeNodeKind.leaf 只是“树叶子”，不是 DiscountLineKind.leaf）。
        XCTAssertEqual(Set(leaves), Set(discountLineDefs.map { $0.key }))
        // 无重复叶子。
        XCTAssertEqual(leaves.count, Set(leaves).count)
    }

    func testFeeRowsForNodeRoot() {
        var profile = ConfigurationProfile()
        profile.rates.byProjectType["通信线路工程"] = NamedRatesRecord(values: ["techPrice": 114, "laborPrice": 61])
        let rows = feeRowsForNode("root:all", profile: profile, result: nil, projectType: "通信线路工程")
        XCTAssertFalse(rows.isEmpty)
        // 根节点 = 全部叶子。
        XCTAssertEqual(rows.map { $0.key }.sorted(), feeLeavesOf(feeTree).sorted())
    }

    func testFeeRowsForNodeGroup() {
        let rows = feeRowsForNode("g:labor", profile: nil, result: nil, projectType: "通信线路工程")
        let keys = rows.map { $0.key }
        XCTAssertTrue(keys.contains("techFee"))
        XCTAssertTrue(keys.contains("laborFee"))
        XCTAssertTrue(keys.contains("laborTotal"))
        XCTAssertFalse(keys.contains("jiaMat"))
    }

    func testFeeRowsUnknownNodeEmpty() {
        XCTAssertEqual(feeRowsForNode("no:such", profile: nil, result: nil, projectType: "通信线路工程"), [])
    }

    func testFeeBasisTextPlaceholders() {
        // 费率占位符 ×100 展开（对照 Electron feeBasisText）。
        let text = feeBasisText("techFee", ["techPrice": 114])
        XCTAssertTrue(text.contains("114"), "techFee basis 应含技工单价 114，实际：\(text)")
        // 无费率时占位符不崩，留空/0。
        let empty = feeBasisText("auxMat", [:])
        XCTAssertFalse(empty.isEmpty)
    }

    func testRateFieldDef() {
        XCTAssertNotNil(rateFieldDef("techPrice"))
        XCTAssertNil(rateFieldDef("noSuchField"))
    }
}
