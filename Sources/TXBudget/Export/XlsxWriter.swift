import Foundation

/// xlsx 直写（无第三方库）：ZIP stored 条目 + XML。
/// 对照 Electron 版（ExcelJS 生成）：数值单元格为数值型，文本为 inlineStr，
/// 样式（字体/对齐/数字格式/边框）去重进 styles.xml，合并区/页边距/页面设置/手动分页符齐全。
/// ZIP 用 stored（不压缩）条目：零依赖、最易验证正确；文件稍大可接受。

// MARK: - 单元格模型

public enum XlsxCellValue: Equatable {
    case blank
    case text(String)
    case number(Double)
}

public struct XlsxFont: Equatable, Hashable {
    public var name: String
    public var size: Double
    public var bold: Bool
    public init(name: String, size: Double, bold: Bool = false) {
        self.name = name; self.size = size; self.bold = bold
    }
}

public enum XlsxHAlign: String, Equatable, Hashable {
    case left, center, right
}

public enum XlsxVAlign: String, Equatable, Hashable {
    case center, top
}

public struct XlsxAlignment: Equatable, Hashable {
    public var horizontal: XlsxHAlign
    public var vertical: XlsxVAlign
    public var wrapText: Bool
    public init(horizontal: XlsxHAlign, vertical: XlsxVAlign, wrapText: Bool = true) {
        self.horizontal = horizontal; self.vertical = vertical; self.wrapText = wrapText
    }
}

public enum XlsxBorderStyle: String, Equatable, Hashable {
    case none, thin, medium
}

public struct XlsxBorder: Equatable, Hashable {
    public var top: XlsxBorderStyle
    public var bottom: XlsxBorderStyle
    public var left: XlsxBorderStyle
    public var right: XlsxBorderStyle
    public init(top: XlsxBorderStyle = .none, bottom: XlsxBorderStyle = .none,
                left: XlsxBorderStyle = .none, right: XlsxBorderStyle = .none) {
        self.top = top; self.bottom = bottom; self.left = left; self.right = right
    }
    public static let none = XlsxBorder()
}

public struct XlsxCellStyle: Equatable, Hashable {
    public var font: XlsxFont?
    public var alignment: XlsxAlignment?
    public var numFmt: String?
    public var border: XlsxBorder
    public init(font: XlsxFont? = nil, alignment: XlsxAlignment? = nil,
                numFmt: String? = nil, border: XlsxBorder = .none) {
        self.font = font; self.alignment = alignment; self.numFmt = numFmt; self.border = border
    }
}

public struct XlsxCell: Equatable {
    public var value: XlsxCellValue
    public var style: XlsxCellStyle?
    public init(value: XlsxCellValue = .blank, style: XlsxCellStyle? = nil) {
        self.value = value; self.style = style
    }
}

public struct XlsxRow: Equatable {
    public var height: Double?
    public var cells: [Int: XlsxCell] // 列（1 起）→ 单元格
    public init(height: Double? = nil, cells: [Int: XlsxCell] = [:]) {
        self.height = height; self.cells = cells
    }
}

public struct XlsxSheet: Equatable {
    public var name: String
    public var widths: [Double]
    public var rows: [Int: XlsxRow] // 行（1 起）→ 行
    public var merges: [String] // "A1:D2"
    public var pageSetup: XlsxPageSetup
    public var rowBreaks: [Int] // 手动分页符：行号（在该行之后分页）
    public var maxRow: Int
    public var maxColumn: Int
    public init(name: String, widths: [Double], rows: [Int: XlsxRow] = [:], merges: [String] = [],
                pageSetup: XlsxPageSetup, rowBreaks: [Int] = [], maxRow: Int = 0, maxColumn: Int = 0) {
        self.name = name; self.widths = widths; self.rows = rows; self.merges = merges
        self.pageSetup = pageSetup; self.rowBreaks = rowBreaks; self.maxRow = maxRow; self.maxColumn = maxColumn
    }

