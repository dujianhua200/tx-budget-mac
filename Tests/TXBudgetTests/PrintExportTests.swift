import XCTest
@testable import TXBudget

/// 导出值断言：用 reference-book.json 夹具生成整本预算书，逐表断言关键单元格。
/// 数值均取夹具内的引擎结果（JS 导出一致值），不重新计算。
final class PrintExportTests: XCTestCase {

    private func exportedBook(profile: ConfigurationProfile? = nil,
                              project: Project? = nil,
                              result: CalcResult? = nil) -> XlsxBook {
        let fixture = ReferenceBookFixture.loadBook()
        let data = buildBudgetBook(
            projectName: fixture.projectName,
            project: project ?? fixture.project,
            result: result ?? fixture.result,
            profile: profile, include: Set(sheetNames))
        guard let book = XlsxTestReader.book(from: data) else {
            XCTFail("导出 xlsx 解析失败")
            return XlsxBook()
        }
        return book
    }

    func testCoverValues() {
        let sheet = exportedBook().sheet(named: "报表封面")
        XCTAssertEqual(sheet?.text("A1"), "通信建设工程预算书")
        XCTAssertEqual(sheet?.text("E2"), "9MA24CE0000019")
        XCTAssertEqual(sheet?.text("B4"), "中国联合网络通信有限公司信阳市分公司")
        XCTAssertEqual(sheet?.text("B5"), "2024年中国联通河南信阳宽带接入扩容工程（31）")
        XCTAssertEqual(sheet?.text("B6"), "275517.84元")
        XCTAssertEqual(sheet?.text("B7"), "中电科普天科技股份有限公司")
        XCTAssertEqual(sheet?.text("B8"), "中国通信建设第一工程局有限公司")
        XCTAssertEqual(sheet?.text("B9"), "河南省通信建设管理咨询有限公司")
        XCTAssertTrue((sheet?.text("B10") ?? "").isEmpty, "编制单位应为空")
        XCTAssertTrue((sheet?.text("B11") ?? "").isEmpty, "参审人员应为空")
        XCTAssertEqual(sheet?.text("B13"), "adu")
    }

    func testNotesContainsDiscountLine() {
        let sheet = exportedBook().sheet(named: "编制说明")
        let text = sheet?.text("A2") ?? ""
        XCTAssertTrue(text.contains("施工折扣按37.9%计取"))
        XCTAssertTrue(text.contains("打折不含主要材料费、辅助材料费、文明施工费、规费、安全生产费"))
    }

    func testSummaryValues() {
        let sheet = exportedBook().sheet(named: "建设项目总算表(汇总表)")
        XCTAssertEqual(sheet?.text("B6"), "通信线路-1")
        XCTAssertEqual(sheet?.text("C6"), "通信线路工程")
        XCTAssertEqual(sheet?.number("G6"), 265267.65)
        XCTAssertEqual(sheet?.number("H6"), 10250.19)
        XCTAssertEqual(sheet?.number("J6"), 275517.84)
        XCTAssertEqual(sheet?.number("L6"), 275517.84)
        XCTAssertEqual(sheet?.text("C7"), "工程总计")
        XCTAssertEqual(sheet?.number("J7"), 275517.84)
    }

    func testTable1Values() {
        let sheet = exportedBook().sheet(named: "工程总表(表一)")
        XCTAssertEqual(sheet?.text("B7"), "通信线路-2")
        XCTAssertEqual(sheet?.text("C7"), "工程费")
        XCTAssertEqual(sheet?.number("G7"), 265267.65)
        XCTAssertEqual(sheet?.number("J7"), 265267.65)
        XCTAssertEqual(sheet?.number("L7"), 265267.65)
        XCTAssertEqual(sheet?.text("B8"), "通信线路-5甲")
        XCTAssertEqual(sheet?.text("C8"), "工程建设其他费")
        XCTAssertEqual(sheet?.number("H8"), 10250.19)
        XCTAssertEqual(sheet?.number("J8"), 10250.19)
        XCTAssertEqual(sheet?.text("C9"), "总 计")
        XCTAssertEqual(sheet?.number("G9"), 265267.65)
        XCTAssertEqual(sheet?.number("H9"), 10250.19)
        XCTAssertEqual(sheet?.number("J9"), 275517.84)
        XCTAssertEqual(sheet?.number("L9"), 275517.84)
    }

