import Foundation

/// xlsx 导入：库导入/导出 + 工程量导入（镜像 Electron `excel.cjs` / `libraryOps.js`，见设计文档 §10）。
/// 解析错误（文件级/行级）与分类错误分开；分类/落库逐字镜像 libraryOps.js。

// MARK: - 导入值（JS 语义）

public enum ImportValue: Equatable {
    case text(String)
    case number(Double)
    case bool(Bool)
    case date(Date)
    /// 公式单元格（JS 对象语义：String → "[object Object]"，Number → NaN，truthy）。
    case formula(String)
    case null

    /// JS `String(v)`：数字用 jsNumberString；日期用 yyyy-MM-dd（与 JS Date.toString 的
    /// 格式不同，仅影响日期型单元格进文本列的极端情况，见 §10.1）。
    public var jsString: String {
        switch self {
        case .text(let s): return s
        case .number(let n): return jsNumberString(n)
        case .bool(let b): return b ? "true" : "false"
        case .date(let d):
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: d)
        case .formula: return "[object Object]"
        case .null: return ""
        }
    }

    /// JS `Number(v)`：文本走 jsNumberFromString；布尔 1/0；日期 = 毫秒时间戳；空 = 0；公式 = NaN。
    public var jsNumber: Double {
        switch self {
        case .text(let s): return jsNumberFromString(s)
        case .number(let n): return n
        case .bool(let b): return b ? 1 : 0
        case .date(let d): return d.timeIntervalSince1970 * 1000
        case .formula: return .nan
        case .null: return 0
        }
    }

    /// 是否为空（null / 空文本）。数字 0、布尔 false、日期、公式均非空。
    public var isEmpty: Bool {
        switch self {
        case .null: return true
        case .text(let s): return s.trimmingCharacters(in: .whitespaces).isEmpty
        default: return false
        }
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// 数值或空：null/缺失/空文本 → nil；其余走 JS Number（NaN 保持 NaN，由调用方决定）。
    public var numberOrNull: Double? {
        switch self {
        case .null: return nil
        case .number(let n): return n
        case .text(let s):
            if s.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
            return jsNumberFromString(s)
        case .bool(let b): return b ? 1 : 0
        case .date(let d): return d.timeIntervalSince1970 * 1000
        case .formula: return .nan
        }
    }

    public var isTruthy: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .number(let n): return n != 0 && !n.isNaN
        case .text(let s): return !s.trimmingCharacters(in: .whitespaces).isEmpty
        case .date: return true
        case .formula: return true
        }
    }
}

/// JS `Number(String)`：trim 后空串 → 0；十六进制/二进制/八进制；Infinity；其余走 Double，非法 → NaN。
public func jsNumberFromString(_ s: String) -> Double {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return 0 }
    if t == "Infinity" || t == "+Infinity" { return .infinity }
    if t == "-Infinity" { return -.infinity }
    var str = t
    var sign: Double = 1
    if str.hasPrefix("+") {
        str.removeFirst()
    } else if str.hasPrefix("-") {
        sign = -1
        str.removeFirst()
    }
    if str.hasPrefix("0x") || str.hasPrefix("0X") {
        if let v = UInt64(String(str.dropFirst(2)), radix: 16) { return sign * Double(v) }
        return .nan
    }
    if str.hasPrefix("0b") || str.hasPrefix("0B") {
        if let v = UInt64(String(str.dropFirst(2)), radix: 2) { return sign * Double(v) }
        return .nan
    }
    if str.hasPrefix("0o") || str.hasPrefix("0O") {
        if let v = UInt64(String(str.dropFirst(2)), radix: 8) { return sign * Double(v) }
        return .nan
    }
    if let v = Double(t) { return v }
    return .nan
}

/// `normStr`（libraryOps.js）：null → ""，其余 String(v).trim()。
public func normStr(_ v: ImportValue?) -> String {
    guard let v else { return "" }
    return v.jsString.trimmingCharacters(in: .whitespaces)
}

func finiteOrNil(_ v: Double?) -> Double? {
    guard let v, v.isFinite else { return nil }
    return v
}

// MARK: - 导入行

public struct RateImportIdentity: Equatable {
    public var section: String // byProjectType | winterTable | vatRates
    public var type: String
    public var key: String
    public init(section: String, type: String, key: String) {
        self.section = section; self.type = type; self.key = key
    }
}

public struct ImportRow: Equatable {
    public var id: String
    public var fields: [String: ImportValue]
    public var rateIdentity: RateImportIdentity?
    public init(id: String = "", fields: [String: ImportValue] = [:], rateIdentity: RateImportIdentity? = nil) {
        self.id = id; self.fields = fields; self.rateIdentity = rateIdentity
    }
    public subscript(_ field: String) -> ImportValue {
        fields[field] ?? .null
    }
}

// MARK: - 库种类与列规格

public struct ExcelColumnSpec: Equatable {
    public var field: String
    public var header: String
    public var kind: LibraryColumnKind
    public var required: Bool
    public var aliases: [String]
    public var options: [String]
    public init(field: String, header: String, kind: LibraryColumnKind, required: Bool = false,
                aliases: [String] = [], options: [String] = []) {
        self.field = field; self.header = header; self.kind = kind; self.required = required
        self.aliases = aliases; self.options = options
    }
}

private let supplyOptions = ["甲供", "乙供", "设备"]
private let basisOptions = ["manual", "preDiscountExclTax", "afterDiscountExclTax", "laborTotal", "fixed", "surveyKm", "sum"]
private let rulesParseKindOptions = ["变体", "变体*", "通用", "备选"]

public enum ImportLibraryKind: String, Equatable, CaseIterable {
    case quotas
    case shortlist
    case materials
    case rulesVariant
    case rulesAlt
    case machinePrices
    case instrumentPrices
    case quotaMachines
    case quotaInstruments
    case rates
    case table5Fees

    public init?(libraryViewKey: LibraryViewKey) {
        switch libraryViewKey {
        case .quotas: self = .quotas
        case .shortlist: self = .shortlist
        case .materials: self = .materials
        case .rulesAlt: self = .rulesAlt
        case .machinePrices: self = .machinePrices
        case .instrumentPrices: self = .instrumentPrices
        }
    }

