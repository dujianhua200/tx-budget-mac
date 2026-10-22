#if os(macOS)
import SwiftUI

/// v2 视觉规范（docs/v2-ui-design.md §5）：系统字体层级、8pt 间距、卡片圆角 10 + 细边框、
/// accent 用图标同系深蓝；颜色全走系统语义色，深色模式自动适配。
enum Theme {
    /// 图标同系深蓝（母图深蓝→青绿渐变中的深蓝端近似）。
    static let accent = Color(red: 0.08, green: 0.28, blue: 0.50)
    /// 费用构成图分段色（深蓝 / 青绿 / 金，与图标同系）。
    static let segmentColors: [Color] = [
        Color(red: 0.08, green: 0.28, blue: 0.50),
        Color(red: 0.05, green: 0.55, blue: 0.55),
        Color(red: 0.85, green: 0.62, blue: 0.15),
    ]
    static let cardCorner: CGFloat = 10
    static let pagePadding: CGFloat = 20
    static let cardPadding: CGFloat = 14
}

extension View {
    /// 卡片：圆角 10 + 细边框 + 控件背景色（深色模式自动适配）。
    func cardStyle() -> some View {
        self
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(Theme.cardCorner)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

/// 页面标题区：大标题 + 一行说明。
struct PageHeader: View {
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2).fontWeight(.bold)
            if let subtitle {
                Text(subtitle).font(.callout).foregroundColor(.secondary)
            }
        }
    }
}

/// 分组卡片（替代裸 GroupBox）：标题 + 可选说明 + 内容。
struct SectionCard<Content: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
            }
            content()
        }
        .cardStyle()
    }
}

/// 概览 KPI 卡片：小标签 + 大数字（等宽）+ 可选副文。
struct KPICard: View {
    var label: String
    var systemImage: String
    var value: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: systemImage)
                .font(.caption).foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let sub {
                Text(sub).font(.caption).foregroundColor(.secondary)
            }
        }
        .cardStyle()
    }
}

/// 空状态引导：图标 + 一句话 + 主按钮。
struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
    }
}
#endif