    func testTable2AfterValues() {
        let sheet = exportedBook().sheet(named: "工程费用表(表二)")
        XCTAssertEqual(sheet?.text("A1"), "建筑安装工程费用预算表（表二）")
        // 左栏（值在 D 列）
        XCTAssertEqual(sheet?.number("D5"), 265267.65, "建安工程费(含税价)")
        XCTAssertEqual(sheet?.number("D6"), 265267.65, "建安工程费(除税价)")
        XCTAssertEqual(sheet?.number("D9"), 73115.99, "人工费")
        XCTAssertEqual(sheet?.number("D10"), 54836.58, "技工费")
        XCTAssertEqual(sheet?.number("D13"), 74246.3, "主要材料费")
        XCTAssertEqual(sheet?.number("D14"), 222.74, "辅助材料费")
        XCTAssertEqual(sheet?.number("D15"), 2114.82, "机械使用费")
        XCTAssertEqual(sheet?.number("D16"), 5857.54, "仪表使用费")
        XCTAssertEqual(sheet?.number("D17"), 10059.14, "措施项目费")
        // 右栏（值在 J 列）；折后=0 项整行空
        XCTAssertNil(sheet?.number("J5"), "夜间施工增加费折后=0")
        XCTAssertNil(sheet?.text("H5"), "夜间施工增加费折后方法列亦空")
        XCTAssertNil(sheet?.number("J8"), "施工用水电蒸汽费折后=0")
        XCTAssertNil(sheet?.number("J12"), "施工队伍调遣费折后=0")
        XCTAssertEqual(sheet?.number("J15"), 64994.14, "规费")
        XCTAssertEqual(sheet?.number("J21"), 14623.2, "利润")
        XCTAssertNil(sheet?.number("J22"), "销项税额为 0")
        // 计算方法列：折后表体现打折关系
        XCTAssertEqual(sheet?.text("C10"), "技工总工日X114X37.9%")
        XCTAssertEqual(sheet?.text("H21"), "人工费X20%", "利润行方法列在右栏 H 列")
    }

    func testTable2BeforeValues() {
        let sheet = exportedBook().sheet(named: "工程费用表(表二)折前")
        XCTAssertEqual(sheet?.text("A1"), "建筑安装工程费用预算表（表二折前）")
        XCTAssertEqual(sheet?.number("D6"), 512509.64, "折前建安工程费(除税价)")
        XCTAssertEqual(sheet?.number("D9"), 192918.18, "折前人工费")
        XCTAssertEqual(sheet?.text("C10"), "技工总工日X114")
        // 调遣费数值写法与参考折前表一致：174X17X2
        XCTAssertEqual(sheet?.text("H12"), "174X17X2")
    }

    func testTable3AValues() {
        let sheet = exportedBook().sheet(named: "工程量表(表三)甲")
        XCTAssertEqual(sheet?.text("B6"), "TSY1-079")
        XCTAssertEqual(sheet?.text("C6"), "放、绑软光纤 设备机架之间放、绑 15m以下")
        XCTAssertEqual(sheet?.number("F6"), 8)
        XCTAssertEqual(sheet?.number("I6"), 2.32)
        XCTAssertNil(sheet?.number("J6"), "普工为空（null→0→空）")
        guard let totalRow = sheet?.findRow(text: "定额工日合计", inColumn: 3) else {
            XCTFail("未找到定额工日合计行")
            return
        }
        XCTAssertEqual(sheet?.number("I\(totalRow)"), 1269.189)
        XCTAssertEqual(sheet?.number("J\(totalRow)"), 790.666)
    }

    func testTable3BCValues() {
        let b = exportedBook().sheet(named: "机械台班表(表三)乙")
        XCTAssertEqual(b?.text("B6"), "TXL6-005")
        XCTAssertEqual(b?.text("C6"), "光缆成端接头 束状（分纤箱）")
        XCTAssertEqual(b?.number("J6"), 3507.84)
        guard let subB = b?.findRow(text: "小计", inColumn: 7) else {
            XCTFail("表三乙未找到小计行")
            return
        }
        XCTAssertEqual(b?.number("J\(subB)"), 5580)
        let c = exportedBook().sheet(named: "仪器仪表使用表(表三)丙")
        XCTAssertEqual(c?.text("B6"), "TXL1-002")
        XCTAssertEqual(c?.number("J6"), 4308.16)
        guard let subC = c?.findRow(text: "合计", inColumn: 7) else {
            XCTFail("表三丙未找到合计行")
            return
        }
        XCTAssertEqual(c?.number("J\(subC)"), 15455.26)
    }