    public var libraryViewKey: LibraryViewKey? { ImportLibraryKind.libraryKey(self) }

    private static func libraryKey(_ kind: ImportLibraryKind) -> LibraryViewKey? {
        switch kind {
        case .quotas: return .quotas
        case .shortlist: return .shortlist
        case .materials: return .materials
        case .rulesAlt: return .rulesAlt
        case .machinePrices: return .machinePrices
        case .instrumentPrices: return .instrumentPrices
        // v2.6.0：三张关联表不再有资料库页面（数据层 kind 保留，导入导出格式兼容不变）。
        case .rulesVariant, .quotaMachines, .quotaInstruments, .rates, .table5Fees: return nil
        }
    }

    public var label: String {
        switch self {
        case .quotas: return "定额库"
        case .shortlist: return "常用短单"
        case .materials: return "材料库"
        case .rulesVariant: return "定额—材料关联"
        case .rulesAlt: return "关联规则（备选）"
        case .machinePrices: return "机械库"
        case .instrumentPrices: return "仪器仪表库"
        case .quotaMachines: return "定额—机械关联"
        case .quotaInstruments: return "定额—仪表关联"
        case .rates: return "表二费率"
        case .table5Fees: return "表五费用"
        }
    }

    public var isRates: Bool { self == .rates }

    /// 业务主键字段（libraryDefs.js 的 businessKey）。
    public var businessKeyFields: [String] {
        switch self {
        case .quotas: return ["code"]
        case .shortlist: return ["code", "name"]
        case .materials: return ["name", "spec"]
        case .rulesVariant, .rulesAlt: return ["quota", "material", "spec", "kind", "variant"]
        case .machinePrices, .instrumentPrices: return ["code"]
        case .quotaMachines, .quotaInstruments: return ["quota", "mcode"]
        case .rates: return ["工程类型", "费率项目"]
        case .table5Fees: return ["key"]
        }
    }

    /// Excel 列规格（逐字取自 EXCEL_COLUMNS；表头用 Electron 表头，aliases 接受原生界面表头）。
    public var excelColumns: [ExcelColumnSpec] {
        switch self {
        case .quotas:
            return [
                ExcelColumnSpec(field: "code", header: "定额编号", kind: .text, required: true),
                ExcelColumnSpec(field: "name", header: "定额名称", kind: .text, required: true),
                ExcelColumnSpec(field: "unit", header: "单位", kind: .text),
                ExcelColumnSpec(field: "tech", header: "技工", kind: .number, aliases: ["技工/单位"]),
                ExcelColumnSpec(field: "labor", header: "普工", kind: .number, aliases: ["普工/单位"]),
                ExcelColumnSpec(field: "coef", header: "系数", kind: .number),
                ExcelColumnSpec(field: "book", header: "分册名称", kind: .text, aliases: ["分册"]),
                ExcelColumnSpec(field: "alias", header: "别名", kind: .text),
            ]
        case .shortlist:
            return [
                ExcelColumnSpec(field: "code", header: "定额编号", kind: .text, required: true),
                ExcelColumnSpec(field: "name", header: "定额名称", kind: .text, required: true),
                ExcelColumnSpec(field: "unit", header: "单位", kind: .text),
                ExcelColumnSpec(field: "coef", header: "系数", kind: .number),
            ]
        case .materials:
            return [
                ExcelColumnSpec(field: "name", header: "名称", kind: .text, required: true),
                ExcelColumnSpec(field: "spec", header: "规格", kind: .text),
                ExcelColumnSpec(field: "unit", header: "单位", kind: .text),
                ExcelColumnSpec(field: "priceExcl", header: "除税单价", kind: .number),
                ExcelColumnSpec(field: "supply", header: "供货", kind: .select, options: supplyOptions),
                ExcelColumnSpec(field: "remark", header: "备注", kind: .text),
            ]
        case .rulesVariant, .rulesAlt:
            return [
                ExcelColumnSpec(field: "quota", header: "定额编号", kind: .text, required: true),
                ExcelColumnSpec(field: "material", header: "材料", kind: .text, required: true),
                ExcelColumnSpec(field: "spec", header: "规格", kind: .text),
                ExcelColumnSpec(field: "unit", header: "单位", kind: .text),
                ExcelColumnSpec(field: "consumption", header: "单位消耗量", kind: .number),
                ExcelColumnSpec(field: "supply", header: "供货", kind: .select, options: supplyOptions),
                // 解析阶段接受全集（变体/变体*/通用/备选）；分类阶段按视图列再校验。
                ExcelColumnSpec(field: "kind", header: "类型", kind: .select, options: rulesParseKindOptions),
                ExcelColumnSpec(field: "variant", header: "变体项目名称", kind: .text),
                ExcelColumnSpec(field: "remark", header: "备注", kind: .text),
                ExcelColumnSpec(field: "appliesTo", header: "适用工程", kind: .text),
            ]
        case .machinePrices:
            return [
                ExcelColumnSpec(field: "code", header: "机械编号", kind: .text, required: true),
                ExcelColumnSpec(field: "name", header: "机械名称", kind: .text, required: true),
                ExcelColumnSpec(field: "unit", header: "单位", kind: .text),
                ExcelColumnSpec(field: "price", header: "台班单价", kind: .number),
            ]
        case .instrumentPrices:
            return [
                ExcelColumnSpec(field: "code", header: "仪表编号", kind: .text, required: true),
                ExcelColumnSpec(field: "name", header: "仪表名称", kind: .text, required: true),
                ExcelColumnSpec(field: "unit", header: "单位", kind: .text),
                ExcelColumnSpec(field: "price", header: "台班单价", kind: .number),
            ]
        case .quotaMachines:
            return [
                ExcelColumnSpec(field: "quota", header: "定额编号", kind: .text, required: true),
                ExcelColumnSpec(field: "mcode", header: "机械编号", kind: .text, required: true),
                ExcelColumnSpec(field: "mname", header: "机械名称", kind: .text),
                ExcelColumnSpec(field: "unit", header: "单位", kind: .text),
                ExcelColumnSpec(field: "qty", header: "数量(台班)", kind: .number),
            ]
        case .quotaInstruments:
            return [
                ExcelColumnSpec(field: "quota", header: "定额编号", kind: .text, required: true),
                ExcelColumnSpec(field: "mcode", header: "仪表编号", kind: .text, required: true),
                ExcelColumnSpec(field: "mname", header: "仪表名称", kind: .text),
                ExcelColumnSpec(field: "unit", header: "单位", kind: .text),
                ExcelColumnSpec(field: "qty", header: "数量(台班)", kind: .number),
            ]
        case .rates:
            return [
                ExcelColumnSpec(field: "工程类型", header: "工程类型", kind: .text, required: true),
                ExcelColumnSpec(field: "费率项目", header: "费率项目", kind: .text, required: true),
                ExcelColumnSpec(field: "数值", header: "数值", kind: .number),
                ExcelColumnSpec(field: "单位", header: "单位", kind: .text),
            ]
        case .table5Fees:
            return [
                ExcelColumnSpec(field: "key", header: "费用 key", kind: .text, required: true),
                ExcelColumnSpec(field: "name", header: "费用名称", kind: .text, required: true),
                ExcelColumnSpec(field: "basis", header: "取费依据", kind: .select, options: basisOptions),
                ExcelColumnSpec(field: "rate", header: "费率", kind: .number),
                ExcelColumnSpec(field: "vatRate", header: "增值税率", kind: .number),
                ExcelColumnSpec(field: "amount", header: "固定金额", kind: .number),
                ExcelColumnSpec(field: "enabled", header: "启用", kind: .checkbox),
                ExcelColumnSpec(field: "order", header: "序号", kind: .number),
                ExcelColumnSpec(field: "note", header: "备注", kind: .text),
            ]
        }
    }
}