    public mutating func setCell(row: Int, col: Int, value: XlsxCellValue, style: XlsxCellStyle? = nil) {
        var r = rows[row] ?? XlsxRow()
        r.cells[col] = XlsxCell(value: value, style: style)
        rows[row] = r
    }

    public mutating func setRowHeight(_ row: Int, _ height: Double) {
        var r = rows[row] ?? XlsxRow()
        r.height = height
        rows[row] = r
    }

    public mutating func merge(_ range: String) {
        if !merges.contains(range) { merges.append(range) }
    }
}

public struct XlsxPageSetup: Equatable {
    public var orientation: String // "landscape"
    public var paperSize: Int // 9 = A4
    public var fitToPage: Bool
    public var scale: Int
    public var margins: PageMargins
    public init(orientation: String = "landscape", paperSize: Int = 9, fitToPage: Bool = false,
                scale: Int = 100, margins: PageMargins) {
        self.orientation = orientation; self.paperSize = paperSize
        self.fitToPage = fitToPage; self.scale = scale; self.margins = margins
    }
}

// MARK: - CRC32（IEEE 多项式）

public func crc32(_ data: Data) -> UInt32 {
    var table = [UInt32](repeating: 0, count: 256)
    for i in 0..<256 {
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        table[i] = c
    }
    var crc: UInt32 = 0xFFFFFFFF
    for b in data { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
    return crc ^ 0xFFFFFFFF
}

// MARK: - ZIP（stored 条目）

public func zipStored(entries: [(name: String, data: Data)]) -> Data {
    var out = Data()
    var central = Data()
    let now = Date()
    // DOS 时间：年-1980 / 月 / 日 / 时 / 分 / 秒/2（小端）。
    let cal = Calendar(identifier: .gregorian)
    let comps = cal.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: now)
    let hour = comps.hour ?? 0
    let minute = comps.minute ?? 0
    let second = comps.second ?? 0
    let year = comps.year ?? 1980
    let month = comps.month ?? 1
    let day = comps.day ?? 1
    let dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
    let dosDate = UInt16(((year - 1980) << 9) | (month << 5) | day)
    func u16(_ v: UInt16, into d: inout Data) {
        d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF))
    }
    func u32(_ v: UInt32, into d: inout Data) {
        d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 24) & 0xFF))
    }
    for (name, data) in entries {
        let nameBytes = [UInt8](name.utf8)
        let crc = crc32(data)
        let offset = UInt32(out.count)
        // 本地文件头
        u32(0x04034b50, into: &out)
        u16(20, into: &out) // 解压所需版本
        u16(0x0800, into: &out) // 标志：UTF-8 文件名
        u16(0, into: &out) // 压缩方法 stored
        u16(dosTime, into: &out); u16(dosDate, into: &out)
        u32(crc, into: &out)
        u32(UInt32(data.count), into: &out) // 压缩后大小 = 原大小
        u32(UInt32(data.count), into: &out) // 原大小
        u16(UInt16(nameBytes.count), into: &out)
        u16(0, into: &out) // 扩展区长度
        out.append(contentsOf: nameBytes)
        out.append(data)
        // 中央目录
        u32(0x02014b50, into: &central)
        u16(20, into: &central) // 制作版本
        u16(20, into: &central) // 解压所需版本
        u16(0x0800, into: &central)
        u16(0, into: &central)
        u16(dosTime, into: &central); u16(dosDate, into: &central)
        u32(crc, into: &central)
        u32(UInt32(data.count), into: &central)
        u32(UInt32(data.count), into: &central)
        u16(UInt16(nameBytes.count), into: &central)
        u16(0, into: &central) // 扩展区
        u16(0, into: &central) // 注释
        u16(0, into: &central) // 磁盘号
        u16(0, into: &central) // 内部属性
        u32(0, into: &central) // 外部属性
        u32(offset, into: &central) // 本地头偏移
        central.append(contentsOf: nameBytes)
    }
    let cdOffset = UInt32(out.count)
    let cdSize = UInt32(central.count)
    out.append(central)
    // 结束记录
    u32(0x06054b50, into: &out)
    u16(0, into: &out); u16(0, into: &out)
    u16(UInt16(entries.count), into: &out); u16(UInt16(entries.count), into: &out)
    u32(cdSize, into: &out); u32(cdOffset, into: &out)
    u16(0, into: &out)
    return out
}