    func testTable4AValues() {
        let sheet = exportedBook().sheet(named: "主要材料表(表四)甲")
        XCTAssertEqual(sheet?.text("B7"), "『甲供材料』")
        XCTAssertEqual(sheet?.text("B8"), "光缆")
        XCTAssertEqual(sheet?.text("C8"), "6芯")
        XCTAssertEqual(sheet?.number("G8"), 48076.63)
        XCTAssertNil(sheet?.text("J8"), "无 profile 时备注为空")
        guard let sub = sheet?.findRow(text: "甲供材料小计", inColumn: 2),
              let total = sheet?.findRow(text: "总计", inColumn: 2) else {
            XCTFail("未找到表四小计/总计行")
            return
        }
        XCTAssertEqual(sheet?.number("G\(sub)"), 74246.3)
        XCTAssertEqual(sheet?.number("G\(total)"), 74246.3)
    }

    func testTable5Values() {
        let sheet = exportedBook().sheet(named: "工程其他费用表(表五)甲")
        guard let safetyRow = sheet?.findRow(text: "安全生产费", inColumn: 2) else {
            XCTFail("未找到安全生产费行")
            return
        }
        XCTAssertEqual(sheet?.number("E\(safetyRow)"), 10250.19)
        XCTAssertEqual(sheet?.text("C\(safetyRow)"), "折前建安工程费除税价X2%")
        guard let totalRow = sheet?.findRow(text: "   总  计", inColumn: 2) else {
            XCTFail("未找到表五总计行")
            return
        }
        XCTAssertEqual(sheet?.number("E\(totalRow)"), 10250.19)
        // 生产准备费在总计之后、金额为 0（空）
        let prodRow = sheet?.cells.values.first { $0.col == 2 && ($0.text ?? "").contains("生产准备") }?.row
        XCTAssertNotNil(prodRow, "应有生产准备费行")
        if let prodRow { XCTAssertNil(sheet?.number("E\(prodRow)")) }
    }

    func testSubsetExportOnlySelectedSheets() {
        let fixture = ReferenceBookFixture.loadBook()
        let data = buildBudgetBook(
            projectName: fixture.projectName, project: fixture.project, result: fixture.result,
            profile: nil, include: ["报表封面", "工程总表(表一)"])
        let book = XlsxTestReader.book(from: data)
        XCTAssertEqual(book?.sheets.map(\.name), ["报表封面", "工程总表(表一)"])
        let empty = buildBudgetBook(
            projectName: fixture.projectName, project: fixture.project, result: fixture.result,
            profile: nil, include: [])
        XCTAssertEqual(XlsxTestReader.book(from: empty)?.sheets.count, 0)
    }

    func testExportWritesFile() throws {
        let fixture = ReferenceBookFixture.loadBook()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("txbudget-test-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try exportBudgetBook(
            to: url, projectName: fixture.projectName, project: fixture.project,
            result: fixture.result, profile: nil, include: Set(sheetNames))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertGreaterThan((attrs[.size] as? NSNumber)?.intValue ?? 0, 0)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(XlsxTestReader.book(from: data)?.sheets.count, sheetNames.count)
    }

    func testEmptyPathThrows() {
        let fixture = ReferenceBookFixture.loadBook()
        // fileURLWithPath("") 在 Linux 下解析为 cwd，故用 URLComponents 构造真正空路径的 URL。
        var components = URLComponents()
        components.scheme = "file"
        components.path = ""
        guard let emptyURL = components.url else { XCTFail("无法构造空路径 URL"); return }
        XCTAssertThrowsError(try exportBudgetBook(
            to: emptyURL, projectName: fixture.projectName,
            project: fixture.project, result: fixture.result, profile: nil,
            include: Set(sheetNames))) { error in
            XCTAssertEqual(error as? PrintExportError, .emptyPath)
        }
    }

    // MARK: - 有 profile 时按工程量重分组