/// 分类阶段的列（diff 用）：libraryKinds 取 LibraryRowCodec.columns；rates 含 readonly 列。
public struct ImportClassifyColumn: Equatable {
    public var field: String
    public var label: String
    public var kind: LibraryColumnKind
    public var readonly: Bool
    public var options: [String]
    public init(field: String, label: String, kind: LibraryColumnKind, readonly: Bool = false,
                options: [String] = []) {
        self.field = field; self.label = label; self.kind = kind; self.readonly = readonly
        self.options = options
    }
}

public func classifyColumns(for kind: ImportLibraryKind) -> [ImportClassifyColumn] {
    if kind == .rates {
        return [
            ImportClassifyColumn(field: "工程类型", label: "工程类型", kind: .text, readonly: true),
            ImportClassifyColumn(field: "费率项目", label: "费率项目", kind: .text, readonly: true),
            ImportClassifyColumn(field: "数值", label: "数值", kind: .number),
            ImportClassifyColumn(field: "单位", label: "单位", kind: .text, readonly: true),
        ]
    }
    if kind == .table5Fees {
        return LibraryRowCodec.table5Columns.map {
            ImportClassifyColumn(field: $0.key, label: $0.label, kind: $0.kind, options: $0.options)
        }
    }
    // v2.6.0：三张关联表已无资料库页面，但导入数据层保留完整列定义（校验/分类口径不变）。
    if kind == .rulesVariant {
        return [
            ImportClassifyColumn(field: "quota", label: "定额编号", kind: .text),
            ImportClassifyColumn(field: "material", label: "材料", kind: .text),
            ImportClassifyColumn(field: "spec", label: "规格", kind: .text),
            ImportClassifyColumn(field: "unit", label: "单位", kind: .text),
            ImportClassifyColumn(field: "consumption", label: "单位消耗量", kind: .number),
            ImportClassifyColumn(field: "supply", label: "供货", kind: .select, options: ["甲供", "乙供", "设备"]),
            ImportClassifyColumn(field: "kind", label: "类型", kind: .select, options: ["变体", "变体*", "通用"]),
            ImportClassifyColumn(field: "variant", label: "变体项目名称", kind: .text),
            ImportClassifyColumn(field: "remark", label: "备注", kind: .text),
            ImportClassifyColumn(field: "appliesTo", label: "适用工程", kind: .text),
        ]
    }
    if kind == .quotaMachines || kind == .quotaInstruments {
        let isMachine = kind == .quotaMachines
        return [
            ImportClassifyColumn(field: "quota", label: "定额编号", kind: .text),
            ImportClassifyColumn(field: "mcode", label: isMachine ? "机械编号" : "仪表编号", kind: .text),
            ImportClassifyColumn(field: "mname", label: isMachine ? "机械名称" : "仪表名称", kind: .text),
            ImportClassifyColumn(field: "unit", label: "单位", kind: .text),
            ImportClassifyColumn(field: "qty", label: "数量(台班)", kind: .number),
        ]
    }
    guard let viewKey = kind.libraryViewKey else { return [] }
    return LibraryRowCodec.columns(for: viewKey).map {
        ImportClassifyColumn(field: $0.key, label: $0.label, kind: $0.kind, options: $0.options)
    }
}

// MARK: - 解析（importLibrary）

public struct LibraryImportParseResult {
    public var rows: [ImportRow]
    public var errors: [String]
    public init(rows: [ImportRow] = [], errors: [String] = []) { self.rows = rows; self.errors = errors }
}

private func parseBoolCell(_ v: ImportValue) -> Bool? {
    switch v {
    case .bool(let b): return b
    case .number(let n): return parseBoolCell(.text(jsNumberString(n)))
    case .text(let s):
        let t = s.trimmingCharacters(in: .whitespaces)
        if ["是", "true", "1", "启用", "TRUE"].contains(t) { return true }
        if ["否", "false", "0", "禁用", "FALSE"].contains(t) { return false }
        return nil
    default: return nil
    }
}

