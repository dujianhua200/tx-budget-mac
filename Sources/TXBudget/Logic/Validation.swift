import Foundation

/// 校验中心（v2.0.0，见 docs/v2-ui-design.md §3、§8）：把引擎已能算出的问题
/// 与数据完整性问题集中聚合，一处看完；每条带定位目标（NavDestination），点击跳转。
/// 纯函数：db/project/profile/result 全部由调用方算好传入（result = calcFor 的结果），可单测。

public enum ValidationSeverity: Int, Equatable, Comparable {
    case error = 0
    case warning = 1
    case info = 2

    public static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .error: return "错误"
        case .warning: return "警告"
        case .info: return "提示"
        }
    }

    public var systemImage: String {
        switch self {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

public struct ValidationIssue: Equatable, Identifiable {
    public var id: String
    public var severity: ValidationSeverity
    public var title: String
    public var detail: String
    public var target: NavDestination
    /// 关联的工程量行 id（仅 orphanQty/invalidQty 的首行），供界面展示，不做精确定位滚动。
    public var rowId: String?
    public init(id: String, severity: ValidationSeverity, title: String, detail: String,
                target: NavDestination, rowId: String? = nil) {
        self.id = id; self.severity = severity; self.title = title; self.detail = detail
        self.target = target; self.rowId = rowId
    }
}

/// 聚合全部校验问题，按严重度（错误 > 警告 > 提示）稳定排序（同级保持产生顺序）。
public func collectValidationIssues(db: DbFile, project: ProjectRecord,
                                    profile: ConfigurationProfile?,
                                    result: CalcResult?) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []

    guard let result else {
        issues.append(ValidationIssue(
            id: "calc-failed", severity: .error,
            title: "工程计算失败",
            detail: "工程所用配置方案不存在或无法计算，请检查工程的配置方案设置。",
            target: .projectInfo))
        return issues
    }

    // 1) 引擎 warnings（引擎已算出的问题，逐条映射定位目标）。
    for (i, w) in result.warnings.enumerated() {
        issues.append(issueForWarning(w, index: i))
    }

    // 2) 未录工程量。
    if project.quantities.isEmpty {
        issues.append(ValidationIssue(
            id: "no-quantities", severity: .warning,
            title: "尚未录入工程量",
            detail: "工程量为空时表三/表四/费用均为 0。去工作量页录入定额与数量。",
            target: .workload))
    }

    // 3) 材料未建档（表四甲/乙/设备中 unmatched 的行，按组聚合一条）。
    let groups: [(String, Table4Result)] = [
        ("甲供主材", result.table4A), ("乙供主材", result.table4B), ("设备", result.table4Equip),
    ]
    for (label, table) in groups {
        let unmatched = table.rows.filter { $0.unmatched }
        if !unmatched.isEmpty {
            let names = unmatched.prefix(3).map { $0.spec.isEmpty ? $0.name : "\($0.name) \($0.spec)" }
                .joined(separator: "、")
            issues.append(ValidationIssue(
                id: "unmatched-\(label)", severity: .warning,
                title: "\(label)有 \(unmatched.count) 项未建档",
                detail: "材料库中找不到对应材料，单价按 0 计算：\(names)\(unmatched.count > 3 ? " 等" : "")。请到材料库补建档或检查映射规则。",
                target: .workload))
        }
    }

    // 4) 表五手动项已启用但未填金额（覆盖优先：override.amount ?? fee.amount）。
    if let profile {
        var overrides: [String: Table5Override] = [:]
        for o in project.table5Overrides { overrides[o.key] = o }
        for fee in profile.table5Fees where fee.basis == "manual" {
            let ov = overrides[fee.key]
            let enabled = ov?.enabled ?? fee.enabled ?? true
            guard enabled else { continue }
            let amount = ov?.amount ?? fee.amount
            if amount == nil {
                issues.append(ValidationIssue(
                    id: "table5-manual-\(fee.key)", severity: .info,
                    title: "表五手动项未填金额：\(fee.name)",
                    detail: "该项为手动填项且已启用，未填金额时按 0 计入。可在费用页表五标签或工程信息页填写。",
                    target: .fees))
            }
        }
    }

    // 5) 工程信息缺项（只查会影响出图/计费的字段；可选字段不查）。
    if project.info.建设项目名称.trimmingCharacters(in: .whitespaces).isEmpty {
        issues.append(ValidationIssue(
            id: "info-project-name", severity: .info,
            title: "建设项目名称未填",
            detail: "封面与汇总表会显示空白，请在工程信息页补填。",
            target: .projectInfo))
    }
    if project.info.建设单位.trimmingCharacters(in: .whitespaces).isEmpty {
        issues.append(ValidationIssue(
            id: "info-builder", severity: .info,
            title: "建设单位未填",
            detail: "封面会显示空白，请在工程信息页补填。",
            target: .projectInfo))
    }
    if project.info.编制日期.trimmingCharacters(in: .whitespaces).isEmpty {
        issues.append(ValidationIssue(
            id: "info-date", severity: .info,
            title: "编制日期未填",
            detail: "预算书封面日期会显示空白，请在工程信息页补填。",
            target: .projectInfo))
    }

    // 按严重度稳定排序（Swift sorted 非稳定，以原下标决胜）。
    return issues.enumerated().sorted {
        if $0.element.severity != $1.element.severity {
            return $0.element.severity < $1.element.severity
        }
        return $0.offset < $1.offset
    }.map { $0.element }
}

/// 引擎 warning → 校验问题（标题用引擎 message 原文，不改口径；detail 给处理指引）。
private func issueForWarning(_ w: CalcWarning, index: Int) -> ValidationIssue {
    switch w.code {
    case "orphanQty":
        return ValidationIssue(id: "warn-orphanQty-\(index)", severity: .error,
                               title: w.message,
                               detail: "去工作量页修正定额编号，或删除孤儿行。",
                               target: .workload, rowId: w.rowIds?.first)
    case "invalidQty":
        return ValidationIssue(id: "warn-invalidQty-\(index)", severity: .error,
                               title: w.message,
                               detail: "去工作量页修正数量（≥0）与系数（>0）。",
                               target: .workload, rowId: w.rowIds?.first)
    case "duplicateCode":
        return ValidationIssue(id: "warn-duplicateCode-\(index)", severity: .warning,
                               title: w.message,
                               detail: "去定额库删除重复编号，只保留一条。",
                               target: .libraries(.quotas))
    case "unknownProjectType":
        return ValidationIssue(id: "warn-unknownProjectType-\(index)", severity: .warning,
                               title: w.message,
                               detail: "去工程信息页把工程类别改成标准类别。",
                               target: .projectInfo)
    case "invalidDiscount":
        return ValidationIssue(id: "warn-invalidDiscount-\(index)", severity: .warning,
                               title: w.message,
                               detail: "去工程信息页检查施工折扣（应为 ≤1 的数，1 = 不打折）。",
                               target: .projectInfo)
    case "unknownTable5Basis":
        return ValidationIssue(id: "warn-unknownTable5Basis-\(index)", severity: .warning,
                               title: w.message,
                               detail: "去取费规则的表五费用页检查该项的计费依据。",
                               target: .feeRules(.table5fees))
    default:
        if w.code == "missingRate" || w.code.hasPrefix("missingRate:") {
            return ValidationIssue(id: "warn-\(w.code)-\(index)", severity: .warning,
                                   title: w.message,
                                   detail: "去取费规则的费率页补齐缺失费率。",
                                   target: .feeRules(.rates))
        }
        return ValidationIssue(id: "warn-\(w.code)-\(index)", severity: .warning,
                               title: w.message, detail: "", target: .overview)
    }
}