    private func testProfile() -> ConfigurationProfile {
        let quotas = [QuotaRow(code: "TXL1-001", name: "光(电)缆工程施工测量", unit: "百米", tech: 0.5, labor: 0.25)]
        let materials = [MaterialRow(name: "光缆", spec: "6芯", unit: "m",
                                     priceExcl: 0.68, supply: "甲供", remark: "测试备注")]
        return ConfigurationProfile(libraries: LibrarySet(quotas: quotas, materials: materials))
    }

    private func testProject() -> Project {
        var info = ProjectInfo()
        info.建设项目名称 = "测试项目"
        info.单项工程名称 = "通信线路工程"
        info.建设单位 = "测试建设单位"
        info.表格编号 = "测试-"
        info.编制日期 = "2026-05-13"
        return Project(info: info, quantities: [
            QuantityRow(quota: "TXL1-001", variant: "架空", qty: 10, coef: 1),
            QuantityRow(quota: "TXL1-001", variant: "直埋", qty: 20, coef: 1),
            QuantityRow(quota: "TXL1-001", variant: "架空", qty: 5, coef: 1), // 合并入架空 → 15
            QuantityRow(quota: "TXL1-001", variant: "架空", qty: 100, coef: 0), // 系数 0 跳过
            QuantityRow(quota: "TXL1-001", variant: "直埋", qty: 0, coef: 1), // 数量 0 跳过
            QuantityRow(quota: "UNKNOWN-001", unit: "m", qty: 5, coef: 1), // 孤儿行
            QuantityRow(quota: "不取费", variant: "测试项", qty: 3, coef: 1), // 不取费
        ])
    }

    func testWithProfileTable3ASplitsByVariantAndKeepsOrphans() {
        let fixture = ReferenceBookFixture.loadBook()
        let book = exportedBook(profile: testProfile(), project: testProject(), result: fixture.result)
        let sheet = book.sheet(named: "工程量表(表三)甲")
        XCTAssertEqual(sheet?.text("B6"), "TXL1-001")
        // A1：variant 是完整变体项目名称，非空时直接用 variant，不拼接定额库名。
        XCTAssertEqual(sheet?.text("C6"), "架空")
        XCTAssertEqual(sheet?.number("F6"), 15, "同变体合并（10+5），系数 0 行跳过")
        XCTAssertEqual(sheet?.number("I6"), 7.5)
        XCTAssertEqual(sheet?.number("J6"), 3.75)
        XCTAssertEqual(sheet?.text("C7"), "直埋")
        XCTAssertEqual(sheet?.number("F7"), 20)
        XCTAssertEqual(sheet?.number("I7"), 10)
        XCTAssertEqual(sheet?.text("B8"), "UNKNOWN-001", "孤儿行保留")
        XCTAssertEqual(sheet?.text("E8"), "m", "孤儿行单位取工程量行单位")
        XCTAssertEqual(sheet?.number("F8"), 5)
        XCTAssertNil(sheet?.number("I8"), "孤儿行无工日")
        XCTAssertEqual(sheet?.text("B9"), "不取费")
        XCTAssertEqual(sheet?.text("C9"), "测试项")
        XCTAssertEqual(sheet?.number("F9"), 3)
    }

    // MARK: - A1：真实变体名称（对照 2024 结算书）