public func parseLibraryFile(data: Data, kind: ImportLibraryKind, fileName: String) -> LibraryImportParseResult {
    let book: XlsxReadBook
    do {
        book = try XlsxReader.read(data: data)
    } catch let err as XlsxReadError {
        if err == .noSheets {
            return LibraryImportParseResult(errors: ["文件无工作表"])
        }
        return LibraryImportParseResult(errors: ["文件打不开（\(fileName)）：\(err.localizedDescription)"])
    } catch {
        return LibraryImportParseResult(errors: ["文件打不开（\(fileName)）：\(error.localizedDescription)"])
    }
    guard let sheet = book.sheets.first else {
        return LibraryImportParseResult(errors: ["文件无工作表"])
    }
    let cols = kind.excelColumns
    // 表头：首行各列 jsString.trim()。
    var headerToCol: [String: Int] = [:]
    for c in 1...max(sheet.maxCol, 1) {
        let v = sheetValue(sheet.cell(row: 1, col: c))
        let text = v.jsString.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { headerToCol[text] = c }
    }
    var colIndex: [String: Int] = [:]
    var missing: [String] = []
    for col in cols {
        if let found = headerToCol[col.header] {
            colIndex[col.field] = found
        } else if let found = col.aliases.compactMap({ headerToCol[$0] }).first {
            colIndex[col.field] = found
        } else if col.required {
            missing.append(col.header)
        }
    }
    if !missing.isEmpty {
        return LibraryImportParseResult(errors: [
            "表头缺失必填列：\(missing.joined(separator: "、"))（首行应为：\(cols.map { $0.header }.joined(separator: " / "))）",
        ])
    }
    var rows: [ImportRow] = []
    var errors: [String] = []
    if sheet.maxRow >= 2 {
        for r in 2...sheet.maxRow {
            var raw: [String: ImportValue] = [:]
            var allEmpty = true
            for col in cols {
                let v: ImportValue
                if let idx = colIndex[col.field] {
                    v = sheetValue(sheet.cell(row: r, col: idx))
                } else {
                    v = .null
                }
                raw[col.field] = v
                if !v.isEmpty { allEmpty = false }
            }
            if allEmpty { continue }
            var row = ImportRow()
            var rowErrors: [String] = []
            for col in cols {
                let v = raw[col.field] ?? .null
                switch col.kind {
                case .number:
                    // Electron：v === '' || v == null → null（仅精确空串；空白串走 Number → 0）。
                    if v == .null || (v == .text("")) {
                        row.fields[col.field] = .null
                    } else {
                        let n = v.jsNumber
                        if n.isFinite { row.fields[col.field] = .number(n) }
                        else { rowErrors.append("\(col.header)不是有效数字") }
                    }
                case .checkbox:
                    if v == .null || v == .text("") {
                        row.fields[col.field] = .bool(true)
                    } else if let b = parseBoolCell(v) {
                        row.fields[col.field] = .bool(b)
                    } else {
                        rowErrors.append("\(col.header)应为是/否")
                    }
                case .select:
                    let t: String
                    if v == .null { t = "" } else { t = v.jsString.trimmingCharacters(in: .whitespaces) }
                    row.fields[col.field] = .text(t)
                    if !t.isEmpty, !col.options.contains(t) {
                        rowErrors.append("\(col.header)非法取值“\(t)”")
                    }
                case .text:
                    if v == .null { row.fields[col.field] = .text("") }
                    else { row.fields[col.field] = .text(v.jsString.trimmingCharacters(in: .whitespaces)) }
                }
                if col.required {
                    let stored = row.fields[col.field] ?? .null
                    if stored.isEmpty { rowErrors.append("\(col.header)必填") }
                }
            }
            if !rowErrors.isEmpty {
                errors.append("第 \(r) 行：\(rowErrors.joined(separator: "；"))")
            } else {
                rows.append(row)
            }
        }
    }
    return LibraryImportParseResult(rows: rows, errors: errors)
}

private func sheetValue(_ v: XlsxReadValue) -> ImportValue {
    switch v {
    case .blank: return .null
    case .text(let s): return .text(s)
    case .number(let n): return .number(n)
    case .bool(let b): return .bool(b)
    case .date(let d): return .date(d)
    case .formula(let f): return .formula(f)
    }
}

// MARK: - 归一化与费率身份（normalizeImportedRows / resolveRateIdentity）

public func resolveRateIdentity(type: String, item: String) -> RateImportIdentity? {
    if type == "冬雨季表" {
        let prefix = "冬雨季施工增加费（"
        let suffix = "）"
        guard item.hasPrefix(prefix), item.hasSuffix(suffix) else { return nil }
        let inner = String(item.dropFirst(prefix.count).dropLast(suffix.count))
        if ["Ⅰ类地区", "Ⅱ类地区", "Ⅲ类地区"].contains(inner) {
            return RateImportIdentity(section: "winterTable", type: inner, key: inner)
        }
        return nil
    }
    if type == "增值税率" {
        let map = ["甲供材料增值税率": "jiaTax", "乙供材料增值税率": "yiTax",
                   "销项税额税率": "outputTax", "安全生产费增值税率": "safetyVat"]
        if let key = map[item] {
            return RateImportIdentity(section: "vatRates", type: key, key: key)
        }
        return nil
    }
    if projectTypes.contains(type) {
        if let def = rateFieldDefs.first(where: { $0.name == item }) {
            return RateImportIdentity(section: "byProjectType", type: type, key: def.key)
        }
    }
    return nil
}

public func normalizeImportedRows(kind: ImportLibraryKind, rows: [ImportRow]) -> [ImportRow] {
    rows.map { row in
        var r = row
        if kind == .rulesVariant, normStr(r.fields["kind"]).isEmpty {
            r.fields["kind"] = .text("变体")
        }
        if kind == .rulesAlt, normStr(r.fields["kind"]).isEmpty {
            r.fields["kind"] = .text("备选")
        }
        if kind == .rates {
            let type = normStr(r.fields["工程类型"])
            let item = normStr(r.fields["费率项目"])
            r.rateIdentity = resolveRateIdentity(type: type, item: item)
        }
        return r
    }
}

// MARK: - 分类（classifyImport）

public struct ImportFieldDiff: Equatable {
    public var field: String
    public var label: String
    public var from: ImportValue
    public var to: ImportValue
    public init(field: String, label: String, from: ImportValue, to: ImportValue) {
        self.field = field; self.label = label; self.from = from; self.to = to
    }
}

public struct ImportAddedItem: Equatable {
    public var key: String
    public var row: ImportRow
    public init(key: String, row: ImportRow) { self.key = key; self.row = row }
}

