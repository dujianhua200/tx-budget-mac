import Foundation

/// 双表二计算核心引擎（同时输出【表二（折后/结算）】与【表二（未打折/折前基准）】并联动计算表五甲折前安全生产费）
/// 严格对应《大宇翔通信建设工程概预算软件》截图 6、13、14、16、17 的取费逻辑与公式：
/// - 折后表二：技工费 A11 = JGGR*114*d，普工费 A12 = PGGR*61*d，机械 A3 = JXFY*d，仪表 A4 = YQFY*d
/// - 文明施工费 B1：支持不打折模式 `A1 * 0.015 / d`
/// - 规费 GF (C2/C3/C4)：支持按折前标准工日 `(JGGR*114 + PGGR*61)` 计取（规费不优惠）
/// - 表五甲第8项【安全生产费】：`((AZFY - A2 - B1 - GF) / d + A2_未打折 + B1 + GF) * 0.015` (即未打折表二除税建安费 × 1.5%)
public struct DualTable2Summary: Codable, Equatable {
    public var discountFactor: Double
    public var techDays: Double
    public var coolieDays: Double

    /// 表二（折后/结算）核心指标
    public var discountedA11: Double
    public var discountedA12: Double
    public var discountedA1: Double
    public var discountedA21: Double
    public var discountedA22: Double
    public var discountedA2: Double
    public var discountedA3: Double
    public var discountedA4: Double
    public var discountedZJ: Double
    public var discountedB1: Double
    public var discountedCS: Double
    public var discountedZJFY: Double
    public var discountedGF: Double
    public var discountedGL: Double
    public var discountedJJ: Double
    public var discountedLR: Double
    public var discountedAZFY: Double
    public var discountedSJ: Double
    public var discountedAZFS: Double

    /// 表二（未打折/折前基准）核心指标
    public var undiscountedA1: Double
    public var undiscountedA21: Double
    public var undiscountedA22: Double
    public var undiscountedA2: Double
    public var undiscountedA3: Double
    public var undiscountedA4: Double
    public var undiscountedZJ: Double
    public var undiscountedB1: Double
    public var undiscountedCS: Double
    public var undiscountedZJFY: Double
    public var undiscountedGF: Double
    public var undiscountedGL: Double
    public var undiscountedJJ: Double
    public var undiscountedLR: Double
    /// 大宇翔图16含主材表二除税价 (如 155.90)
    public var undiscountedAZFYWithMainMat: Double
    /// 大宇翔图6/图17折前安全生产费计算基数: ((AZFY - A2 - B1 - GF) / d + A2_raw + B1 + GF)
    public var preDiscountSafetyBaseAZFY: Double
    /// 折前基准安全生产费 (preDiscountSafetyBaseAZFY * 1.5%)
    public var preDiscountSafetyFee: Double
    /// 折后基准安全生产费 (discountedAZFY * 1.5%)
    public var postDiscountSafetyFee: Double
}

public enum DualTable2Calculator {
    public static func round2(_ v: Double) -> Double {
        (v * 100.0).rounded() / 100.0
    }

