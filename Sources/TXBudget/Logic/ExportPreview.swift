import Foundation

/// 报表导出迷你预览（v2.0.0，见 docs/v2-ui-design.md §3、§8）：
/// 每张表给几行关键数字，让用户导出前先核对。数据全部来自 CalcResult，
/// 与 xlsx 导出同源同值；本文件只做展示格式化，不参与计算。

public func exportSheetPreviewLines(_ sheet: String, project: ProjectRecord,
                                    profileName: String, result: CalcResult) -> [String] {
    switch sheet {
    case "报表封面":
        return [
            "工程：\(project.name)",
            "建设单位：\(project.info.建设单位.isEmpty ? "—" : project.info.建设单位)",
            "工程总费用：\(money(result.table1.grandIncl)) 元",
            "编制日期：\(project.info.编制日期.isEmpty ? "—" : project.info.编制日期)",
        ]
    case "编制说明":
        return [
            "按配置方案“\(profileName)”编制",
            "施工折扣：\(result.discount == 1 ? "不打折" : ratePercentText(result.discount))",
            "共 \(sheetNames.count) 张表，本表为编制说明",
        ]
    case "建设项目总算表(汇总表)":
        return [
            "建筑安装工程费：\(money(result.summary.constructionIncl)) 元",
            "工程建设其他费：\(money(result.summary.otherIncl)) 元",
            "合计（含税）：\(money(result.summary.totalIncl)) 元",
        ]
    case "工程总表(表一)":
        return [
            "建安费（折后除税）：\(money(result.table1.afterDiscount)) 元",
            "设备费（含税）：\(money(result.table1.equipIncl)) 元",
            "其他费（含税）：\(money(result.table1.otherIncl)) 元",
            "总计（含税）：\(money(result.table1.grandIncl)) 元",
        ]
    case "工程费用表(表二)":
        return [
            "除税价（折后）：\(money(result.table2After.exclTax)) 元",
            "含税价（折后）：\(money(result.table2After.inclTax)) 元",
            "人工费：\(money(result.table2After.values["laborTotal"])) 元",
        ]
    case "工程费用表(表二)折前":
        return [
            "除税价（折前）：\(money(result.table2Before.exclTax)) 元",
            "含税价（折前）：\(money(result.table2Before.inclTax)) 元",
            "人工费：\(money(result.table2Before.values["laborTotal"])) 元",
        ]
    case "工程量表(表三)甲":
        return [
            "定额行数：\(result.table3A.count) 行",
            "技工工日：\(num2(result.techDays)) · 普工工日：\(num2(result.laborDays))",
            "工日调整率：\(ratePercentText(result.adjRate))",
        ]
    case "机械台班表(表三)乙":
        return [
            "机械行数：\(result.table3B.rows.count) 行",
            "机械费合计：\(money(result.table3B.total)) 元",
        ]
    case "仪器仪表使用表(表三)丙":
        return [
            "仪表行数：\(result.table3C.rows.count) 行",
            "仪表费合计：\(money(result.table3C.total)) 元",
        ]
    case "主要材料表(表四)甲":
        return [
            "甲供主材（含税）：\(money(result.table4A.totalIncl)) 元",
            "乙供主材（含税）：\(money(result.table4B.totalIncl)) 元",
            "设备（含税）：\(money(result.table4Equip.totalIncl)) 元",
        ]
    case "工程其他费用表(表五)甲":
        var lines = [
            "其他费合计（除税）：\(money(result.table5.totalExcl)) 元",
            "其他费合计（含税）：\(money(result.table5.totalIncl)) 元",
        ]
        if let safety = result.table5.rows.first(where: { $0.key == "safetyFee" }) {
            lines.append("其中安全生产费：\(money(safety.excl)) 元")
        }
        return lines
    default:
        return []
    }
}