public struct ImportUpdatedItem: Equatable {
    public var key: String
    public var row: ImportRow
    public var existing: ImportRow
    public var diffs: [ImportFieldDiff]
    public init(key: String, row: ImportRow, existing: ImportRow, diffs: [ImportFieldDiff]) {
        self.key = key; self.row = row; self.existing = existing; self.diffs = diffs
    }
}

public struct ImportSkippedItem: Equatable {
    public var key: String
    public var row: ImportRow
    public var existing: ImportRow
    public init(key: String, row: ImportRow, existing: ImportRow) {
        self.key = key; self.row = row; self.existing = existing
    }
}

public struct ImportErrorItem: Equatable {
    public var key: String
    public var row: ImportRow
    public var errors: [String]
    public init(key: String, row: ImportRow, errors: [String]) {
        self.key = key; self.row = row; self.errors = errors
    }
}

public struct ImportClassification: Equatable {
    public var added: [ImportAddedItem]
    public var updated: [ImportUpdatedItem]
    public var skipped: [ImportSkippedItem]
    public var errors: [ImportErrorItem]
    public init(added: [ImportAddedItem] = [], updated: [ImportUpdatedItem] = [],
                skipped: [ImportSkippedItem] = [], errors: [ImportErrorItem] = []) {
        self.added = added; self.updated = updated; self.skipped = skipped; self.errors = errors
    }
}

public func businessKey(kind: ImportLibraryKind, row: ImportRow) -> String {
    kind.businessKeyFields.map { normStr(row.fields[$0]) }.joined(separator: "\0")
}

public func businessKeyDisplay(_ key: String) -> String {
    if key.isEmpty { return "(空)" }
    return key.components(separatedBy: "\0").joined(separator: " / ")
}

/// 行校验（validateRow 镜像）：必填 / number 有限 / select 取值 / checkbox 布尔 / 费率未知项目。
public func validateImportRow(kind: ImportLibraryKind, row: ImportRow) -> [String] {
    var errors: [String] = []
    let specs = kind.excelColumns
    let cols = classifyColumns(for: kind)
    for spec in specs where spec.required {
        if normStr(row.fields[spec.field]).isEmpty {
            errors.append("\(spec.header)必填")
        }
    }
    for col in cols where !col.readonly {
        let v = row.fields[col.field]
        switch col.kind {
        case .number:
            if let v, !v.isEmpty {
                if !v.jsNumber.isFinite { errors.append("\(col.label)不是有效数字") }
            }
        case .select:
            let t = normStr(v)
            if !t.isEmpty, !col.options.contains(t) {
                errors.append("\(col.label)非法取值“\(t)”")
            }
        case .checkbox:
            if let v, v != .null, v.boolValue == nil {
                errors.append("\(col.label)应为是/否")
            }
        case .text:
            break
        }
    }
    if kind == .rates, row.rateIdentity == nil {
        errors.append("未知费率项目“\(normStr(row.fields["费率项目"]))”")
    }
    return errors
}

public func classifyImport(kind: ImportLibraryKind, existing: [ImportRow], incoming: [ImportRow]) -> ImportClassification {
    let normalized = normalizeImportedRows(kind: kind, rows: incoming)
    var byKey: [String: ImportRow] = [:]
    for r in existing { byKey[businessKey(kind: kind, row: r)] = r }
    var seenInFile = Set<String>()
    var out = ImportClassification()
    let cols = classifyColumns(for: kind)
    for rawRow in normalized {
        let row = rawRow
        let key = businessKey(kind: kind, row: row)
        var rowErrors = validateImportRow(kind: kind, row: row)
        if seenInFile.contains(key) {
            rowErrors.append("文件内业务主键重复：\(businessKeyDisplay(key))")
            out.errors.append(ImportErrorItem(key: key, row: row, errors: rowErrors))
            continue
        }
        seenInFile.insert(key)
        if !rowErrors.isEmpty {
            out.errors.append(ImportErrorItem(key: key, row: row, errors: rowErrors))
            continue
        }
        guard let existingRow = byKey[key] else {
            out.added.append(ImportAddedItem(key: key, row: row))
            continue
        }
        var diffs: [ImportFieldDiff] = []
        for col in cols where !col.readonly {
            // 费率视图“数值”为空视为不参与 diff（保留旧值），见 §10.3。
            if kind == .rates, col.field == "数值", (row.fields["数值"] ?? .null) == .null {
                continue
            }
            let from = existingRow.fields[col.field]
            let to = row.fields[col.field]
            if col.kind == .number {
                let fv = from?.numberOrNull
                let tv = to?.numberOrNull
                if fv != tv {
                    diffs.append(ImportFieldDiff(field: col.field, label: col.label,
                                                from: from ?? .null, to: to ?? .null))
                }
            } else if normStr(from) != normStr(to), !(from == nil && to == nil) {
                diffs.append(ImportFieldDiff(field: col.field, label: col.label,
                                            from: from ?? .null, to: to ?? .null))
            }
        }
        if diffs.isEmpty {
            out.skipped.append(ImportSkippedItem(key: key, row: row, existing: existingRow))
        } else {
            out.updated.append(ImportUpdatedItem(key: key, row: row, existing: existingRow, diffs: diffs))
        }
    }
    return out
}

// MARK: - 落库（applyImport）

public enum ImportMode: Equatable {
    case merge
    case replace
}

public struct ImportDecisions: Equatable {
    public var mode: ImportMode
    /// 合并时勾选的新增主键；nil = 全部新增。
    public var addedKeys: Set<String>?
    /// 合并时更新的逐字段勾选；缺失字段默认采用新值。
    public var updatedChoices: [String: [String: Bool]]
    public init(mode: ImportMode = .merge, addedKeys: Set<String>? = nil,
                updatedChoices: [String: [String: Bool]] = [:]) {
        self.mode = mode; self.addedKeys = addedKeys; self.updatedChoices = updatedChoices
    }
}

