import Foundation
/// 舍入与数值工具。对照 JS 引擎的 r2 / num / String(v)。
/// 架构文档 §3：不许用 Decimal / NSDecimalNumber 替代——JS 引擎是二进制浮点逐项舍入。

/// 金额 ROUND(x, 2)，与 Excel 一致（均为非负数）。
/// JS：`Math.round((x + Number.EPSILON) * 100) / 100`；Math.round 为“半向 +∞”，
/// 与 `floor(y + 0.5)` 等价。`Double.ulpOfOne == Number.EPSILON`。
public func r2(_ x: Double) -> Double {
    floor((x + Double.ulpOfOne) * 100 + 0.5) / 100
}

/// JS `num(x)`：非数字 / 非有限 → 0。
public func num(_ x: Double?) -> Double {
    guard let x, x.isFinite else { return 0 }
    return x
}

/// JS `String(v)`（数字转字符串）。JS 与 Swift 的 Double 短格式对常见值一致；
/// 整数值 JS 输出无小数点（"114" 而非 "114.0"），此处特殊处理。
public func jsNumberString(_ v: Double) -> String {
    if v.isNaN { return "NaN" }
    if v == .infinity { return "Infinity" }
    if v == -.infinity { return "-Infinity" }
    if v == v.rounded(), abs(v) < 1e15 {
        return String(Int64(v))
    }
    return String(v)
}
