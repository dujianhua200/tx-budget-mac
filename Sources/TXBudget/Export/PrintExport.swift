import Foundation

/// 打印导出（对照 Electron `electron/printExport.cjs`，逐表搬运）。
/// 只渲染引擎输出（calcProject 的 table2Before/table2After、table5.rows 等），不重算口径。
/// 数值单元格为数值型；为 0 的金额/工日/台班/数量输出空单元格（参考文件惯例）。
/// 方法列模板与 `Discount.swift` 的 DISCOUNT_LINE_DEFS 逐项一致（见 table2Methods）。

public enum PrintExportError: Error, Equatable, LocalizedError {
    case emptyPath
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyPath: return "导出路径为空"
        case .writeFailed(let msg): return "写入文件失败：\(msg)"
        }
    }
}

// MARK: - 导出上下文（对照 JS buildCtx）

struct PrintContext {
    var project: Project
    var result: CalcResult
    var profile: ConfigurationProfile?
    var info: ProjectInfo // result.info（已合并默认值）
    var projectName: String
    var singleName: String
    var company: String
    var dateStr: String
    var coverDateStr: String
    var prefix: String
    var quotaByCode: [String: QuotaRow] // 首条匹配；profile 为 nil 时为空
    var libByKey: [String: MaterialRow] // "名称|规格" → 行；profile 为 nil 时为空
    var noDisc: Set<String> // 生效的不打折集合（含合计项联动子项）
    var zeroKeys: Set<String> // 生效的折后=0 集合（仅折扣率 < 1 时）
    var vars: [String: String] // 方法列模板变量（已格式化为字符串）
    var discount: Double
    var rate: ResolvedRates { result.rate }
}

// MARK: - 数值格式化（对照 JS money / fmt2 / fmtTrim / pct）

/// 导出数值：0 / 非有限 → 空单元格（参考惯例），其余原样写数值型。
func exportMoney(_ v: Double) -> Double? {
    guard v.isFinite, v != 0 else { return nil }
    return v
}

/// 文本用金额：无千分位，2 位小数（与参考文本一致，如 275517.84）。
func fmt2(_ v: Double) -> String {
    String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), num(v))
}

/// 去尾零的小数（如 12.345 / 0 / 36.5），用于调整备注与里程。
func fmtTrim(_ v: Double) -> String {
    jsNumberString(((num(v) * 1000).rounded()) / 1000)
}

/// 费率/折扣转百分比数字（去浮点噪声：0.015→"1.5"，0.379→"37.9"）。
func pct(_ x: Double) -> String {
    jsNumberString(((num(x) * 100 * 10000).rounded()) / 10000)
}

/// 日期 → “YYYY年M月D日”；解析失败返回 ''。
func formatDateCn(_ s: String) -> String {
    let t = s.trimmingCharacters(in: .whitespaces)
    guard !t.isEmpty else { return "" }
    let patterns = [
        #"^(\d{4})年(\d{1,2})月(\d{1,2})日"#,
        #"^(\d{4})[-/](\d{1,2})[-/](\d{1,2})"#,
    ]
    for p in patterns {
        if let m = t.range(of: p, options: .regularExpression) {
            let parts = t[m].split { !$0.isNumber }.map(String.init)
            if parts.count == 3,
               let y = Int(parts[0]), let mo = Int(parts[1]), let d = Int(parts[2]) {
                return "\(y)年\(mo)月\(d)日"
            }
        }
    }
    return ""
}

func todayCn() -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    return "\(c.year ?? 0)年\(c.month ?? 0)月\(c.day ?? 0)日"
}

/// 信息行页码文本。
func pageText(_ p: Int, _ total: Int) -> String { "第\(p)页 共\(total)页" }

// MARK: - 样式常量（对照 JS F_* / A_* / B_*）

let fTitle = XlsxFont(name: "Noto Sans CJK SC", size: 18, bold: true)
let fTitleCover = XlsxFont(name: "Noto Sans CJK SC", size: 36, bold: true)
let fNotesTitle = XlsxFont(name: "Noto Sans CJK SC", size: 21, bold: true)
let fCoverVal = XlsxFont(name: "黑体", size: 18, bold: true)
let fCoverLabel = XlsxFont(name: "宋体", size: 18, bold: true)
let fCoverNo = XlsxFont(name: "宋体", size: 12, bold: true)
let fInfo = XlsxFont(name: "宋体", size: 9)
let fHead = XlsxFont(name: "宋体", size: 10)
let fData = XlsxFont(name: "宋体", size: 10)
let fFoot = XlsxFont(name: "宋体", size: 10)
let fNotes = XlsxFont(name: "宋体", size: 12)

let aCenter = XlsxAlignment(horizontal: .center, vertical: .center, wrapText: true)
let aLeft = XlsxAlignment(horizontal: .left, vertical: .center, wrapText: true)
let aRight = XlsxAlignment(horizontal: .right, vertical: .center, wrapText: true)
let aLeftTop = XlsxAlignment(horizontal: .left, vertical: .top, wrapText: true)

let bHead = XlsxBorder(top: .medium, bottom: .medium, left: .thin, right: .thin)
let bData = XlsxBorder(top: .thin, bottom: .thin, left: .thin, right: .thin)
let bBottomMedium = XlsxBorder(bottom: .medium)

let moneyFmt = "#,##0.00"
let daysFmt = "0.000"
let qty3Fmt = "#,##0.000"
let price5Fmt = "#,##0.00000"

// MARK: - 工作表构建器

struct SheetBuilder {
    var sheet: XlsxSheet
    let layout: SheetLayout

    init(name: String) {
        let l = sheetLayouts[name]!
        layout = l
        sheet = XlsxSheet(name: name, widths: l.colWidths,
                          pageSetup: XlsxPageSetup(margins: l.margins),
                          maxRow: l.maxRow, maxColumn: l.maxColumn)
    }

    mutating func set(_ r: Int, _ c: Int, _ value: XlsxCellValue, _ style: XlsxCellStyle) {
        sheet.setCell(row: r, col: c, value: value, style: style)
    }

    mutating func setText(_ r: Int, _ c: Int, _ text: String?, font: XlsxFont,
                           alignment: XlsxAlignment, border: XlsxBorder = .none) {
        // 空字符串按空白处理（与空白格显示一致；LibreOffice 重算往返亦归一为无值）。
        let value: XlsxCellValue
        if let text, !text.isEmpty { value = .text(text) } else { value = .blank }
        set(r, c, value,
            XlsxCellStyle(font: font, alignment: alignment, border: border))
    }

    /// 数值格：v 为 nil → 空白（调用方先过 exportMoney）。
    mutating func setNum(_ r: Int, _ c: Int, _ v: Double?, font: XlsxFont,
                          alignment: XlsxAlignment, numFmt: String? = nil, border: XlsxBorder = .none) {
        set(r, c, v.map { .number($0) } ?? .blank,
            XlsxCellStyle(font: font, alignment: alignment, numFmt: numFmt, border: border))
    }

    mutating func merge(_ range: String) { sheet.merge(range) }

    mutating func setHeight(_ r: Int, _ h: Double) { sheet.setRowHeight(r, h) }

    func height(_ r: Int) -> Double? { sheet.rows[r]?.height }

    /// 整行涂边框（headRows 用 B_HEAD，dataRows 用 B_DATA；保留原有值/字体/对齐/数字格式）。
    mutating func paintBorders(maxCol: Int, headRows: [Int], dataRows: [Int]) {
        for r in headRows { for c in 1...maxCol { setBorder(r, c, bHead) } }
        for r in dataRows { for c in 1...maxCol { setBorder(r, c, bData) } }
    }

    mutating func setBorder(_ r: Int, _ c: Int, _ border: XlsxBorder) {
        var cell = sheet.rows[r]?.cells[c] ?? XlsxCell()
        var style = cell.style ?? XlsxCellStyle()
        style.border = border
        cell.style = style
        sheet.setCell(row: r, col: c, value: cell.value, style: style)
    }

    /// 固定单页表：按版式行高逐行设置。
    mutating func applyFixedRowHeights() {
        for r in 1...layout.maxRow {
            setHeight(r, layout.rowHeights[r] ?? layout.defaultRowHeight)
        }
    }

    /// 固定表：应用版式合并区。
    mutating func applyLayoutMerges() {
        for m in layout.merged { merge(m) }
    }
}

/// 估算数据行高：换行符与超长文本按 7.2pt/行递增（2 行 = 23.75，与参考表三丙一致）。
/// 长度按 UTF-16 计（与 JS String.length 一致）。
func estimateRowHeight(_ cells: [(text: String?, width: Double)]) -> Double {
    var lines = 1
    for (text, width) in cells {
        guard let text, !text.isEmpty else { continue }
        let nl = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let len = text.replacingOccurrences(of: "\n", with: "").utf16.count
        let wrapped = max(1, Int(ceil(Double(len) / max(10, width))))
        lines = max(lines, nl, wrapped)
    }
    return 16.55 + Double(lines - 1) * 7.2
}

/// 表尾四段式（施工负责人 / 审核 / 编制 / 编制日期），按给定合并区写。
/// leader：第一段前导空格（汇总表/表一用 6 空格；其余表无）。
func writeFooter(_ b: inout SheetBuilder, _ row: Int, _ merges: [String],
                  _ ctx: PrintContext, leader: String = "") {
    let texts = [
        "\(leader)施工负责人：\(ctx.info.工程负责人)",
        "审核：\(ctx.info.审核)",
        "编制：\(ctx.info.编制)",
        "编制日期：\(ctx.dateStr)",
    ]
    for (i, range) in merges.enumerated() {
        b.merge(range)
        let (r, c) = parseCellRef(range)
        b.setText(r, c, texts[i], font: fFoot, alignment: aLeft)
    }
}