public func applyImport(kind: ImportLibraryKind, existing: [ImportRow],
                        classification: ImportClassification, decisions: ImportDecisions) -> [ImportRow] {
    if decisions.mode == .replace {
        var byKey: [String: ImportRow] = [:]
        for r in existing { byKey[businessKey(kind: kind, row: r)] = r }
        var out: [ImportRow] = []
        var seen = Set<String>()
        for item in classification.added.map({ ($0.key, $0.row) }) + classification.updated.map({ ($0.key, $0.row) }) {
            if seen.contains(item.0) { continue }
            seen.insert(item.0)
            var row = item.1
            let old = byKey[item.0]
            if let oldId = old?.id, !oldId.isEmpty {
                row.id = oldId
            } else if row.id.isEmpty {
                row.id = newUID()
            }
            out.append(row)
        }
        return out
    }
    var next = existing
    let addedKeys = decisions.addedKeys ?? Set(classification.added.map { $0.key })
    for a in classification.added where addedKeys.contains(a.key) {
        var row = a.row
        if row.id.isEmpty { row.id = newUID() }
        next.append(row)
    }
    for u in classification.updated {
        var targetIdx: Int?
        if !u.existing.id.isEmpty {
            targetIdx = next.firstIndex { $0.id == u.existing.id }
        }
        if targetIdx == nil {
            targetIdx = next.firstIndex { businessKey(kind: kind, row: $0) == u.key }
        }
        guard let idx = targetIdx else { continue }
        for d in u.diffs {
            let take = decisions.updatedChoices[u.key]?[d.field] ?? true
            if !take { continue }
            next[idx].fields[d.field] = u.row.fields[d.field]
        }
    }
    return next
}

// MARK: - 现有行 ↔ ImportRow 转换 + 写回

private func txt(_ s: String) -> ImportValue { .text(s) }
private func numVal(_ d: Double) -> ImportValue { .number(d) }
private func numOpt(_ d: Double?) -> ImportValue { finiteOrNil(d).map { .number($0) } ?? .null }
private func boolOpt(_ b: Bool?) -> ImportValue { b.map { .bool($0) } ?? .null }

private func strField(_ row: ImportRow, _ field: String) -> String {
    normStr(row.fields[field])
}

private func numField(_ row: ImportRow, _ field: String) -> Double {
    finiteOrNil(row.fields[field]?.numberOrNull) ?? 0
}

private func numOptField(_ row: ImportRow, _ field: String) -> Double? {
    finiteOrNil(row.fields[field]?.numberOrNull)
}

private func boolOptField(_ row: ImportRow, _ field: String) -> Bool? {
    row.fields[field]?.boolValue
}

public func existingImportRows(kind: ImportLibraryKind, profile: ConfigurationProfile) -> [ImportRow] {
    let libs = profile.libraries
    switch kind {
    case .quotas:
        return libs.quotas.map { r in
            ImportRow(id: r.id, fields: ["code": txt(r.code), "name": txt(r.name), "unit": txt(r.unit),
                                           "tech": numVal(r.tech), "labor": numVal(r.labor), "coef": numOpt(r.coef),
                                           "book": txt(r.book), "alias": txt(r.alias)])
        }
    case .shortlist:
        return libs.shortlist.map { r in
            ImportRow(id: r.id, fields: ["code": txt(r.code), "name": txt(r.name), "unit": txt(r.unit),
                                           "coef": numOpt(r.coef)])
        }
    case .materials:
        return libs.materials.map { r in
            ImportRow(id: r.id, fields: ["name": txt(r.name), "spec": txt(r.spec), "unit": txt(r.unit),
                                           "priceExcl": numVal(r.priceExcl), "supply": txt(r.supply),
                                           "remark": txt(r.remark)])
        }
    case .rulesVariant:
        return libs.rules.filter { ["变体", "变体*", "通用"].contains($0.kind) }.map(ruleImportRow)
    case .rulesAlt:
        return libs.rules.filter { $0.kind == "备选" }.map(ruleImportRow)
    case .machinePrices:
        return libs.machinePrices.map { r in
            ImportRow(id: r.id, fields: ["code": txt(r.code), "name": txt(r.name), "unit": txt(r.unit),
                                           "price": numVal(r.price)])
        }
    case .instrumentPrices:
        return libs.instrumentPrices.map { r in
            ImportRow(id: r.id, fields: ["code": txt(r.code), "name": txt(r.name), "unit": txt(r.unit),
                                           "price": numVal(r.price)])
        }
    case .quotaMachines:
        return libs.quotaMachines.map { r in
            ImportRow(id: r.id, fields: ["quota": txt(r.quota), "mcode": txt(r.mcode), "mname": txt(r.mname),
                                           "unit": txt(r.unit), "qty": numVal(r.qty)])
        }
    case .quotaInstruments:
        return libs.quotaInstruments.map { r in
            ImportRow(id: r.id, fields: ["quota": txt(r.quota), "mcode": txt(r.mcode), "mname": txt(r.mname),
                                           "unit": txt(r.unit), "qty": numVal(r.qty)])
        }
    case .rates:
        var out: [ImportRow] = []
        for t in projectTypes {
            let rec = profile.rates.byProjectType[t]
            for def in rateFieldDefs {
                out.append(ImportRow(
                    id: "rate:\(t):\(def.key)",
                    fields: ["工程类型": txt(t), "费率项目": txt(def.name),
                             "数值": numOpt(rec?.value(forKey: def.key) ?? nil), "单位": txt(def.unit)],
                    rateIdentity: RateImportIdentity(section: "byProjectType", type: t, key: def.key)))
            }
        }
        for region in ["Ⅰ类地区", "Ⅱ类地区", "Ⅲ类地区"] {
            out.append(ImportRow(
                id: "rate:winter:\(region)",
                fields: ["工程类型": txt("冬雨季表"), "费率项目": txt("冬雨季施工增加费（\(region)）"),
                         "数值": numOpt(profile.rates.winterTable[region]), "单位": txt("费率")],
                rateIdentity: RateImportIdentity(section: "winterTable", type: region, key: region)))
        }
        for (key, name) in [("jiaTax", "甲供材料增值税率"), ("yiTax", "乙供材料增值税率"),
                            ("outputTax", "销项税额税率"), ("safetyVat", "安全生产费增值税率")] {
            let value: Double?
            switch key {
            case "jiaTax": value = profile.rates.vatRates.jiaTax
            case "yiTax": value = profile.rates.vatRates.yiTax
            case "outputTax": value = profile.rates.vatRates.outputTax
            default: value = profile.rates.vatRates.safetyVat
            }
            out.append(ImportRow(
                id: "rate:vat:\(key)",
                fields: ["工程类型": txt("增值税率"), "费率项目": txt(name),
                         "数值": numOpt(value), "单位": txt("费率")],
                rateIdentity: RateImportIdentity(section: "vatRates", type: key, key: key)))
        }
        return out
    case .table5Fees:
        return profile.table5Fees.map { f in
            ImportRow(id: f.key, fields: ["key": txt(f.key), "name": txt(f.name), "basis": txt(f.basis),
                                            "rate": numOpt(f.rate), "vatRate": numOpt(f.vatRate),
                                            "amount": numOpt(f.amount), "enabled": boolOpt(f.enabled),
                                            "order": numVal(f.order), "note": txt(f.note)])
        }
    }
}

