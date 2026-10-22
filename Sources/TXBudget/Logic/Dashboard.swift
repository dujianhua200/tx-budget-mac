import Foundation

/// 概览仪表盘数据派生（v2.0.0，见 docs/v2-ui-design.md §3、§8）。
/// 全部取自 CalcResult，与导出同源同值；本文件只做展示口径的分组，不改任何计算。

public struct DashboardKPI: Equatable {
    /// 总造价（含税）= 表一 grandIncl。
    public var grandIncl: Double
    /// 建安费（除税价）= 表二折后 exclTax。
    public var buildExcl: Double
    /// 设备材料费（除税）= 表四甲 + 表四乙 + 设备 三组除税合计。
    public var materialEquipExcl: Double
    /// 总工日（技工 + 普工，调整后）。
    public var techDays: Double
    public var laborDays: Double
    public var totalDays: Double { techDays + laborDays }
    public init(grandIncl: Double, buildExcl: Double, materialEquipExcl: Double,
                techDays: Double, laborDays: Double) {
        self.grandIncl = grandIncl; self.buildExcl = buildExcl
        self.materialEquipExcl = materialEquipExcl
        self.techDays = techDays; self.laborDays = laborDays
    }
}

public func dashboardKPI(_ result: CalcResult) -> DashboardKPI {
    DashboardKPI(
        grandIncl: result.table1.grandIncl,
        buildExcl: result.table2After.exclTax,
        materialEquipExcl: result.table4A.totalExcl + result.table4B.totalExcl + result.table4Equip.totalExcl,
        techDays: result.techDays,
        laborDays: result.laborDays
    )
}

/// 费用构成段（概览图）：含税口径三段——建安 / 设备 / 其他。
/// 分母 = 三段之和（与 grandIncl 一致：grandIncl = 汇总含税 + 设备含税，
/// 汇总含税 = 建安含税 + 其他含税），占比以三段之和计，避免口径交叉。
public struct FeeSegment: Equatable, Identifiable {
    public var id: String
    public var label: String
    public var amount: Double
    public init(id: String, label: String, amount: Double) {
        self.id = id; self.label = label; self.amount = amount
    }

    public func fraction(of segments: [FeeSegment]) -> Double {
        let total = segments.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return 0 }
        return amount / total
    }
}

public func feeComposition(_ result: CalcResult) -> [FeeSegment] {
    [
        FeeSegment(id: "build", label: "建筑安装工程费", amount: result.summary.constructionIncl),
        FeeSegment(id: "equip", label: "设备费", amount: result.table1.equipIncl),
        FeeSegment(id: "other", label: "工程建设其他费", amount: result.summary.otherIncl),
    ]
}