// MARK: - XML 工具

func xmlEscape(_ s: String) -> String {
    var out = ""
    out.reserveCapacity(s.count)
    for scalar in s.unicodeScalars {
        switch scalar.value {
        case 0x26: out += "&amp;"
        case 0x3C: out += "&lt;"
        case 0x3E: out += "&gt;"
        case 0x22: out += "&quot;"
        case 0x27: out += "&apos;"
        case 0x09, 0x0A, 0x0D: out += String(scalar) // 制表/换行/回车合法
        case 0x00...0x1F: break // 其余控制字符非法，丢弃
        default: out += String(scalar)
        }
    }
    return out
}

public func colLetter(_ n: Int) -> String {
    var s = ""
    var n = n
    while n > 0 {
        let m = (n - 1) % 26
        s = String(UnicodeScalar(65 + m)!) + s
        n = (n - 1) / 26
    }
    return s
}

func cellRef(row: Int, col: Int) -> String { "\(colLetter(col))\(row)" }

func formatDouble(_ v: Double) -> String {
    if v == v.rounded(), abs(v) < 1e15 { return String(Int64(v)) }
    return String(v)
}

// MARK: - 工作簿

public struct XlsxWorkbook {
    public var sheets: [XlsxSheet]
    public var creator: String
    public init(sheets: [XlsxSheet] = [], creator: String = "通信概预算") {
        self.sheets = sheets; self.creator = creator
    }

