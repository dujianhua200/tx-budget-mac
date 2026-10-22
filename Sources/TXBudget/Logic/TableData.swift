import Foundation

/// ProTable 的纯逻辑：过滤 / 稳定排序 / 列合计（v2.0.0，见 docs/v2-ui-design.md §4、§8）。
/// 行 = [String: String] 字典（与 LibraryRowCodec 的行字典同形），Views 只负责呈现。

public struct TableSort: Equatable {
    public var key: String
    public var ascending: Bool
    public init(key: String, ascending: Bool = true) {
        self.key = key; self.ascending = ascending
    }
}

/// 搜索过滤：query 去空白后，任意列值（不含 id）大小写不敏感包含即命中；空 query 返回全部。
public func tableRowsFiltered(_ rows: [[String: String]], query: String) -> [[String: String]] {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return rows }
    return rows.filter { row in
        row.contains { $0.key != "id" && $0.value.lowercased().contains(q) }
    }
}

/// 稳定排序：同值保持原顺序（以原下标决胜）。
/// key ∈ numericKeys 且两值都能解析为数字 → 按数值比；否则按本地化字符串比。
/// 解析不了的数字值排在可解析值之后（升序时），保证数字列不乱序。
public func tableRowsSorted(_ rows: [[String: String]], sort: TableSort,
                            numericKeys: Set<String>) -> [[String: String]] {
    let numeric = numericKeys.contains(sort.key)
    let indexed = Array(rows.enumerated())
    let sorted = indexed.sorted { a, b in
        let av = a.element[sort.key] ?? ""
        let bv = b.element[sort.key] ?? ""
        if numeric {
            let an = Double(av.trimmingCharacters(in: .whitespaces))
            let bn = Double(bv.trimmingCharacters(in: .whitespaces))
            switch (an, bn) {
            case let (x?, y?):
                if x != y { return sort.ascending ? x < y : x > y }
            case (_?, nil):
                return true // 有数值的排前（与 ascending 无关，空值永远靠后）
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return a.offset < b.offset
        }
        let cmp = av.localizedCompare(bv)
        if cmp != .orderedSame { return sort.ascending ? cmp == .orderedAscending : cmp == .orderedDescending }
        return a.offset < b.offset
    }
    return sorted.map { $0.element }
}

/// 列合计：对全部行（非过滤子集）求和，不可解析按 0。
public func tableColumnTotal(_ rows: [[String: String]], key: String) -> Double {
    rows.reduce(0) { sum, row in
        sum + (Double((row[key] ?? "").trimmingCharacters(in: .whitespaces)) ?? 0)
    }
}