/// 合并区左上角行列（"A25:D25" → (25, 1)）。
func parseCellRef(_ range: String) -> (Int, Int) {
    let start = range.split(separator: ":").first ?? ""
    var col = 0
    var rowStr = ""
    for ch in start {
        if ch.isLetter { col = col * 26 + Int(ch.asciiValue! - 65) + 1 } else { rowStr.append(ch) }
    }
    return (Int(rowStr) ?? 1, col)
}

// MARK: - 表二：固定双栏布局与方法列模板

struct Table2RowDef: Equatable {
    var seq: String
    var label: String
    var key: String?
}

let table2Left: [Table2RowDef] = [
    .init(seq: "", label: "建安工程费(含税价)", key: "inclTax"),
    .init(seq: "", label: "建安工程费(除税价)", key: "exclTax"),
    .init(seq: "一", label: "直接费", key: "directTotal"),
    .init(seq: "(一)", label: "直接工程费", key: "directFee"),
    .init(seq: "1", label: "人工费", key: "laborTotal"),
    .init(seq: "⑴", label: "技工费", key: "techFee"),
    .init(seq: "⑵", label: "普工费", key: "laborFee"),
    .init(seq: "2", label: "材料费", key: "matTotal"),
    .init(seq: "⑴", label: "主要材料费", key: "mainMat"),
    .init(seq: "⑵", label: "辅助材料费", key: "auxMat"),
    .init(seq: "3", label: "机械使用费", key: "machineFee"),
    .init(seq: "4", label: "仪表使用费", key: "instrumentFee"),
    .init(seq: "(二)", label: "措施项目费", key: "measureFee"),
    .init(seq: "1", label: "文明施工费", key: "civilFee"),
    .init(seq: "2", label: "工地器材搬运费", key: "carryFee"),
    .init(seq: "3", label: "工程干扰费", key: "disturbFee"),
    .init(seq: "4", label: "工程点交、场地清理费", key: "handoverFee"),
    .init(seq: "5", label: "临时设施费", key: "tempFee"),
    .init(seq: "6", label: "工程车辆使用费", key: "vehicleFee"),
]

let table2Right: [Table2RowDef] = [
    .init(seq: "7", label: "夜间施工增加费", key: "nightFee"),
    .init(seq: "8", label: "冬雨季施工增加费", key: "winterFee"),
    .init(seq: "9", label: "生产工具用具使用费", key: "toolFee"),
    .init(seq: "10", label: "施工用水电蒸汽费", key: "utilityFee"),
    .init(seq: "11", label: "特殊地区施工增加费", key: "specialFee"),
    .init(seq: "12", label: "已完工程及设备保护费", key: "protectFee"),
    .init(seq: "13", label: "运土费", key: "earthFee"),
    .init(seq: "14", label: "施工队伍调遣费", key: "dispatchFee"),
    .init(seq: "15", label: "大型施工机械调遣费", key: "bigMachineFee"),
    .init(seq: "二", label: "间接费", key: "indirectTotal"),
    .init(seq: "(一)", label: "规费", key: "regFee"),
    .init(seq: "1", label: "工程排污费", key: "sewageFee"),
    .init(seq: "2", label: "社会保障费", key: "socialFee"),
    .init(seq: "3", label: "住房公积金", key: "housingFee"),
    .init(seq: "4", label: "危险作业意外伤害保险\n费", key: "accidentFee"),
    .init(seq: "(二)", label: "企业管理费", key: "mgmtFee"),
    .init(seq: "三", label: "利润", key: "profit"),
    .init(seq: "四", label: "销项税额", key: "outputTax"),
    .init(seq: "", label: "", key: nil),
]

/// 方法列模板（before / discounted / restored，与 discount.mjs 的 DISCOUNT_LINE_DEFS 逐项一致）。
let table2Methods: [String: (before: String, discounted: String, restored: String)] = [
    "techFee": ("技工总工日X{techPrice}", "技工总工日X{techPrice}X{discountPct}%", "技工总工日X{techPrice}/{discountPct}%"),
    "laborFee": ("普工总工日X{laborPrice}", "普工总工日X{laborPrice}X{discountPct}%", "普工总工日X{laborPrice}/{discountPct}%"),
    "laborTotal": ("技工费+普工费", "技工费+普工费", "技工费+普工费"),
    "jiaMat": ("甲供材料费用", "甲供材料费用X{discountPct}%", "甲供材料费用"),
    "yiMat": ("乙供材料费用", "乙供材料费用X{discountPct}%", "乙供材料费用"),
    "mainMat": ("主材费用", "主材费用", "主材费用"),
    "auxMat": ("主要材料费X{auxRate}%", "主要材料费X{auxRate}%X{discountPct}%", "主要材料费X{auxRate}%"),
    "matTotal": ("主要材料费+辅助材料费", "主要材料费+辅助材料费", "主要材料费+辅助材料费"),
    "machineFee": ("机械费合计", "机械费合计X{discountPct}%", "机械费合计"),
    "instrumentFee": ("仪表费合计", "仪表费合计X{discountPct}%", "仪表费合计"),
    "directFee": ("1-4之和", "1-4之和", "1-4之和"),
    "civilFee": ("人工费X{civilRate}%", "人工费X{civilRate}%X{discountPct}%", "人工费X{civilRate}%/{discountPct}%"),
    "carryFee": ("人工费X{carryRate}%", "人工费X{carryRate}%X{discountPct}%", "人工费X{carryRate}%"),
    "disturbFee": ("人工费X{disturbRate}%", "人工费X{disturbRate}%X{discountPct}%", "人工费X{disturbRate}%"),
    "handoverFee": ("人工费X{handoverRate}%", "人工费X{handoverRate}%", "人工费X{handoverRate}%"),
    "tempFee": ("人工费X{tempRate}%", "人工费X{tempRate}%X{discountPct}%", "人工费X{tempRate}%/{discountPct}%"),
    "vehicleFee": ("人工费X{vehicleRate}%", "人工费X{vehicleRate}%", "人工费X{vehicleRate}%"),
    "nightFee": ("人工费X{nightRate}%", "人工费X{nightRate}%X{discountPct}%", "人工费X{nightRate}%"),
    "winterFee": ("人工费X{winterRate}%", "人工费X{winterRate}%X{discountPct}%", "人工费X{winterRate}%"),
    "toolFee": ("人工费X{toolRate}%", "人工费X{toolRate}%", "人工费X{toolRate}%"),
    "utilityFee": ("人工费X{utilityRate}%", "人工费X{utilityRate}%X{discountPct}%", "人工费X{utilityRate}%"),
    "specialFee": ("工日X8X0", "工日X8X0X{discountPct}%", "工日X8X0"),
    "protectFee": ("人工费X{protectRate}%", "人工费X{protectRate}%X{discountPct}%", "人工费X{protectRate}%"),
    "earthFee": ("运土费", "运土费X{discountPct}%", "运土费"),
    "dispatchFee": ("调遣单价X人数X2", "调遣单价X人数X2X{discountPct}%", "调遣单价X人数X2"),
    "bigMachineFee": ("大型施工机械调遣费", "大型施工机械调遣费X{discountPct}%", "大型施工机械调遣费"),
    "measureFee": ("1-15之和", "1-15之和", "1-15之和"),
    "directTotal": ("(一)+(二)", "(一)+(二)", "(一)+(二)"),
    "sewageFee": ("工程排污费", "工程排污费X{discountPct}%", "工程排污费"),
    "socialFee": ("人工费X{socialRate}%", "人工费X{socialRate}%", "人工费X{socialRate}%"),
    "housingFee": ("人工费X{housingRate}%", "人工费X{housingRate}%", "人工费X{housingRate}%"),
    "accidentFee": ("人工费X{accidentRate}%", "人工费X{accidentRate}%", "人工费X{accidentRate}%"),
    "regFee": ("1-4之和", "1-4之和", "(1-4之和)/{discountPct}%"),
    "mgmtFee": ("人工费X{mgmtRate}%", "人工费X{mgmtRate}%", "人工费X{mgmtRate}%"),
    "indirectTotal": ("(一)+(二)", "(一)+(二)", "(一)+(二)"),
    "profit": ("人工费X{profitRate}%", "人工费X{profitRate}%", "人工费X{profitRate}%"),
    "exclTax": ("一+二+三", "一+二+三", "一+二+三"),
    "outputTax": ("销项税额", "销项税额", "销项税额"),
    "inclTax": ("一+二+三+四", "一+二+三+四", "一+二+三+四"),
]

/// 模板变量替换：{name} → vars[name]，缺失保留原样（与 JS replace 一致）。
func substituteTemplate(_ tpl: String, vars: [String: String]) -> String {
    var out = ""
    var i = tpl.startIndex
    while i < tpl.endIndex {
        if tpl[i] == "{", let close = tpl[i...].firstIndex(of: "}") {
            let key = String(tpl[tpl.index(after: i)..<close])
            out += vars[key] ?? "{\(key)}"
            i = tpl.index(after: close)
        } else {
            out.append(tpl[i])
            i = tpl.index(after: i)
        }
    }
    return out
}

/// 渲染表二一行的方法列。after=true → 折后表，false → 折前表。
func table2Method(_ key: String, after: Bool, t2: Table2, ctx: PrintContext) -> String {
    // 折后=0 的项：折后表整行空（含方法列，与参考折后表一致）；折前表不受影响。
    if after && ctx.zeroKeys.contains(key) { return "" }
    // 调遣费：用实际数值写法（与参考折前表“174X17X2”一致）。
    if key == "dispatchFee" {
        let base = "\(fmtTrim(t2.dispatchUnit))X\(fmtTrim(t2.dispatchPeople))X2"
        if !after { return base }
        return ctx.noDisc.contains(key) ? base : "\(base)X\(ctx.vars["discountPct"] ?? "")%"
    }
    // 施工用水电蒸汽费率为 0 时方法列为空（参考折前表该行方法列为空）。
    if key == "utilityFee" && !(ctx.rate.utilityRate > 0) { return "" }
    guard let tpl = table2Methods[key] else { return "" }
    let t = !after ? tpl.before : (ctx.noDisc.contains(key) ? tpl.restored : tpl.discounted)
    return substituteTemplate(t, vars: ctx.vars)
}

