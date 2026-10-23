import Foundation

/// 库表行 ↔ 字典编解码（供通用字典表格 DictTableView 使用）。
/// 列定义对照 Electron `libraryDefs.js`；rules 表在资料库仅保留“关联规则（备选）”视图
/// （v2.6.0 起定额—材料/机械/仪表关联的维护入口收敛到表三甲底部关联区，
/// 见 docs/v2.6-batch-design.md §8）。

public struct LibraryRowCodec {
    public static func columns(for key: LibraryViewKey) -> [LibraryColumn] {
        switch key {
        case .quotas:
            return [
                LibraryColumn(key: "code", label: "定额编号", kind: .text),
                LibraryColumn(key: "name", label: "定额名称", kind: .text),
                LibraryColumn(key: "unit", label: "单位", kind: .text),
                LibraryColumn(key: "tech", label: "技工/单位", kind: .number),
                LibraryColumn(key: "labor", label: "普工/单位", kind: .number),
                LibraryColumn(key: "coef", label: "系数", kind: .number),
                LibraryColumn(key: "book", label: "分册", kind: .text),
                LibraryColumn(key: "alias", label: "别名", kind: .text),
            ]
        case .shortlist:
            return [
                LibraryColumn(key: "code", label: "定额编号", kind: .text),
                LibraryColumn(key: "name", label: "定额名称", kind: .text),
                LibraryColumn(key: "unit", label: "单位", kind: .text),
                LibraryColumn(key: "coef", label: "系数", kind: .number),
            ]
        case .materials:
            return [
                LibraryColumn(key: "name", label: "名称", kind: .text),
                LibraryColumn(key: "spec", label: "规格", kind: .text),
                LibraryColumn(key: "unit", label: "单位", kind: .text),
                LibraryColumn(key: "priceExcl", label: "除税单价", kind: .number),
                LibraryColumn(key: "supply", label: "供货", kind: .select, options: ["甲供", "乙供", "设备"]),
                LibraryColumn(key: "remark", label: "备注", kind: .text),
            ]
        case .rulesAlt:
            return [
                LibraryColumn(key: "quota", label: "定额编号", kind: .text),
                LibraryColumn(key: "material", label: "材料", kind: .text),
                LibraryColumn(key: "spec", label: "规格", kind: .text),
                LibraryColumn(key: "unit", label: "单位", kind: .text),
                LibraryColumn(key: "consumption", label: "单位消耗量", kind: .number),
                LibraryColumn(key: "supply", label: "供货", kind: .select, options: ["甲供", "乙供", "设备"]),
                LibraryColumn(key: "kind", label: "类型", kind: .select, options: ["备选"]),
                LibraryColumn(key: "variant", label: "变体项目名称", kind: .text),
                LibraryColumn(key: "remark", label: "备注", kind: .text),
                LibraryColumn(key: "appliesTo", label: "适用工程", kind: .text),
            ]
        case .machinePrices:
            return [
                LibraryColumn(key: "code", label: "机械编号", kind: .text),
                LibraryColumn(key: "name", label: "机械名称", kind: .text),
                LibraryColumn(key: "unit", label: "单位", kind: .text),
                LibraryColumn(key: "price", label: "台班单价", kind: .number),
            ]
        case .instrumentPrices:
            return [
                LibraryColumn(key: "code", label: "仪表编号", kind: .text),
                LibraryColumn(key: "name", label: "仪表名称", kind: .text),
                LibraryColumn(key: "unit", label: "单位", kind: .text),
                LibraryColumn(key: "price", label: "台班单价", kind: .number),
            ]
        }
    }

    /// 表五费用列（取费规则 · 表五费用视图用）。
    public static var table5Columns: [LibraryColumn] {
        [
            LibraryColumn(key: "key", label: "费用 key", kind: .text),
            LibraryColumn(key: "name", label: "费用名称", kind: .text),
            LibraryColumn(key: "basis", label: "取费依据", kind: .select,
                          options: ["manual", "preDiscountExclTax", "afterDiscountExclTax", "laborTotal", "fixed", "surveyKm", "sum"]),
            LibraryColumn(key: "rate", label: "费率", kind: .number),
            LibraryColumn(key: "vatRate", label: "增值税率", kind: .number),
            LibraryColumn(key: "amount", label: "固定金额", kind: .number),
            LibraryColumn(key: "enabled", label: "启用", kind: .checkbox),
            LibraryColumn(key: "order", label: "序号", kind: .number),
            LibraryColumn(key: "note", label: "备注", kind: .text),
        ]
    }

    // MARK: - 行 → 字典

