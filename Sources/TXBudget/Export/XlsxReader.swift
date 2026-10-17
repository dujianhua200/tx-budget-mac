import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// xlsx 读取器（无第三方库，与 XlsxWriter 配对）。
/// ZIP（中央目录，stored/deflate）+ 纯 Swift DEFLATE 解压 + OOXML（workbook / rels /
/// sharedStrings / styles / 工作表）。对照 Electron 的 ExcelJS 读取行为，见设计文档 §10.2。

// MARK: - 错误

public enum XlsxReadError: Error, LocalizedError, Equatable {
    case notZip
    case corrupt(String)
    case noSheets
    case unsupported(String)

    public var errorDescription: String? {
        switch self {
        case .notZip: return "不是有效的 xlsx 文件（ZIP 结构缺失）"
        case .corrupt(let msg): return "xlsx 文件损坏：\(msg)"
        case .noSheets: return "文件无工作表"
        case .unsupported(let msg): return "不支持的 xlsx 格式：\(msg)"
        }
    }
}

// MARK: - 读入模型

public enum XlsxReadValue: Equatable {
    case blank
    case text(String)
    case number(Double)
    case bool(Bool)
    case date(Date)
    /// 公式单元格：ExcelJS 读出的是 {formula, result} 对象而非缓存值，
    /// 故不取 <v> 缓存值；ImportValue.formula 按 JS 对象语义转换
    /// （Number → NaN，String → "[object Object]"），与 Electron 行集合一致。
    case formula(String)
}

public struct XlsxReadSheet: Equatable {
    public var name: String
    /// 行（1 起）→ 列（1 起）→ 值。缺失 = 空白。
    public var cells: [Int: [Int: XlsxReadValue]]
    public init(name: String, cells: [Int: [Int: XlsxReadValue]] = [:]) {
        self.name = name; self.cells = cells
    }
    public func cell(row: Int, col: Int) -> XlsxReadValue {
        cells[row]?[col] ?? .blank
    }
    public var maxRow: Int { cells.keys.max() ?? 0 }
    public var maxCol: Int { cells.values.flatMap { $0.keys }.max() ?? 0 }
}

public struct XlsxReadBook: Equatable {
    public var sheets: [XlsxReadSheet]
    public init(sheets: [XlsxReadSheet] = []) { self.sheets = sheets }
    public func sheet(named name: String) -> XlsxReadSheet? {
        sheets.first { $0.name == name }
    }
}

// MARK: - DEFLATE（纯 Swift，RFC 1951）

private struct BitReader {
    var bytes: [UInt8]
    var bytePos = 0
    var bitPos = 0 // 0...7，当前字节内已读位数（LSB 先出）

    mutating func bit() throws -> Int {
        guard bytePos < bytes.count else { throw XlsxReadError.corrupt("DEFLATE 数据截断") }
        let v = (Int(bytes[bytePos]) >> bitPos) & 1
        bitPos += 1
        if bitPos == 8 { bitPos = 0; bytePos += 1 }
        return v
    }

    mutating func bits(_ n: Int) throws -> Int {
        var v = 0
        for i in 0..<n { v |= (try bit()) << i }
        return v
    }

    mutating func alignToByte() {
        if bitPos != 0 { bitPos = 0; bytePos += 1 }
    }

    mutating func u16() throws -> Int {
        alignToByte()
        guard bytePos + 2 <= bytes.count else { throw XlsxReadError.corrupt("DEFLATE 数据截断") }
        let v = Int(bytes[bytePos]) | (Int(bytes[bytePos + 1]) << 8)
        bytePos += 2
        return v
    }

    mutating func take(_ n: Int) throws -> [UInt8] {
        alignToByte()
        guard n >= 0, bytePos + n <= bytes.count else { throw XlsxReadError.corrupt("DEFLATE 数据截断") }
        let out = Array(bytes[bytePos..<(bytePos + n)])
        bytePos += n
        return out
    }
}

/// 规范 Huffman 码表：lengths[i] = 符号 i 的码长（0 = 未使用）。
private struct HuffmanTable {
    var counts: [Int] // 下标 = 码长 1...15
    var symbols: [Int] // 按规范码序排列

    init(lengths: [Int]) {
        var counts = [Int](repeating: 0, count: 16)
        for len in lengths where len > 0 { counts[len] += 1 }
        self.counts = counts
        var symbols: [Int] = []
        for len in 1...15 {
            for (sym, l) in lengths.enumerated() where l == len { symbols.append(sym) }
        }
        self.symbols = symbols
    }

