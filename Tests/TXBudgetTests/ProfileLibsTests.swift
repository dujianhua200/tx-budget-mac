import XCTest
@testable import TXBudget

/// 方案 → 引擎 libs 转换 / 方案查找与回落 / 创建与复制。
final class ProfileLibsTests: XCTestCase {

    private func sampleProfile() -> ConfigurationProfile {
        var p = ConfigurationProfile()
        p.id = "prof_1"
        p.name = "测试方案"
        p.libraries.quotas = [QuotaRow(id: "q1", code: "TXL1-001", name: "架设吊线", unit: "条公里", tech: 2, labor: 1, coef: 1)]
        p.libraries.materials = [MaterialRow(id: "m1", name: "钢绞线", spec: "7/2.2", unit: "kg", priceExcl: 5, supply: "乙供")]
        p.libraries.rules = [
            RuleRow(id: "r1", quota: "TXL1-001", material: "钢绞线", spec: "7/2.2", unit: "kg",
                    consumption: 10, supply: "乙供", kind: "变体", variant: "", remark: "", appliesTo: "全"),
        ]
        p.libraries.machinePrices = [MachinePriceRow(id: "mp1", code: "JX-01", name: "空压机", unit: "台班", price: 100)]
        p.libraries.instrumentPrices = [InstrumentPriceRow(id: "ip1", code: "YB-01", name: "OTDR", unit: "台班", price: 80)]
        return p
    }

    func testProfileToLibsNil() {
        XCTAssertNil(profileToLibs(nil))
    }

    func testProfileToLibsConversion() {
        let libs = profileToLibs(sampleProfile())!
        XCTAssertEqual(libs.quotas.count, 1)
        XCTAssertEqual(libs.quotas.first?.code, "TXL1-001")
        XCTAssertEqual(libs.quotas.first?.tech, 2)
        XCTAssertEqual(libs.materials.count, 1)
        XCTAssertEqual(libs.materials.first?.supply, "乙供")
        XCTAssertEqual(libs.rules.count, 1)
        XCTAssertEqual(libs.rules.first?.consumption, 10)
        XCTAssertEqual(libs.machinePrices.first?.price, 100)
        XCTAssertEqual(libs.instrumentPrices.first?.name, "OTDR")
        // rateGrid 兼容垫片不再需要：引擎直接读具名 rates。
        XCTAssertNil(libs.rateGrid)
    }

    func testGetAndActiveProfile() {
        var db = DbFile()
        db.configurationProfiles = [sampleProfile()]
        db.settings.activeProfileId = "prof_1"
        XCTAssertEqual(getProfile(db, "prof_1")?.name, "测试方案")
        XCTAssertNil(getProfile(db, "missing"))
        XCTAssertNil(getProfile(db, nil))
        XCTAssertEqual(activeProfile(db)?.id, "prof_1")
        // 激活 id 命中失败 → 回落第一个方案。
        db.settings.activeProfileId = "missing"
        XCTAssertEqual(activeProfile(db)?.id, "prof_1")
    }

    func testResolveEditingProfileFallback() {
        var db = DbFile()
        let p1 = sampleProfile()
        var p2 = sampleProfile()
        p2.id = "prof_2"
        db.configurationProfiles = [p1, p2]
        db.settings.activeProfileId = "prof_1"
        // editing 命中。
        db.settings.editingProfileId = "prof_2"
        XCTAssertEqual(resolveEditingProfileId(db), "prof_2")
        // editing 命中失败 → active。
        db.settings.editingProfileId = "missing"
        XCTAssertEqual(resolveEditingProfileId(db), "prof_1")
        // active 也失败 → 第一个。
        db.settings.activeProfileId = "missing"
        XCTAssertEqual(resolveEditingProfileId(db), "prof_1")
        // 无方案 → nil。
        db.configurationProfiles = []
        XCTAssertNil(resolveEditingProfileId(db))
    }

    func testCreateProfileDefaults() {
        let p = createProfile(name: "新方案")
        XCTAssertEqual(p.name, "新方案")
        XCTAssertEqual(p.source, "user-created")
        XCTAssertFalse(p.isBuiltIn)
        XCTAssertEqual(p.discountRule.discountRate, 1)
        XCTAssertEqual(p.rates.winterTable["Ⅲ类地区"], 0.018)
        XCTAssertFalse(p.table5Fees.isEmpty)
        XCTAssertFalse(p.id.isEmpty)
    }

    func testDuplicateProfile() {
        let p = sampleProfile()
        let copy = duplicateProfile(p)
        XCTAssertNotEqual(copy.id, p.id)
        XCTAssertEqual(copy.name, "测试方案（副本）")
        XCTAssertFalse(copy.isBuiltIn)
        // 内容完整复制。
        XCTAssertEqual(copy.libraries.quotas, p.libraries.quotas)
        XCTAssertEqual(copy.libraries.rules, p.libraries.rules)
    }

    func testCalcForUsesProjectProfile() {
        var db = DbFile()
        db.configurationProfiles = [sampleProfile()]
        db.settings.activeProfileId = "prof_1"
        var project = ProjectRecord(id: "p", name: "P", profileId: "prof_1")
        project.quantities = [QuantityRow(id: "q", quota: "TXL1-001", qty: 1)]
        let result = calcFor(db, project)
        XCTAssertNotNil(result)
    }
}