private func ruleImportRow(_ r: RuleRow) -> ImportRow {
    ImportRow(id: r.id, fields: ["quota": txt(r.quota), "material": txt(r.material), "spec": txt(r.spec),
                                   "unit": txt(r.unit), "consumption": numVal(r.consumption),
                                   "supply": txt(r.supply), "kind": txt(r.kind), "variant": txt(r.variant),
                                   "remark": txt(r.remark), "appliesTo": txt(r.appliesTo)])
}

/// 写回（规则两视图只替换本视图切片；费率逐行写回；表五保留原 children；表五行 id = key）。
public func writeImportRows(kind: ImportLibraryKind, profile: inout ConfigurationProfile, rows: [ImportRow]) {
    switch kind {
    case .quotas:
        profile.libraries.quotas = rows.map { r in
            QuotaRow(id: r.id, code: strField(r, "code"), name: strField(r, "name"), unit: strField(r, "unit"),
                     tech: numField(r, "tech"), labor: numField(r, "labor"), coef: numOptField(r, "coef"),
                     book: strField(r, "book"), alias: strField(r, "alias"))
        }
    case .shortlist:
        profile.libraries.shortlist = rows.map { r in
            ShortlistRow(id: r.id, code: strField(r, "code"), name: strField(r, "name"),
                         unit: strField(r, "unit"), coef: numOptField(r, "coef"))
        }
    case .materials:
        profile.libraries.materials = rows.map { r in
            MaterialRow(id: r.id, name: strField(r, "name"), spec: strField(r, "spec"),
                        unit: strField(r, "unit"), priceExcl: numField(r, "priceExcl"),
                        supply: strField(r, "supply"), remark: strField(r, "remark"))
        }
    case .rulesVariant:
        let rest = profile.libraries.rules.filter { !["变体", "变体*", "通用"].contains($0.kind) }
        profile.libraries.rules = rest + rows.map(rowToRule)
    case .rulesAlt:
        let rest = profile.libraries.rules.filter { $0.kind != "备选" }
        profile.libraries.rules = rest + rows.map(rowToRule)
    case .machinePrices:
        profile.libraries.machinePrices = rows.map { r in
            MachinePriceRow(id: r.id, code: strField(r, "code"), name: strField(r, "name"),
                            unit: strField(r, "unit"), price: numField(r, "price"))
        }
    case .instrumentPrices:
        profile.libraries.instrumentPrices = rows.map { r in
            InstrumentPriceRow(id: r.id, code: strField(r, "code"), name: strField(r, "name"),
                               unit: strField(r, "unit"), price: numField(r, "price"))
        }
    case .quotaMachines:
        profile.libraries.quotaMachines = rows.map { r in
            QuotaMachineRow(id: r.id, quota: strField(r, "quota"), mcode: strField(r, "mcode"),
                            mname: strField(r, "mname"), unit: strField(r, "unit"), qty: numField(r, "qty"))
        }
    case .quotaInstruments:
        profile.libraries.quotaInstruments = rows.map { r in
            QuotaInstrumentRow(id: r.id, quota: strField(r, "quota"), mcode: strField(r, "mcode"),
                               mname: strField(r, "mname"), unit: strField(r, "unit"), qty: numField(r, "qty"))
        }
    case .rates:
        for row in rows {
            guard let ident = row.rateIdentity ?? resolveRateIdentity(
                type: normStr(row.fields["工程类型"]), item: normStr(row.fields["费率项目"])) else { continue }
            let value = numOptField(row, "数值")
            switch ident.section {
            case "byProjectType":
                if profile.rates.byProjectType[ident.type] == nil {
                    profile.rates.byProjectType[ident.type] = NamedRatesRecord()
                }
                profile.rates.byProjectType[ident.type]?.setValue(value, forKey: ident.key)
            case "winterTable":
                if let value { profile.rates.winterTable[ident.key] = value }
                else { profile.rates.winterTable.removeValue(forKey: ident.key) }
            case "vatRates":
                switch ident.key {
                case "jiaTax": profile.rates.vatRates.jiaTax = value
                case "yiTax": profile.rates.vatRates.yiTax = value
                case "outputTax": profile.rates.vatRates.outputTax = value
                case "safetyVat": profile.rates.vatRates.safetyVat = value
                default: break
                }
            default: break
            }
        }
    case .table5Fees:
        let oldByKey = Dictionary(uniqueKeysWithValues: profile.table5Fees.map { ($0.key, $0) })
        profile.table5Fees = rows.map { r in
            let key = strField(r, "key")
            return Table5Fee(key: key, name: strField(r, "name"), basis: strField(r, "basis"),
                             rate: numOptField(r, "rate"), vatRate: numOptField(r, "vatRate"),
                             amount: numOptField(r, "amount"), enabled: boolOptField(r, "enabled"),
                             order: numField(r, "order"), note: strField(r, "note"),
                             children: oldByKey[key]?.children)
        }
    }
}

private func rowToRule(_ r: ImportRow) -> RuleRow {
    RuleRow(id: r.id, quota: strField(r, "quota"), material: strField(r, "material"),
            spec: strField(r, "spec"), unit: strField(r, "unit"),
            consumption: numField(r, "consumption"), supply: strField(r, "supply"),
            kind: strField(r, "kind"), variant: strField(r, "variant"),
            remark: strField(r, "remark"), appliesTo: strField(r, "appliesTo"))
}

