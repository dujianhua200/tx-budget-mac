#if os(macOS)
import SwiftUI
import Charts

/// 概览（仪表盘，v2.0.0）：KPI 卡片 + 费用构成图 + 数据问题 + 快捷操作 + 工程摘要。
/// 数字全部来自 CalcResult（Logic/Dashboard.swift 派生），与导出同源同值。
struct OverviewView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "概览",
                           subtitle: "\(project.name) · 方案：\(appState.projectProfile?.name ?? "—")")
                if let result = appState.calcResult(for: project) {
                    content(result: result)
                } else {
                    EmptyStateView(
                        systemImage: "exclamationmark.triangle",
                        title: "计算失败",
                        message: "工程所用配置方案不存在或无法计算，请到工程信息页检查配置方案。",
                        actionTitle: "去工程信息",
                        action: { appState.nav = .projectInfo }
                    )
                    .cardStyle()
                }
            }
            .padding(Theme.pagePadding)
        }
    }

    private func content(result: CalcResult) -> some View {
        let kpi = dashboardKPI(result)
        let segments = feeComposition(result)
        return VStack(alignment: .leading, spacing: 16) {
            // KPI 卡片行
            HStack(spacing: 16) {
                KPICard(label: "总造价（含税）", systemImage: "yensign.circle",
                        value: "¥" + money(kpi.grandIncl),
                        sub: "表一总计")
                KPICard(label: "建安费（除税）", systemImage: "building.2",
                        value: money(kpi.buildExcl),
                        sub: "表二折后除税价")
                KPICard(label: "设备材料费（除税）", systemImage: "shippingbox",
                        value: money(kpi.materialEquipExcl),
                        sub: "表四甲 + 表四乙 + 设备")
                KPICard(label: "总工日", systemImage: "person.2",
                        value: num2(kpi.totalDays),
                        sub: "技工 \(num2(kpi.techDays)) · 普工 \(num2(kpi.laborDays))")
            }
            HStack(alignment: .top, spacing: 16) {
                // 费用构成
                SectionCard(title: "费用构成", subtitle: "含税口径，占比以三段之和为分母") {
                    Chart {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                            BarMark(
                                x: .value("金额", seg.amount),
                                y: .value("类别", seg.label)
                            )
                            .foregroundStyle(Theme.segmentColors[idx % Theme.segmentColors.count])
                            .cornerRadius(4)
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(height: 150)
                    VStack(spacing: 6) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Theme.segmentColors[idx % Theme.segmentColors.count])
                                    .frame(width: 10, height: 10)
                                Text(seg.label)
                                Spacer()
                                Text(money(seg.amount) + " 元").monospacedDigit()
                                Text(ratePercentText(seg.fraction(of: segments)))
                                    .foregroundColor(.secondary)
                                    .frame(width: 52, alignment: .trailing)
                            }
                            .font(.callout)
                        }
                    }
                }
                // 右列：问题 + 快捷操作
                VStack(spacing: 16) {
                    issuesCard
                    quickActionsCard
                }
                .frame(width: 330)
            }
            // 工程摘要
            SectionCard(title: "工程摘要") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          alignment: .leading, spacing: 8) {
                    summaryRow("建设单位", project.info.建设单位)
                    summaryRow("工程类别", project.info.工程类型)
                    summaryRow("施工折扣", discountOption(project.info) == "discount"
                        ? ratePercentText(project.info.施工折扣 ?? 1) : "不打折")
                    summaryRow("编制日期", project.info.编制日期)
                    summaryRow("工程量行数", "\(project.quantities.count) 行")
                    summaryRow("最后修改", dateTimeText(project.updatedAt))
                }
            }
        }
    }

    private var issuesCard: some View {
        let issues = appState.openProjectIssues
        return SectionCard(title: "数据问题", subtitle: issues.isEmpty ? "全部校验通过" : "共 \(issues.count) 条，前 5 条") {
            if issues.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                    Text("没有发现问题，可以放心导出。")
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(issues.prefix(5)) { issue in
                        Button {
                            appState.nav = issue.target
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: issue.severity.systemImage)
                                    .foregroundColor(issue.severity == .error ? .red
                                        : issue.severity == .warning ? .orange : .blue)
                                Text(issue.title)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button("查看全部（校验中心）") { appState.nav = .validation }
                }
            }
        }
    }

    private var quickActionsCard: some View {
        SectionCard(title: "快捷操作") {
            VStack(alignment: .leading, spacing: 8) {
                quickButton("录工程量", "list.bullet.rectangle", .workload)
                quickButton("完善工程信息", "doc.text", .projectInfo)
                quickButton("查看费用", "yensign.circle", .fees)
                quickButton("导出预算书", "square.and.arrow.up", .export)
            }
        }
    }

    private func quickButton(_ label: String, _ icon: String, _ dest: NavDestination) -> some View {
        Button {
            appState.nav = dest
        } label: {
            HStack {
                Label(label, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label).foregroundColor(.secondary).frame(width: 86, alignment: .leading)
            Text(value.isEmpty ? "—" : value).lineLimit(1)
        }
        .font(.callout)
    }
}
#endif
