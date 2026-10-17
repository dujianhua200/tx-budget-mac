/// 打折模型 + 引擎口径测试。对照 tests/discount.test.mjs（全部断言搬运）。
import XCTest
@testable import TXBudget

final class DiscountTests: XCTestCase {
    // 参考样本折前表二（实测自参考结算书表二折前表）。
    func refBefore() -> Table2 {
        Table2(values: [
            "techFee": 144687.55, "laborFee": 48230.63, "laborTotal": 192918.18,
            "jiaMat": 74246.30, "yiMat": 0, "mainMat": 74246.30, "auxMat": 222.74, "matTotal": 74469.04,
            "machineFee": 5580.00, "instrumentFee": 15455.26, "directFee": 288422.48,
            "envFee": 0, "civilFee": 2893.77, "carryFee": 6559.22, "disturbFee": 11575.09, "handoverFee": 6366.30,
            "tempFee": 9645.91, "vehicleFee": 9645.91, "nightFee": 4822.95, "winterFee": 3472.53, "toolFee": 2893.77,
            "utilityFee": 0, "specialFee": 0, "protectFee": 3858.36, "earthFee": 0, "dispatchFee": 5916.00, "bigMachineFee": 0,
            "measureFee": 67649.81, "directTotal": 356072.29,
            "sewageFee": 0, "socialFee": 54981.68, "housingFee": 8083.27, "accidentFee": 1929.18, "regFee": 64994.13,
            "mgmtFee": 52859.58, "indirectTotal": 117853.71, "profit": 38583.64, "exclTax": 512509.64,
            "outputTax": 39443.70, "inclTax": 551953.34, "dispatchUnit": 0, "dispatchPeople": 0,
        ])
    }

    // Q2 的 11 项措施（参考折前值；参考折后表为空 = 0，裁决 b）。
    let q2Keys = ["carryFee", "disturbFee", "tempFee", "nightFee", "winterFee", "utilityFee",
                  "specialFee", "protectFee", "earthFee", "dispatchFee", "bigMachineFee"]

    /// 11 项置 0 的参考折前表（折后结果应与完整参考折前表一致）。
    func refBeforeNoQ2() -> Table2 {
        var t = refBefore()
        for k in q2Keys { t.values[k] = 0 }
        t.measureFee = 21799.75 // 文明 2893.77 + 点交 6366.30 + 车辆 9645.91 + 工具 2893.77
        t.directTotal = 288422.48 + 21799.75
        t.exclTax = 466659.58
        t.outputTax = (466659.58 - 74246.30) * 0.09 // jiaTax=0 时的销项税额（仅用于本测试的 before 占位）
        return t
    }

    var ruleRef: DiscountRuleInput {
        DiscountRuleInput(discountRate: 0.379, noDiscountKeys: defaultNoDiscountKeys,
                          outputTaxRate: 0.09, jiaTax: 0)
    }

    func testDiscountPerLine() {
        let after = try! applyDiscount(refBeforeNoQ2(), rule: ruleRef)
        XCTAssertEqual(after.techFee, 54836.58, accuracy: 0.011)
        XCTAssertEqual(after.laborFee, 18279.41, accuracy: 0.011)
        XCTAssertEqual(after.laborTotal, 73115.99, accuracy: 0.011)
        XCTAssertEqual(after.machineFee, 2114.82, accuracy: 0.011)
        XCTAssertEqual(after.instrumentFee, 5857.54, accuracy: 0.011)
        XCTAssertEqual(after.civilFee, 2893.77, accuracy: 0.011)
        XCTAssertEqual(after.handoverFee, 2412.83, accuracy: 0.011)
        XCTAssertEqual(after.vehicleFee, 3655.80, accuracy: 0.011)
        XCTAssertEqual(after.toolFee, 1096.74, accuracy: 0.011)
        XCTAssertEqual(after.mainMat, 74246.30, accuracy: 0.011)
        XCTAssertEqual(after.auxMat, 222.74, accuracy: 0.011)
        XCTAssertEqual(after.mgmtFee, 20033.78, accuracy: 0.011)
        XCTAssertEqual(after.profit, 14623.20, accuracy: 0.011)
        XCTAssertEqual(after.regFee, 64994.13, accuracy: 0.02)
        XCTAssertEqual(after.socialFee, 54981.68, accuracy: 0.011)
        XCTAssertEqual(after.measureFee, 10059.14, accuracy: 0.011)
        XCTAssertEqual(after.exclTax, 265267.64, accuracy: 0.02)
        XCTAssertEqual(after.directFee, 155557.39, accuracy: 0.011)
    }

