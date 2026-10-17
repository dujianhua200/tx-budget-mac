import Foundation

/// 导航状态（对照 Electron `v3.js`：NAV_SECTIONS / CURRENT_TABS；section + tab 单一事实源）。

public enum CurrentTab: String, Equatable, Hashable, CaseIterable {
    case info
    case workload3a
    case workload4a
    case workloadEquip
    case workload3b
    case workload3c
    case fee
    case table5
    case export

    public var label: String {
        switch self {
        case .info: return "工程信息"
        case .workload3a: return "工作量 · 表三甲"
        case .workload4a: return "工作量 · 材料汇总"
        case .workloadEquip: return "工作量 · 安装设备"
        case .workload3b: return "工作量 · 机械"
        case .workload3c: return "工作量 · 仪器仪表"
        case .fee: return "费用（表二）"
        case .table5: return "表五"
        case .export: return "报表导出"
        }
    }
}

public enum LibraryViewKey: String, Equatable, Hashable, CaseIterable {
    case quotas
    case shortlist
    case materials
    case rulesVariant
    case rulesAlt
    case machinePrices
    case instrumentPrices
    case quotaMachines
    case quotaInstruments

    public var label: String {
        switch self {
        case .quotas: return "定额库"
        case .shortlist: return "常用短单"
        case .materials: return "材料库"
        case .rulesVariant: return "定额—材料映射"
        case .rulesAlt: return "关联规则（备选）"
        case .machinePrices: return "机械库"
        case .instrumentPrices: return "仪器仪表库"
        case .quotaMachines: return "定额—机械映射"
        case .quotaInstruments: return "定额—仪表映射"
        }
    }
}

public enum FeeRuleTab: String, Equatable, Hashable, CaseIterable {
    case rates
    case table5fees
    case discount
    case rulesAlt

    public var label: String {
        switch self {
        case .rates: return "费率"
        case .table5fees: return "表五费用"
        case .discount: return "打折规则"
        case .rulesAlt: return "关联规则"
        }
    }
}

public enum NavDestination: Equatable, Hashable {
    case projects
    case current(CurrentTab)
    case batch
    case libraries(LibraryViewKey)
    case feeRules(FeeRuleTab)
    case profiles
    case settings
}

/// 底栏操作提示（对照 Electron `statusHintFor`），随视图变化。
public func statusHintFor(_ nav: NavDestination) -> String {
    switch nav {
    case .projects: return "点工程名打开工程；勾选后可批量导出/删除"
    case .current(let tab):
        switch tab {
        case .info: return "填写工程信息；取费标准切换即切换工程所用配置方案"
        case .workload3a: return "输定额编号回车下一行；数量填 0 即不计"
        case .workload4a: return "数量 = 自动计算 ＋ 手动调整；单价只影响本工程"
        case .workloadEquip: return "仅显示 supply = 设备 的材料行"
        case .workload3b: return "机械台班由定额—机械映射自动汇总"
        case .workload3c: return "仪器仪表台班由定额—仪表映射自动汇总"
        case .fee: return "点左树切换费用组；费率可直接在右表编辑"
        case .table5: return "勾选启用/停用费用项；手动项金额可覆盖"
        case .export: return "勾选要出的表后点导出"
        }
    case .batch: return "批量新建 / 导入 / 导出 / 改价 / 改折扣 / 删除"
    case .libraries: return "编辑的是“正在编辑方案”的库，不影响新建默认方案"
    case .feeRules: return "点左树切换费用组；费率可直接在右表编辑"
    case .profiles: return "编辑内容置编辑目标；设为默认只影响新建工程"
    case .settings: return "整库备份 / 导入导出"
    }
}