    public func build() -> Data {
        // 样式去重：字体 / 边框 / （字体+对齐+数字格式+边框）组合。
        var fonts: [XlsxFont] = [XlsxFont(name: "Calibri", size: 11)]
        var fontIds: [XlsxFont: Int] = [XlsxFont(name: "Calibri", size: 11): 0]
        var borders: [XlsxBorder] = [.none]
        var borderIds: [XlsxBorder: Int] = [.none: 0]
        var numFmtIds: [String: Int] = [:] // 自定义格式 → id（164 起）
        var customFormats: [(id: Int, code: String)] = []
        func numFmtId(_ code: String?) -> Int {
            guard let code else { return 0 }
            if code == "General" { return 0 }
            if code == "#,##0.00" { return 4 }
            if let id = numFmtIds[code] { return id }
            let id = 164 + customFormats.count
            numFmtIds[code] = id
            customFormats.append((id: id, code: code))
            return id
        }
        var xfs: [XlsxCellStyle] = [XlsxCellStyle()] // xf 0 = 默认
        var xfIds: [XlsxCellStyle: Int] = [XlsxCellStyle(): 0]
        func xfId(_ style: XlsxCellStyle?) -> Int? {
            guard let style else { return nil }
            if let id = xfIds[style] { return id }
            // 注册字体 / 边框 / 数字格式（注册顺序即 id 顺序，先字体后边框与数字格式无关）。
            if let font = style.font, fontIds[font] == nil {
                fontIds[font] = fonts.count
                fonts.append(font)
            }
            if borderIds[style.border] == nil {
                borderIds[style.border] = borders.count
                borders.append(style.border)
            }
            _ = numFmtId(style.numFmt)
            let id = xfs.count
            xfIds[style] = id
            xfs.append(style)
            return id
        }
        // 先注册全部样式（保证 styles.xml 完整），再生成各表。
        for sheet in sheets {
            for row in sheet.rows.values {
                for cell in row.cells.values { _ = xfId(cell.style) }
            }
        }

        // styles.xml
        var styles = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            """
        if !customFormats.isEmpty {
            styles += "<numFmts count=\"\(customFormats.count)\">"
            for f in customFormats {
                styles += "<numFmt numFmtId=\"\(f.id)\" formatCode=\"\(xmlEscape(f.code))\"/>"
            }
            styles += "</numFmts>"
        }
        styles += "<fonts count=\"\(fonts.count)\">"
        for font in fonts {
            styles += "<font>"
            if font.bold { styles += "<b/>" }
            styles += "<sz val=\"\(formatDouble(font.size))\"/>"
            styles += "<color theme=\"1\"/>"
            styles += "<name val=\"\(xmlEscape(font.name))\"/><family val=\"2\"/>"
            styles += "</font>"
        }
        styles += "</fonts>"
        styles += "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill>"
        styles += "<fill><patternFill patternType=\"gray125\"/></fill></fills>"
        styles += "<borders count=\"\(borders.count)\">"
        for border in borders {
            styles += "<border>"
            for (tag, s) in [("left", border.left), ("right", border.right),
                             ("top", border.top), ("bottom", border.bottom)] {
                if s == .none { styles += "<\(tag)/>" } else { styles += "<\(tag) style=\"\(s.rawValue)\"/>" }
            }
            styles += "<diagonal/></border>"
        }
        styles += "</borders>"
        styles += "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
        styles += "<cellXfs count=\"\(xfs.count)\">"
        for xf in xfs {
            let fontId = xf.font.flatMap { fontIds[$0] } ?? 0
            let borderId = borderIds[xf.border] ?? 0
            let fmtId = numFmtId(xf.numFmt)
            styles += "<xf numFmtId=\"\(fmtId)\" fontId=\"\(fontId)\" fillId=\"0\" borderId=\"\(borderId)\""
            styles += " applyFont=\"1\" applyBorder=\"1\" applyAlignment=\"1\" applyNumberFormat=\"1\""
            if let a = xf.alignment {
                styles += "><alignment horizontal=\"\(a.horizontal.rawValue)\" vertical=\"\(a.vertical.rawValue)\""
                if a.wrapText { styles += " wrapText=\"1\"" }
                styles += "/></xf>"
            } else {
                styles += "/>"
            }
        }
        styles += "</cellXfs>"
        styles += "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles>"
        styles += "</styleSheet>"

        // 各工作表
        var entries: [(name: String, data: Data)] = []
        for (i, sheet) in sheets.enumerated() {
            entries.append(("xl/worksheets/sheet\(i + 1).xml", Data(sheetXML(sheet, xfIds: xfIds).utf8)))
        }
        // workbook.xml
        var wb = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>
            """
        for (i, sheet) in sheets.enumerated() {
            wb += "<sheet name=\"\(xmlEscape(sheet.name))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
        }
        wb += "</sheets></workbook>"
        entries.append(("xl/workbook.xml", Data(wb.utf8)))
        // workbook rels
        var wbRels = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            """
        for (i, _) in sheets.enumerated() {
            wbRels += "<Relationship Id=\"rId\(i + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\(i + 1).xml\"/>"
        }
        wbRels += "<Relationship Id=\"rId\(sheets.count + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        wbRels += "</Relationships>"
        entries.append(("xl/_rels/workbook.xml.rels", Data(wbRels.utf8)))
        entries.append(("xl/styles.xml", Data(styles.utf8)))
        // 根 rels
        let rootRels = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/package/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>
            """
        entries.append(("_rels/.rels", Data(rootRels.utf8)))
        // Content_Types
        var types = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>
            """
        types += "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
        for (i, _) in sheets.enumerated() {
            types += "<Override PartName=\"/xl/worksheets/sheet\(i + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }
        types += "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
        types += "<Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>"
        types += "<Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.extended-properties+xml\"/>"
        types += "</Types>"
        entries.append(("[Content_Types].xml", Data(types.utf8)))
        // docProps
        let iso = iso8601Now()
        let core = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:creator>\(xmlEscape(creator))</dc:creator><cp:lastModifiedBy>\(xmlEscape(creator))</cp:lastModifiedBy><dcterms:created xsi:type="dcterms:W3CDTF">\(iso)</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">\(iso)</dcterms:modified></cp:coreProperties>
            """
        entries.append(("docProps/core.xml", Data(core.utf8)))
        let app = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>\(xmlEscape(creator))</Application></Properties>
            """
        entries.append(("docProps/app.xml", Data(app.utf8)))
        return zipStored(entries: entries)
    }

    private func sheetXML(_ sheet: XlsxSheet, xfIds: [XlsxCellStyle: Int]) -> String {
        let maxRow = max(sheet.maxRow, sheet.rows.keys.max() ?? 0)
        let maxCol = max(sheet.maxColumn, sheet.rows.values.flatMap { $0.cells.keys }.max() ?? 0)
        var xml = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
            """
        xml += "<dimension ref=\"\(cellRef(row: 1, col: 1)):\(cellRef(row: max(maxRow, 1), col: max(maxCol, 1)))\"/>"
        xml += "<sheetViews><sheetView workbookViewId=\"0\"/></sheetViews>"
        xml += "<sheetFormatPr defaultRowHeight=\"15.2\"/>"
        if !sheet.widths.isEmpty {
            xml += "<cols>"
            for (i, w) in sheet.widths.enumerated() {
                xml += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(formatDouble(w))\" customWidth=\"1\"/>"
            }
            xml += "</cols>"
        }
        xml += "<sheetData>"
        for row in sheet.rows.keys.sorted() {
            let r = sheet.rows[row]!
            xml += "<row r=\"\(row)\""
            if let h = r.height { xml += " ht=\"\(formatDouble(h))\" customHeight=\"1\"" }
            xml += ">"
            for col in r.cells.keys.sorted() {
                let cell = r.cells[col]!
                let ref = cellRef(row: row, col: col)
                var attrs = " r=\"\(ref)\""
                if let style = cell.style, let id = xfIds[style], id != 0 {
                    attrs += " s=\"\(id)\""
                }
                switch cell.value {
                case .blank:
                    // 有样式的空白格仍写出（边框/合并区占位）；无样式空白格省略。
                    if cell.style != nil { xml += "<c\(attrs)/>" }
                case .text(let t):
                    xml += "<c\(attrs) t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscape(t))</t></is></c>"
                case .number(let v):
                    xml += "<c\(attrs)><v>\(formatDouble(v))</v></c>"
                }
            }
            xml += "</row>"
        }
        xml += "</sheetData>"
        if !sheet.merges.isEmpty {
            xml += "<mergeCells count=\"\(sheet.merges.count)\">"
            for m in sheet.merges { xml += "<mergeCell ref=\"\(m)\"/>" }
            xml += "</mergeCells>"
        }
        let m = sheet.pageSetup.margins
        xml += "<pageMargins left=\"\(formatDouble(m.left))\" right=\"\(formatDouble(m.right))\" top=\"\(formatDouble(m.top))\" bottom=\"\(formatDouble(m.bottom))\" header=\"\(formatDouble(m.header))\" footer=\"\(formatDouble(m.footer))\"/>"
        let ps = sheet.pageSetup
        xml += "<pageSetup orientation=\"\(ps.orientation)\" paperSize=\"\(ps.paperSize)\" fitToPage=\"\(ps.fitToPage ? 1 : 0)\" scale=\"\(ps.scale)\"/>"
        if !sheet.rowBreaks.isEmpty {
            xml += "<rowBreaks count=\"\(sheet.rowBreaks.count)\" manualBreakCount=\"\(sheet.rowBreaks.count)\">"
            for br in sheet.rowBreaks { xml += "<brk id=\"\(br)\" max=\"16383\" man=\"1\"/>" }
            xml += "</rowBreaks>"
        }
        xml += "</worksheet>"
        return xml
    }
}

private func iso8601Now() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    return f.string(from: Date())
}
