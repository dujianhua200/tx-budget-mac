import XCTest
@testable import TXBudget

/// 库表行 ↔ 字典编解码（通用字典表格的后端）：往返 / 视图切片 / 新增 / 删除。
final class LibraryRowCodecTests: XCTestCase {

    private func sampleProfile() -> ConfigurationProfile {
        var p = ConfigurationProfile()
        p.libraries.quotas = [QuotaRow(id: "q1", code: "TXL1-001", name: "架设吊线", unit: "条公里", tech: 2, labor: 1, coef: 1)]
        p.libraries.materials = [MaterialRow(id: "m1", name: "钢绞线", spec: "7/2.2", unit: "kg", priceExcl: 5, supply: "乙供")]
        p.libraries.rules = [
            RuleRow(id: "r1", quota: "TXL1-001", material: "钢绞线", spec: "7/2.2", unit: "kg",
                    consumption: 10, supply: "乙供", kind: "变体", variant: "", remark: "", appliesTo: "全"),
            RuleRow(id: "r2", quota: "TXL1-001", material: "钢绞线", spec: "7/2.2", unit: "kg",
                    consumption: 12, supply: "乙供", kind: "备选", variant: "", remark: "", appliesTo: "全"),
        ]
        p.table5Fees = [Table5Fee(key: "safetyFee", name: "安全生产费", basis: "preDiscountExclTax",
                                  rate: 0.02, vatRate: 0, amount: nil, enabled: true, order: 1, note: "")]
        return p
    }

    func testQuotaRoundTrip() {
        var p = sampleProfile()
        let dicts = LibraryRowCodec.dicts(for: .quotas, profile: p)
        XCTAssertEqual(dicts.count, 1)
        XCTAssertEqual(dicts[0]["code"], "TXL1-001")
        // 改一个值写回。
        var edited = dicts[0]
        edited["tech"] = "2.5"
        LibraryRowCodec.commit(id: "q1", dict: edited, viewKey: .quotas, profile: &p)
        XCTAssertEqual(p.libraries.quotas.first?.tech, 2.5)
        // 未知 id → 追加。
        LibraryRowCodec.commit(id: "q-new", dict: ["code": "TXL1-009", "name": "新定额"], viewKey: .quotas, profile: &p)
        XCTAssertEqual(p.libraries.quotas.count, 2)
        XCTAssertEqual(p.libraries.quotas.last?.code, "TXL1-009")
    }

    func testRulesAltViewFiltersAltKindOnly() {
        // v2.6.0：资料库只保留“关联规则（备选）”视图（变体/机械/仪表关联的维护
        // 收敛到表三甲底部关联区）；数据层 rules 全量仍在（见导入层回归测试）。
        let p = sampleProfile()
        let alt = LibraryRowCodec.dicts(for: .rulesAlt, profile: p)
        XCTAssertEqual(alt.map { $0["id"] }, ["r2"])
        // 备选视图 kind 只给“备选”。
        let altKind = LibraryRowCodec.columns(for: .rulesAlt).first { $0.key == "kind" }
        XCTAssertEqual(altKind?.options, ["备选"])
        // 页面已下线：导航键里不再有三张关联表。
        XCTAssertFalse(LibraryViewKey.allCases.map { $0.label }.contains { $0.contains("映射") })
    }

    func testRulesAltCommitMapsBackToStorage() {
        var p = sampleProfile()
        let alt = LibraryRowCodec.dicts(for: .rulesAlt, profile: p)
        var edited = alt[0]
        edited["consumption"] = "15"
        LibraryRowCodec.commit(id: "r2", dict: edited, viewKey: .rulesAlt, profile: &p)
        XCTAssertEqual(p.libraries.rules.first { $0.id == "r2" }?.consumption, 15)
        // 变体行不受影响。
        XCTAssertEqual(p.libraries.rules.first { $0.id == "r1" }?.consumption, 10)
    }

    func testAddAndDelete() {
        var p = sampleProfile()
        LibraryRowCodec.add(viewKey: .materials, profile: &p)
        XCTAssertEqual(p.libraries.materials.count, 2)
        XCTAssertEqual(p.libraries.materials.first?.supply, "甲供")
        LibraryRowCodec.delete(ids: ["m1"], viewKey: .materials, profile: &p)
        XCTAssertEqual(p.libraries.materials.count, 1)
        XCTAssertNotEqual(p.libraries.materials.first?.id, "m1")
    }

    func testTable5DictsAndCommit() {
        var p = sampleProfile()
        let dicts = LibraryRowCodec.table5Dicts(p.table5Fees)
        XCTAssertEqual(dicts.count, 1)
        XCTAssertEqual(dicts[0]["id"], "safetyFee")
        XCTAssertEqual(dicts[0]["rate"], "0.02")
        var edited = dicts[0]
        edited["rate"] = "0.025"
        LibraryRowCodec.commitTable5(id: "safetyFee", dict: edited, profile: &p)
        XCTAssertEqual(p.table5Fees.first?.rate, 0.025)
        // 新增费用项。
        LibraryRowCodec.addTable5(profile: &p)
        XCTAssertEqual(p.table5Fees.count, 2)
        LibraryRowCodec.deleteTable5(ids: ["newFee"], profile: &p)
        XCTAssertEqual(p.table5Fees.count, 1)
    }

    func testColumnsCoverAllViewKeys() {
        for key in LibraryViewKey.allCases {
            XCTAssertFalse(LibraryRowCodec.columns(for: key).isEmpty, "\(key) 应有列定义")
            XCTAssertTrue(LibraryRowCodec.columns(for: key).contains { $0.key == "id" || $0.key == "code" || $0.key == "quota" || $0.key == "name" },
                          "\(key) 应有标识列")
        }
    }
}
