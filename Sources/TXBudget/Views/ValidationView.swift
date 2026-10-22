#if os(macOS)
import SwiftUI

/// 校验中心（v2.0.0）：全部数据问题一处看完，按严重度分组，每条可定位到目标页面。
/// 数据来自 Logic/Validation.swift 的 collectValidationIssues（AppState.openProjectIssues）。
struct ValidationView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "校验中心",
                           subtitle: subtitle)
                if issues.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.green)
                        Text("全部校验通过").font(.title3).fontWeight(.bold)
                        Text("没有发现孤儿行、缺单价、空费率等问题，可以放心导出预算书。")
                            .foregroundColor(.secondary)
                        Button("去导出预算书") { appState.nav = .export }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .cardStyle()
                } else {
                    ForEach([ValidationSeverity.error, .warning, .info], id: \.self) { severity in
                        let group = issues.filter { $0.severity == severity }
                        if !group.isEmpty {
                            SectionCard(title: "\(severity.label)（\(group.count)）") {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(group.enumerated()), id: \.element.id) { idx, issue in
                                        issueRow(issue)
                                        if idx < group.count - 1 { Divider() }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Theme.pagePadding)
        }
    }

    private var issues: [ValidationIssue] { appState.openProjectIssues }

    private var subtitle: String {
        guard let name = appState.openProject?.name else { return "" }
        if issues.isEmpty { return "\(name) · 无问题" }
        let errors = issues.filter { $0.severity == .error }.count
        let warnings = issues.filter { $0.severity == .warning }.count
        let infos = issues.filter { $0.severity == .info }.count
        return "\(name) · 共 \(issues.count) 条（错误 \(errors) · 警告 \(warnings) · 提示 \(infos)）"
    }

    private func issueRow(_ issue: ValidationIssue) -> some View {
        Button {
            appState.nav = issue.target
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: issue.severity.systemImage)
                    .foregroundColor(issue.severity == .error ? .red
                        : issue.severity == .warning ? .orange : .blue)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(issue.title)
                        .font(.callout).fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                    if !issue.detail.isEmpty {
                        Text(issue.detail)
                            .font(.caption).foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer()
                HStack(spacing: 2) {
                    Text("去\(issue.target.label)")
                    Image(systemName: "chevron.right")
                }
                .font(.caption).foregroundColor(Theme.accent)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