    func decode(_ reader: inout BitReader) throws -> Int {
        var code = 0
        var first = 0
        var index = 0
        for len in 1...15 {
            code |= try reader.bit()
            let count = counts[len]
            if code - first < count { return symbols[index + (code - first)] }
            index += count
            first = (first + count) << 1
            code <<= 1
        }
        throw XlsxReadError.corrupt("DEFLATE Huffman 码无效")
    }
}

private let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
private let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
private let distBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
private let distExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
/// 动态 Huffman 码长字母表顺序。
private let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

private func inflateBlock(_ reader: inout BitReader, out: inout [UInt8],
                           lit: HuffmanTable, dist: HuffmanTable) throws {
    while true {
        let sym = try lit.decode(&reader)
        if sym < 256 {
            out.append(UInt8(sym))
        } else if sym == 256 {
            return
        } else {
            let lenIdx = sym - 257
            guard lenIdx >= 0, lenIdx < lengthBase.count else {
                throw XlsxReadError.corrupt("DEFLATE 长度码越界")
            }
            let length = lengthBase[lenIdx] + (try reader.bits(lengthExtra[lenIdx]))
            let dsym = try dist.decode(&reader)
            guard dsym >= 0, dsym < distBase.count else {
                throw XlsxReadError.corrupt("DEFLATE 距离码越界")
            }
            let distance = distBase[dsym] + (try reader.bits(distExtra[dsym]))
            guard distance >= 1, distance <= out.count else {
                throw XlsxReadError.corrupt("DEFLATE 距离超出窗口")
            }
            var from = out.count - distance
            for _ in 0..<length {
                out.append(out[from])
                from += 1
            }
        }
    }
}

/// DEFLATE 解压。expectedSize > 0 时校验输出长度（中央目录的未压缩大小）。
public func inflateData(_ data: Data, expectedSize: Int) throws -> Data {
    var reader = BitReader(bytes: [UInt8](data))
    var out: [UInt8] = []
    if expectedSize > 0 { out.reserveCapacity(expectedSize) }
    while true {
        let bfinal = try reader.bit()
        let btype = try reader.bits(2)
        switch btype {
        case 0: // stored
            let len = try reader.u16()
            let nlen = try reader.u16()
            guard len ^ nlen == 0xFFFF else { throw XlsxReadError.corrupt("DEFLATE stored 块长度校验失败") }
            out += try reader.take(len)
        case 1: // 固定 Huffman
            var litLengths = [Int](repeating: 0, count: 288)
            for i in 0..<144 { litLengths[i] = 8 }
            for i in 144..<256 { litLengths[i] = 9 }
            for i in 256..<280 { litLengths[i] = 7 }
            for i in 280..<288 { litLengths[i] = 8 }
            let distLengths = [Int](repeating: 5, count: 32)
            try inflateBlock(&reader, out: &out, lit: HuffmanTable(lengths: litLengths), dist: HuffmanTable(lengths: distLengths))
        case 2: // 动态 Huffman
            let hlit = try reader.bits(5) + 257
            let hdist = try reader.bits(5) + 1
            let hclen = try reader.bits(4) + 4
            guard hlit <= 286, hdist <= 32, hclen <= 19 else {
                throw XlsxReadError.corrupt("DEFLATE 动态头越界")
            }
            var clLengths = [Int](repeating: 0, count: 19)
            for i in 0..<hclen { clLengths[codeLengthOrder[i]] = try reader.bits(3) }
            let clTable = HuffmanTable(lengths: clLengths)
            var lengths = [Int](repeating: 0, count: hlit + hdist)
            var i = 0
            while i < lengths.count {
                let sym = try clTable.decode(&reader)
                if sym <= 15 {
                    lengths[i] = sym
                    i += 1
                } else if sym == 16 {
                    guard i > 0 else { throw XlsxReadError.corrupt("DEFLATE 重复码无前值") }
                    let repeatCount = 3 + (try reader.bits(2))
                    let prev = lengths[i - 1]
                    for _ in 0..<repeatCount {
                        guard i < lengths.count else { throw XlsxReadError.corrupt("DEFLATE 码长溢出") }
                        lengths[i] = prev
                        i += 1
                    }
                } else if sym == 17 {
                    let repeatCount = 3 + (try reader.bits(3))
                    for _ in 0..<repeatCount {
                        guard i < lengths.count else { throw XlsxReadError.corrupt("DEFLATE 码长溢出") }
                        lengths[i] = 0
                        i += 1
                    }
                } else if sym == 18 {
                    let repeatCount = 11 + (try reader.bits(7))
                    for _ in 0..<repeatCount {
                        guard i < lengths.count else { throw XlsxReadError.corrupt("DEFLATE 码长溢出") }
                        lengths[i] = 0
                        i += 1
                    }
                } else {
                    throw XlsxReadError.corrupt("DEFLATE 码长码无效")
                }
            }
            let litTable = HuffmanTable(lengths: Array(lengths[0..<hlit]))
            let distTable = HuffmanTable(lengths: Array(lengths[hlit..<(hlit + hdist)]))
            try inflateBlock(&reader, out: &out, lit: litTable, dist: distTable)
        default:
            throw XlsxReadError.corrupt("DEFLATE 保留块类型")
        }
        if bfinal == 1 { break }
    }
    if expectedSize > 0, out.count != expectedSize {
        throw XlsxReadError.corrupt("DEFLATE 解压后长度不符（期望 \(expectedSize)，实际 \(out.count)）")
    }
    return Data(out)
}

