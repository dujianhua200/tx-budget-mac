import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import TXBudget

/// 测试用最小 OOXML 读取器：只支持 XlsxWriter 产出的 stored 条目 + 直写 XML。
/// 用途：布局对比 / 导出值断言。LibreOffice 重算的往返校验不在 Swift 测试内（本地手动验）。

final class XmlNode {
    let name: String
    var attrs: [String: String]
    var children: [XmlNode] = []
    var text = ""
    init(name: String, attrs: [String: String]) { self.name = name; self.attrs = attrs }
    func child(_ name: String) -> XmlNode? { children.first { $0.name == name } }
    func children(_ name: String) -> [XmlNode] { children.filter { $0.name == name } }
    /// 递归找第一个指定名后代。
    func descendant(_ name: String) -> XmlNode? {
        for c in children {
            if c.name == name { return c }
            if let d = c.descendant(name) { return d }
        }
        return nil
    }
    func descendants(_ name: String) -> [XmlNode] {
        var out: [XmlNode] = []
        for c in children {
            if c.name == name { out.append(c) }
            out += c.descendants(name)
        }
        return out
    }
}

private final class XmlTreeBuilder: NSObject, XMLParserDelegate {
    var root: XmlNode?
    var stack: [XmlNode] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = XmlNode(name: elementName, attrs: attributeDict)
        if let top = stack.last { top.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        _ = stack.popLast()
    }
}

struct XlsxBook {
    struct Font {
        var name: String?
        var size: Double?
        var bold = false
        var color: String?
    }
    struct Xf {
        var fontId = 0
        var numFmtId = 0
        var borderId = 0
    }
    struct Cell {
        var ref: String
        var row: Int
        var col: Int
        var style: Int?
        var type: String?
        var text: String?
        var number: Double?
    }
    struct Sheet {
        var name: String
        var cols: [Int: Double] = [:]
        var heights: [Int: Double] = [:]
        var merges: Set<String> = []
        var cells: [String: Cell] = [:]
        var margins: [String: Double] = [:]
        var pageSetup: [String: String] = [:]
        var fitToPage: Bool?
        var rowBreaks: [Int] = []
        var lastRow = 0
        var lastCol = 0
        func text(_ ref: String) -> String? { cells[ref]?.text }
        func number(_ ref: String) -> Double? { cells[ref]?.number }
        /// 找到某列中值为 text 的第一个单元格引用（按行序）。
        func findRow(text: String, inColumn col: Int? = nil) -> Int? {
            let sorted = cells.values.sorted { $0.row < $1.row }
            for c in sorted where c.text == text && (col == nil || c.col == col) { return c.row }
            return nil
        }
    }

    var sheets: [Sheet] = []
    var fonts: [Font] = []
    var xfs: [Xf] = []
    var numFmts: [Int: String] = [:]

    func sheet(named name: String) -> Sheet? { sheets.first { $0.name == name } }
    func font(of cell: Cell) -> Font? {
        guard let s = cell.style, s < xfs.count else { return nil }
        let fid = xfs[s].fontId
        return fid < fonts.count ? fonts[fid] : nil
    }
    func numFmt(of cell: Cell) -> String? {
        guard let s = cell.style, s < xfs.count else { return nil }
        let id = xfs[s].numFmtId
        switch id {
        case 0: return "General"
        case 4: return "#,##0.00"
        case 164: return numFmts[164] ?? "0.000"
        case 165: return numFmts[165] ?? "#,##0.000"
        case 166: return numFmts[166] ?? "#,##0.00000"
        default: return numFmts[id]
        }
    }
}

enum XlsxTestReader {
    /// 解包 stored-only ZIP（XlsxWriter 产出）。遇到非 stored 条目直接返回 nil。
    static func unzipStored(_ data: Data) -> [String: Data]? {
        let bytes = [UInt8](data)
        func u16(_ o: Int) -> Int { Int(bytes[o]) | (Int(bytes[o + 1]) << 8) }
        func u32(_ o: Int) -> Int {
            Int(bytes[o]) | (Int(bytes[o + 1]) << 8) | (Int(bytes[o + 2]) << 16) | (Int(bytes[o + 3]) << 24)
        }
        var out: [String: Data] = [:]
        var offset = 0
        while offset + 30 <= bytes.count {
            guard u32(offset) == 0x04034B50 else { break }
            let flags = u16(offset + 6)
            let method = u16(offset + 8)
            guard method == 0, flags & 0x08 == 0 else { return nil }
            let compSize = u32(offset + 18)
            let nameLen = u16(offset + 26)
            let extraLen = u16(offset + 28)
            guard offset + 30 + nameLen + extraLen + compSize <= bytes.count else { return nil }
            let nameBytes = bytes[(offset + 30)..<(offset + 30 + nameLen)]
            guard let name = String(bytes: nameBytes, encoding: .utf8) else { return nil }
            let start = offset + 30 + nameLen + extraLen
            out[name] = Data(bytes[start..<(start + compSize)])
            offset = start + compSize
        }
        return out
    }

    static func parseXml(_ data: Data) -> XmlNode? {
        let builder = XmlTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        guard parser.parse() else { return nil }
        return builder.root
    }

    static func parseColRef(_ ref: String) -> (row: Int, col: Int)? {
        var col = 0
        var idx = ref.startIndex
        while idx < ref.endIndex, let v = ref[idx].asciiValue, v >= 65, v <= 90 {
            col = col * 26 + Int(v - 64)
            idx = ref.index(after: idx)
        }
        guard idx < ref.endIndex, let row = Int(ref[idx...]) else { return nil }
        return (row, col)
    }

