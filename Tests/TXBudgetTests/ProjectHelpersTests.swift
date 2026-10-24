import XCTest
@testable import TXBudget

/// 工程列表 / 打折单选 / 定额联想 / 新建工程（对照 Electron `v3.js` + `store.js`）。
final class ProjectHelpersTests: XCTestCase {

    func testSortProjectsRecent() {
        let a = ProjectRecord(id: "a", name: "A", profileId: "p", lastOpenedAt: 100)
        let b = ProjectRecord(id: "b", name: "B", profileId: "p", lastOpenedAt: 300)
        let c = ProjectRecord(id: "c", name: "C", profileId: "p", lastOpenedAt: nil)
        let d = ProjectRecord(id: "d", name: "D", profileId: "p", lastOpenedAt: 200)
        XCTAssertEqual(sortProjectsRecent([a, b, c, d]).map { $0.id }, ["b", "d", "a", "c"])
        // 无时间戳的保持原有相对顺序。
        let e = ProjectRecord(id: "e", name: "E", profileId: "p", lastOpenedAt: nil)
        XCTAssertEqual(sortProjectsRecent([c, e]).map { $0.id }, ["c", "e"])
    }

    func testDiscountOption() {
        var info = ProjectInfo()
        XCTAssertEqual(discountOption(info), "noDiscount")
        info.施工折扣 = 0.379
        XCTAssertEqual(discountOption(info), "discount")
    }

    func testApplyDiscountOption() {
        var info = ProjectInfo()
        info.施工折扣 = 0.379
        // 切到不打折 → 1。
        let no = applyDiscountOption(info, "noDiscount", nil)
        XCTAssertEqual(no.info.施工折扣, 1)
        XCTAssertFalse(no.needsInput)
        // 切回打折 → 恢复上次折扣率。
        let back = applyDiscountOption(no.info, "discount", 0.5)
        XCTAssertEqual(back.info.施工折扣, 0.5)
        XCTAssertFalse(back.needsInput)
        // 无上次折扣率且当前为 1 → 提示输入。
        let fresh = applyDiscountOption(ProjectInfo(), "discount", nil)
        XCTAssertTrue(fresh.needsInput)
        XCTAssertEqual(fresh.info.施工折扣, nil)
        // 无上次折扣率但已有非 1 折扣 → 保持。
        let kept = applyDiscountOption(info, "discount", nil)
        XCTAssertFalse(kept.needsInput)
        XCTAssertEqual(kept.info.施工折扣, 0.379)
    }

    func testSwitchProjectProfile() {
        let p = ProjectRecord(id: "p", name: "P", profileId: "a")
        XCTAssertEqual(switchProjectProfile(p, "b").profileId, "b")
        XCTAssertEqual(p.profileId, "a")
    }

    func testQuotaSuggestionsShortlistFirstDeduped() {
        var libs = LibrarySet()
        libs.shortlist = [ShortlistRow(id: "s1", code: "TXL1-001", name: "架设吊线", unit: "条公里", coef: 1)]
        libs.quotas = [
            QuotaRow(id: "q1", code: "TXL1-001", name: "架设吊线", unit: "条公里", tech: 2, labor: 1),
            QuotaRow(id: "q2", code: "TXL1-002", name: "架设光缆", unit: "条公里", tech: 3, labor: 1),
        ]
        let hits = quotaSuggestions(libs, "TXL1")
        // 短单在前；同 code+name 去重（全库重复项不重复出现）。
        XCTAssertEqual(hits.map { $0.code }, ["TXL1-001", "TXL1-002"])
        XCTAssertEqual(hits.first?.tech, 2) // v2.6.1：短单转 QuotaRow 时工日按 code 回查定额库
        XCTAssertTrue(quotaSuggestions(libs, "  ").isEmpty)
        XCTAssertTrue(quotaSuggestions(libs, "不存在").isEmpty)
        // limit 生效。
        XCTAssertEqual(quotaSuggestions(libs, "TXL1", limit: 1).count, 1)
    }

    func testNewProjectUsesDefaultInfoAndActiveProfile() {
        var db = DbFile()
        db.settings.activeProfileId = "prof_x"
        db.settings.defaultInfo.工程类型 = "通信管道工程"
        let p = newProject(db, name: "新工程")
        XCTAssertEqual(p.name, "新工程")
        XCTAssertEqual(p.profileId, "prof_x")
        XCTAssertEqual(p.info.建设项目名称, "新工程")
        XCTAssertEqual(p.info.工程类型, "通信管道工程")
        XCTAssertTrue(p.quantities.isEmpty)
    }

    func testQuantityRowStatus() {
        let row = QuantityRow(id: "q1", quota: "TXL1-001")
        XCTAssertEqual(quantityRowStatus(row, orphanIds: ["q1"], invalidIds: [], duplicateCodes: []), .orphan)
        XCTAssertEqual(quantityRowStatus(row, orphanIds: [], invalidIds: ["q1"], duplicateCodes: []), .invalid)
        let dup = QuantityRow(id: "q2", quota: "TXL1-001")
        XCTAssertEqual(quantityRowStatus(dup, orphanIds: [], invalidIds: [], duplicateCodes: ["TXL1-001"]), .duplicate)
        XCTAssertEqual(quantityRowStatus(dup, orphanIds: [], invalidIds: [], duplicateCodes: []), .ok)
    }
}