    func testDiscountFullReference_Q2Zero() {
        let afterFull = try! applyDiscount(refBefore(), rule: ruleRef)
        XCTAssertTrue(q2Keys.allSatisfy { afterFull.values[$0] == 0 })
        for k in q2Keys { XCTAssertEqual(afterFull.values[k] ?? -1, 0, accuracy: 0.011) }
        XCTAssertEqual(afterFull.measureFee, 10059.14, accuracy: 0.011)
        XCTAssertEqual(afterFull.exclTax, 265267.64, accuracy: 0.02)
        let after = try! applyDiscount(refBeforeNoQ2(), rule: ruleRef)
        XCTAssertEqual(afterFull.measureFee, after.measureFee)
        XCTAssertEqual(afterFull.exclTax, after.exclTax)
    }

    func testDiscountZeroListCustomizable() {
        // 零值清单清空则 11 项恢复打折（措施回到 27436.31）。
        var rule = ruleRef
        rule.zeroAfterDiscountKeys = []
        let noZero = try! applyDiscount(refBefore(), rule: rule)
        XCTAssertEqual(noZero.measureFee, 27436.31, accuracy: 0.011)
        XCTAssertEqual(noZero.carryFee, 2485.94, accuracy: 0.011)
        XCTAssertEqual(noZero.disturbFee, 4386.96, accuracy: 0.011)
        XCTAssertEqual(noZero.tempFee, 3655.80, accuracy: 0.011)
        XCTAssertEqual(noZero.nightFee, 1827.90, accuracy: 0.011)
        XCTAssertEqual(noZero.winterFee, 1316.09, accuracy: 0.011)
        XCTAssertEqual(noZero.protectFee, 1462.32, accuracy: 0.011)
        XCTAssertEqual(noZero.dispatchFee, 2242.16, accuracy: 0.011)

        // 某项从零值清单移入不打折清单则保持折前值。
        let keepQ2 = try! applyDiscount(refBefore(), rule: DiscountRuleInput(
            discountRate: 0.379,
            noDiscountKeys: defaultNoDiscountKeys + ["carryFee"],
            zeroAfterDiscountKeys: defaultZeroAfterDiscountKeys.filter { $0 != "carryFee" },
            outputTaxRate: 0.09, jiaTax: 0))
        XCTAssertEqual(keepQ2.carryFee, 6559.22, accuracy: 0.011)

        // 两清单同时含某项时折后=0 优先。
        let both = try! applyDiscount(refBefore(), rule: DiscountRuleInput(
            discountRate: 0.379,
            noDiscountKeys: defaultNoDiscountKeys + ["carryFee"],
            outputTaxRate: 0.09, jiaTax: 0))
        XCTAssertEqual(both.carryFee, 0, accuracy: 0.011)
    }

    func testDiscountRateOneIsIdentity() {
        var rule = ruleRef
        rule.discountRate = 1
        let after1 = try! applyDiscount(refBefore(), rule: rule)
        let before = refBefore()
        for k in ["techFee", "laborFee", "mainMat", "civilFee", "regFee", "measureFee", "exclTax", "outputTax",
                  "dispatchFee", "winterFee", "carryFee", "tempFee"] {
            XCTAssertEqual(after1.values[k] ?? -1, before.values[k] ?? -2, accuracy: 0.011, "discount=1 时 \(k) 不变")
        }
    }