/// noDiscountKeys 合计项联动子项（与 Discount.swift 的 discountParentChildren 一致）。
func effectiveNoDisc(_ list: [String]) -> Set<String> {
    var s = Set(list)
    if s.contains("mainMat") { s.insert("jiaMat"); s.insert("yiMat") }
    if s.contains("regFee") {
        s.insert("sewageFee"); s.insert("socialFee"); s.insert("housingFee"); s.insert("accidentFee")
    }
    return s
}

// MARK: - 分页

/// 表三甲分页：首 23、后续每页数据 ≤18（含合计行占 1 槽，末页数据 ≤17）。
func paginateTable3A(_ n: Int) -> [Int] {
    if n <= 22 { return [n] }
    var chunks = [23]
    var rest = n - 23
    while rest > 17 { chunks.append(18); rest -= 18 }
    chunks.append(rest) // rest ∈ [0,17]；0 = 合计行独占一页
    return chunks
}

/// 通用溢出分页（表三乙/丙、表四甲、表五甲）：非末页满页，末页留 1 行表尾。
func chunkSequence(_ n: Int, pageTotal: Int, headerRows: Int) -> [Int] {
    let fullCap = pageTotal - headerRows
    let lastCap = pageTotal - headerRows - 1
    if n <= lastCap { return [n] }
    var chunks: [Int] = []
    var rest = n
    while rest > lastCap {
        let take = min(fullCap, rest - 1)
        chunks.append(take)
        rest -= take
    }
    chunks.append(rest)
    return chunks
}

// MARK: - 1. 报表封面

func buildCover(_ ctx: PrintContext) -> XlsxSheet {
    var b = SheetBuilder(name: "报表封面")
    b.applyFixedRowHeights()
    b.applyLayoutMerges()
    let info = ctx.info
    b.setText(1, 1, "通信建设工程预算书", font: fTitleCover, alignment: aCenter)
    b.setText(2, 5, info.项目编号.isEmpty ? info.表格编号 : info.项目编号,
              font: fCoverNo, alignment: aCenter)
    let labels = [" 建设单位：", " 工程名称：", " 工程造价：", " 设计单位：",
                  " 施工单位：", " 监理单位：", " 编制单位：", " 参审人员："]
    let values = [
        ctx.company, ctx.projectName, "\(fmt2(ctx.result.table1.grandIncl))元",
        info.设计单位 ?? "", info.施工单位 ?? "", info.监理单位,
        "", "",
    ]
    for (i, lab) in labels.enumerated() {
        let r = 4 + i
        b.setText(r, 1, lab, font: fCoverLabel, alignment: aLeft)
        b.setText(r, 2, values[i], font: fCoverVal, alignment: aLeft)
    }
    b.setText(13, 1, " 编制人：", font: fCoverLabel, alignment: aLeft)
    b.setText(13, 2, info.编制, font: fCoverVal, alignment: aLeft)
    b.setText(13, 3, " 审核人：", font: fCoverLabel, alignment: aLeft)
    b.setText(13, 4, info.审核, font: fCoverVal, alignment: aLeft)
    b.setText(14, 1, " 资格证号：", font: fCoverLabel, alignment: aLeft)
    b.setText(14, 2, "", font: fCoverVal, alignment: aLeft)
    b.setText(14, 3, " 资格证号：", font: fCoverLabel, alignment: aLeft)
    b.setText(14, 4, "", font: fCoverVal, alignment: aLeft)
    b.setText(15, 1, ctx.coverDateStr, font: fCoverVal, alignment: aCenter)
    return b.sheet
}

// MARK: - 2. 编制说明

let noDiscLabels: [String: String] = [
    "mainMat": "主要材料费", "auxMat": "辅助材料费", "civilFee": "文明施工费", "regFee": "规费",
    "socialFee": "社会保障费", "housingFee": "住房公积金", "accidentFee": "危险作业意外伤害保险费",
    "sewageFee": "工程排污费", "safetyFee": "安全生产费", "jiaMat": "甲供材料", "yiMat": "乙供材料",
]

func buildNotes(_ ctx: PrintContext) -> XlsxSheet {
    var b = SheetBuilder(name: "编制说明")
    b.applyFixedRowHeights()
    b.setText(1, 1, "编制说明", font: fNotesTitle, alignment: aCenter, border: bBottomMedium)
    let info = ctx.info
    let t1 = ctx.result.table1
    var discountLine = ""
    if ctx.discount < 1 {
        let keys = ctx.result.discountRule.noDiscountKeys
        var labels: [String] = []
        for k in keys {
            if k == "regFee" { if !labels.contains("规费") { labels.append("规费") }; continue }
            if ["socialFee", "housingFee", "accidentFee", "sewageFee"].contains(k) && keys.contains("regFee") { continue }
            if ["jiaMat", "yiMat"].contains(k) && keys.contains("mainMat") { continue }
            if let lab = noDiscLabels[k], !labels.contains(lab) { labels.append(lab) }
        }
        discountLine = "\n  5.施工折扣按\(ctx.vars["discountPct"] ?? "")%计取，打折不含\(labels.joined(separator: "、"))。"
    }
    let text = "一、编制依据："
        + "\n  1.本工程定额套用中华人民共和国工业和信息化部《通信建设工程预算定额》与《通信建设工程施工机械、仪表台班费用定额》2017年版。"
        + "\n  2.取费标准及其它费用均按照工信部通信(2016)451号文发布的《通信建设工程概算、预算编制办法》、《通信建设工程费用定额》执行。"
        + "\n  3.勘查设计费：参照国家计委、建设部《关于发布<工程勘查设计费管理规定》的通知》计价格(2002)10号规定。"
        + "\n  4.建设工程监理费：根据《国家发展改革委关于进一步开放建设项目专业服务价格的通知》(发改价格(2015)299号）文件要求。"
        + discountLine
        + "\n\n二、造价分析："
        + "\n  1.本工程属\(info.工程类型),工程共分为：\(info.工程类型)一个分项工程。"
        + "\n    第一个分项工程所在地距基地为\(fmtTrim(num(info.施工实际里程)))公里，由企业施工。 "
        + "\n  2.工程总费用：\(fmt2(t1.grandIncl))，增值税\(fmt2(t1.grandVat))，"
        + "\n    其中建筑安装工程费：\(fmt2(t1.afterDiscount))，小型建筑工程费：0.00，"
        + "\n    安装设备费：\(fmt2(t1.equipFee))，不安装设备费：0.00，"
        + "\n    其他费用：\(fmt2(t1.otherFee))，预备费：0.00。"
    b.setText(2, 1, text, font: fNotes, alignment: aLeftTop)
    return b.sheet
}

// MARK: - 3. 汇总表

func buildSummary(_ ctx: PrintContext) -> XlsxSheet {
    var b = SheetBuilder(name: "建设项目总算表(汇总表)")
    b.applyFixedRowHeights()
    b.applyLayoutMerges()
    let t1 = ctx.result.table1
    let t5 = ctx.result.table5
    let equipExcl = num(t1.equipFee)
    let equipVat = num(t1.equipVat)
    let after = num(t1.afterDiscount)
    let other = num(t1.otherFee)
    let otherVat = num(t1.otherVat)
    let taxAfter = num(t1.taxAfter)
    let prodPrep = num(t5.productionPrepFee)
    let totalExcl = equipExcl + after + other
    let totalVat = equipVat + taxAfter + otherVat
    b.setText(1, 1, "建设项目总预算表（汇总表）", font: fTitle, alignment: aCenter)
    b.setText(2, 1, "建设项目名称：\(ctx.projectName)", font: fInfo, alignment: aLeft)
    b.setText(2, 6, "建设单位名称：\(ctx.company)", font: fInfo, alignment: aLeft)
    b.setText(2, 11, "表格编号：-总", font: fInfo, alignment: aLeft)
    b.setText(2, 13, pageText(1, 1), font: fInfo, alignment: aRight)
    let headers3: [String?] = ["序\n号", "表格编号", "工程名称", "小型建筑\n工程费", "需要安装\n的设备费",
                                "不需要安装\n的设备、工\n器具费", "建筑安装\n工程费", "其他费用", "预备费",
                                "总 价 值", nil, nil, nil, "生产准备\n及开办费"]
    for (i, h) in headers3.enumerated() {
        if let h { b.setText(3, i + 1, h, font: fHead, alignment: aCenter) }
    }
    b.setText(4, 4, "（元）", font: fHead, alignment: aCenter)
    b.setText(4, 10, "除税价", font: fHead, alignment: aCenter)
    b.setText(4, 11, "增值税", font: fHead, alignment: aCenter)
    b.setText(4, 12, "含税价", font: fHead, alignment: aCenter)
    b.setText(4, 13, "其中外币\n()", font: fHead, alignment: aCenter)
    b.setText(4, 14, "（元）", font: fHead, alignment: aCenter)
    let roman = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ", "Ⅹ", "Ⅺ", "Ⅻ", "XIII", "XIV"]
    for (i, r) in roman.enumerated() { b.setText(5, i + 1, r, font: fData, alignment: aCenter) }
    let rowVals: [Double?] = [nil, nil, nil, nil, exportMoney(equipExcl), nil,
                               exportMoney(after), exportMoney(other), nil,
                               exportMoney(totalExcl), exportMoney(totalVat),
                               exportMoney(totalExcl + totalVat), nil, exportMoney(prodPrep)]
    func writeDataRow(_ r: Int, _ seq: Int, _ tableNo: String, _ feeName: String) {
        b.setNum(r, 1, Double(seq), font: fData, alignment: aCenter)
        b.setText(r, 2, tableNo, font: fData, alignment: aCenter)
        b.setText(r, 3, feeName, font: fData, alignment: aLeft)
        for (i, v) in rowVals.enumerated() {
            if i < 3 { continue }
            b.setNum(r, i + 1, v, font: fData, alignment: aRight, numFmt: moneyFmt)
        }
    }
    writeDataRow(6, 1, "\(ctx.prefix)1", ctx.singleName)
    writeDataRow(7, 2, "", "工程总计")
    b.paintBorders(maxCol: 14, headRows: [3, 4], dataRows: Array(5...24))
    writeFooter(&b, 25, ["A25:D25", "E25:G25", "H25:J25", "K25:N25"], ctx, leader: "      ")
    return b.sheet
}