// MARK: - ZIP（中央目录）

private struct ZipEntry {
    var name: String
    var method: Int
    var flags: Int
    var compSize: Int
    var uncompSize: Int
    var localOffset: Int
}

private func u16le(_ bytes: [UInt8], _ o: Int) -> Int {
    Int(bytes[o]) | (Int(bytes[o + 1]) << 8)
}

private func u32le(_ bytes: [UInt8], _ o: Int) -> Int {
    Int(bytes[o]) | (Int(bytes[o + 1]) << 8) | (Int(bytes[o + 2]) << 16) | (Int(bytes[o + 3]) << 24)
}

/// 解析 ZIP 中央目录并解出全部条目。支持 data descriptor（中央目录含真实大小）。
private func unzipEntries(_ data: Data) throws -> [String: Data] {
    let bytes = [UInt8](data)
    guard bytes.count >= 22 else { throw XlsxReadError.notZip }
    // EOCD 在末尾 64KB + 22 字节内。
    let searchStart = max(0, bytes.count - 65557)
    var eocd = -1
    var i = bytes.count - 22
    while i >= searchStart {
        if u32le(bytes, i) == 0x06054B50 { eocd = i; break }
        i -= 1
    }
    guard eocd >= 0 else { throw XlsxReadError.notZip }
    let total = u16le(bytes, eocd + 10)
    let cdOffset = u32le(bytes, eocd + 16)
    let cdSize = u32le(bytes, eocd + 12)
    guard cdOffset + cdSize <= bytes.count else { throw XlsxReadError.corrupt("中央目录越界") }
    var entries: [ZipEntry] = []
    var p = cdOffset
    for _ in 0..<total {
        guard p + 46 <= bytes.count, u32le(bytes, p) == 0x02014B50 else {
            throw XlsxReadError.corrupt("中央目录条目签名无效")
        }
        let flags = u16le(bytes, p + 8)
        let method = u16le(bytes, p + 10)
        let compSize = u32le(bytes, p + 20)
        let uncompSize = u32le(bytes, p + 24)
        let nameLen = u16le(bytes, p + 28)
        let extraLen = u16le(bytes, p + 30)
        let commentLen = u16le(bytes, p + 32)
        let localOffset = u32le(bytes, p + 42)
        guard p + 46 + nameLen + extraLen + commentLen <= bytes.count else {
            throw XlsxReadError.corrupt("中央目录条目越界")
        }
        let nameBytes = Array(bytes[(p + 46)..<(p + 46 + nameLen)])
        let name = String(bytes: nameBytes, encoding: .utf8)
            ?? String(bytes: nameBytes, encoding: .isoLatin1)
            ?? ""
        // ZIP64 占位（0xFFFFFFFF）不支持。
        if compSize == 0xFFFFFFFF || uncompSize == 0xFFFFFFFF || localOffset == 0xFFFFFFFF {
            throw XlsxReadError.unsupported("ZIP64")
        }
        entries.append(ZipEntry(name: name, method: method, flags: flags,
                                compSize: compSize, uncompSize: uncompSize, localOffset: localOffset))
        p += 46 + nameLen + extraLen + commentLen
    }
    var out: [String: Data] = [:]
    for e in entries {
        guard e.localOffset + 30 <= bytes.count, u32le(bytes, e.localOffset) == 0x04034B50 else {
            throw XlsxReadError.corrupt("本地文件头签名无效：\(e.name)")
        }
        if e.flags & 0x01 != 0 { throw XlsxReadError.unsupported("加密 ZIP 条目：\(e.name)") }
        let nameLen = u16le(bytes, e.localOffset + 26)
        let extraLen = u16le(bytes, e.localOffset + 28)
        let dataStart = e.localOffset + 30 + nameLen + extraLen
        guard dataStart + e.compSize <= bytes.count else {
            throw XlsxReadError.corrupt("条目数据越界：\(e.name)")
        }
        let raw = Data(bytes[dataStart..<(dataStart + e.compSize)])
        switch e.method {
        case 0:
            out[e.name] = raw
        case 8:
            out[e.name] = try inflateData(raw, expectedSize: e.uncompSize)
        default:
            throw XlsxReadError.unsupported("ZIP 压缩方法 \(e.method)：\(e.name)")
        }
    }
    return out
}

