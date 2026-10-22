import Foundation

/// 按官方清理（v2.3.0，见 docs/v2.3-cleanup-design.md）。
///
/// 删除用户方案里官方 451 手册没有的错误关联（三张关联表：rules / quotaMachines /
/// quotaInstruments）。判定与 v2.2 合并/校正同口径（见 LibraryCompletion.swift）：
/// 行的定额编码必须在内置库（官方）定额表中，且该行按判定键在内置库同一编码
/// 定额的关联中不存在，才列入待删。明确不删：rules 中 kind != "通用" 的行
/// （变体/备选是一号多材机制）、手册外定额（如 TGD2-161）与自建定额的关联；
/// 定额本体、材料表、台班价、费率、工程数据一律不碰。
///
/// 三重保险：plan 是 dry-run（只读，返回完整待删清单供预览）；apply 按 plan 清单
/// 逐行删除（预览什么删什么，匹配口径见 applyLibraryCleanup）；删前由调用方先写
/// 方案备份（writeLibraryCleanupBackup）。

/// 待删清单中的一行（供预览逐行展示与 apply 逐行匹配删除）。
public struct LibraryCleanupItem: Equatable {
    /// base 中该行的 id（仅作参考：真实数据可能为空/重复，删除按内容匹配，见 apply）。
    public var id: String
    public var quota: String
    /// 材料名（rules）或台班名称（机械/仪表）。
    public var name: String
    /// 规格（rules 的 spec；机械/仪表为台班编码 mcode，可能为空）。
    public var spec: String
    public var unit: String
    /// 消耗量（rules 的 consumption / 关联的 qty）。
    public var qty: Double
    public init(id: String, quota: String, name: String, spec: String, unit: String, qty: Double) {
        self.id = id; self.quota = quota; self.name = name
        self.spec = spec; self.unit = unit; self.qty = qty
    }
    /// 预览一行文案：“TXL4-026 电缆挂钩 × 2060 只”。
    public var displayText: String {
        "\(quota) \(name) × \(num2(qty))\(unit.isEmpty ? "" : " \(unit)")"
    }
}

/// dry-run 结果：三张表的待删清单（保持 base 行序）。
public struct LibraryCleanupPlan: Equatable {
    public var rules: [LibraryCleanupItem] = []
    public var quotaMachines: [LibraryCleanupItem] = []
    public var quotaInstruments: [LibraryCleanupItem] = []
    public init() {}
    public var total: Int { rules.count + quotaMachines.count + quotaInstruments.count }
    /// 一行汇总：“材料关联 N 条、机械关联 N 条、仪表关联 N 条”。
    public var detailText: String {
        "材料关联 \(rules.count) 条、机械关联 \(quotaMachines.count) 条、仪表关联 \(quotaInstruments.count) 条"
    }
}

    /// apply 的实际删除计数（按清单逐行匹配删除，预览后数据有变动时可能少于 plan）。
public struct LibraryCleanupReport: Equatable {
    public var rulesRemoved = 0
    public var quotaMachinesRemoved = 0
    public var quotaInstrumentsRemoved = 0
    public init() {}
    public var total: Int { rulesRemoved + quotaMachinesRemoved + quotaInstrumentsRemoved }
    public var detailText: String {
        "材料关联 \(rulesRemoved) 条、机械关联 \(quotaMachinesRemoved) 条、仪表关联 \(quotaInstrumentsRemoved) 条"
    }
}

