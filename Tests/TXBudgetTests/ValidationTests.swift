import XCTest
@testable import TXBudget

/// 校验中心聚合（Logic/Validation.swift）：引擎 warnings 映射、材料未建档、
/// 表五手动项、工程信息缺项、严重度排序。
final class ValidationTests: XCTestCase {

    /// 费率齐全的方案：一项定额 + 一项材料 + 变体规则，算出结果无引擎 warnings。
    private func fullProfile() -> ConfigurationProfile {
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
        return p
    }

    private func makeDb(_ profile: ConfigurationProfile) -> DbFile {
        var db = DbFile()
        db.configurationProfiles = [profile]
        db.settings.activeProfileId = profile.id
        return db
    }

    /// 信息齐全 + 一行有效工程量的工程。
    private func cleanProject(profileId: String = "prof_1") -> ProjectRecord {
        var project = ProjectRecord(id: "p1", name: "测试工程", profileId: profileId)
        project.info.建设项目名称 = "测试工程"
        project.info.建设单位 = "某建设单位"
        project.info.编制日期 = "2026-10-22"
        project.quantities = [QuantityRow(id: "row1", quota: "TXL1-001", qty: 10)]
        return project
    }

    /// 给全部表五手动项填上金额覆盖（消除“未填金额”提示）。
    private func fillManualAmounts(_ project: inout ProjectRecord, profile: ConfigurationProfile) {
        for fee in profile.table5Fees where fee.basis == "manual" {
            project.table5Overrides.append(Table5Override(key: fee.key, enabled: nil, amount: 100))
        }
    }

    func testCleanProjectHasNoIssues() {
        let profile = fullProfile()
        let db = makeDb(profile)
        var project = cleanProject()
        fillManualAmounts(&project, profile: profile)
        let result = calcFor(db, project)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.warnings.count, 0, "夹具应无引擎警告，实际：\(result?.warnings.map { $0.code } ?? [])")
        let issues = collectValidationIssues(db: db, project: project, profile: profile, result: result)
        XCTAssertTrue(issues.isEmpty, "干净工程不应有校验问题，实际：\(issues.map { $0.id })")
    }

    func testOrphanQuantityIsErrorTargetingWorkload() {
        let profile = fullProfile()
        let db = makeDb(profile)
        var project = cleanProject()
        project.quantities = [QuantityRow(id: "bad1", quota: "NOPE-999", qty: 3)]
        let issues = collectValidationIssues(db: db, project: project, profile: profile,
                                             result: calcFor(db, project))
        let orphan = issues.first { $0.id.hasPrefix("warn-orphanQty") }
        XCTAssertNotNil(orphan)
        XCTAssertEqual(orphan?.severity, .error)
        XCTAssertEqual(orphan?.target, .workload)
        XCTAssertEqual(orphan?.rowId, "bad1")
        // 错误排在最前。
        XCTAssertEqual(issues.first?.severity, .error)
    }

    func testInvalidQuantityIsError() {
        let profile = fullProfile()
        let db = makeDb(profile)
        var project = cleanProject()
        project.quantities = [QuantityRow(id: "bad2", quota: "TXL1-001", qty: -1)]
        let issues = collectValidationIssues(db: db, project: project, profile: profile,
                                             result: calcFor(db, project))
        XCTAssertTrue(issues.contains { $0.id.hasPrefix("warn-invalidQty") && $0.severity == .error })
    }

    func testNoQuantitiesWarning() {
        let profile = fullProfile()
        let db = makeDb(profile)
        var project = cleanProject()
        project.quantities = []
        let issues = collectValidationIssues(db: db, project: project, profile: profile,
                                             result: calcFor(db, project))
        let issue = issues.first { $0.id == "no-quantities" }
        XCTAssertEqual(issue?.severity, .warning)
        XCTAssertEqual(issue?.target, .workload)
    }

    func testManualTable5MissingAmountIsInfo() {
        let profile = fullProfile()
        let db = makeDb(profile)
        let project = cleanProject()
        let issues = collectValidationIssues(db: db, project: project, profile: profile,
                                             result: calcFor(db, project))
        let land = issues.first { $0.id == "table5-manual-landFee" }
        XCTAssertEqual(land?.severity, .info)
        XCTAssertEqual(land?.target, .fees)
        // 填了覆盖金额后消失。
        var filled = project
        filled.table5Overrides.append(Table5Override(key: "landFee", enabled: nil, amount: 500))
        let issues2 = collectValidationIssues(db: db, project: filled, profile: profile,
                                              result: calcFor(db, filled))
        XCTAssertFalse(issues2.contains { $0.id == "table5-manual-landFee" })
        // 停用后也不提示。
        var disabled = project
        disabled.table5Overrides.append(Table5Override(key: "landFee", enabled: false, amount: nil))
        let issues3 = collectValidationIssues(db: db, project: disabled, profile: profile,
                                              result: calcFor(db, disabled))
        XCTAssertFalse(issues3.contains { $0.id == "table5-manual-landFee" })
    }

    func testUnmatchedMaterialIsWarning() {
        var profile = fullProfile()
        profile.libraries.rules = [
            RuleRow(id: "rX", quota: "TXL1-001", material: "不存在的材料", spec: "", unit: "kg",
                    consumption: 1, supply: "乙供", kind: "变体", variant: "", remark: "", appliesTo: "全"),
        ]
        let db = makeDb(profile)
        let project = cleanProject()
        let issues = collectValidationIssues(db: db, project: project, profile: profile,
                                             result: calcFor(db, project))
        XCTAssertTrue(issues.contains { $0.id == "unmatched-乙供主材" && $0.severity == .warning },
                      "实际：\(issues.map { $0.id })")
    }

    func testMissingInfoFieldsAreInfo() {
        let profile = fullProfile()
        let db = makeDb(profile)
        var project = cleanProject()
        project.info.建设单位 = ""
        project.info.编制日期 = ""
        let issues = collectValidationIssues(db: db, project: project, profile: profile,
                                             result: calcFor(db, project))
        XCTAssertTrue(issues.contains { $0.id == "info-builder" && $0.severity == .info })
        XCTAssertTrue(issues.contains { $0.id == "info-date" && $0.severity == .info })
        XCTAssertFalse(issues.contains { $0.id == "info-project-name" })
    }

    func testCalcFailureIsSingleError() {
        let db = DbFile()
        let project = cleanProject(profileId: "missing")
        let issues = collectValidationIssues(db: db, project: project, profile: nil, result: nil)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.id, "calc-failed")
        XCTAssertEqual(issues.first?.severity, .error)
    }

    func testSeverityOrderingErrorsFirst() {
        let profile = fullProfile()
        let db = makeDb(profile)
        var project = cleanProject()
        project.quantities = [QuantityRow(id: "bad3", quota: "NOPE-1", qty: 1)] // 错误
        project.info.建设单位 = "" // 提示
        let issues = collectValidationIssues(db: db, project: project, profile: profile,
                                             result: calcFor(db, project))
        let severities = issues.map { $0.severity }
        XCTAssertEqual(severities, severities.sorted())
        XCTAssertEqual(severities.first, .error)
        XCTAssertEqual(severities.last, .info)
    }
}