// MARK: - XML 小树（生产侧，与测试的 XlsxTestReader 独立）

private final class XmlNode {
    let name: String
    var attrs: [String: String]
    var children: [XmlNode] = []
    var text = ""
    init(name: String, attrs: [String: String]) { self.name = name; self.attrs = attrs }
    func child(_ name: String) -> XmlNode? { children.first { $0.name == name } }
    func children(_ name: String) -> [XmlNode] { children.filter { $0.name == name } }
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
    var parseError: Error?
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
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}

private func parseXml(_ data: Data, part: String) throws -> XmlNode {
    let builder = XmlTreeBuilder()
    let parser = XMLParser(data: data)
    parser.delegate = builder
    guard parser.parse(), let root = builder.root else {
        throw XlsxReadError.corrupt("XML 解析失败：\(part)（\(builder.parseError?.localizedDescription ?? "未知错误")）")
    }
    return root
}

// MARK: - 单元格引用 / 日期格式

private func parseCellRef(_ ref: String) -> (row: Int, col: Int)? {
    var col = 0
    var idx = ref.startIndex
    while idx < ref.endIndex, let v = ref[idx].asciiValue, v >= 65, v <= 90 {
        col = col * 26 + Int(v - 64)
        idx = ref.index(after: idx)
    }
    guard idx < ref.endIndex, let row = Int(ref[idx...]) else { return nil }
    return (row, col)
}

/// 内置日期 numFmtId（ECMA-376）：14–22、27–36、45–47、49、50、57。
private let builtinDateFmtIds: Set<Int> = [14, 15, 16, 17, 18, 19, 20, 21, 22,
                                           27, 28, 29, 30, 31, 32, 33, 34, 35, 36,
                                           45, 46, 47, 49, 50, 57]

/// 自定义数字格式是否为日期格式（启发式：去引号 / [...] 后含 y/m/d/h 日期令牌）。
private func isCustomDateFormat(_ code: String) -> Bool {
    var s = ""
    var inQuote = false
    var inBracket = 0
    for ch in code {
        if ch == "\"" { inQuote.toggle(); continue }
        if inQuote { continue }
        if ch == "[" { inBracket += 1; continue }
        if ch == "]" { inBracket = max(0, inBracket - 1); continue }
        if inBracket > 0 { continue }
        s.append(ch)
    }
    let lower = s.lowercased()
    let hasDateToken = lower.contains("yyyy") || lower.contains("yy")
        || lower.contains("mm") || lower.contains("dd")
        || lower.contains("hh") || lower.contains("ss")
    // 排除纯数字/货币格式误判：必须含 y 或（m 且 d）或 h。
    return hasDateToken && (lower.contains("y") || (lower.contains("m") && lower.contains("d")) || lower.contains("h"))
}

/// Excel 序号 → Date（标准公式；序号 ≥ 61 时准确，1900 闰年 bug 由 25569 常数消化）。
private func excelSerialToDate(_ serial: Double) -> Date {
    Date(timeIntervalSince1970: (serial - 25569) * 86400)
}

// MARK: - 读取入口