    static func book(from data: Data) -> XlsxBook? {
        guard let entries = unzipStored(data),
              let wbXml = entries["xl/workbook.xml"].flatMap(parseXml),
              let relsXml = entries["xl/_rels/workbook.xml.rels"].flatMap(parseXml),
              let stylesXml = entries["xl/styles.xml"].flatMap(parseXml) else { return nil }
        var book = XlsxBook()
        // styles
        if let numFmtsNode = stylesXml.child("numFmts") {
            for n in numFmtsNode.children("numFmt") {
                if let id = n.attrs["numFmtId"].flatMap(Int.init), let code = n.attrs["formatCode"] {
                    book.numFmts[id] = code
                }
            }
        }
        if let fontsNode = stylesXml.child("fonts") {
            for f in fontsNode.children("font") {
                var font = XlsxBook.Font()
                font.name = f.child("name")?.attrs["val"]
                font.size = f.child("sz")?.attrs["val"].flatMap(Double.init)
                font.bold = f.child("b") != nil
                font.color = f.child("color")?.attrs["rgb"]
                book.fonts.append(font)
            }
        }
        if let xfsNode = stylesXml.child("cellXfs") {
            for x in xfsNode.children("xf") {
                var xf = XlsxBook.Xf()
                xf.fontId = x.attrs["fontId"].flatMap(Int.init) ?? 0
                xf.numFmtId = x.attrs["numFmtId"].flatMap(Int.init) ?? 0
                xf.borderId = x.attrs["borderId"].flatMap(Int.init) ?? 0
                book.xfs.append(xf)
            }
        }
        // workbook rels: rId -> target
        var relTargets: [String: String] = [:]
        for rel in relsXml.children("Relationship") {
            if let id = rel.attrs["Id"], let target = rel.attrs["Target"] {
                relTargets[id] = target
            }
        }
        // sheets in workbook order
        guard let sheetsNode = wbXml.child("sheets") else { return nil }
        for sheetNode in sheetsNode.children("sheet") {
            guard let name = sheetNode.attrs["name"],
                  let rid = sheetNode.attrs["r:id"],
                  let target = relTargets[rid] else { continue }
            let path = "xl/" + target
            guard let sheetXml = entries[path].flatMap(parseXml) else { continue }
            var sheet = XlsxBook.Sheet(name: name)
            if let dim = sheetXml.child("dimension")?.attrs["ref"] {
                let parts = dim.split(separator: ":")
                if let last = parts.last, let (r, c) = parseColRef(String(last)) {
                    sheet.lastRow = r
                    sheet.lastCol = c
                }
            }
            if let colsNode = sheetXml.child("cols") {
                for col in colsNode.children("col") {
                    guard let min = col.attrs["min"].flatMap(Int.init),
                          let max = col.attrs["max"].flatMap(Int.init),
                          let w = col.attrs["width"].flatMap(Double.init) else { continue }
                    for c in min...max { sheet.cols[c] = w }
                }
            }
            if let dataNode = sheetXml.child("sheetData") {
                for rowNode in dataNode.children("row") {
                    guard let r = rowNode.attrs["r"].flatMap(Int.init) else { continue }
                    if let ht = rowNode.attrs["ht"].flatMap(Double.init) { sheet.heights[r] = ht }
                    sheet.lastRow = max(sheet.lastRow, r)
                    for cNode in rowNode.children("c") {
                        guard let ref = cNode.attrs["r"], let (row, col) = parseColRef(ref) else { continue }
                        var cell = XlsxBook.Cell(ref: ref, row: row, col: col, style: nil, type: nil, text: nil, number: nil)
                        cell.style = cNode.attrs["s"].flatMap(Int.init)
                        cell.type = cNode.attrs["t"]
                        if let isNode = cNode.child("is"), let tNode = isNode.child("t") {
                            cell.text = tNode.text
                        } else if let vNode = cNode.child("v") {
                            cell.number = Double(vNode.text)
                            cell.text = vNode.text
                        }
                        sheet.cells[ref] = cell
                        sheet.lastCol = max(sheet.lastCol, col)
                    }
                }
            }
            if let mergesNode = sheetXml.child("mergeCells") {
                for m in mergesNode.children("mergeCell") {
                    if let ref = m.attrs["ref"] { sheet.merges.insert(ref) }
                }
            }
            if let marginsNode = sheetXml.child("pageMargins") {
                for (k, v) in marginsNode.attrs { sheet.margins[k] = Double(v) }
            }
            if let setupNode = sheetXml.child("pageSetup") {
                sheet.pageSetup = setupNode.attrs
            }
            if let setupPr = sheetXml.descendant("pageSetUpPr"), let fit = setupPr.attrs["fitToPage"] {
                sheet.fitToPage = (fit == "1" || fit.lowercased() == "true")
            } else if let fit = sheet.pageSetup["fitToPage"] {
                sheet.fitToPage = (fit == "1" || fit.lowercased() == "true")
            }
            if let breaksNode = sheetXml.child("rowBreaks") {
                for b in breaksNode.children("brk") {
                    if let id = b.attrs["id"].flatMap(Int.init) { sheet.rowBreaks.append(id) }
                }
            }
            book.sheets.append(sheet)
        }
        return book
    }
}
