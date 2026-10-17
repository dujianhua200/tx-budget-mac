/// 引擎单元测试：对标 v3.0 母版 LibreOffice 实测值。对照 tests/engine.test.mjs。
import XCTest
@testable import TXBudget

final class EngineTests: XCTestCase {
    func testScenarioA_MaterialQuantities() {
        let seed = loadSeed()
        let libs = engineLibs(from: seed)
        let variantOf = { (quota: String, kind: String) in
            libs.rules.filter { $0.quota == quota && $0.kind == kind }.map { $0.variant }
        }
        let v187 = variantOf("TXL3-187", "变体")
        let v7023 = variantOf("TXL7-023", "变体")

        var info = ProjectInfo()
        info.工程类型 = "通信线路工程"
        info.施工折扣 = 1
        let quantities: [QuantityRow] = [
            // TXL3-187 只填 6芯=2、24芯=3（12芯留空）
            QuantityRow(quota: "TXL3-187", variant: v187.first(where: { $0.hasSuffix("6芯") }), unit: "", qty: 2, coef: 1),
            QuantityRow(quota: "TXL3-187", variant: v187.first(where: { $0.hasSuffix("24芯") }), unit: "", qty: 3, coef: 1),
            QuantityRow(quota: "TXL4-053", variant: "架设吊线式墙壁光缆 6芯(工日X0.5)", unit: "", qty: 4, coef: 0.5),
            // TXL7-023 只填两个变体：二槽位(SMC)=5、48芯=1（四槽位留空）
            QuantityRow(quota: "TXL7-023", variant: v7023[0], unit: "", qty: 5, coef: 1),
            QuantityRow(quota: "TXL7-023", variant: v7023[4], unit: "", qty: 1, coef: 1),
            QuantityRow(quota: "TXL7-043", variant: libs.rules.first(where: { $0.quota == "TXL7-043" && $0.kind == "变体" })?.variant ?? "", unit: "", qty: 2, coef: 1),
        ]
        let res = calcProject(Project(info: info, quantities: quantities), libs)

        XCTAssertEqual(matQty(res, "光缆", "GYTS_6芯"), 2.4168, accuracy: 0.011)
        XCTAssertEqual(matQty(res, "光缆", "GYTS_24芯"), 3.021, accuracy: 0.011)
        XCTAssertEqual(matQty(res, "光缆", "GYTS_12芯"), 0, accuracy: 0.011)
        XCTAssertEqual(matQty(res, "抱杆2槽（SMC）", ""), 5, accuracy: 0.011)
        XCTAssertEqual(matQty(res, "抱杆4槽（SMC）", ""), 0, accuracy: 0.011)
        XCTAssertEqual(matQty(res, "48芯分纤箱（SMC）", ""), 1, accuracy: 0.011)
        XCTAssertEqual(matQty(res, "光缆交接箱", "288芯"), 2, accuracy: 0.011)
        XCTAssertEqual(matQty(res, "光缆交接箱", "144芯"), 0, accuracy: 0.011)
    }

    func testScenarioB_EmptyProject() {
        let seed = loadSeed()
        let libs = engineLibs(from: seed)
        let res = calcProject(Project(info: ProjectInfo(), quantities: []), libs)
        XCTAssertEqual(res.table2.exclTax, 0, accuracy: 0.011)
        XCTAssertEqual(res.table1.grandIncl, 0, accuracy: 0.011)
    }

    func testScenarioC_MachineInstrument() {
        let seed = loadSeed()
        let libs = engineLibs(from: seed)
        let res = calcProject(Project(info: ProjectInfo(),
                                      quantities: [QuantityRow(quota: "TXL1-008", variant: "", unit: "", qty: 7, coef: 1)]),
                              libs)
        // TXL1-008 机械/仪表（v2.1 实测：空压机 5.95 台班）
        let air = res.table3B.rows.first(where: { $0.equipName.contains("空气压缩机") })
        XCTAssertEqual(air?.sessions ?? 0, 5.95, accuracy: 0.011)
        let cutter = res.table3B.rows.first(where: { $0.equipName.contains("切割机") })
        XCTAssertEqual(cutter?.sessions ?? 0, 3.5, accuracy: 0.011)
    }
}