// MARK: - 4. 表一

func buildTable1(_ ctx: PrintContext) -> XlsxSheet {
    var b = SheetBuilder(name: "工程总表(表一)")
    b.applyFixedRowHeights()
    b.applyLayoutMerges()
    let t1 = ctx.result.table1
    let equipExcl = num(t1.equipFee)
    let equipVat = num(t1.equipVat)
    let after = num(t1.afterDiscount)
    let other = num(t1.otherFee)
    let otherVat = num(t1.otherVat)
    let taxAfter = num(t1.taxAfter)
    b.setText(1, 1, "工程预算总表(表一)", font: fTitle, alignment: aCenter)
    b.setText(2, 1, "建设项目名称：\(ctx.projectName)", font: fInfo, alignment: aLeft)
    b.setText(3, 1, "项目名称：\(ctx.singleName)", font: fInfo, alignment: aLeft)
    b.setText(3, 5, "建设单位名称：\(ctx.company)", font: fInfo, alignment: aLeft)
    b.setText(3, 10, "表格编号：-1", font: fInfo, alignment: aLeft)
    b.setText(3, 12, pageText(1, 1), font: fInfo, alignment: aRight)
    let headers4: [String?] = ["序\n号", "表格编号", "费用名称", "小型建筑\n工程费", "需要安装\n的设备费",
                                "不需要安装\n的设备、工\n器具费", "建筑安装\n工程费", "其他费用", "预备费",
                                "总 价 值", nil, nil, nil]
    for (i, h) in headers4.enumerated() {
        if let h { b.setText(4, i + 1, h, font: fHead, alignment: aCenter) }
    }
    b.setText(5, 4, "（元）", font: fHead, alignment: aCenter)
    b.setText(5, 10, "除税价", font: fHead, alignment: aCenter)
    b.setText(5, 11, "增值税", font: fHead, alignment: aCenter)
    b.setText(5, 12, "含税价", font: fHead, alignment: aCenter)
    b.setText(5, 13, "其中外币\n()", font: fHead, alignment: aCenter)
    let roman = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ", "Ⅹ", "Ⅺ", "Ⅻ", "XIII"]
    for (i, r) in roman.enumerated() { b.setText(6, i + 1, r, font: fData, alignment: aCenter) }
    func writeRow(_ r: Int, _ seq: Int, _ tableNo: String, _ feeName: String,
                  _ e: Double, _ g: Double, _ h: Double) {
        let excl = num(e) + num(g) + num(h)
        let vat: Double
        if r == 7 { vat = num(equipVat) + taxAfter }
        else if r == 8 { vat = otherVat }
        else { vat = num(equipVat) + taxAfter + otherVat }
        b.setNum(r, 1, Double(seq), font: fData, alignment: aCenter)
        b.setText(r, 2, tableNo, font: fData, alignment: aCenter)
        b.setText(r, 3, feeName, font: fData, alignment: aLeft)
        b.setNum(r, 5, exportMoney(e), font: fData, alignment: aRight, numFmt: moneyFmt)
        b.setNum(r, 7, exportMoney(g), font: fData, alignment: aRight, numFmt: moneyFmt)
        b.setNum(r, 8, exportMoney(h), font: fData, alignment: aRight, numFmt: moneyFmt)
        b.setNum(r, 10, exportMoney(excl), font: fData, alignment: aRight, numFmt: moneyFmt)
        b.setNum(r, 11, exportMoney(vat), font: fData, alignment: aRight, numFmt: moneyFmt)
        b.setNum(r, 12, exportMoney(excl + vat), font: fData, alignment: aRight, numFmt: moneyFmt)
    }
    writeRow(7, 1, "\(ctx.prefix)2", "工程费", equipExcl, after, 0)
    writeRow(8, 2, "\(ctx.prefix)5甲", "工程建设其他费", 0, 0, other)
    writeRow(9, 3, "", "总 计", equipExcl, after, other)
    b.paintBorders(maxCol: 13, headRows: [4, 5], dataRows: Array(6...26))
    writeFooter(&b, 27, ["A27:D27", "E27:G27", "H27:J27", "K27:M27"], ctx, leader: "      ")
    return b.sheet
}

// MARK: - 5/6. 表二（折后 / 折前）：版式完全一致，仅方法列与数值不同

func buildTable2(_ ctx: PrintContext, after: Bool) -> XlsxSheet {
    let sheetName = after ? "工程费用表(表二)" : "工程费用表(表二)折前"
    var b = SheetBuilder(name: sheetName)
    b.applyFixedRowHeights()
    b.applyLayoutMerges()
    let t2 = after ? ctx.result.table2After : ctx.result.table2Before
    b.setText(1, 1, after ? "建筑安装工程费用预算表（表二）" : "建筑安装工程费用预算表（表二折前）",
              font: fTitle, alignment: aCenter)
    b.setText(2, 1, "工程名称：\(ctx.singleName)", font: fInfo, alignment: aLeft)
    b.setText(2, 4, "建设单位名称：\(ctx.company)", font: fInfo, alignment: aLeft)
    b.setText(2, 9, "表格编号：-2", font: fInfo, alignment: aLeft)
    b.setText(2, 10, pageText(1, 1), font: fInfo, alignment: aRight)
    b.setText(3, 1, "序号", font: fHead, alignment: aCenter)
    b.setText(3, 2, "费用名称", font: fHead, alignment: aCenter)
    b.setText(3, 3, "依据和计算方法", font: fHead, alignment: aCenter)
    b.setText(3, 4, "合计(元)", font: fHead, alignment: aCenter)
    b.setText(3, 5, " ", font: fHead, alignment: aLeft)
    b.setText(3, 6, "序号", font: fHead, alignment: aCenter)
    b.setText(3, 7, "费用名称", font: fHead, alignment: aCenter)
    b.setText(3, 8, "依据和计算方法", font: fHead, alignment: aCenter)
    b.setText(3, 10, "合计(元)", font: fHead, alignment: aCenter)
    for (c, v) in [(1, "Ⅰ"), (2, "Ⅱ"), (3, "Ⅲ"), (4, "Ⅳ"), (6, "Ⅰ"), (7, "Ⅱ"), (8, "Ⅲ"), (10, "Ⅳ")] {
        b.setText(4, c, v, font: fData, alignment: aCenter)
    }
    func writeSide(_ rows: [Table2RowDef], _ cols: [Int]) {
        for (i, row) in rows.enumerated() {
            let r = 5 + i
            let (seqC, labelC, methodC, valueC) = (cols[0], cols[1], cols[2], cols[3])
            b.setText(r, seqC, row.seq.isEmpty ? nil : row.seq, font: fData, alignment: aCenter)
            b.setText(r, labelC, row.label.isEmpty ? nil : row.label, font: fData, alignment: aLeft)
            let method = row.key.map { table2Method($0, after: after, t2: t2, ctx: ctx) } ?? ""
            b.setText(r, methodC, method.isEmpty ? nil : method, font: fData, alignment: aLeft)
            let value = row.key.flatMap { k in t2.values[k].flatMap(exportMoney) }
            b.setNum(r, valueC, value, font: fData, alignment: aRight, numFmt: moneyFmt)
        }
    }
    writeSide(table2Left, [1, 2, 3, 4])
    writeSide(table2Right, [6, 7, 8, 10])
    b.paintBorders(maxCol: 10, headRows: [3, 4], dataRows: Array(5...23))
    // 表尾：A24:B24 / C24:D24 / F24:H24 / I24:J24（E24 为间隔列，留空格）。
    b.merge("A24:B24")
    b.setText(24, 1, "施工负责人：\(ctx.info.工程负责人)", font: fFoot, alignment: aLeft)
    b.merge("C24:D24")
    b.setText(24, 3, "     审核：\(ctx.info.审核)", font: fFoot, alignment: aLeft)
    b.setText(24, 5, " ", font: fFoot, alignment: aLeft)
    b.merge("F24:H24")
    b.setText(24, 6, "编制：\(ctx.info.编制)", font: fFoot, alignment: aLeft)
    b.merge("I24:J24")
    b.setText(24, 9, "    编制日期：\(ctx.dateStr)", font: fFoot, alignment: aLeft)
    return b.sheet
}

// MARK: - 工程量分组（对照 JS groupQuantities）

enum GroupedKind { case normal, orphan }

struct GroupedQuantity {
    var kind: GroupedKind
    var code: String
    var variant: String
    var unit: String // 普通组：首行有效单位（行快照 ?? 定额库）；孤儿行：工程量行 unit
    var weighted: Double
    /// 普通组首行的有效单位工日（v2.6.0 快照模型：行快照 ?? 定额库值）；孤儿行为 0。
    var techUnit: Double = 0
    var laborUnit: Double = 0
}