// MARK: - 导出（exportLibrary）

/// 库导出：Sheet1、列宽 18、首行加粗、checkbox 写 是/否、空写空白格（exportLibrary 镜像）。
public func exportLibraryWorkbook(kind: ImportLibraryKind, rows: [ImportRow]) -> Data {
    let cols = kind.excelColumns
    let bold = XlsxCellStyle(font: XlsxFont(name: "Arial", size: 10, bold: true))
    var sheet = XlsxSheet(name: "Sheet1", widths: [Double](repeating: 18, count: cols.count),
                          pageSetup: XlsxPageSetup(margins: PageMargins(left: 0.7, right: 0.7, top: 0.75,
                                                                       bottom: 0.75, header: 0.3, footer: 0.3)))
    for (j, col) in cols.enumerated() {
        sheet.setCell(row: 1, col: j + 1, value: .text(col.header), style: bold)
    }
    for (i, row) in rows.enumerated() {
        for (j, col) in cols.enumerated() {
            let v = row.fields[col.field] ?? .null
            let cell: XlsxCellValue
            if col.kind == .checkbox {
                cell = .text(v.isTruthy ? "是" : "否")
            } else {
                switch v {
                case .null: cell = .blank
                case .text(let s): cell = s.isEmpty ? .blank : .text(s)
                case .number(let n): cell = .number(n)
                case .bool(let b): cell = .text(b ? "true" : "false")
                case .date(let d): cell = .text(ImportValue.date(d).jsString)
                case .formula: cell = .text("[object Object]")
                }
            }
            sheet.setCell(row: i + 2, col: j + 1, value: cell)
        }
    }
    return XlsxWorkbook(sheets: [sheet]).build()
}

// MARK: - 工程量导入（importQuantities）

public struct ImportedQuantity: Equatable {
    public var quota: String
    public var variant: String
    public var unit: String
    public var qty: Double
    public var coef: Double
    public init(quota: String, variant: String = "", unit: String = "", qty: Double, coef: Double = 1) {
        self.quota = quota; self.variant = variant; self.unit = unit; self.qty = qty; self.coef = coef
    }
}

public struct ImportedProject: Equatable {
    public var name: String
    public var quantities: [ImportedQuantity]
    public init(name: String, quantities: [ImportedQuantity] = []) {
        self.name = name; self.quantities = quantities
    }
}

public enum QuantitiesImportKind: Equatable {
    case v3
    case simple
}

public struct QuantitiesImportResult: Equatable {
    public var kind: QuantitiesImportKind
    public var projects: [ImportedProject]
    public init(kind: QuantitiesImportKind, projects: [ImportedProject] = []) {
        self.kind = kind; self.projects = projects
    }
}

/// JS `Number(v) || fallback`：0 / NaN → fallback。
private func numberOr(_ v: ImportValue, fallback: Double) -> Double {
    let n = v.jsNumber
    if n == 0 || n.isNaN { return fallback }
    return n
}

public func parseQuantitiesFile(data: Data) throws -> QuantitiesImportResult {
    let book = try XlsxReader.read(data: data)
    guard let ws0 = book.sheets.first else { throw XlsxReadError.noSheets }
    let cellValue: (XlsxReadSheet, Int, Int) -> ImportValue = { sheet, r, c in
        sheetValue(sheet.cell(row: r, col: c))
    }
    let isSimple = sheetValue(ws0.cell(row: 1, col: 1)).jsString
        .trimmingCharacters(in: .whitespaces) == "工程名称"
    if let ws = book.sheet(named: "工程量"), !isSimple {
        var names: [String] = []
        for c in 2...10 {
            names.append(cellValue(ws, 1, c).jsString.trimmingCharacters(in: .whitespaces))
        }
        var projects: [ImportedProject] = []
        for p in 0..<9 {
            let name = names[p]
            if name.isEmpty { continue }
            var quantities: [ImportedQuantity] = []
            if ws.maxRow >= 4 {
                for r in 4...ws.maxRow {
                    let codeCell = cellValue(ws, r, 2)
                    let qty = numberOr(cellValue(ws, r, 5 + p), fallback: 0)
                    if codeCell.isTruthy, qty != 0 {
                        let variantCell = cellValue(ws, r, 3)
                        quantities.append(ImportedQuantity(
                            quota: codeCell.jsString.trimmingCharacters(in: .whitespaces),
                            variant: variantCell == .null ? "" : variantCell.jsString,
                            unit: "", qty: qty, coef: 1))
                    }
                }
            }
            if !quantities.isEmpty {
                projects.append(ImportedProject(name: name, quantities: quantities))
            }
        }
        if !projects.isEmpty {
            return QuantitiesImportResult(kind: .v3, projects: projects)
        }
    }
    // 简易格式：首表第 2 行起 [工程名称, 定额编号, 项目名称, 数量, 工日系数]。
    var order: [String] = []
    var byName: [String: [ImportedQuantity]] = [:]
    if ws0.maxRow >= 2 {
        for r in 2...ws0.maxRow {
            let pname = cellValue(ws0, r, 1).jsString.trimmingCharacters(in: .whitespaces)
            let codeCell = cellValue(ws0, r, 2)
            let qty = numberOr(cellValue(ws0, r, 4), fallback: 0)
            if pname.isEmpty || !codeCell.isTruthy || qty == 0 { continue }
            let variantCell = cellValue(ws0, r, 3)
            let coef = numberOr(cellValue(ws0, r, 5), fallback: 1)
            let q = ImportedQuantity(
                quota: codeCell.jsString.trimmingCharacters(in: .whitespaces),
                variant: variantCell == .null ? "" : variantCell.jsString,
                unit: "", qty: qty, coef: coef)
            if byName[pname] == nil {
                order.append(pname)
                byName[pname] = []
            }
            byName[pname]?.append(q)
        }
    }
    return QuantitiesImportResult(kind: .simple,
                                  projects: order.map { ImportedProject(name: $0, quantities: byName[$0] ?? []) })
}
