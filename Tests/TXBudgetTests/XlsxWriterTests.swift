import XCTest
@testable import TXBudget

/// XlsxWriter 单元测试：CRC32 已知向量、ZIP 结构、样式去重、XML 转义。
final class XlsxWriterTests: XCTestCase {

    private func makeSheet(name: String = "T") -> XlsxSheet {
        XlsxSheet(name: name, widths: [10, 10],
                  pageSetup: XlsxPageSetup(margins: PageMargins(left: 0.8, right: 1.39, top: 0.98,
                                                                 bottom: 0.98, header: 0.51, footer: 0.51)))
    }

    func testCRC32KnownVectors() {
        XCTAssertEqual(crc32(Data()), 0)
        XCTAssertEqual(crc32(Data("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(crc32(Data("hello".utf8)), 0x3610A686)
    }

    func testZipStoredRoundTrip() {
        let data = zipStored(entries: [
            (name: "a.txt", data: Data("hello".utf8)),
            (name: "dir/b.xml", data: Data("<x/>".utf8)),
            (name: "empty", data: Data()),
        ])
        // ZIP 签名（文件头）+ 末尾中央目录签名（EOCD，倒数 22 字节处）
        XCTAssertEqual(data.prefix(4), Data([0x50, 0x4B, 0x03, 0x04]))
        XCTAssertEqual(data.dropFirst(data.count - 22).prefix(4), Data([0x50, 0x4B, 0x05, 0x06]))
        let entries = XlsxTestReader.unzipStored(data)
        XCTAssertEqual(entries?.count, 3)
        XCTAssertEqual(entries?["a.txt"], Data("hello".utf8))
        XCTAssertEqual(entries?["dir/b.xml"], Data("<x/>".utf8))
        XCTAssertEqual(entries?["empty"], Data())
    }

    func testSheetXmlEscapingAndTypes() {
        var sheet = makeSheet()
        let style = XlsxCellStyle(font: .init(name: "宋体", size: 10))
        sheet.setCell(row: 1, col: 1, value: .text("a&b<c>\"d'e\n第二行\tTab"), style: style)
        sheet.setCell(row: 1, col: 2, value: .number(12.5), style: style)
        sheet.setCell(row: 2, col: 1, value: .text("控制\u{01}字符\u{07}丢弃"), style: style)
        let data = XlsxWorkbook(sheets: [sheet]).build()
        let book = XlsxTestReader.book(from: data)
        let parsed = book?.sheet(named: "T")
        XCTAssertEqual(parsed?.text("A1"), "a&b<c>\"d'e\n第二行\tTab")
        XCTAssertEqual(parsed?.number("B1"), 12.5)
        XCTAssertEqual(parsed?.text("A2"), "控制字符丢弃")
        // 原始 XML 里不应出现裸 & < >（转义后应为 &amp; &lt; &gt;）
        let entries = XlsxTestReader.unzipStored(data)
        let xml = String(data: entries?["xl/worksheets/sheet1.xml"] ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("a&amp;b&lt;c&gt;&quot;d&apos;e"))
        XCTAssertFalse(xml.contains("a&b<c>"))
    }

    func testStyleDedup() {
        var sheet = makeSheet()
        let shared = XlsxCellStyle(font: .init(name: "宋体", size: 10))
        for r in 1...50 {
            sheet.setCell(row: r, col: 1, value: .number(Double(r)), style: shared)
            sheet.setCell(row: r, col: 2, value: .number(Double(r)), style: shared)
        }
        let data = XlsxWorkbook(sheets: [sheet]).build()
        let entries = XlsxTestReader.unzipStored(data)
        guard let styles = entries?["xl/styles.xml"].flatMap(XlsxTestReader.parseXml),
              let fonts = styles.child("fonts"),
              let xfs = styles.child("cellXfs") else {
            XCTFail("styles.xml 解析失败")
            return
        }
        // 相同样式只注册一个字体 / 一个 xf（+ 默认）
        XCTAssertEqual(fonts.children("font").count, 2)
        XCTAssertEqual(xfs.children("xf").count, 2)
    }

    func testNumberFormats() {
        var sheet = makeSheet()
        sheet.setCell(row: 1, col: 1, value: .number(1.5), style: .init(numFmt: "#,##0.00"))
        sheet.setCell(row: 2, col: 1, value: .number(1.23456), style: .init(numFmt: "0.000"))
        sheet.setCell(row: 3, col: 1, value: .number(1.23456), style: .init(numFmt: "#,##0.000"))
        sheet.setCell(row: 4, col: 1, value: .number(1.23456), style: .init(numFmt: "#,##0.00000"))
        let data = XlsxWorkbook(sheets: [sheet]).build()
        let book = XlsxTestReader.book(from: data)
        let parsed = book?.sheet(named: "T")
        XCTAssertEqual(parsed?.cells["A1"].flatMap { book?.numFmt(of: $0) }, "#,##0.00")
        XCTAssertEqual(parsed?.cells["A2"].flatMap { book?.numFmt(of: $0) }, "0.000")
        XCTAssertEqual(parsed?.cells["A3"].flatMap { book?.numFmt(of: $0) }, "#,##0.000")
        XCTAssertEqual(parsed?.cells["A4"].flatMap { book?.numFmt(of: $0) }, "#,##0.00000")
    }

    func testMergesAndBreaksAndMargins() {
        var sheet = makeSheet()
        sheet.merge("A1:B1")
        sheet.merge("A1:B1") // 重复合并去重
        sheet.setCell(row: 1, col: 1, value: .text("x"))
        sheet.rowBreaks = [29]
        let data = XlsxWorkbook(sheets: [sheet]).build()
        let book = XlsxTestReader.book(from: data)
        let parsed = book?.sheet(named: "T")
        XCTAssertEqual(parsed?.merges, ["A1:B1"])
        XCTAssertEqual(parsed?.rowBreaks, [29])
        XCTAssertEqual(parsed?.margins["left"] ?? -1, 0.8, accuracy: 0.001)
        XCTAssertEqual(parsed?.margins["right"] ?? -1, 1.39, accuracy: 0.001)
    }

    func testStyledBlankCellWritten() {
        var sheet = makeSheet()
        let style = XlsxCellStyle(font: .init(name: "宋体", size: 10),
                                  border: .init(top: .thin, bottom: .thin, left: .thin, right: .thin))
        sheet.setCell(row: 1, col: 1, value: .blank, style: style)
        sheet.setCell(row: 1, col: 2, value: .blank, style: nil)
        let data = XlsxWorkbook(sheets: [sheet]).build()
        let entries = XlsxTestReader.unzipStored(data)
        let xml = String(data: entries?["xl/worksheets/sheet1.xml"] ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("r=\"A1\""))
        XCTAssertFalse(xml.contains("r=\"B1\""))
    }
}