    public static func dicts(for key: LibraryViewKey, profile: ConfigurationProfile) -> [[String: String]] {
        let libs = profile.libraries
        switch key {
        case .quotas:
            return libs.quotas.map { quotaDict($0) }
        case .shortlist:
            return libs.shortlist.map { r in
                ["id": r.id, "code": r.code, "name": r.name, "unit": r.unit,
                 "coef": r.coef.map { jsNumberString($0) } ?? ""]
            }
        case .materials:
            return libs.materials.map { r in
                ["id": r.id, "name": r.name, "spec": r.spec, "unit": r.unit,
                 "priceExcl": jsNumberString(r.priceExcl), "supply": r.supply, "remark": r.remark]
            }
        case .rulesAlt:
            return libs.rules.filter { $0.kind == "备选" }.map { ruleDict($0) }
        case .machinePrices:
            return libs.machinePrices.map { r in
                ["id": r.id, "code": r.code, "name": r.name, "unit": r.unit, "price": jsNumberString(r.price)]
            }
        case .instrumentPrices:
            return libs.instrumentPrices.map { r in
                ["id": r.id, "code": r.code, "name": r.name, "unit": r.unit, "price": jsNumberString(r.price)]
            }
        }
    }

    public static func table5Dicts(_ fees: [Table5Fee]) -> [[String: String]] {
        fees.map { f in
            ["id": f.key,
             "key": f.key, "name": f.name, "basis": f.basis,
             "rate": f.rate.map { jsNumberString($0) } ?? "",
             "vatRate": f.vatRate.map { jsNumberString($0) } ?? "",
             "amount": f.amount.map { jsNumberString($0) } ?? "",
             "enabled": (f.enabled ?? true) ? "true" : "false",
             "order": jsNumberString(f.order), "note": f.note]
        }
    }

    private static func quotaDict(_ r: QuotaRow) -> [String: String] {
        ["id": r.id, "code": r.code, "name": r.name, "unit": r.unit,
         "tech": jsNumberString(r.tech), "labor": jsNumberString(r.labor),
         "coef": r.coef.map { jsNumberString($0) } ?? "",
         "book": r.book, "alias": r.alias]
    }

    private static func ruleDict(_ r: RuleRow) -> [String: String] {
        ["id": r.id, "quota": r.quota, "material": r.material, "spec": r.spec, "unit": r.unit,
         "consumption": jsNumberString(r.consumption), "supply": r.supply, "kind": r.kind,
         "variant": r.variant, "remark": r.remark, "appliesTo": r.appliesTo]
    }

    // MARK: - 字典 → 行（按 id 写回；找不到 id 时追加）

    public static func commit(id: String, dict: [String: String], viewKey: LibraryViewKey,
                              profile: inout ConfigurationProfile) {
        switch viewKey {
        case .quotas:
            upsert(&profile.libraries.quotas, id: id) {
                QuotaRow(id: id, code: dict["code"] ?? "", name: dict["name"] ?? "", unit: dict["unit"] ?? "",
                         tech: num(dict["tech"]), labor: num(dict["labor"]),
                         coef: optNum(dict["coef"]), book: dict["book"] ?? "", alias: dict["alias"] ?? "")
            }
        case .shortlist:
            upsert(&profile.libraries.shortlist, id: id) {
                ShortlistRow(id: id, code: dict["code"] ?? "", name: dict["name"] ?? "",
                             unit: dict["unit"] ?? "", coef: optNum(dict["coef"]))
            }
        case .materials:
            upsert(&profile.libraries.materials, id: id) {
                MaterialRow(id: id, name: dict["name"] ?? "", spec: dict["spec"] ?? "",
                            unit: dict["unit"] ?? "", priceExcl: num(dict["priceExcl"]),
                            supply: dict["supply"] ?? "", remark: dict["remark"] ?? "")
            }
        case .rulesAlt:
            upsert(&profile.libraries.rules, id: id) {
                RuleRow(id: id, quota: dict["quota"] ?? "", material: dict["material"] ?? "",
                        spec: dict["spec"] ?? "", unit: dict["unit"] ?? "",
                        consumption: num(dict["consumption"]), supply: dict["supply"] ?? "",
                        kind: dict["kind"] ?? "", variant: dict["variant"] ?? "",
                        remark: dict["remark"] ?? "", appliesTo: dict["appliesTo"] ?? "全")
            }
        case .machinePrices:
            upsert(&profile.libraries.machinePrices, id: id) {
                MachinePriceRow(id: id, code: dict["code"] ?? "", name: dict["name"] ?? "",
                                unit: dict["unit"] ?? "", price: num(dict["price"]))
            }
        case .instrumentPrices:
            upsert(&profile.libraries.instrumentPrices, id: id) {
                InstrumentPriceRow(id: id, code: dict["code"] ?? "", name: dict["name"] ?? "",
                                   unit: dict["unit"] ?? "", price: num(dict["price"]))
            }
        }
    }

