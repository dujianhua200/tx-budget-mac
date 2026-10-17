import XCTest
@testable import TXBudget

/// 导出布局 vs 2024 参考结算书逐项比对（镜像 Electron tests/layoutCompare.test.mjs）。
/// 由 fixture 结算书生成 xlsx，解包逐项比对版式 fixture：
/// 表名顺序 / 列宽（容差 0.1）/ 行高（容差 0.6）/ 合并区（集合精确相等）/
/// 页边距（容差 0.001）/ 页面设置 / 表名标题字体（Noto Sans CJK SC + 字号 + 加粗）。
/// 差一处即失败。标题措辞不比对（参考是“结算”口径，导出是“预算”口径）。
final class LayoutCompareTests: XCTestCase {

    private func exportedBook() -> XlsxBook {
        let fixture = ReferenceBookFixture.loadBook()
        let data = buildBudgetBook(
            projectName: fixture.projectName, project: fixture.project, result: fixture.result,
            profile: nil, include: Set(sheetNames))
        guard let book = XlsxTestReader.book(from: data) else {
            XCTFail("导出 xlsx 解析失败")
            return XlsxBook()
        }
        return book
    }

    func testSheetOrderMatchesFixture() {
        let ref = ReferenceBookFixture.loadLayout()
        XCTAssertEqual(ref.sheetOrder, sheetNames)
        let book = exportedBook()
        XCTAssertEqual(book.sheets.map(\.name), sheetNames)
    }

    func testLayoutMatchesReference() {
        let ref = ReferenceBookFixture.loadLayout()
        let book = exportedBook()
        let titleSize: [String: Double] = ["报表封面": 36, "编制说明": 21]
        for name in sheetNames {
            guard let refSheet = ref.sheets[name] else {
                XCTFail("\(name) fixture 中无此表")
                continue
            }
            guard let sheet = book.sheet(named: name) else {
                XCTFail("\(name) 导出缺此表")
                continue
            }
            // 列宽（容差 0.1）
            XCTAssertEqual(sheet.cols.count, refSheet.columnCount, "\(name) 列数")
            for (i, w) in refSheet.widths.enumerated() {
                XCTAssertEqual(sheet.cols[i + 1] ?? -1, w, accuracy: 0.1, "\(name) 列宽 \(i + 1)")
            }
            // 行高（容差 0.6pt）
            XCTAssertEqual(sheet.lastRow, refSheet.rowCount, "\(name) 行数")
            for (i, h) in refSheet.heights.enumerated() {
                XCTAssertEqual(sheet.heights[i + 1] ?? -1, h, accuracy: 0.6, "\(name) 行高 \(i + 1)")
            }
            // 合并区：集合精确相等
            XCTAssertEqual(sheet.merges, Set(refSheet.merges), "\(name) 合并区")
            // 页边距（容差 0.001）
            for k in ["left", "right", "top", "bottom", "header", "footer"] {
                XCTAssertEqual(sheet.margins[k] ?? -1, refSheet.margins[k] ?? -1,
                               accuracy: 0.001, "\(name) 页边距 \(k)")
            }
            // 页面设置
            XCTAssertEqual(sheet.pageSetup["orientation"], refSheet.orientation, "\(name) 横向")
            XCTAssertEqual(sheet.pageSetup["paperSize"], "\(refSheet.paperSize)", "\(name) A4")
            XCTAssertEqual(sheet.fitToPage, refSheet.fitToPage, "\(name) fitToPage 关闭")
            XCTAssertEqual(sheet.pageSetup["scale"], "\(Int(refSheet.scale))", "\(name) 缩放 100")
            // 表名标题字体
            guard let a1 = sheet.cells["A1"], let font = book.font(of: a1) else {
                XCTFail("\(name) A1 无字体")
                continue
            }
            XCTAssertEqual(font.name, "Noto Sans CJK SC", "\(name) 标题字体")
            XCTAssertEqual(font.size, titleSize[name] ?? 18, "\(name) 标题字号")
            XCTAssertEqual(font.bold, true, "\(name) 标题加粗")
            XCTAssertEqual(font.name, refSheet.titleFontName, "\(name) 参考标题字体为 Noto")
            XCTAssertEqual(font.size, refSheet.titleFontSize, "\(name) 参考标题字号与导出一致")
            XCTAssertEqual(refSheet.titleFontBold, true, "\(name) 参考标题加粗")
        }
    }

    func testTable3AHasSingleManualBreak() {
        // 唯一手动分页符在表三甲第 29 行之后。
        let book = exportedBook()
        let sheet = book.sheet(named: "工程量表(表三)甲")
        XCTAssertEqual(sheet?.rowBreaks, [29])
        for name in sheetNames where name != "工程量表(表三)甲" {
            XCTAssertEqual(book.sheet(named: name)?.rowBreaks, [], "\(name) 不应有手动分页符")
        }
    }
}
