import Foundation

/// 导出勾选（对照 Electron `v3.js`：SHEET_NAMES / EXPORT_GROUPS / resolve / toggle）。

public let sheetNames = [
    "报表封面",
    "编制说明",
    "建设项目总算表(汇总表)",
    "工程总表(表一)",
    "工程费用表(表二)",
    "工程费用表(表二)折前",
    "工程量表(表三)甲",
    "机械台班表(表三)乙",
    "仪器仪表使用表(表三)丙",
    "主要材料表(表四)甲",
    "工程其他费用表(表五)甲",
]

public struct ExportGroup: Equatable, Identifiable {
    public var id: String
    public var label: String
    public var sheets: [String]
    public init(id: String, label: String, sheets: [String]) {
        self.id = id; self.label = label; self.sheets = sheets
    }
}

public let exportGroups = [
    ExportGroup(id: "cover", label: "封面与说明", sheets: ["报表封面", "编制说明"]),
    ExportGroup(id: "total", label: "汇总与总表", sheets: ["建设项目总算表(汇总表)", "工程总表(表一)"]),
    ExportGroup(id: "t2", label: "费用表（表二）", sheets: ["工程费用表(表二)", "工程费用表(表二)折前"]),
    ExportGroup(id: "t3", label: "工程量与台班（表三）", sheets: ["工程量表(表三)甲", "机械台班表(表三)乙", "仪器仪表使用表(表三)丙"]),
    ExportGroup(id: "t4", label: "材料（表四）", sheets: ["主要材料表(表四)甲"]),
    ExportGroup(id: "t5", label: "其他费用（表五）", sheets: ["工程其他费用表(表五)甲"]),
]

public func defaultExportSelection() -> [String] { sheetNames }

/// 解析 settings.exportSelection：非法/缺失 → 全选；过滤不在 11 张表内的条目。
public func resolveExportSelection(_ settings: SettingsRecord) -> [String] {
    guard let sel = settings.exportSelection else { return defaultExportSelection() }
    let kept = sel.filter { sheetNames.contains($0) }
    return kept.isEmpty ? defaultExportSelection() : kept
}

/// 批量导出文件名：`<清洗后工程名>_概预算.xlsx`（与 Electron Batch.jsx / Projects.jsx 一致）。
/// 清洗：文件名非法字符 `\ / : * ? " < > |` 换成 `_`。
public func batchExportFileName(for projectName: String) -> String {
    let bad = CharacterSet(charactersIn: "\\/:*?\"<>|")
    let safe = projectName.unicodeScalars.map { bad.contains($0) ? "_" : String($0) }.joined()
    return "\(safe)_概预算.xlsx"
}

/// 勾选切换（单张表）。
public func toggleExportSelection(_ selection: [String], _ sheet: String) -> [String] {
    var set = Set(selection)
    if set.contains(sheet) { set.remove(sheet) } else { set.insert(sheet) }
    return sheetNames.filter { set.contains($0) }
}

/// 勾选切换（整组）：组内全选 → 全取消；否则全选该组。
public func toggleExportGroup(_ selection: [String], _ groupSheets: [String]) -> [String] {
    var set = Set(selection)
    let all = groupSheets.allSatisfy { set.contains($0) }
    for s in groupSheets {
        if all { set.remove(s) } else { set.insert(s) }
    }
    return sheetNames.filter { set.contains($0) }
}
