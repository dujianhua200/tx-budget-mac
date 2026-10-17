import Foundation

/// 批量工程工作量表解析与批量增删改导服务
/// 支持：
/// 1. 从工作量汇总表批量生成多个单项概预算工程（每个工程自带双表二及折前安生费）
/// 2. 批量修改已勾选工程的折扣率、建设单位、施工单位、定额工程量比例
/// 3. 批量删除勾选工程、批量导入/导出工程包
public struct BatchProjectSpec: Codable {
    public var code: String
    public var name: String
    public var specialty: String
    public var discountFactor: Double
    public var ownerUnit: String
    public var quotaQuantities: [(quotaId: String, quantity: Double)]

    enum CodingKeys: String, CodingKey {
        case code, name, specialty, discountFactor, ownerUnit
    }

    public init(code: String, name: String, specialty: String, discountFactor: Double, ownerUnit: String, quotaQuantities: [(String, Double)]) {
        self.code = code
        self.name = name
        self.specialty = specialty
        self.discountFactor = discountFactor
        self.ownerUnit = ownerUnit
        self.quotaQuantities = quotaQuantities
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(String.self, forKey: .code)
        name = try c.decode(String.self, forKey: .name)
        specialty = try c.decode(String.self, forKey: .specialty)
        discountFactor = try c.decode(Double.self, forKey: .discountFactor)
        ownerUnit = try c.decode(String.self, forKey: .ownerUnit)
        quotaQuantities = []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        try c.encode(name, forKey: .name)
        try c.encode(specialty, forKey: .specialty)
        try c.encode(discountFactor, forKey: .discountFactor)
        try c.encode(ownerUnit, forKey: .ownerUnit)
    }
}

public enum BatchWorkloadParser {
    /// 解析形如：`项目编号 | 工程名称 | TXL1-002:15, TXL3-187:1.5` 的多工程工作量文本
    public static func parseLines(
        _ text: String,
        defaultSpecialty: String = "通信线路工程",
        defaultDiscount: Double = 0.379,
        defaultOwner: String = "中国联合网络通信有限公司信阳市分公司"
    ) -> [BatchProjectSpec] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.enumerated().map { idx, line in
            let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            let code = parts.indices.contains(0) && !parts[0].isEmpty ? parts[0] : String(format: "9NA26BATCH%03d", idx + 1)
            let name = parts.indices.contains(1) && !parts[1].isEmpty ? parts[1] : "批量生成通信工程(\(idx + 1))"
            let pairsRaw = parts.indices.contains(2) ? parts[2] : ""
            let pairs: [(String, Double)] = pairsRaw.components(separatedBy: ",").compactMap { token in
                let kv = token.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let qid = kv.first, !qid.isEmpty else { return nil }
                let qty = kv.count > 1 ? (Double(kv[1]) ?? 1.0) : 1.0
                return (qid, qty)
            }
            return BatchProjectSpec(
                code: code,
                name: name,
                specialty: defaultSpecialty,
                discountFactor: defaultDiscount,
                ownerUnit: defaultOwner,
                quotaQuantities: pairs
            )
        }
    }
}