public enum XlsxReader {
    public static func read(data: Data) throws -> XlsxReadBook {
        let entries = try unzipEntries(data)
        guard let wbXml = entries["xl/workbook.xml"] else {
            throw XlsxReadError.corrupt("缺 xl/workbook.xml")
        }
        let wb = try parseXml(wbXml, part: "xl/workbook.xml")
        // 共享字符串。
        var sharedStrings: [String] = []
        if let ssData = entries["xl/sharedStrings.xml"] {
            let ss = try parseXml(ssData, part: "xl/sharedStrings.xml")
            for si in ss.children("si") {
                sharedStrings.append(si.descendants("t").map { $0.text }.joined())
            }
        }
        // 样式：numFmtId → 是否日期格式；cellXfs 顺序 → numFmtId。
        var isDateFmtByXf: [Bool] = []
        if let stylesData = entries["xl/styles.xml"] {
            let styles = try parseXml(stylesData, part: "xl/styles.xml")
            var customFmts: [Int: String] = [:]
            if let numFmts = styles.child("numFmts") {
                for n in numFmts.children("numFmt") {
                    if let id = n.attrs["numFmtId"].flatMap(Int.init),
                       let code = n.attrs["formatCode"] {
                        customFmts[id] = code
                    }
                }
            }
            func isDateFmt(_ id: Int) -> Bool {
                if builtinDateFmtIds.contains(id) { return true }
                if let code = customFmts[id] { return isCustomDateFormat(code) }
                return false
            }
            if let xfs = styles.child("cellXfs") {
                for xf in xfs.children("xf") {
                    isDateFmtByXf.append(isDateFmt(xf.attrs["numFmtId"].flatMap(Int.init) ?? 0))
                }
            }
        }
        // workbook rels：rId → Target。
        var relTargets: [String: String] = [:]
        if let relsData = entries["xl/_rels/workbook.xml.rels"] {
            let rels = try parseXml(relsData, part: "xl/_rels/workbook.xml.rels")
            for rel in rels.children("Relationship") {
                if let id = rel.attrs["Id"], let target = rel.attrs["Target"] {
                    relTargets[id] = target
                }
            }
        }
        guard let sheetsNode = wb.child("sheets") else { throw XlsxReadError.noSheets }
        let sheetNodes = sheetsNode.children("sheet")
        guard !sheetNodes.isEmpty else { throw XlsxReadError.noSheets }
        var book = XlsxReadBook()
        for (i, sheetNode) in sheetNodes.enumerated() {
            guard let name = sheetNode.attrs["name"] else { continue }
            var path: String?
            if let rid = sheetNode.attrs["r:id"], let target = relTargets[rid] {
                if target.hasPrefix("/") {
                    path = String(target.dropFirst())
                } else if target.hasPrefix("xl/") {
                    path = target
                } else {
                    path = "xl/" + target
                }
            } else {
                path = "xl/worksheets/sheet\(i + 1).xml"
            }
            guard let path, let sheetData = entries[path] else { continue }
            let sheetXml = try parseXml(sheetData, part: path)
            var cells: [Int: [Int: XlsxReadValue]] = [:]
            var fallbackCol = 0
            if let sheetDataNode = sheetXml.child("sheetData") {
                for rowNode in sheetDataNode.children("row") {
                    let rowNum = rowNode.attrs["r"].flatMap(Int.init)
                    var fallbackRow = (cells.keys.max() ?? 0) + 1
                    let row = rowNum ?? fallbackRow
                    fallbackRow = row
                    fallbackCol = 0
                    for cNode in rowNode.children("c") {
                        fallbackCol += 1
                        let (r, c) = cNode.attrs["r"].flatMap(parseCellRef) ?? (row, fallbackCol)
                        let styleIdx = cNode.attrs["s"].flatMap(Int.init)
                        let isDate = styleIdx.map { $0 < isDateFmtByXf.count ? isDateFmtByXf[$0] : false } ?? false
                        let t = cNode.attrs["t"]
                        let value: XlsxReadValue
                        if let fNode = cNode.child("f") {
                            // 公式单元格一律按对象语义处理，不取缓存值（见 XlsxReadValue.formula）。
                            value = .formula(fNode.text)
                        } else if let isNode = cNode.child("is") {
                            value = .text(isNode.descendants("t").map { $0.text }.joined())
                        } else if t == "s" {
                            let idx = cNode.child("v").flatMap { Int($0.text.trimmingCharacters(in: .whitespaces)) }
                            value = idx.map { $0 < sharedStrings.count ? .text(sharedStrings[$0]) : .text("") } ?? .blank
                        } else if t == "b" {
                            value = .bool(cNode.child("v")?.text.trimmingCharacters(in: .whitespaces) == "1")
                        } else if t == "e" {
                            value = .blank
                        } else if t == "str" {
                            value = cNode.child("v").map { .text($0.text) } ?? .blank
                        } else if let vNode = cNode.child("v") {
                            if let num = Double(vNode.text.trimmingCharacters(in: .whitespaces)) {
                                value = isDate ? .date(excelSerialToDate(num)) : .number(num)
                            } else {
                                value = .blank
                            }
                        } else {
                            value = .blank
                        }
                        if cells[r] == nil { cells[r] = [:] }
                        cells[r]?[c] = value
                    }
                }
            }
            book.sheets.append(XlsxReadSheet(name: name, cells: cells))
        }
        guard !book.sheets.isEmpty else { throw XlsxReadError.noSheets }
        return book
    }
}