/// dry-run：算出 base 中按官方口径应删的关联行清单。不修改 base。
public func planLibraryCleanup(base: LibrarySet, full: LibrarySet) -> LibraryCleanupPlan {
    var plan = LibraryCleanupPlan()
    let officialQuotas = Set(full.quotas.map { $0.code })

    // 材料关联：仅 kind == "通用" 且定额在官方内；键 (quota, 归一化材料名, spec)。
    var fullRuleKeys = Set<String>()
    for r in full.rules where r.kind == "通用" {
        fullRuleKeys.insert("\(r.quota)|\(libraryMatchNorm(r.material))|\(r.spec)")
    }
    for r in base.rules where r.kind == "通用" && officialQuotas.contains(r.quota) {
        let key = "\(r.quota)|\(libraryMatchNorm(r.material))|\(r.spec)"
        if !fullRuleKeys.contains(key) {
            plan.rules.append(LibraryCleanupItem(
                id: r.id, quota: r.quota, name: r.material, spec: r.spec,
                unit: r.unit, qty: r.consumption))
        }
    }

    // 机械/仪表关联：定额在官方内；编码键或名称键任一命中即视为官方有此关联。
    func planAssoc<T>(rows: [T], fullRows: [T],
                      quota: (T) -> String, mcode: (T) -> String,
                      mname: (T) -> String, unit: (T) -> String,
                      qty: (T) -> Double, id: (T) -> String) -> [LibraryCleanupItem] {
        var codeKeys = Set<String>()
        var nameKeys = Set<String>()
        for r in fullRows {
            if !mcode(r).isEmpty { codeKeys.insert("\(quota(r))|\(mcode(r))") }
            nameKeys.insert("\(quota(r))|\(libraryMatchNorm(mname(r)))")
        }
        var items: [LibraryCleanupItem] = []
        for r in rows where officialQuotas.contains(quota(r)) {
            let byCode = !mcode(r).isEmpty && codeKeys.contains("\(quota(r))|\(mcode(r))")
            let byName = nameKeys.contains("\(quota(r))|\(libraryMatchNorm(mname(r)))")
            if !byCode && !byName {
                items.append(LibraryCleanupItem(
                    id: id(r), quota: quota(r), name: mname(r), spec: mcode(r),
                    unit: unit(r), qty: qty(r)))
            }
        }
        return items
    }
    plan.quotaMachines = planAssoc(
        rows: base.quotaMachines, fullRows: full.quotaMachines,
        quota: { $0.quota }, mcode: { $0.mcode }, mname: { $0.mname },
        unit: { $0.unit }, qty: { $0.qty }, id: { $0.id })
    plan.quotaInstruments = planAssoc(
        rows: base.quotaInstruments, fullRows: full.quotaInstruments,
        quota: { $0.quota }, mcode: { $0.mcode }, mname: { $0.mname },
        unit: { $0.unit }, qty: { $0.qty }, id: { $0.id })
    return plan
}

/// 执行清理：按 plan 清单逐行删除三张关联表中的对应行，其余表逐字不动。
/// 逐行匹配口径：(quota, 名称, spec/编码, unit, qty) 全等的第一行——真实数据中
/// 行 id 可能为空或重复（Electron 时代数据无 id），不能只按 id 删；plan 清单里的
/// 每一行都按谓词判定过，任何与之全等的行本身必是额外行，按出现顺序逐个删，
/// plan 有几行删几行（全等重复行同理）。返回清理后集合与实际删除计数。
/// 对已清理结果再 plan 必为 0（幂等）。
public func applyLibraryCleanup(base: LibrarySet, plan: LibraryCleanupPlan)
    -> (cleaned: LibrarySet, report: LibraryCleanupReport) {
    var cleaned = base
    var report = LibraryCleanupReport()
    for item in plan.rules {
        if let i = cleaned.rules.firstIndex(where: {
            $0.quota == item.quota && $0.material == item.name && $0.spec == item.spec
                && $0.unit == item.unit && $0.consumption == item.qty
        }) {
            cleaned.rules.remove(at: i)
            report.rulesRemoved += 1
        }
    }
    for item in plan.quotaMachines {
        if let i = cleaned.quotaMachines.firstIndex(where: {
            $0.quota == item.quota && $0.mname == item.name && $0.mcode == item.spec
                && $0.unit == item.unit && $0.qty == item.qty
        }) {
            cleaned.quotaMachines.remove(at: i)
            report.quotaMachinesRemoved += 1
        }
    }
    for item in plan.quotaInstruments {
        if let i = cleaned.quotaInstruments.firstIndex(where: {
            $0.quota == item.quota && $0.mname == item.name && $0.mcode == item.spec
                && $0.unit == item.unit && $0.qty == item.qty
        }) {
            cleaned.quotaInstruments.remove(at: i)
            report.quotaInstrumentsRemoved += 1
        }
    }
    return (cleaned, report)
}

/// 删前自动备份：把方案完整导出为方案文件 JSON（`DatabaseStore.exportProfileData`
/// 格式，可经“导入方案文件”恢复），写入指定目录（App 惯例落数据目录，与滚动备份
/// 同目录），文件名 `cleanup-backup-<方案id>-<yyyyMMdd-HHmmss>.json`。
/// 备份失败抛错——调用方必须中止清理，绝不无备份删数据。
public func writeLibraryCleanupBackup(profile: ConfigurationProfile,
                                      directory: URL,
                                      now: Date = Date()) throws -> URL {
    let fm = FileManager.default
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "yyyyMMdd-HHmmss"
    let url = directory.appendingPathComponent(
        "cleanup-backup-\(profile.id)-\(fmt.string(from: now)).json")
    let data = try DatabaseStore.exportProfileData(profile)
    try data.write(to: url, options: [.atomic])
    return url
}
