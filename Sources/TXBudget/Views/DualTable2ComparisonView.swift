import SwiftUI

/// 大宇翔风格【双表二】同屏对比与切换视图
/// 左侧：工程费用表(表二 · 折后结算表)
/// 右侧：工程费用表(表二未打折 · 折前安全生产费基准表)
public struct DualTable2ComparisonView: View {
    @Binding public var discountFactor: Double
    @Binding public var civilUnDiscounted: Bool
    @Binding public var regFeeUnDiscounted: Bool
    @Binding public var excludeMainMatInDiscounted2: Bool
    @Binding public var usePreDiscountSafetyFee: Bool

    public var summary: DualTable2Summary

    @State private var displayMode: Int = 0 // 0: 双表二同屏对比, 1: 仅折后表二, 2: 仅未打折表二

    public init(
        discountFactor: Binding<Double>,
        civilUnDiscounted: Binding<Bool>,
        regFeeUnDiscounted: Binding<Bool>,
        excludeMainMatInDiscounted2: Binding<Bool>,
        usePreDiscountSafetyFee: Binding<Bool>,
        summary: DualTable2Summary
    ) {
        self._discountFactor = discountFactor
        self._civilUnDiscounted = civilUnDiscounted
        self._regFeeUnDiscounted = regFeeUnDiscounted
        self._excludeMainMatInDiscounted2 = excludeMainMatInDiscounted2
        self._usePreDiscountSafetyFee = usePreDiscountSafetyFee
        self.summary = summary
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 顶部控制条
            HStack(spacing: 12) {
                Picker("显示模式", selection: $displayMode) {
                    Text("双表二同屏对比 (折后 + 未打折)").tag(0)
                    Text("表二 (折后结算)").tag(1)
                    Text("表二 (未打折/折前基准)").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 420)

                Divider().frame(height: 18)

                HStack(spacing: 6) {
                    Text("施工折扣:")
                        .font(.caption.bold())
                    TextField("0.379", value: $discountFactor, format: .number.precision(.fractionLength(3)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                }

                Toggle("文明施工费不打折", isOn: $civilUnDiscounted)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Toggle("规费不打折", isOn: $regFeeUnDiscounted)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Toggle("按未打折表二算安生费(1.5%)", isOn: $usePreDiscountSafetyFee)
                    .toggleStyle(.checkbox)
                    .font(.caption.bold())

                Spacer()
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 双表二对比区
            HStack(spacing: 1) {
                if displayMode == 0 || displayMode == 1 {
                    feeTableColumn(
                        title: "【表二 · 折后结算表】工程费用表(表二)",
                        subtitle: String(format: "除税建安费: %.2f 元 | 含税: %.2f 元", summary.discountedAZFY, summary.discountedAZFS),
                        headerColor: Color.green.opacity(0.12),
                        rows: [
                            ("建安工程费(含税价)", "AZFS", "AZFY+SJ", summary.discountedAZFS),
                            ("建安工程费(除税价)", "AZFY", "ZJFY+JJ+LR", summary.discountedAZFY),
                            ("一、直接费", "ZJFY", "ZJ+CS", summary.discountedZJFY),
                            ("  (一)直接工程费", "ZJ", "A1+A2+A3+A4", summary.discountedZJ),
                            ("    1.人工费", "A1", "A11+A12", summary.discountedA1),
                            ("      (1)技工费", "A11", String(format: "JGGR*114*%.3f", summary.discountFactor), summary.discountedA11),
                            ("      (2)普工费", "A12", String(format: "PGGR*61*%.3f", summary.discountFactor), summary.discountedA12),
                            ("    2.材料费", "A2", "A21+A22", summary.discountedA2),
                            ("      (1)主要材料费", "A21", "ZCFY", summary.discountedA21),
                            ("      (2)辅助材料费", "A22", "A21*0.003", summary.discountedA22),
                            ("    3.机械使用费", "A3", String(format: "JXFY*%.3f", summary.discountFactor), summary.discountedA3),
                            ("    4.仪表使用费", "A4", String(format: "YQFY*%.3f", summary.discountFactor), summary.discountedA4),
                            ("  (二)措施项目费", "CS", "B1+B4+B6+B9", summary.discountedCS),
                            ("    1.文明施工费", "B1", civilUnDiscounted ? String(format: "A1*0.015/%.3f", summary.discountFactor) : "A1*0.015", summary.discountedB1),
                            ("二、间接费", "JJ", "GF+GL", summary.discountedJJ),
                            ("  (一)规费(不优惠)", "GF", "C2+C3+C4", summary.discountedGF),
                            ("  (二)企业管理费", "GL", "A1*0.274", summary.discountedGL),
                            ("三、利润", "LR", "A1*0.2", summary.discountedLR),
                            ("四、销项税额", "SJ", "AZFY*税率", summary.discountedSJ)
                        ]
                    )
                }

                if displayMode == 0 || displayMode == 2 {
                    feeTableColumn(
                        title: "【表二 · 未打折/折前基准表】工程费用表(表二未打折)",
                        subtitle: String(format: "折前安生费基数: %.2f 元 | 折前安生费(1.5%%): %.2f 元", summary.preDiscountSafetyBaseAZFY, summary.preDiscountSafetyFee),
                        headerColor: Color.orange.opacity(0.14),
                        rows: [
                            ("建安工程费(折前安生费基数)", "AZFY_RAW", "((AZFY-A2-B1-GF)/折扣)+A2+B1+GF", summary.preDiscountSafetyBaseAZFY),
                            ("建安工程费(含主材表二)", "AZFY_155", "ZJFY+JJ+LR(含主材)", summary.undiscountedAZFYWithMainMat),
                            ("一、直接费(未打折100%)", "ZJFY", "ZJ+CS", summary.undiscountedZJFY),
                            ("  (一)直接工程费(未打折)", "ZJ", "A1+A2+A3+A4", summary.undiscountedZJ),
                            ("    1.人工费(100%工日)", "A1", "JGGR*114+PGGR*61", summary.undiscountedA1),
                            ("    2.材料费(含主材+辅材)", "A2", "A21+A22", summary.undiscountedA2),
                            ("      (1)主要材料费", "A21", "ZCFY", summary.undiscountedA21),
                            ("      (2)辅助材料费", "A22", "A21*0.003", summary.undiscountedA22),
                            ("    3.机械使用费(100%)", "A3", "JXFY", summary.undiscountedA3),
                            ("    4.仪表使用费(100%)", "A4", "YQFY", summary.undiscountedA4),
                            ("  (二)措施项目费(100%)", "CS", "B1+B4+B6+B9", summary.undiscountedCS),
                            ("    1.文明施工费", "B1", "A1_RAW*0.015", summary.undiscountedB1),
                            ("二、间接费(未打折)", "JJ", "GF+GL", summary.undiscountedJJ),
                            ("  (一)规费", "GF", "C2+C3+C4", summary.undiscountedGF),
                            ("  (二)企业管理费", "GL", "A1_RAW*0.274", summary.undiscountedGL),
                            ("三、利润(未打折)", "LR", "A1_RAW*0.2", summary.undiscountedLR),
                            ("★ 折前安全生产费(表五#8)", "AQF", "AZFY_RAW * 0.015", summary.preDiscountSafetyFee)
                        ]
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func feeTableColumn(
        title: String,
        subtitle: String,
        headerColor: Color,
        rows: [(String, String, String, Double)]
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.caption.bold())
                Spacer()
                Text(subtitle).font(.caption.monospacedDigit()).foregroundColor(.secondary)
            }
            .padding(8)
            .background(headerColor)

            List(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack {
                    Text(row.0)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.1)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.blue)
                        .frame(width: 72, alignment: .center)
                    Text(row.2)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 190, alignment: .leading)
                    Text(String(format: "%.2f", row.3))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(width: 90, alignment: .trailing)
                }
            }
            .listStyle(.plain)
        }
    }
}
