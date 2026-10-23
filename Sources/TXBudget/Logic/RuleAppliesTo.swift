import Foundation

/// 规则「适用工程」（appliesTo）解析与判定（v2.4.1，docs/v2.4.1-appliesto-design.md §3）。
/// 语义沿用母版与 Electron v2-design.md 定义：'' = 不启用，'全' = 全部工程，
/// '1,3' = 仅工程序号 1、3（序号 = 工程在所属方案工程集合中的 1 基位置）。
/// 引擎（Calc）与工作量关联区面板（WorkloadLinks）共用本判定，不许另写一套。

public enum RuleAppliesTo: Equatable {
    /// "全"：全部工程生效。
    case all
    /// ""（或无法解析出任何合法序号）：任何工程都不生效。
    case disabled
    /// 序号列表：仅集合内序号生效。
    case only(Set<Int>)
}

/// 解析 appliesTo 原始字符串（容错见设计文档 §3.2）。
public func parseRuleAppliesTo(_ raw: String) -> RuleAppliesTo {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "　"))
    if trimmed == "全" { return .all }
    if trimmed.isEmpty { return .disabled }
    // 分隔符：半/全角逗号、顿号、分号、空白；全角数字归一化后逐 token 解析。
    var normalized = ""
    for ch in trimmed {
        if let v = ch.unicodeScalars.first, v.value >= 0xFF10, v.value <= 0xFF19,
           let ascii = UnicodeScalar(v.value - 0xFF10 + 0x30) {
            normalized.append(Character(ascii))
        } else {
            normalized.append(ch)
        }
    }
    let separators = CharacterSet(charactersIn: ",，、;；").union(.whitespacesAndNewlines)
    var ordinals = Set<Int>()
    for token in normalized.components(separatedBy: separators) {
        if let n = Int(token), n >= 1 { ordinals.insert(n) }
    }
    return ordinals.isEmpty ? .disabled : .only(ordinals)
}

/// 某条规则在给定工程序号下是否生效。
public func ruleAppliesToProject(_ raw: String, projectOrdinal: Int) -> Bool {
    switch parseRuleAppliesTo(raw) {
    case .all: return true
    case .disabled: return false
    case .only(let set): return set.contains(projectOrdinal)
    }
}

/// 面板灰显原因文案（规则与本行相关但被 appliesTo 挡住时）。
public func ruleAppliesToInactiveReason(_ raw: String, projectOrdinal: Int) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "适用工程为空，本行不启用" }
    return "适用工程为「\(trimmed)」，本工程序号 \(projectOrdinal)，未生效"
}