    func testDiscountInvalidRateThrows() {
        XCTAssertThrowsError(try applyDiscount(refBefore(), rule: DiscountRuleInput(discountRate: 0)))
        XCTAssertThrowsError(try applyDiscount(refBefore(), rule: DiscountRuleInput(discountRate: 1.5)))
    }

    func testDiscountCustomRule() {
        let custom = try! applyDiscount(refBeforeNoQ2(), rule: DiscountRuleInput(
            discountRate: 0.5,
            noDiscountKeys: defaultNoDiscountKeys + ["machineFee"],
            outputTaxRate: 0.09, jiaTax: 0))
        XCTAssertEqual(custom.techFee, 72343.78, accuracy: 0.011) // 144687.55×0.5=72343.775→72343.78
        XCTAssertEqual(custom.machineFee, 5580.00, accuracy: 0.011)
        XCTAssertEqual(custom.mainMat, 74246.30, accuracy: 0.011)

        // 表二内含 safetyFee 行时同样按规则处理。
        var withSafetyBefore = refBeforeNoQ2()
        withSafetyBefore.values["safetyFee"] = 1000
        let withSafety = try! applyDiscount(withSafetyBefore, rule: ruleRef)
        XCTAssertEqual(withSafety.values["safetyFee"] ?? -1, 1000, accuracy: 0.011)
        let withSafety2 = try! applyDiscount(withSafetyBefore, rule: DiscountRuleInput(
            discountRate: 0.379,
            noDiscountKeys: defaultNoDiscountKeys.filter { $0 != "safetyFee" },
            outputTaxRate: 0.09, jiaTax: 0))
        XCTAssertEqual(withSafety2.values["safetyFee"] ?? -1, 379.00, accuracy: 0.011)

        // 销项税额按折后基数公式：(265267.64-74246.30)×0.09 + 74246.30×0.13 = 26843.94。
        var taxRule = ruleRef
        taxRule.jiaTax = 0.13
        let afterTax = try! applyDiscount(refBeforeNoQ2(), rule: taxRule)
        XCTAssertEqual(afterTax.outputTax, 26843.94, accuracy: 0.011)
    }

    func testSafetyFee() {
        let seed = loadSeed()
        let libs = gridLibs(from: seed)
        let rSafe = calcProject(smallProject(), libs)
        XCTAssertEqual(rSafe.table5.safetyFee, rSafe.table2Before.exclTax * 0.02, accuracy: 0.011)
        XCTAssertEqual(rSafe.table5.safetyVat, 0, accuracy: 0.011)
        XCTAssertEqual(rSafe.table5.safetyIncl, rSafe.table5.safetyFee, accuracy: 0.011)
        XCTAssertEqual(rSafe.table5.rows.count, 16)
        XCTAssertTrue(rSafe.table5.rows.contains { $0.key == "designTotal" && $0.basis == "sum" })
        XCTAssertEqual(rSafe.table5.designTotal, rSafe.table5.surveyFee + rSafe.table5.designFee, accuracy: 0.011)
        XCTAssertEqual(rSafe.table5.totalExcl,
                       rSafe.table5.mgmt2 + rSafe.table5.designTotal + rSafe.table5.safetyFee, accuracy: 0.011)
        // 安全生产费验证数：10250.19 = 512509.64 × 2%。
        XCTAssertEqual(r2(512509.64 * 0.02), 10250.19, accuracy: 0.011)
    }

    func testSummaryBasis() {
        let seed = loadSeed()
        let libs = gridLibs(from: seed)
        let rSafe = calcProject(smallProject(), libs)
        XCTAssertEqual(rSafe.summary.constructionExcl, rSafe.table1.afterDiscount)
        XCTAssertEqual(rSafe.summary.constructionExcl, rSafe.table2After.exclTax)
        XCTAssertEqual(rSafe.summary.other, rSafe.table5.totalExcl)
        XCTAssertEqual(rSafe.summary.totalExcl, rSafe.summary.constructionExcl + rSafe.summary.other, accuracy: 0.011)
        XCTAssertEqual(rSafe.summary.totalVat, rSafe.summary.constructionVat + rSafe.summary.otherVat, accuracy: 0.011)
        // 汇总表无 selfMat（Swift 类型即保证无此字段，无需运行时断言）。
    }