    public static func calculate(
        techDays: Double,
        coolieDays: Double,
        rawMainMaterialFee: Double,
        rawMachineFee: Double,
        rawInstrumentFee: Double,
        discountFactor: Double,
        vatRatePercent: Double = 9.0,
        civilFeeUnDiscounted: Bool = true,
        regulatoryFeeUnDiscounted: Bool = true,
        excludeMainMatInDiscountedTable2: Bool = false
    ) -> DualTable2Summary {
        let d = max(0.0001, min(1.0, discountFactor))

        // 1. 折后表二
        let a11_d = round2(techDays * 114.0 * d)
        let a12_d = round2(coolieDays * 61.0 * d)
        let a1_d = round2(a11_d + a12_d)

        let a21_d = excludeMainMatInDiscountedTable2 ? 0.0 : round2(rawMainMaterialFee)
        let a22_d = round2(a21_d * 0.003)
        let a2_d = round2(a21_d + a22_d)

        let a3_d = round2(rawMachineFee * d)
        let a4_d = round2(rawInstrumentFee * d)
        let zj_d = round2(a1_d + a2_d + a3_d + a4_d)

        let b1_d = civilFeeUnDiscounted ? round2((a1_d * 0.015) / d) : round2(a1_d * 0.015)
        let b4_d = round2(a1_d * 0.033)
        let b6_d = round2(a1_d * 0.050)
        let b9_d = round2(a1_d * 0.015)
        let cs_d = round2(b1_d + b4_d + b6_d + b9_d)
        let zjfy_d = round2(zj_d + cs_d)

        let rawLaborBase = techDays * 114.0 + coolieDays * 61.0
        let regBase = regulatoryFeeUnDiscounted ? rawLaborBase : a1_d
        let c2 = round2(regBase * 0.285)
        let c3 = round2(regBase * 0.0419)
        let c4 = round2(regBase * 0.010)
        let gf_d = round2(c2 + c3 + c4)

        let gl_d = round2(a1_d * 0.274)
        let jj_d = round2(gf_d + gl_d)
        let lr_d = round2(a1_d * 0.200)
        let azfy_d = round2(zjfy_d + jj_d + lr_d)
        let sj_d = round2(azfy_d * (vatRatePercent / 100.0))
        let azfs_d = round2(azfy_d + sj_d)

        // 2. 未打折表二
        let a11_r = round2(techDays * 114.0)
        let a12_r = round2(coolieDays * 61.0)
        let a1_r = round2(a11_r + a12_r)
        let a21_r = round2(rawMainMaterialFee)
        let a22_r = round2(a21_r * 0.003)
        let a2_r = round2(a21_r + a22_r)
        let a3_r = round2(rawMachineFee)
        let a4_r = round2(rawInstrumentFee)
        let zj_r = round2(a1_r + a2_r + a3_r + a4_r)

        let b1_r = round2(a1_r * 0.015)
        let cs_r = round2(b1_r + round2(a1_r * 0.033) + round2(a1_r * 0.050) + round2(a1_r * 0.015))
        let zjfy_r = round2(zj_r + cs_r)
        let gl_r = round2(a1_r * 0.274)
        let jj_r = round2(gf_d + gl_r)
        let lr_r = round2(a1_r * 0.200)

        let azfyWithMainMat = round2(azfy_d - a2_d + a2_r)
        let preDiscountBase = round2(((azfy_d - a2_d - b1_d - gf_d) / d) + a2_r + b1_d + gf_d)
        let safetyPre = round2(preDiscountBase * 0.015)
        let safetyPost = round2(azfy_d * 0.015)

        return DualTable2Summary(
            discountFactor: d,
            techDays: techDays,
            coolieDays: coolieDays,
            discountedA11: a11_d,
            discountedA12: a12_d,
            discountedA1: a1_d,
            discountedA21: a21_d,
            discountedA22: a22_d,
            discountedA2: a2_d,
            discountedA3: a3_d,
            discountedA4: a4_d,
            discountedZJ: zj_d,
            discountedB1: b1_d,
            discountedCS: cs_d,
            discountedZJFY: zjfy_d,
            discountedGF: gf_d,
            discountedGL: gl_d,
            discountedJJ: jj_d,
            discountedLR: lr_d,
            discountedAZFY: azfy_d,
            discountedSJ: sj_d,
            discountedAZFS: azfs_d,
            undiscountedA1: a1_r,
            undiscountedA21: a21_r,
            undiscountedA22: a22_r,
            undiscountedA2: a2_r,
            undiscountedA3: a3_r,
            undiscountedA4: a4_r,
            undiscountedZJ: zj_r,
            undiscountedB1: b1_r,
            undiscountedCS: cs_r,
            undiscountedZJFY: zjfy_r,
            undiscountedGF: gf_d,
            undiscountedGL: gl_r,
            undiscountedJJ: jj_r,
            undiscountedLR: lr_r,
            undiscountedAZFYWithMainMat: azfyWithMainMat,
            preDiscountSafetyBaseAZFY: preDiscountBase,
            preDiscountSafetyFee: safetyPre,
            postDiscountSafetyFee: safetyPost
        )
    }
}
