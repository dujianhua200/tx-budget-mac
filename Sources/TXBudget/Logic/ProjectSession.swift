import Foundation

/// 工程会话与表四行序的纯逻辑（v2.6.0，docs/v2.6-batch-design.md §7/§9）。

/// 关闭工程前的 dirty 判定：本会话内工程是否有改动 = 当前记录与打开时基线
/// 不一致。比较时忽略 `lastOpenedAt`（打开工程时打戳，非用户编辑）与
/// `updatedAt`（任何编辑的副产物时间戳——真实内容变更必伴随其他字段变化，
/// 仅时间戳不同不算改动；改回原值即视为无改动）。任一为 nil → 无基线可比，
/// 按无改动处理（AppState 在打开工程时恒设基线，此分支仅为防御）。
public func projectSessionDirty(baseline: ProjectRecord?, current: ProjectRecord?) -> Bool {
    guard let baseline, let current else { return false }
    var a = baseline
    var b = current
    a.lastOpenedAt = nil
    b.lastOpenedAt = nil
    a.updatedAt = ""
    b.updatedAt = ""
    return a != b
}

/// 表四材料行上移/下移后的新 materialOrder（纯函数）。
/// - `tablesKeysInOrder`：当前三组生效表的显示行 key（表四甲、表四乙、设备，
///   按界面拼接序传入），是行序的事实基底。
/// - 移动只在 `movingKey` 所属表内与相邻行交换（delta 为 -1 上移 / +1 下移；
///   到边界则原样返回 currentOrder，不写新序）。
/// - 返回值 = 三组拼接的全量显式序（陈旧 key 自然剔除，未入序的新行就此入序）。
public func movedMaterialOrder(currentOrder: [String],
                               tablesKeysInOrder: [[String]],
                               movingKey: String, delta: Int) -> [String] {
    guard delta == -1 || delta == 1 else { return currentOrder }
    var tables = tablesKeysInOrder
    for t in tables.indices {
        guard let i = tables[t].firstIndex(of: movingKey) else { continue }
        let j = i + delta
        guard tables[t].indices.contains(j) else { return currentOrder }
        tables[t].swapAt(i, j)
        return tables.flatMap { $0 }
    }
    return currentOrder
}
