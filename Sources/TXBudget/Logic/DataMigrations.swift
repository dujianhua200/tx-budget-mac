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
