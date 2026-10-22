import Foundation

/// 导航状态（v2.0.0 界面架构，见 docs/v2-ui-design.md §2）。
/// 单一事实源：AppState.nav。projectList = 启动页（工程列表）；
/// overview/projectInfo/workload/fees/export/validation 需先打开工程（requiresProject）。

public enum NavDestination: Equatable, Hashable {
    case projectList
    case overview
    case projectInfo
    case workload
    case fees
    case export
    case libraries(LibraryViewKey)
    case feeRules(FeeRuleTab)
    case profiles
    case validation
    case batch
    case settings

    public var label: String {
        switch self {
        case .projectList: return "工程列表"
        case .overview: return "概览"
        case .projectInfo: return "工程信息"
        case .workload: return "工作量"
        case .fees: return "费用"
        case .export: return "报表导出"
        case .libraries(let key): return key.label
        case .feeRules(let tab): return tab.label
        case .profiles: return "配置方案"
        case .validation: return "校验中心"
        case .batch: return "批量生成"
        case .settings: return "设置"
        }
    }

    /// SF Symbols 图标名（Views 层用 Image(systemName:) 渲染；Logic 只给字符串，保持可单测）。
    public var systemImage: String {
        switch self {
        case .projectList: return "folder"
        case .overview: return "gauge.with.dots.needle.67percent"
        case .projectInfo: return "doc.text"
        case .workload: return "list.bullet.rectangle"
        case .fees: return "yensign.circle"
        case .export: return "square.and.arrow.up"
        case .libraries(let key): return key.systemImage
        case .feeRules: return "percent"
        case .profiles: return "square.stack.3d.up"
        case .validation: return "checkmark.shield"
        case .batch: return "square.grid.2x2"
        case .settings: return "gearshape"
        }
    }

    /// 是否必须先打开一个工程才能进入（侧边栏据此禁用、状态栏据此提示）。
    public var requiresProject: Bool {
        switch self {
        case .overview, .projectInfo, .workload, .fees, .export, .validation:
            return true
        default:
            return false
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

    public var systemImage: String {
        switch self {
        case .quotas: return "book.closed"
        case .shortlist: return "star"
        case .materials: return "shippingbox"
        case .rulesVariant: return "link"
        case .rulesAlt: return "arrow.triangle.branch"
        case .machinePrices: return "truck.box"
        case .instrumentPrices: return "gauge"
        case .quotaMachines: return "wrench.and.screwdriver"
        case .quotaInstruments: return "waveform.path.ecg"
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

    public var systemImage: String {
        switch self {
        case .rates: return "percent"
        case .table5fees: return "list.bullet"
        case .discount: return "tag"
        case .rulesAlt: return "arrow.triangle.branch"
        }
    }
}

/// 底栏操作提示（随页面变化）。
public func statusHintFor(_ nav: NavDestination) -> String {
    switch nav {
    case .projectList: return "点工程卡片打开工程；列表模式可多选批量导出/删除"
    case .overview: return "概览：关键数字、费用构成与数据问题一览"
    case .projectInfo: return "填写工程信息；取费标准切换即切换工程所用配置方案"
    case .workload: return "录工程量一处即可：输定额编号/名称搜索，输数量回车添加；右侧自动生成表三/表四"
    case .fees: return "表一总表 / 表二取费（折前可编辑费率，折后只读）/ 表五其他费"
    case .export: return "勾选要出的表，右侧预览关键数字，确认后点导出"
    case .libraries: return "编辑的是“正在编辑方案”的库，不影响新建默认方案"
    case .feeRules: return "点左树切换费用组；费率可直接在右表编辑"
    case .profiles: return "编辑内容置编辑目标；设为默认只影响新建工程"
    case .validation: return "全部数据问题集中在这里，点任意一条可定位到对应页面"
    case .batch: return "批量新建 / 导入 / 导出 / 改价 / 改折扣 / 删除"
    case .settings: return "整库备份 / 导入导出"
    }
}
