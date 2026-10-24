import Foundation

/// 一次性数据迁移（加载时由 DatabaseStore.repair 调用；结果随下一次保存落盘）。
/// 全部迁移按 MetaRecord.appliedMigrations 标记保证幂等，且不误伤迁移后
/// 用户自建的数据（有标记即整体跳过）。

/// 光缆长度单位迁移标记（v2.6.0，docs/v2.6-batch-design.md §3）。
public let cableUnitMigrationId = "cable-unit-m-v26"

/// 光缆主材单位修正：种子/旧库把「光缆 GYTS_*/GYTA_*、皮线光缆」等线缆材料
/// 的单位写成“千米”，且规则消耗量与之配套为 1.007（千米/千米条）。
/// 用户裁决主材长度单位是米：材料行 unit 改 "m"（与内置完整库既有「光缆」行
/// 一致），引用同一（名称|规格）的规则 consumption × 1000（→ 1007 米/千米条），
/// 生成总量等价换算、价格不动。命中口径 = 材料行 unit == "千米"（全库排查，
/// 种子内仅线缆类材料命中）。
/// 返回改动行数（材料行 + 规则行）；已应用过标记时返回 0 且不做任何改动。
@discardableResult
public func migrateCableMaterialUnits(_ db: inout DbFile) -> Int {
    if (db.meta.appliedMigrations ?? []).contains(cableUnitMigrationId) { return 0 }
    var changed = 0
    for pi in db.configurationProfiles.indices {
        var libs = db.configurationProfiles[pi].libraries
        var hitKeys = Set<String>()
        for i in libs.materials.indices where libs.materials[i].unit == "千米" {
            libs.materials[i].unit = "m"
            hitKeys.insert("\(libs.materials[i].name)|\(libs.materials[i].spec)")
            changed += 1
        }
        if !hitKeys.isEmpty {
            for i in libs.rules.indices
            where hitKeys.contains("\(libs.rules[i].material)|\(libs.rules[i].spec)") {
                libs.rules[i].consumption *= 1000
                changed += 1
            }
        }
        db.configurationProfiles[pi].libraries = libs
    }
    var marks = db.meta.appliedMigrations ?? []
    marks.append(cableUnitMigrationId)
    db.meta.appliedMigrations = marks
    return changed
}

/// 基准行变体补齐迁移标记（v2.6.1，docs/v2.6-batch-design.md §11.1）。
public let baselineVariantMigrationId = "baseline-variant-v261"

/// 零快照修复迁移标记（v2.6.1，§11.2）。
public let zeroSnapshotMigrationId = "zero-snapshot-v261"

/// 从名称/规格中提取芯数标记（正则 `(\d+)\s*芯`，首个命中；无则 nil）。
/// spec 优先（材料真实芯数），variant 兜底。
public func coreNumber(of text: String) -> Int? {
    guard let range = text.range(of: "\\d+\\s*芯", options: .regularExpression) else { return nil }
    let digits = text[range].prefix(while: { $0.isNumber })
    return Int(digits)
}

/// 某定额的基准行（variant = 定额名）是否已有主材规则命中（与面板/引擎
/// kind 语义同口径：通用 / 变体|备选 variant 精确相等 / 变体* 前缀命中）。
public func baselineRuleHit(quota: QuotaRow, rules: [RuleRow]) -> Bool {
    for r in rules where r.quota == quota.code {
        switch r.kind {
        case "通用": return true
        case "变体", "备选": if r.variant == quota.name { return true }
        case "变体*": if !r.variant.isEmpty && quota.name.hasPrefix(r.variant) { return true }
        default: break
        }
    }
    return false
}

/// 基准行变体补齐（v2.6.1 §11.1）：对基准行无主材命中的定额，若定额名含芯数
/// 上限 N，取同定额 kind=变体、芯数 ≤ N 的最大者复制一条 variant=定额名的
/// 规则（新 id，其余字段不变）。天然幂等（复制后基准行已命中，再跑为 0）。
/// 返回新增规则数。只处理材料规则表（libraries.rules）。
@discardableResult
public func repairBaselineVariantRules(in libs: inout LibrarySet) -> Int {
    var added = 0
    var quotasByCode: [String: QuotaRow] = [:]
    for q in libs.quotas where quotasByCode[q.code] == nil { quotasByCode[q.code] = q }
    for quota in libs.quotas {
        guard !baselineRuleHit(quota: quota, rules: libs.rules),
              let limit = coreNumber(of: quota.name) else { continue }
        var best: RuleRow? = nil
        var bestCore = -1
        for r in libs.rules where r.quota == quota.code && r.kind == "变体" {
            let core = coreNumber(of: r.spec) ?? coreNumber(of: r.variant)
            guard let c = core, c <= limit, c > bestCore else { continue }
            best = r; bestCore = c
        }
        guard var copy = best else { continue }
        copy.id = newUID()
        copy.variant = quota.name
        libs.rules.append(copy)
        added += 1
    }
    return added
}

/// DbFile 级基准补齐迁移（标记防用户删除后复活；与电缆迁移同模式）。
@discardableResult
public func migrateBaselineVariantRules(_ db: inout DbFile) -> Int {
    if (db.meta.appliedMigrations ?? []).contains(baselineVariantMigrationId) { return 0 }
    var changed = 0
    for pi in db.configurationProfiles.indices {
        changed += repairBaselineVariantRules(in: &db.configurationProfiles[pi].libraries)
    }
    var marks = db.meta.appliedMigrations ?? []
    marks.append(baselineVariantMigrationId)
    db.meta.appliedMigrations = marks
    return changed
}

/// 零快照修复（v2.6.1 §11.2）：短单联想 bug 留下的已落盘行——tech/labor 快照
/// 同时为 0 且库中任一非 0 → 两快照置 nil（回落库值）。用户主动改出的 0/0
/// 不在本函数语义内（DbFile 层标记只跑一次，见 migrateZeroSnapshots）。
/// 返回修复行数。
@discardableResult
public func repairBugZeroSnapshots(rows: inout [QuantityRow], libraries: LibrarySet) -> Int {
    var fixed = 0
    for i in rows.indices {
        let row = rows[i]
        guard row.tech == 0, row.labor == 0,
              let quota = libraries.quotas.first(where: { $0.code == row.quota }),
              quota.tech != 0 || quota.labor != 0 else { continue }
        rows[i].tech = nil
        rows[i].labor = nil
        fixed += 1
    }
    return fixed
}

/// DbFile 级零快照迁移（标记防重复）。
@discardableResult
public func migrateZeroSnapshots(_ db: inout DbFile) -> Int {
    if (db.meta.appliedMigrations ?? []).contains(zeroSnapshotMigrationId) { return 0 }
    var changed = 0
    for pj in db.projects.indices {
        let pid = db.projects[pj].profileId
        let libs = (db.configurationProfiles.first { $0.id == pid }
            ?? db.configurationProfiles.first { $0.id == db.settings.activeProfileId }
            ?? db.configurationProfiles.first)?.libraries ?? LibrarySet()
        changed += repairBugZeroSnapshots(rows: &db.projects[pj].quantities, libraries: libs)
    }
    var marks = db.meta.appliedMigrations ?? []
    marks.append(zeroSnapshotMigrationId)
    db.meta.appliedMigrations = marks
    return changed
}
