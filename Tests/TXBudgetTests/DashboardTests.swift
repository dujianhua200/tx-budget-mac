import XCTest
@testable import TXBudget

/// 概览派生（Logic/Dashboard.swift）与导出迷你预览（Logic/ExportPreview.swift）：
/// 全部取自 CalcResult，与引擎结果逐项对齐。
final class DashboardTests: XCTestCase {

    private func sampleResult() -> (DbFile, ProjectRecord, CalcResult) {
        var p = ConfigurationProfile()
        p.id = "prof_1"
        p.name = "测试方案"
        p.libraries.quotas = [QuotaRow(id: "q1", code: "TXL1-001", name: "架设吊线", unit: "条公里", tech: 2, labor: 1, coef: 1)]
        p.libraries.materials = [MaterialRow(id: "m1", name: "钢绞线", spec: "7/2.2", unit: "kg", priceExcl: 5, supply: "乙供")]
        p.libraries.rules = [
            RuleRow(id: "r1", quota: "TXL1-001", material: "钢绞线", spec: "7/2.2", unit: "kg",
                    consumption: 10, supply: "乙供", kind: "变体", variant: "", remark: "", appliesTo: "全"),
        ]
        var named = NamedRatesRecord()
        for def in rateFieldDefs { named.setValue(0.01, forKey: def.key) }
        p.rates.byProjectType["通信线路工程"] = named
        p.rates.winterTable = ["Ⅲ类地区": 0.018]
        p.table5Fees = defaultTable5Fees()
        var db = DbFile()
        db.configurationProfiles = [p]
        db.settings.activeProfileId = "prof_1"
        var project = ProjectRecord(id: "p1", name: "测试工程", profileId: "prof_1")
        project.info.建设项目名称 = "测试工程"
        project.quantities = [QuantityRow(id: "row1", quota: "TXL1-001", qty: 10)]
        let result = calcFor(db, project)!
        return (db, project, result)
    }

    func testKPIMatchesResult() {
        let (_, _, result) = sampleResult()
        let kpi = dashboardKPI(result)
        XCTAssertEqual(kpi.grandIncl, result.table1.grandIncl)
        XCTAssertEqual(kpi.buildExcl, result.table2After.exclTax)
        XCTAssertEqual(kpi.materialEquipExcl,
                       result.table4A.totalExcl + result.table4B.totalExcl + result.table4Equip.totalExcl)
        XCTAssertEqual(kpi.totalDays, result.techDays + result.laborDays)
        XCTAssertGreaterThan(kpi.grandIncl, 0)
    }

    func testFeeCompositionSegments() {
        let (_, _, result) = sampleResult()
        let segments = feeComposition(result)
        XCTAssertEqual(segments.map { $0.id }, ["build", "equip", "other"])
        XCTAssertEqual(segments[0].amount, result.summary.constructionIncl)
        XCTAssertEqual(segments[1].amount, result.table1.equipIncl)
        XCTAssertEqual(segments[2].amount, result.summary.otherIncl)
        // 三段之和 = 总造价（grandIncl = 汇总含税 + 设备含税）。
        let sum = segments.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(sum, result.table1.grandIncl, accuracy: 0.001)
        // 占比之和 = 1。
        let fracSum = segments.reduce(0) { $0 + $1.fraction(of: segments) }
        XCTAssertEqual(fracSum, 1, accuracy: 1e-9)
    }

    func testExportPreviewLinesForAllSheets() {
        let (_, project, result) = sampleResult()
        for sheet in sheetNames {
            let lines = exportSheetPreviewLines(sheet, project: project,
                                                profileName: "测试方案", result: result)
            XCTAssertFalse(lines.isEmpty, "表 \(sheet) 预览为空")
        }
        XCTAssertTrue(exportSheetPreviewLines("不存在的表", project: project,
                                              profileName: "测试方案", result: result).isEmpty)
    }

    func testExportPreviewTable1ShowsGrandTotal() {
        let (_, project, result) = sampleResult()
        let lines = exportSheetPreviewLines("工程总表(表一)", project: project,
                                            profileName: "测试方案", result: result)
        XCTAssertTrue(lines.contains { $0.contains(money(result.table1.grandIncl)) },
                      "表一预览应含总计 \(money(result.table1.grandIncl))，实际：\(lines)")
    }
}