    public static func commitTable5(id: String, dict: [String: String], profile: inout ConfigurationProfile) {
        // 表五费用以 key 为 id（字典 id 即 fee.key）。
        let fee = Table5Fee(
            key: dict["key"] ?? id, name: dict["name"] ?? "", basis: dict["basis"] ?? "manual",
            rate: optNum(dict["rate"]), vatRate: optNum(dict["vatRate"]),
            amount: optNum(dict["amount"]), enabled: dict["enabled"] == "true",
            order: num(dict["order"]), note: dict["note"] ?? "", children: nil
        )
        // 保留原 children（字典不编辑 children）。
        if let i = profile.table5Fees.firstIndex(where: { $0.key == id }) {
            var merged = fee
            merged.children = profile.table5Fees[i].children
            profile.table5Fees[i] = merged
        } else {
            profile.table5Fees.append(fee)
        }
    }

    public static func add(viewKey: LibraryViewKey, profile: inout ConfigurationProfile) {
        let id = newUID()
        switch viewKey {
        case .quotas:
            profile.libraries.quotas.insert(QuotaRow(id: id, coef: 1), at: 0)
        case .shortlist:
            profile.libraries.shortlist.insert(ShortlistRow(id: id, coef: 1), at: 0)
        case .materials:
            profile.libraries.materials.insert(MaterialRow(id: id, supply: "甲供"), at: 0)
        case .rulesAlt:
            profile.libraries.rules.insert(RuleRow(id: id, supply: "甲供", kind: "备选", appliesTo: "全"), at: 0)
        case .machinePrices:
            profile.libraries.machinePrices.insert(MachinePriceRow(id: id, unit: "台班"), at: 0)
        case .instrumentPrices:
            profile.libraries.instrumentPrices.insert(InstrumentPriceRow(id: id, unit: "台班"), at: 0)
        }
    }

    public static func addTable5(profile: inout ConfigurationProfile) {
        var key = "newFee"
        var n = 1
        while profile.table5Fees.contains(where: { $0.key == key }) { n += 1; key = "newFee\(n)" }
        profile.table5Fees.append(Table5Fee(key: key, name: "新费用项", basis: "manual", rate: 0,
                                            vatRate: 0, amount: nil, enabled: true, order: 99, note: ""))
    }

    public static func delete(ids: Set<String>, viewKey: LibraryViewKey, profile: inout ConfigurationProfile) {
        guard !ids.isEmpty else { return }
        switch viewKey {
        case .quotas: profile.libraries.quotas.removeAll { ids.contains($0.id) }
        case .shortlist: profile.libraries.shortlist.removeAll { ids.contains($0.id) }
        case .materials: profile.libraries.materials.removeAll { ids.contains($0.id) }
        case .rulesAlt: profile.libraries.rules.removeAll { ids.contains($0.id) }
        case .machinePrices: profile.libraries.machinePrices.removeAll { ids.contains($0.id) }
        case .instrumentPrices: profile.libraries.instrumentPrices.removeAll { ids.contains($0.id) }
        }
    }

    public static func deleteTable5(ids: Set<String>, profile: inout ConfigurationProfile) {
        profile.table5Fees.removeAll { ids.contains($0.key) }
    }

    // MARK: - 助手

    private static func num(_ s: String?) -> Double {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return 0 }
        return Double(s) ?? 0
    }

    private static func optNum(_ s: String?) -> Double? {
        guard let s = s?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        return Double(s)
    }

    private static func upsert<T>(_ rows: inout [T], id: String, make: () -> T) where T: IdentifiableID {
        if let i = rows.firstIndex(where: { $0.rowId == id }) {
            rows[i] = make()
        } else {
            rows.append(make())
        }
    }
}

/// 行 id 协议（库表行统一按 id 查找）。
protocol IdentifiableID {
    var rowId: String { get }
}

extension QuotaRow: IdentifiableID { var rowId: String { id } }
extension ShortlistRow: IdentifiableID { var rowId: String { id } }
extension MaterialRow: IdentifiableID { var rowId: String { id } }
extension RuleRow: IdentifiableID { var rowId: String { id } }
extension MachinePriceRow: IdentifiableID { var rowId: String { id } }
extension InstrumentPriceRow: IdentifiableID { var rowId: String { id } }
extension QuotaMachineRow: IdentifiableID { var rowId: String { id } }
extension QuotaInstrumentRow: IdentifiableID { var rowId: String { id } }
