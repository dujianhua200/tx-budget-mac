import Foundation

/// 工程列表 / 工程信息 / 定额联想等纯逻辑（对照 Electron `v3.js` + `store.js`）。

// MARK: - 工程列表：最近置顶

/// 按 lastOpenedAt 降序；无 lastOpenedAt 的保持原有相对顺序排在后面。
public func sortProjectsRecent(_ projects: [ProjectRecord]) -> [ProjectRecord] {
    var withTs: [(Int, ProjectRecord)] = []
    var without: [(Int, ProjectRecord)] = []
    for (i, p) in projects.enumerated() {
        if p.lastOpenedAt != nil { withTs.append((i, p)) } else { without.append((i, p)) }
    }
    withTs.sort {
        if $0.1.lastOpenedAt! != $1.1.lastOpenedAt! { return $0.1.lastOpenedAt! > $1.1.lastOpenedAt! }
        return $0.0 < $1.0
    }
    return withTs.map { $0.1 } + without.map { $0.1 }
}

// MARK: - 工程信息：打折单选派生

/// 打折选项派生：施工折扣 = 1 → 不打折，否则打折；不新增数据字段。
public func discountOption(_ info: ProjectInfo) -> String {
    if let d = info.施工折扣, d != 1 { return "discount" }
    return "noDiscount"
}

/// 应用打折单选：'noDiscount' → 施工折扣 = 1；
/// 'discount' → 恢复上次折扣率 lastRate（合法 (0,1)），无上次折扣率时不改值、返回 needsInput=true 由界面提示输入。
public func applyDiscountOption(_ info: ProjectInfo, _ option: String, _ lastRate: Double?) -> (info: ProjectInfo, needsInput: Bool) {
    var next = info
    if option == "noDiscount" {
        next.施工折扣 = 1
        return (next, false)
    }
    if let lastRate, lastRate > 0, lastRate < 1 {
        next.施工折扣 = lastRate
        return (next, false)
    }
    if let d = next.施工折扣, d != 1 { return (next, false) }
    return (next, true)
}

/// 切换工程所用配置方案（改 profileId）。
public func switchProjectProfile(_ project: ProjectRecord, _ profileId: String) -> ProjectRecord {
    var next = project
    next.profileId = profileId
    return next
}

// MARK: - 定额联想

/// 定额编号联想：常用短单在前、全库在后，按 code+name 去重，上限 50。
public func quotaSuggestions(_ libraries: LibrarySet, _ keyword: String, limit: Int = 50) -> [QuotaRow] {
    let kw = keyword.trimmingCharacters(in: .whitespaces)
    guard !kw.isEmpty else { return [] }
    // 常用短单（shortlist）按 code+name 匹配，转为 QuotaRow（coef 保留）。
    let inShort = libraries.shortlist.filter { $0.code.contains(kw) || $0.name.contains(kw) }
        .map { QuotaRow(id: $0.id, code: $0.code, name: $0.name, unit: $0.unit, tech: 0, labor: 0, coef: $0.coef) }
    var seen = Set(inShort.map { "\($0.code)|\($0.name)" })
    var inFull: [QuotaRow] = []
    for q in libraries.quotas where (q.code.contains(kw) || q.name.contains(kw)) && !seen.contains("\(q.code)|\(q.name)") {
        seen.insert("\(q.code)|\(q.name)")
        inFull.append(q)
    }
    return Array((inShort + inFull).prefix(limit))
}

// MARK: - 新建工程

/// 新建工程（对照 Electron `newProject`：info 取 settings.defaultInfo + 工程名；
/// profileId 取 activeProfileId；模板复制全部工程量/调整/覆盖）。
public func newProject(_ db: DbFile, name: String, template: ProjectRecord? = nil) -> ProjectRecord {
    var info = db.settings.defaultInfo
    info.建设项目名称 = name
    info.单项工程名称 = name
    let profileId = db.settings.activeProfileId.isEmpty
        ? (db.configurationProfiles.first?.id ?? "prof_default")
        : db.settings.activeProfileId
    let ts = nowISO()
    var p = ProjectRecord(id: newUID(), name: name, createdAt: ts, updatedAt: ts,
                          profileId: profileId, info: info)
    if let template {
        p.info = template.info
        p.info.建设项目名称 = name
        p.info.单项工程名称 = name
        p.quantities = template.quantities.map { var q = $0; q.id = q.id ?? newUID(); return q }
        p.materialAdjust = template.materialAdjust
        p.materialPriceOverrides = template.materialPriceOverrides
        p.ruleOverrides = template.ruleOverrides
        p.rateOverrides = template.rateOverrides
        p.table5Overrides = template.table5Overrides
        p.warningsDismissed = template.warningsDismissed
    }
    return p
}

/// 工程量行状态（孤儿 / 无效 / 编号重复），供表三甲状态列展示。
public enum QuantityRowStatus: Equatable {
    case ok
    case orphan
    case invalid
    case duplicate
}

public func quantityRowStatus(_ row: QuantityRow, orphanIds: Set<String>, invalidIds: Set<String>,
                              duplicateCodes: Set<String>) -> QuantityRowStatus {
    if let id = row.id, orphanIds.contains(id) { return .orphan }
    if let id = row.id, invalidIds.contains(id) { return .invalid }
    if duplicateCodes.contains(row.quota) { return .duplicate }
    return .ok
}

public func quantityRowStatusText(_ status: QuantityRowStatus) -> String {
    switch status {
    case .orphan: return "⚠ 未建档"
    case .invalid: return "⚠ 数量无效"
    case .duplicate: return "⚠ 编号重复"
    case .ok: return ""
    }
}
