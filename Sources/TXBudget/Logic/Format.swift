import Foundation

/// 数值格式化（对照 Electron `store.js` 的 money / num2）。

/// 金额：千分位 + 2 位小数（如 123,456.78）；非有限 → "—"。
public func money(_ n: Double?) -> String {
    guard let n, n.isFinite else { return "—" }
    let f = NumberFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.numberStyle = .decimal
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f.string(from: NSNumber(value: n)) ?? "—"
}

/// 数量：千分位，最多 2 位小数；非有限 → "—"。
public func num2(_ n: Double?) -> String {
    guard let n, n.isFinite else { return "—" }
    let f = NumberFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.numberStyle = .decimal
    f.maximumFractionDigits = 2
    return f.string(from: NSNumber(value: n)) ?? "—"
}

/// 费率显示：×100 后去尾零的百分比（如 0.02 → "2%"，0.0495 → "4.95%"）。
public func ratePercentText(_ rate: Double?) -> String {
    guard let rate else { return "—" }
    let v = (rate * 100 * 10000).rounded() / 10000
    return "\(jsNumberString(v))%"
}

/// 日期时间（工程列表“更新时间”列）。
public func dateTimeText(_ iso: String) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: iso) {
        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.dateFormat = "yyyy-MM-dd HH:mm"
        return out.string(from: d)
    }
    let f2 = ISO8601DateFormatter()
    if let d = f2.date(from: iso) {
        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.dateFormat = "yyyy-MM-dd HH:mm"
        return out.string(from: d)
    }
    return iso
}