/// 工程量按 (定额编号, 变体) 分组（首次出现顺序；孤儿行单独成组）。
/// splitBySnapshot（v2.6.0，仅导出表三甲用）：组键追加有效技工/普工/单位判别，
/// 改过工日快照的行自成一组（与引擎表三甲分组同口径）；表三乙/丙不启用，
/// 分组与旧版逐项一致。
func groupQuantities(_ project: Project, _ quotaByCode: [String: QuotaRow],
                     splitBySnapshot: Bool = false) -> [GroupedQuantity] {
    var entries: [GroupedQuantity] = []
    var map: [String: Int] = [:]
    for q in project.quantities {
        let qty = num(q.qty)
        if let quota = quotaByCode[q.quota] {
            let coef = q.coef ?? 1
            if !(qty > 0) || !(coef > 0) { continue } // 零/无效行不参与计算（与引擎一致）
            let effTech = q.tech ?? num(quota.tech)
            let effLabor = q.labor ?? num(quota.labor)
            let effUnit = q.unit ?? quota.unit
            var key = "q|\(q.quota)|\(q.variant ?? "")"
            if splitBySnapshot { key += "|\(effTech)|\(effLabor)|\(effUnit)" }
            if let idx = map[key] { entries[idx].weighted += qty * coef }
            else {
                map[key] = entries.count
                entries.append(GroupedQuantity(kind: .normal, code: q.quota, variant: q.variant ?? "",
                                               unit: effUnit, weighted: qty * coef,
                                               techUnit: effTech, laborUnit: effLabor))
            }
        } else {
            if !(qty > 0) { continue }
            let coef = (q.coef != nil && q.coef! > 0) ? q.coef! : 1
            let key = "o|\(q.quota)|\(q.variant ?? "")"
            if let idx = map[key] { entries[idx].weighted += qty * coef }
            else {
                map[key] = entries.count
                entries.append(GroupedQuantity(kind: .orphan, code: q.quota, variant: q.variant ?? "",
                                              unit: q.unit ?? "", weighted: qty * coef))
            }
        }
    }
    return entries
}

/// 定额项目显示名：variant 是**完整变体项目名称**（如“挂钩法架设架空光缆 平原 6芯”），
/// 非空时直接用 variant（替换定额库名），为空时取定额库 name。
/// 注意：不得拼接 `quota.name + variant`——定额库名（如 TXL3-187 的“…平原 36 芯以下”）
/// 与 variant（如“…平原 6芯”）拼接会在导出表三甲 C 列出现重复（v1.0.0 bug，见 A1）。
/// 结算书 ground truth：TXL3-187 行即 variant 单独；TXL3-192 三行分别为丘陵、城区、水田 6/12/24芯。
/// Electron `printExport.cjs:615-617` 有同一行拼接 bug（不在原生修复范围，见汇报）。
func displayName(_ quota: QuotaRow, _ variant: String) -> String {
    variant.isEmpty ? quota.name : variant
}

// MARK: - 7. 表三甲（分页：每页 29 行）

struct Table3AEntry {
    var code: String
    var name: String
    var unit: String
    var qty: Double
    var techUnit: Double
    var laborUnit: Double
    var tech: Double
    var labor: Double
}

func table3AEntries(_ ctx: PrintContext) -> [Table3AEntry] {
    if let profile = ctx.profile {
        _ = profile
        return groupQuantities(ctx.project, ctx.quotaByCode, splitBySnapshot: true).map { e in
            if e.kind == .orphan {
                let isNoFee = e.code == "不取费" || e.code.contains("不取费") || e.code.contains("预留")
                return Table3AEntry(
                    code: isNoFee ? "不取费" : e.code,
                    name: e.code == "不取费" ? e.variant
                        : (isNoFee ? "\(e.code)\(e.variant.isEmpty ? "" : " \(e.variant)")" : e.variant),
                    unit: e.unit, qty: r2(e.weighted),
                    techUnit: 0, laborUnit: 0, tech: 0, labor: 0)
            }
            let quota = ctx.quotaByCode[e.code]!
            return Table3AEntry(
                code: e.code, name: displayName(quota, e.variant), unit: e.unit,
                qty: r2(e.weighted), techUnit: e.techUnit, laborUnit: e.laborUnit,
                tech: r2(e.weighted * e.techUnit), labor: r2(e.weighted * e.laborUnit))
        }
    }
    return ctx.result.table3A.map {
        Table3AEntry(code: $0.code, name: $0.name, unit: $0.unit, qty: $0.qty,
                     techUnit: $0.techUnit, laborUnit: $0.laborUnit, tech: $0.tech, labor: $0.labor)
    }
}

func buildTable3A(_ ctx: PrintContext) -> XlsxSheet {
    var b = SheetBuilder(name: "工程量表(表三)甲")
    let entries = table3AEntries(ctx)
    let n = entries.count
    let chunks = paginateTable3A(n)
    let totalPages = chunks.count
    let result = ctx.result
    let techSub = num(result.techSub)
    let laborSub = num(result.laborSub)
    let techDays = num(result.techDays)
    let laborDays = num(result.laborDays)
    var adjNote = ""
    let techAdj = techDays - techSub
    let laborAdj = laborDays - laborSub
    if abs(techAdj) > 0.0005 || abs(laborAdj) > 0.0005 {
        adjNote = "（其中调整技工 +\(fmtTrim(techAdj)) / 普工 +\(fmtTrim(laborAdj)) 工日）"
    }
    var cursor = 0
    for (pi, size) in chunks.enumerated() {
        let base = pi * 29
        let page = pi + 1
        let isLast = pi == totalPages - 1
        b.merge("A\(base + 1):J\(base + 1)")
        b.setText(base + 1, 1, "建筑安装工程量预算表（表三）甲", font: fTitle, alignment: aCenter)
        b.merge("A\(base + 2):C\(base + 2)")
        b.setText(base + 2, 1, "工程名称：\(ctx.singleName)", font: fInfo, alignment: aLeft)
        b.merge("D\(base + 2):G\(base + 2)")
        b.setText(base + 2, 4, "建设单位名称：\(ctx.company)", font: fInfo, alignment: aLeft)
        b.merge("H\(base + 2):I\(base + 2)")
        b.setText(base + 2, 8, "表格编号：-3甲", font: fInfo, alignment: aLeft)
        b.setText(base + 2, 10, pageText(page, totalPages), font: fInfo, alignment: aRight)
        b.merge("A\(base + 3):A\(base + 4)")
        b.setText(base + 3, 1, "序号", font: fHead, alignment: aCenter)
        b.merge("B\(base + 3):B\(base + 4)")
        b.setText(base + 3, 2, "定额编号", font: fHead, alignment: aCenter)
        b.merge("C\(base + 3):D\(base + 4)")
        b.setText(base + 3, 3, "项目名称", font: fHead, alignment: aCenter)
        b.merge("E\(base + 3):E\(base + 4)")
        b.setText(base + 3, 5, "单位", font: fHead, alignment: aCenter)
        b.merge("F\(base + 3):F\(base + 4)")
        b.setText(base + 3, 6, "数量", font: fHead, alignment: aCenter)
        b.merge("G\(base + 3):H\(base + 3)")
        b.setText(base + 3, 7, "单位定额值（工日）", font: fHead, alignment: aCenter)
        b.merge("I\(base + 3):J\(base + 3)")
        b.setText(base + 3, 9, "合计值（工日）", font: fHead, alignment: aCenter)
        b.setText(base + 4, 7, "技工", font: fHead, alignment: aCenter)
        b.setText(base + 4, 8, "普工", font: fHead, alignment: aCenter)
        b.setText(base + 4, 9, "技工", font: fHead, alignment: aCenter)
        b.setText(base + 4, 10, "普工", font: fHead, alignment: aCenter)
        let roman = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ"]
        b.merge("C\(base + 5):D\(base + 5)")
        for (i, v) in roman.enumerated() {
            b.setText(base + 5, [1, 2, 3, 5, 6, 7, 8, 9, 10][i], v, font: fData, alignment: aCenter)
        }
        for i in 0..<size {
            let e = entries[cursor]
            let r = base + 6 + i
            b.merge("C\(r):D\(r)")
            b.setNum(r, 1, Double(cursor + 1), font: fData, alignment: aCenter)
            b.setText(r, 2, e.code, font: fData, alignment: aCenter)
            b.setText(r, 3, e.name, font: fData, alignment: aLeft)
            b.setText(r, 5, e.unit, font: fData, alignment: aCenter)
            b.setNum(r, 6, exportMoney(e.qty), font: fData, alignment: aRight, numFmt: qty3Fmt)
            b.setNum(r, 7, exportMoney(e.techUnit), font: fData, alignment: aRight, numFmt: daysFmt)
            b.setNum(r, 8, exportMoney(e.laborUnit), font: fData, alignment: aRight, numFmt: daysFmt)
            b.setNum(r, 9, exportMoney(e.tech), font: fData, alignment: aRight, numFmt: daysFmt)
            b.setNum(r, 10, exportMoney(e.labor), font: fData, alignment: aRight, numFmt: daysFmt)
            b.setHeight(r, estimateRowHeight([(text: e.name, width: 42)]))
            cursor += 1
        }
        if isLast {
            let r = base + 6 + size
            b.merge("C\(r):D\(r)")
            b.setNum(r, 1, Double(n + 1), font: fData, alignment: aCenter)
            b.setText(r, 3, "定额工日合计\(adjNote)", font: fData, alignment: aLeft)
            b.setNum(r, 9, exportMoney(techDays), font: fData, alignment: aRight, numFmt: daysFmt)
            b.setNum(r, 10, exportMoney(laborDays), font: fData, alignment: aRight, numFmt: daysFmt)
            b.setHeight(r, 16.55)
            // 空白填充行同样合并 C:D（与参考一致；直至表尾前一行）。
            for br in (r + 1)...(base + 28) { b.merge("C\(br):D\(br)") }
        }
        let footerRow = base + 29
        b.merge("A\(footerRow):C\(footerRow)")
        b.setText(footerRow, 1, "施工负责人：\(ctx.info.工程负责人)", font: fFoot, alignment: aLeft)
        b.merge("D\(footerRow):F\(footerRow)")
        b.setText(footerRow, 4, "审核：\(ctx.info.审核)", font: fFoot, alignment: aLeft)
        b.merge("G\(footerRow):H\(footerRow)")
        b.setText(footerRow, 7, "编制：\(ctx.info.编制)", font: fFoot, alignment: aLeft)
        b.merge("I\(footerRow):J\(footerRow)")
        b.setText(footerRow, 9, "编制日期：\(ctx.dateStr)", font: fFoot, alignment: aLeft)
        b.setHeight(base + 1, 23.05)
        b.setHeight(base + 2, 13.7)
        for r in (base + 3)...(base + 27) { if b.height(r) == nil { b.setHeight(r, 16.55) } }
        b.setHeight(base + 28, 17.3)
        b.setHeight(footerRow, 15.1)
        b.paintBorders(maxCol: 10, headRows: [base + 3, base + 4],
                       dataRows: Array((base + 5)...(base + 28)))
        if !isLast { b.sheet.rowBreaks.append(base + 29) }
    }
    return b.sheet
}