    func testTable1NoShortcutFormula() {
        let seed = loadSeed()
        let libs = gridLibs(from: seed)
        let rDisc = calcProject(smallProject { p in p.info.施工折扣 = 0.379 }, libs)
        XCTAssertEqual(rDisc.table1.afterDiscount, rDisc.table2After.exclTax)
        XCTAssertEqual(rDisc.table1.taxAfter, rDisc.table2After.outputTax)
        let shortcut = (rDisc.table2Before.exclTax - rDisc.table2Before.mainMat - rDisc.table2Before.regFee) * 0.379
            + rDisc.table2Before.mainMat + rDisc.table2Before.regFee
        XCTAssertTrue(abs(rDisc.table1.afterDiscount - shortcut) > 1, "表一折后 ≠ v1 快捷公式值")
        XCTAssertEqual(rDisc.table2.exclTax, rDisc.table2After.exclTax)
        XCTAssertTrue(rDisc.table2Before.exclTax > rDisc.table2After.exclTax)
    }

    func testTable5Configurable() {
        let seed = loadSeed()
        let libs = gridLibs(from: seed)
        let rSafe = calcProject(smallProject(), libs)

        // 费率可配（安全生产费 0.03）。
        var libsRate = libs
        libsRate.table5Fees = defaultTable5Fees().map { $0.key == "safetyFee" ? Table5Fee(
            key: $0.key, name: $0.name, basis: $0.basis, rate: 0.03, vatRate: $0.vatRate,
            amount: $0.amount, enabled: $0.enabled, order: $0.order, note: $0.note) : $0 }
        let rRate = calcProject(smallProject(), libsRate)
        XCTAssertEqual(rRate.table5.safetyFee, rRate.table2Before.exclTax * 0.03, accuracy: 0.011)

        // 单项覆盖 amount。
        let rOverride = calcProject(smallProject { p in
            p.table5Overrides = [Table5Override(key: "landFee", amount: 12345)]
        }, libs)
        XCTAssertEqual(rOverride.table5.rows.first(where: { $0.key == "landFee" })?.excl ?? -1, 12345, accuracy: 0.011)
        XCTAssertEqual(rOverride.table5.totalExcl, rSafe.table5.totalExcl + 12345, accuracy: 0.011)

        // 禁用项不输出、不计入总计。
        var libsDisabled = libs
        libsDisabled.table5Fees = defaultTable5Fees().map { $0.key == "mgmt2" ? Table5Fee(
            key: $0.key, name: $0.name, basis: $0.basis, rate: $0.rate, vatRate: $0.vatRate,
            amount: $0.amount, enabled: false, order: $0.order, note: $0.note) : $0 }
        let rDisabled = calcProject(smallProject(), libsDisabled)
        XCTAssertFalse(rDisabled.table5.rows.contains { $0.key == "mgmt2" })
        XCTAssertEqual(rDisabled.table5.totalExcl, rSafe.table5.totalExcl - rSafe.table5.mgmt2, accuracy: 0.011)

        // afterDiscountExclTax 基数用折后除税价。
        var libsAfter = libs
        libsAfter.table5Fees = defaultTable5Fees() + [Table5Fee(
            key: "customFee", name: "自定义费", basis: "afterDiscountExclTax", rate: 0.01,
            vatRate: 0, amount: nil, enabled: true, order: 15, note: "")]
        let rAfterBasis = calcProject(smallProject { p in p.info.施工折扣 = 0.379 }, libsAfter)
        XCTAssertEqual(rAfterBasis.table5.rows.first(where: { $0.key == "customFee" })?.excl ?? -1,
                       rAfterBasis.table2After.exclTax * 0.01, accuracy: 0.011)
    }