    /// TXL3-187（定额库名“…平原 36 芯以下”）+ variant“…平原 6芯” → C6 恰为 variant，不重复。
    /// TXL3-192 三变体 → 拆 3 行，C 列各为 variant 本身。
    /// TXL1-002（定额库名“光（电）缆工程施工测量 架空”）+ variant“光(电)缆工程施工测量 架空”
    /// → C 列为 variant；表三丙 quotaName 同样为 variant（equipRows 共用 displayName）。
    func testDisplayNameRealVariants() {
        let fixture = ReferenceBookFixture.loadBook()
        var info = ProjectInfo()
        info.建设项目名称 = "测试项目"
        info.单项工程名称 = "通信线路工程"
        info.建设单位 = "测试建设单位"
        info.表格编号 = "测试-"
        info.编制日期 = "2026-05-13"
        let project = Project(info: info, quantities: [
            QuantityRow(quota: "TXL3-187", variant: "挂钩法架设架空光缆 平原 6芯", qty: 2, coef: 1),
            QuantityRow(quota: "TXL3-192", variant: "挂钩法架设架空光缆 丘陵、城区、水田 6芯", qty: 3, coef: 1),
            QuantityRow(quota: "TXL3-192", variant: "挂钩法架设架空光缆 丘陵、城区、水田 12芯", qty: 1, coef: 1),
            QuantityRow(quota: "TXL3-192", variant: "挂钩法架设架空光缆 丘陵、城区、水田 24芯", qty: 1, coef: 1),
            QuantityRow(quota: "TXL1-002", variant: "光(电)缆工程施工测量 架空", qty: 10, coef: 1),
        ])
        let quotas = [
            QuotaRow(code: "TXL3-187", name: "挂钩法架设架空光缆 平原 36 芯以下", unit: "千米条",
                     tech: 6.31, labor: 5.13),
            QuotaRow(code: "TXL3-192", name: "挂钩法架设架空光缆 丘陵、城区、水田 36 芯以下", unit: "千米条",
                     tech: 8.68, labor: 6.86),
            QuotaRow(code: "TXL1-002", name: "光（电）缆工程施工测量 架空", unit: "百米",
                     tech: 0.46, labor: 0.12),
        ]
        let profile = ConfigurationProfile(libraries: LibrarySet(
            quotas: quotas,
            instrumentPrices: [InstrumentPriceRow(code: "TXY001", name: "激光测距仪", unit: "台班", price: 119)],
            quotaInstruments: [QuotaInstrumentRow(quota: "TXL1-002", mcode: "TXY001",
                                                  mname: "激光测距仪", unit: "台班", qty: 0.05)]))
        let book = exportedBook(profile: profile, project: project, result: fixture.result)
        let sheet = book.sheet(named: "工程量表(表三)甲")
        XCTAssertEqual(sheet?.text("B6"), "TXL3-187")
        XCTAssertEqual(sheet?.text("C6"), "挂钩法架设架空光缆 平原 6芯")
        XCTAssertEqual(sheet?.text("B7"), "TXL3-192")
        XCTAssertEqual(sheet?.text("C7"), "挂钩法架设架空光缆 丘陵、城区、水田 6芯")
        XCTAssertEqual(sheet?.text("C8"), "挂钩法架设架空光缆 丘陵、城区、水田 12芯")
        XCTAssertEqual(sheet?.text("C9"), "挂钩法架设架空光缆 丘陵、城区、水田 24芯")
        XCTAssertEqual(sheet?.text("B10"), "TXL1-002")
        XCTAssertEqual(sheet?.text("C10"), "光(电)缆工程施工测量 架空")
        // 定额库名不得出现在 C 列（拼接重复的回归断言）。
        for r in 6...10 {
            XCTAssertFalse((sheet?.text("C\(r)") ?? "").contains("36 芯以下"), "C\(r) 不得含定额库名“36 芯以下”")
        }
        let c = book.sheet(named: "仪器仪表使用表(表三)丙")
        XCTAssertEqual(c?.text("B6"), "TXL1-002")
        XCTAssertEqual(c?.text("C6"), "光(电)缆工程施工测量 架空", "表三丙 quotaName 同样为 variant")
        // variant 为空时回落定额库名。
        XCTAssertEqual(displayName(quotas[0], ""), "挂钩法架设架空光缆 平原 36 芯以下")
    }

    func testWithProfileTable4RemarkFromLibrary() {
        let fixture = ReferenceBookFixture.loadBook()
        let book = exportedBook(profile: testProfile(), project: testProject(), result: fixture.result)
        let sheet = book.sheet(named: "主要材料表(表四)甲")
        XCTAssertEqual(sheet?.text("J8"), "测试备注", "备注取材料库 remark")
    }

    func testUnmatchedTable4RowRemark() {
        let fixture = ReferenceBookFixture.loadBook()
        var result = fixture.result
        result.table4A = Table4Result(
            rows: [Table4Row(key: "未知|未知", name: "未知材料", spec: "未知", unit: "m",
                             qty: 1, autoQty: 1, delta: 0, priceExcl: 1, priceVat: 0, priceIncl: 1,
                             amtExcl: 1, amtVat: 0, amtIncl: 1, unmatched: true)],
            totalExcl: 1, totalVat: 0, totalIncl: 1)
        result.table4B = Table4Result()
        result.table4Equip = Table4Result()
        let book = exportedBook(project: testProject(), result: result)
        let sheet = book.sheet(named: "主要材料表(表四)甲")
        XCTAssertEqual(sheet?.text("J8"), "未建档")
    }
}