// MARK: - 8/9. 表三乙 / 表三丙（溢出按通用规则分页）

func equipRows(_ ctx: PrintContext, machine: Bool) -> (rows: [Table3EquipRow], total: Double) {
    let engineTable = machine ? ctx.result.table3B : ctx.result.table3C
    guard let profile = ctx.profile else {
        return (engineTable.rows, num(engineTable.total))
    }
    let libs = profile.libraries
    let mappings: [(quota: String, mcode: String, mname: String, unit: String, qty: Double)] = machine
        ? libs.quotaMachines.map { ($0.quota, $0.mcode, $0.mname, $0.unit, $0.qty) }
        : libs.quotaInstruments.map { ($0.quota, $0.mcode, $0.mname, $0.unit, $0.qty) }
    let prices: [(code: String, price: Double)] = machine
        ? libs.machinePrices.map { ($0.code, $0.price) }
        : libs.instrumentPrices.map { ($0.code, $0.price) }
    var priceMap: [String: Double] = [:]
    for m in prices { priceMap[m.code] = m.price }
    var byCode: [String: [(mcode: String, mname: String, unit: String, qty: Double)]] = [:]
    for m in mappings {
        byCode[m.quota, default: []].append((mcode: m.mcode, mname: m.mname, unit: m.unit, qty: m.qty))
    }
    var rows: [Table3EquipRow] = []
    for g in groupQuantities(ctx.project, ctx.quotaByCode) {
        if g.kind != .normal { continue }
        guard let quota = ctx.quotaByCode[g.code] else { continue }
        for m in byCode[g.code] ?? [] {
            let sessions = g.weighted * num(m.qty)
            let price = num(priceMap[m.mcode])
            rows.append(Table3EquipRow(
                quota: g.code, quotaName: displayName(quota, g.variant), unit: quota.unit,
                qty: r2(g.weighted), equipName: m.mname, equipUnit: m.unit,
                consumption: num(m.qty), price: price,
                sessions: r2(sessions), amount: r2(sessions * price)))
        }
    }
    return (rows, num(engineTable.total))
}