    func testOrphanRows() {
        let seed = loadSeed()
        let libs = gridLibs(from: seed)
        let rSafe = calcProject(smallProject(), libs)
        let rOrphan = calcProject(smallProject { p in
            p.quantities = [
                QuantityRow(id: "qty_ok", quota: "TXL1-008", variant: "", unit: "", qty: 7, coef: 1),
                QuantityRow(id: "qty_orphan", quota: "NOPE-001", variant: "", unit: "", qty: 5, coef: 1),
                QuantityRow(id: "qty_neg", quota: "TXL1-008", variant: "", unit: "", qty: -3, coef: 1),
            ]
        }, libs)
        let orphanWarn = rOrphan.warnings.first(where: { $0.code == "orphanQty" })
        XCTAssertNotNil(orphanWarn)
        XCTAssertEqual(orphanWarn?.rowIds ?? [], ["qty_orphan"])
        XCTAssertFalse(rOrphan.table3A.contains { $0.code == "NOPE-001" })
        XCTAssertEqual(rOrphan.techDays, rSafe.techDays)
        XCTAssertNotNil(rOrphan.warnings.first(where: { $0.code == "invalidQty" }))
        XCTAssertEqual(rOrphan.laborDays, rSafe.laborDays)

        // 孤儿定额的规则不产生材料。
        var libsOrphanRule = libs
        libsOrphanRule.rules = libs.rules + [Rule(id: "r_orphan", quota: "NOPE-001", material: "光缆",
                                                  spec: "GYTS_6芯", consumption: 1, supply: "甲供",
                                                  kind: "通用", variant: "")]
        let rOrphanRule = calcProject(smallProject { p in
            p.quantities = [QuantityRow(id: "qty_o", quota: "NOPE-001", variant: "", unit: "", qty: 5, coef: 1)]
        }, libsOrphanRule)
        XCTAssertEqual(rOrphanRule.table4A.totalExcl, 0, accuracy: 0.011)

        // 定额库编号重复警告。
        var libsDup = libs
        if let dup = libs.quotas.first(where: { $0.code == "TXL1-008" }) {
            libsDup.quotas = libs.quotas + [dup]
        }
        let rDup = calcProject(smallProject(), libsDup)
        XCTAssertNotNil(rDup.warnings.first(where: { $0.code == "duplicateCode" }))
    }

    func testWinterRateOverride() {
        let seed = loadSeed()
        let libs = gridLibs(from: seed)
        let rSafe = calcProject(smallProject(), libs)

        let rWinterNull = calcProject(smallProject(), withWinterRate(namedLibs(from: seed), nil))
        XCTAssertEqual(rWinterNull.table2Before.winterFee, rWinterNull.table2Before.laborTotal * 0.018, accuracy: 0.011)
        let rWinterOverride = calcProject(smallProject(), withWinterRate(namedLibs(from: seed), 0.05))
        XCTAssertEqual(rWinterOverride.table2Before.winterFee, rWinterOverride.table2Before.laborTotal * 0.05, accuracy: 0.011)
        let rWinterZero = calcProject(smallProject(), withWinterRate(namedLibs(from: seed), 0))
        XCTAssertEqual(rWinterZero.table2Before.winterFee, 0, accuracy: 0.011)
        // 具名费率路径与 rateGrid 路径一致。
        XCTAssertEqual(abs(rWinterNull.table2Before.exclTax - rSafe.table2Before.exclTax), 0, accuracy: 0.011)
    }

    func testProfileLevelDiscount() {
        let seed = loadSeed()
        var info = ProjectInfo()
        info.工程类型 = "通信线路工程" // 施工折扣未填 → 落到配置方案折扣率
        let libs = namedLibs(from: seed, discountRule: DiscountRule(
            discountRate: 0.5, noDiscountKeys: defaultNoDiscountKeys))
        let r = calcProject(Project(info: info, quantities: [
            QuantityRow(quota: "TXL1-008", variant: "", unit: "", qty: 7, coef: 1),
        ]), libs)
        XCTAssertEqual(r.discount, 0.5)
        XCTAssertEqual(r.table2After.techFee, r.table2Before.techFee * 0.5, accuracy: 0.011)
    }
}