func buildTable3BC(_ ctx: PrintContext, machine: Bool) -> XlsxSheet {
    let sheetName = machine ? "机械台班表(表三)乙" : "仪器仪表使用表(表三)丙"
    var b = SheetBuilder(name: sheetName)
    let (rows, total) = equipRows(ctx, machine: machine)
    var seqRows: [Table3EquipRow?] = rows.map { $0 }
    seqRows.append(nil) // 小计行
    let pageTotal = b.layout.maxRow
    let headerRows = 5
    let chunks = chunkSequence(seqRows.count, pageTotal: pageTotal, headerRows: headerRows)
    let totalPages = chunks.count
    let equipHeader = machine ? "机械名称" : "仪表名称"
    let totalLabel = machine ? "小计" : "合计"
    let tableNo = machine ? "-3乙" : "-3丙"
    var cursor = 0
    var seqNo = 0 // 数据行序号，跨页连续
    for (pi, size) in chunks.enumerated() {
        let base = pi * pageTotal
        let page = pi + 1
        let isLast = pi == totalPages - 1
        b.merge("A\(base + 1):J\(base + 1)")
        b.setText(base + 1, 1, machine ? "建筑安装工程机械使用费预算表（表三）乙"
            : "建筑安装工程仪器仪表使用费预算表（表三）丙", font: fTitle, alignment: aCenter)
        b.merge("A\(base + 2):C\(base + 2)")
        b.setText(base + 2, 1, "工程名称：\(ctx.singleName)", font: fInfo, alignment: aLeft)
        b.merge("D\(base + 2):F\(base + 2)")
        b.setText(base + 2, 4, "建设单位名称：\(ctx.company)", font: fInfo, alignment: aLeft)
        b.merge("G\(base + 2):H\(base + 2)")
        b.setText(base + 2, 7, "表格编号：\(tableNo)", font: fInfo, alignment: aLeft)
        b.merge("I\(base + 2):J\(base + 2)")
        b.setText(base + 2, 9, pageText(page, totalPages), font: fInfo, alignment: aRight)
        for (c, v) in [(1, "序\n号"), (2, "定额编号"), (3, "项目名称"), (4, "单位"), (5, "数量"), (6, equipHeader)] {
            b.merge("\(colLetter(c))\(base + 3):\(colLetter(c))\(base + 4)")
            b.setText(base + 3, c, v, font: fHead, alignment: aCenter)
        }
        b.merge("G\(base + 3):H\(base + 3)")
        b.setText(base + 3, 7, "单位定额值", font: fHead, alignment: aCenter)
        b.merge("I\(base + 3):J\(base + 3)")
        b.setText(base + 3, 9, "合计值", font: fHead, alignment: aCenter)
        b.setText(base + 4, 7, "数量(台班)", font: fHead, alignment: aCenter)
        b.setText(base + 4, 8, "单价(元)", font: fHead, alignment: aCenter)
        b.setText(base + 4, 9, "数量(台班)", font: fHead, alignment: aCenter)
        b.setText(base + 4, 10, "合价(元)", font: fHead, alignment: aCenter)
        let roman = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ", "Ⅹ"]
        for (i, v) in roman.enumerated() { b.setText(base + 5, i + 1, v, font: fData, alignment: aCenter) }
        for i in 0..<size {
            let item = seqRows[cursor]
            let r = base + 6 + i
            if let item {
                seqNo += 1
                b.setNum(r, 1, Double(seqNo), font: fData, alignment: aCenter)
                b.setText(r, 2, item.quota, font: fData, alignment: aCenter)
                b.setText(r, 3, item.quotaName, font: fData, alignment: aLeft)
                b.setText(r, 4, item.unit, font: fData, alignment: aCenter)
                b.setNum(r, 5, exportMoney(item.qty), font: fData, alignment: aRight, numFmt: qty3Fmt)
                b.setText(r, 6, item.equipName, font: fData, alignment: aLeft)
                b.setNum(r, 7, exportMoney(item.consumption), font: fData, alignment: aRight, numFmt: daysFmt)
                b.setNum(r, 8, exportMoney(item.price), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setNum(r, 9, exportMoney(item.sessions), font: fData, alignment: aRight, numFmt: daysFmt)
                b.setNum(r, 10, exportMoney(item.amount), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setHeight(r, estimateRowHeight([(text: item.quotaName, width: 30)]))
            } else {
                b.setNum(r, 1, Double(seqNo + 1), font: fData, alignment: aCenter)
                b.setText(r, 7, totalLabel, font: fData, alignment: aCenter)
                b.setNum(r, 10, exportMoney(total), font: fData, alignment: aRight, numFmt: moneyFmt)
            }
            cursor += 1
        }
        let footerRow = base + pageTotal
        if isLast {
            b.merge("A\(footerRow):C\(footerRow)")
            b.setText(footerRow, 1, "施工负责人：\(ctx.info.工程负责人)", font: fFoot, alignment: aLeft)
            b.merge("D\(footerRow):F\(footerRow)")
            b.setText(footerRow, 4, "审核：\(ctx.info.审核)", font: fFoot, alignment: aLeft)
            b.merge("G\(footerRow):H\(footerRow)")
            b.setText(footerRow, 7, "编制：\(ctx.info.编制)", font: fFoot, alignment: aLeft)
            b.merge("I\(footerRow):J\(footerRow)")
            b.setText(footerRow, 9, "编制日期：\(ctx.dateStr)", font: fFoot, alignment: aLeft)
        }
        let l = b.layout
        for k in 1...headerRows { b.setHeight(base + k, l.rowHeights[k] ?? l.defaultRowHeight) }
        let dataEnd = base + pageTotal - (isLast ? 1 : 0)
        for r in (base + headerRows + 1)...dataEnd {
            if b.height(r) == nil { b.setHeight(r, 16.55) }
        }
        if isLast {
            b.setHeight(base + pageTotal - 1, 17.3)
            b.setHeight(footerRow, 15.1)
        }
        b.paintBorders(maxCol: 10, headRows: [base + 3, base + 4],
                       dataRows: Array((base + 5)...dataEnd))
        if !isLast { b.sheet.rowBreaks.append(base + pageTotal) }
    }
    return b.sheet
}

// MARK: - 10. 表四甲（甲供 / 乙供 / 设备三组；无某组则整组省略）

enum Table4SeqItem {
    case group(String)
    case data(Table4Row)
    case subtotal(String, Table4Result)
    case total
}

func buildTable4A(_ ctx: PrintContext) -> XlsxSheet {
    var b = SheetBuilder(name: "主要材料表(表四)甲")
    let groups: [(label: String, sublabel: String, table: Table4Result)] = [
        ("『甲供材料』", "甲供材料小计", ctx.result.table4A),
        ("『乙供材料』", "乙供材料小计", ctx.result.table4B),
        ("『设备』", "设备小计", ctx.result.table4Equip),
    ].filter { !$0.table.rows.isEmpty }
    var seqRows: [Table4SeqItem] = []
    for g in groups {
        seqRows.append(.group(g.label))
        for r in g.table.rows { seqRows.append(.data(r)) }
        seqRows.append(.subtotal(g.sublabel, g.table))
    }
    seqRows.append(.total)
    let pageTotal = b.layout.maxRow
    let headerRows = 6
    let chunks = chunkSequence(seqRows.count, pageTotal: pageTotal, headerRows: headerRows)
    let totalPages = chunks.count
    var cursor = 0
    var seqNo = 0
    for (pi, size) in chunks.enumerated() {
        let base = pi * pageTotal
        let page = pi + 1
        let isLast = pi == totalPages - 1
        b.merge("A\(base + 1):J\(base + 1)")
        b.setText(base + 1, 1, "国内器材预算表（表四）甲", font: fTitle, alignment: aCenter)
        b.merge("A\(base + 2):J\(base + 2)")
        b.setText(base + 2, 1, "（主材）表", font: fHead, alignment: aCenter)
        b.merge("A\(base + 3):C\(base + 3)")
        b.setText(base + 3, 1, "工程名称：\(ctx.singleName)", font: fInfo, alignment: aLeft)
        b.merge("D\(base + 3):G\(base + 3)")
        b.setText(base + 3, 4, "建设单位名称：\(ctx.company)", font: fInfo, alignment: aLeft)
        b.merge("H\(base + 3):I\(base + 3)")
        b.setText(base + 3, 8, "表格编号：-4甲A", font: fInfo, alignment: aLeft)
        b.setText(base + 3, 10, pageText(page, totalPages), font: fInfo, alignment: aRight)
        for (c, v) in [(1, "序号"), (2, "名 称"), (3, "规格程式"), (4, "单位"), (5, "数量")] {
            b.merge("\(colLetter(c))\(base + 4):\(colLetter(c))\(base + 5)")
            b.setText(base + 4, c, v, font: fHead, alignment: aCenter)
        }
        b.setText(base + 4, 6, "单价(元)", font: fHead, alignment: aCenter)
        b.merge("G\(base + 4):I\(base + 4)")
        b.setText(base + 4, 7, "合计(元)", font: fHead, alignment: aCenter)
        b.merge("J\(base + 4):J\(base + 5)")
        b.setText(base + 4, 10, "备 注", font: fHead, alignment: aCenter)
        b.setText(base + 5, 6, "除税价", font: fHead, alignment: aCenter)
        b.setText(base + 5, 7, "除税价", font: fHead, alignment: aCenter)
        b.setText(base + 5, 8, "增值税", font: fHead, alignment: aCenter)
        b.setText(base + 5, 9, "含税价", font: fHead, alignment: aCenter)
        let roman = ["Ⅰ", "Ⅱ", "Ⅲ", "Ⅳ", "Ⅴ", "Ⅵ", "Ⅶ", "Ⅷ", "Ⅸ", "Ⅹ"]
        for (i, v) in roman.enumerated() { b.setText(base + 6, i + 1, v, font: fData, alignment: aCenter) }
        for i in 0..<size {
            let item = seqRows[cursor]
            let r = base + 7 + i
            switch item {
            case .group(let label):
                b.setText(r, 2, label, font: fData, alignment: aLeft)
            case .subtotal(let label, let table):
                b.setText(r, 2, label, font: fData, alignment: aLeft)
                b.setNum(r, 7, exportMoney(table.totalExcl), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setNum(r, 8, exportMoney(table.totalVat), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setNum(r, 9, exportMoney(table.totalIncl), font: fData, alignment: aRight, numFmt: moneyFmt)
            case .total:
                b.setText(r, 2, "总计", font: fData, alignment: aLeft)
                let sum = { (key: KeyPath<Table4Result, Double>) in groups.reduce(0) { $0 + $1.table[keyPath: key] } }
                b.setNum(r, 7, exportMoney(sum(\.totalExcl)), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setNum(r, 8, exportMoney(sum(\.totalVat)), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setNum(r, 9, exportMoney(sum(\.totalIncl)), font: fData, alignment: aRight, numFmt: moneyFmt)
            case .data(let row):
                seqNo += 1
                let remark: String
                if row.unmatched { remark = "未建档" }
                else if !row.remark.isEmpty { remark = row.remark }
                else { remark = ctx.libByKey[row.key]?.remark ?? "" }
                b.setNum(r, 1, Double(seqNo), font: fData, alignment: aCenter)
                b.setText(r, 2, row.name, font: fData, alignment: aLeft)
                b.setText(r, 3, row.spec, font: fData, alignment: aLeft)
                b.setText(r, 4, row.unit, font: fData, alignment: aCenter)
                b.setNum(r, 5, exportMoney(row.qty), font: fData, alignment: aRight, numFmt: qty3Fmt)
                b.setNum(r, 6, exportMoney(row.priceExcl), font: fData, alignment: aRight, numFmt: price5Fmt)
                b.setNum(r, 7, exportMoney(row.amtExcl), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setNum(r, 8, exportMoney(row.amtVat), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setNum(r, 9, exportMoney(row.amtIncl), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setText(r, 10, remark.isEmpty ? nil : remark, font: fData, alignment: aLeft)
                b.setHeight(r, estimateRowHeight([(text: row.name, width: 27), (text: row.spec, width: 21)]))
            }
            cursor += 1
        }
        let footerRow = base + pageTotal
        if isLast {
            b.merge("A\(footerRow):B\(footerRow)")
            b.setText(footerRow, 1, "施工负责人：\(ctx.info.工程负责人)", font: fFoot, alignment: aLeft)
            b.merge("C\(footerRow):D\(footerRow)")
            b.setText(footerRow, 3, "审核：\(ctx.info.审核)", font: fFoot, alignment: aLeft)
            b.merge("E\(footerRow):G\(footerRow)")
            b.setText(footerRow, 5, "编制：\(ctx.info.编制)", font: fFoot, alignment: aLeft)
            b.merge("H\(footerRow):J\(footerRow)")
            b.setText(footerRow, 8, "编制日期：\(ctx.dateStr)", font: fFoot, alignment: aLeft)
        }
        let l = b.layout
        for k in 1...headerRows { b.setHeight(base + k, l.rowHeights[k] ?? l.defaultRowHeight) }
        let dataEnd = base + pageTotal - (isLast ? 1 : 0)
        for r in (base + headerRows + 1)...dataEnd {
            if b.height(r) == nil { b.setHeight(r, 16.55) }
        }
        if isLast {
            b.setHeight(base + pageTotal - 1, 17.3)
            b.setHeight(footerRow, 15.1)
        }
        b.paintBorders(maxCol: 10, headRows: [base + 4, base + 5],
                       dataRows: Array((base + 6)...dataEnd))
        if !isLast { b.sheet.rowBreaks.append(base + pageTotal) }
    }
    return b.sheet
}

// MARK: - 11. 表五甲（生产准备费恒在总计之后，不计入总计）

func table5Method(_ row: Table5Row, _ feeRows: [Table5Row]) -> String {
    let rate = num(row.rate)
    switch row.basis {
    case "preDiscountExclTax": return "折前建安工程费除税价X\(pct(rate))%"
    case "afterDiscountExclTax": return "折后建安工程费除税价X\(pct(rate))%"
    case "laborTotal": return "人工费X\(pct(rate))%"
    case "surveyKm": return num(row.excl) != 0 ? "按勘察里程分段计取" : ""
    case "sum":
        let kids = feeRows.filter { num($0.order) > num(row.order) && num($0.order) < num(row.order) + 1 }
        return "\(kids.map { jsNumberString(num($0.order)) }.joined(separator: "+"))之和"
    case "fixed": return num(row.excl) != 0 ? "固定金额" : ""
    case "manual": return num(row.excl) != 0 ? "按工程给定金额计取" : ""
    default: return ""
    }
}

enum Table5SeqItem {
    case fee(Table5Row)
    case total
    case prodPrep(Table5Row)
}

func buildTable5(_ ctx: PrintContext) -> XlsxSheet {
    var b = SheetBuilder(name: "工程其他费用表(表五)甲")
    let allRows = ctx.result.table5.rows.sorted { num($0.order) < num($1.order) }
    let prodPrep = allRows.first { $0.key == "productionPrepFee" }
    let fees = allRows.filter { $0.key != "productionPrepFee" }
    var seqRows: [Table5SeqItem] = fees.map { .fee($0) }
    seqRows.append(.total)
    if let prodPrep { seqRows.append(.prodPrep(prodPrep)) }
    let pageTotal = b.layout.maxRow
    let headerRows = 5
    let chunks = chunkSequence(seqRows.count, pageTotal: pageTotal, headerRows: headerRows)
    let totalPages = chunks.count
    var cursor = 0
    for (pi, size) in chunks.enumerated() {
        let base = pi * pageTotal
        let page = pi + 1
        let isLast = pi == totalPages - 1
        b.merge("A\(base + 1):H\(base + 1)")
        b.setText(base + 1, 1, "工程建设其他费预算表（表五）甲", font: fTitle, alignment: aCenter)
        b.merge("A\(base + 2):C\(base + 2)")
        b.setText(base + 2, 1, "工程名称：\(ctx.singleName)", font: fInfo, alignment: aLeft)
        b.merge("D\(base + 2):E\(base + 2)")
        b.setText(base + 2, 4, "建设单位名称：\(ctx.company)", font: fInfo, alignment: aLeft)
        b.merge("F\(base + 2):G\(base + 2)")
        b.setText(base + 2, 6, "表格编号：-5甲", font: fInfo, alignment: aLeft)
        b.setText(base + 2, 8, pageText(page, totalPages), font: fInfo, alignment: aRight)
        b.merge("A\(base + 3):A\(base + 4)")
        b.setText(base + 3, 1, "序号", font: fHead, alignment: aCenter)
        b.merge("B\(base + 3):B\(base + 4)")
        b.setText(base + 3, 2, "费用名称", font: fHead, alignment: aCenter)
        // 表头“计算依据及方法”合并 C3:D4（与参考结算书合并区一致）。
        b.merge("C\(base + 3):D\(base + 4)")
        b.setText(base + 3, 3, "计算依据及方法", font: fHead, alignment: aCenter)
        b.merge("E\(base + 3):G\(base + 3)")
        b.setText(base + 3, 5, "金 额（元）", font: fHead, alignment: aCenter)
        b.merge("H\(base + 3):H\(base + 4)")
        b.setText(base + 3, 8, "备注", font: fHead, alignment: aCenter)
        b.setText(base + 4, 5, "除税价", font: fHead, alignment: aCenter)
        b.setText(base + 4, 6, "增值税", font: fHead, alignment: aCenter)
        b.setText(base + 4, 7, "含税价", font: fHead, alignment: aCenter)
        b.merge("C\(base + 5):D\(base + 5)")
        for (c, v) in [(1, "Ⅰ"), (2, "Ⅱ"), (3, "Ⅲ"), (5, "Ⅳ"), (6, "Ⅴ"), (7, "Ⅵ"), (8, "Ⅶ")] {
            b.setText(base + 5, c, v, font: fData, alignment: aCenter)
        }
        for i in 0..<size {
            let item = seqRows[cursor]
            let r = base + 6 + i
            b.merge("C\(r):D\(r)")
            switch item {
            case .fee(let row), .prodPrep(let row):
                b.setText(r, 1, jsNumberString(num(row.order)), font: fData, alignment: aCenter)
                b.setText(r, 2, row.name, font: fData, alignment: aLeft)
                let method = table5Method(row, fees)
                b.setText(r, 3, method.isEmpty ? nil : method, font: fData, alignment: aLeft)
                b.setNum(r, 5, exportMoney(row.excl), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setNum(r, 6, exportMoney(row.vat), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setNum(r, 7, exportMoney(row.incl), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setHeight(r, estimateRowHeight([(text: row.name, width: 33)]))
            case .total:
                b.setText(r, 2, "   总  计", font: fData, alignment: aLeft)
                b.setNum(r, 5, exportMoney(ctx.result.table5.totalExcl), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setNum(r, 6, exportMoney(ctx.result.table5.totalVat), font: fData, alignment: aRight, numFmt: moneyFmt)
                b.setNum(r, 7, exportMoney(ctx.result.table5.totalIncl), font: fData, alignment: aRight, numFmt: moneyFmt)
            }
            cursor += 1
        }
        let footerRow = base + pageTotal
        if isLast {
            // 空白填充行合并 C:D（与参考一致；直至表尾前一行）。
            let fillStart = base + 6 + size
            if fillStart <= base + pageTotal - 1 {
                for br in fillStart...(base + pageTotal - 1) { b.merge("C\(br):D\(br)") }
            }
            b.merge("A\(footerRow):B\(footerRow)")
            b.setText(footerRow, 1, "施工负责人：\(ctx.info.工程负责人)", font: fFoot, alignment: aLeft)
            b.merge("C\(footerRow):D\(footerRow)")
            b.setText(footerRow, 3, "审核：\(ctx.info.审核)", font: fFoot, alignment: aLeft)
            b.merge("E\(footerRow):H\(footerRow)")
            b.setText(footerRow, 5, "编制：\(ctx.info.编制)\(String(repeating: " ", count: 23))编制日期：\(ctx.dateStr)",
                      font: fFoot, alignment: aLeft)
        }
        let l = b.layout
        for k in 1...headerRows { b.setHeight(base + k, l.rowHeights[k] ?? l.defaultRowHeight) }
        let dataEnd = base + pageTotal - (isLast ? 1 : 0)
        for r in (base + headerRows + 1)...dataEnd {
            if b.height(r) == nil { b.setHeight(r, 16.55) }
        }
        if isLast {
            b.setHeight(base + pageTotal - 1, 17.3)
            b.setHeight(footerRow, 15.1)
        }
        b.paintBorders(maxCol: 8, headRows: [base + 3, base + 4],
                       dataRows: Array((base + 5)...dataEnd))
        if !isLast { b.sheet.rowBreaks.append(base + pageTotal) }
    }
    return b.sheet
}

// MARK: - 主入口

/// 导出上下文：从 project/result/profile 汇总各表共用的显示值。
func buildPrintContext(projectName: String, project: Project, result: CalcResult,
                       profile: ConfigurationProfile?) -> PrintContext {
    let info = result.info
    let discount = num(result.discount)
    let noDisc = effectiveNoDisc(result.discountRule.noDiscountKeys)
    let zeroKeys: Set<String> = discount < 1 ? Set(result.discountRule.zeroAfterDiscountKeys) : []
    let rate = result.rate
    let tempRate = info.施工距离 == "35KM以内" ? rate.tempNearRate : rate.tempFarRate
    let vars: [String: String] = [
        "techPrice": fmtTrim(rate.techPrice),
        "laborPrice": fmtTrim(rate.laborPrice),
        "auxRate": pct(rate.auxRate),
        "civilRate": pct(rate.civilRate),
        "carryRate": pct(rate.carryRate),
        "disturbRate": pct(rate.disturbRate),
        "handoverRate": pct(rate.handoverRate),
        "tempRate": pct(tempRate),
        "vehicleRate": pct(rate.vehicleRate),
        "nightRate": pct(rate.nightRate),
        "winterRate": pct(rate.winterRate),
        "toolRate": pct(rate.toolRate),
        "utilityRate": pct(rate.utilityRate),
        "protectRate": pct(rate.protectRate),
        "socialRate": pct(rate.socialRate),
        "housingRate": pct(rate.housingRate),
        "accidentRate": pct(rate.accidentRate),
        "mgmtRate": pct(rate.mgmtRate),
        "profitRate": pct(rate.profitRate),
        "discountPct": pct(discount),
        "discountRate": jsNumberString(discount),
    ]
    let dateFromInfo = formatDateCn(info.编制日期)
    let dateStr = dateFromInfo.isEmpty ? todayCn() : dateFromInfo
    let coverDateStr = dateFromInfo.isEmpty ? "\(todayCn())（导出日）" : dateFromInfo
    var prefix = info.表格编号.trimmingCharacters(in: .whitespaces)
    if prefix.isEmpty { prefix = "通信线路-" }
    else if !prefix.hasSuffix("-") { prefix += "-" }
    var quotaByCode: [String: QuotaRow] = [:]
    var libByKey: [String: MaterialRow] = [:]
    if let profile {
        for m in profile.libraries.materials { libByKey["\(m.name)|\(m.spec)"] = m }
        for q in profile.libraries.quotas where quotaByCode[q.code] == nil {
            quotaByCode[q.code] = q
        }
    }
    return PrintContext(
        project: project, result: result, profile: profile, info: info,
        projectName: info.建设项目名称.isEmpty ? (info.单项工程名称.isEmpty ? projectName : info.单项工程名称) : info.建设项目名称,
        singleName: info.单项工程名称.isEmpty ? info.工程类型 : info.单项工程名称,
        company: info.建设单位,
        dateStr: dateStr, coverDateStr: coverDateStr, prefix: prefix,
        quotaByCode: quotaByCode, libByKey: libByKey,
        noDisc: noDisc, zeroKeys: zeroKeys, vars: vars, discount: discount)
}

/// 生成预算书 xlsx 数据（不写盘；可单测）。include：要出的表名集合（默认全选由调用方传入）。
public func buildBudgetBook(projectName: String, project: Project, result: CalcResult,
                             profile: ConfigurationProfile?, include: Set<String>) -> Data {
    let ctx = buildPrintContext(projectName: projectName, project: project, result: result, profile: profile)
    var sheets: [XlsxSheet] = []
    if include.contains("报表封面") { sheets.append(buildCover(ctx)) }
    if include.contains("编制说明") { sheets.append(buildNotes(ctx)) }
    if include.contains("建设项目总算表(汇总表)") { sheets.append(buildSummary(ctx)) }
    if include.contains("工程总表(表一)") { sheets.append(buildTable1(ctx)) }
    if include.contains("工程费用表(表二)") { sheets.append(buildTable2(ctx, after: true)) }
    if include.contains("工程费用表(表二)折前") { sheets.append(buildTable2(ctx, after: false)) }
    if include.contains("工程量表(表三)甲") { sheets.append(buildTable3A(ctx)) }
    if include.contains("机械台班表(表三)乙") { sheets.append(buildTable3BC(ctx, machine: true)) }
    if include.contains("仪器仪表使用表(表三)丙") { sheets.append(buildTable3BC(ctx, machine: false)) }
    if include.contains("主要材料表(表四)甲") { sheets.append(buildTable4A(ctx)) }
    if include.contains("工程其他费用表(表五)甲") { sheets.append(buildTable5(ctx)) }
    return XlsxWorkbook(sheets: sheets).build()
}

/// 导出预算书到文件（写盘；路径为空时抛错）。
public func exportBudgetBook(to url: URL, projectName: String, project: Project, result: CalcResult,
                             profile: ConfigurationProfile?, include: Set<String>) throws {
    guard !url.path.isEmpty else { throw PrintExportError.emptyPath }
    let data = buildBudgetBook(projectName: projectName, project: project, result: result,
                               profile: profile, include: include)
    do {
        try data.write(to: url, options: .atomic)
    } catch {
        throw PrintExportError.writeFailed(error.localizedDescription)
    }
}
