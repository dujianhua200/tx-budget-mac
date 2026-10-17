/// 引擎 vs LibreOffice 重算母版：全链路逐项比对。对照 tests/crosscheck.test.mjs。
import XCTest
@testable import TXBudget

final class CrosscheckTests: XCTestCase {
    func testCrosscheck() {
        let seed = loadSeed()
        let lo = loadLOValues()
        let libs = gridLibs(from: seed)
        var info = ProjectInfo()
        info.工程类型 = "通信线路工程"
        info.施工折扣 = 1
        info.施工实际里程 = 36
        info.冬雨季施工费 = "Ⅲ类地区"
        info.乙供增值税 = 0.09
        info.甲供增值税 = 0.13
        let quantities: [QuantityRow] = [
            QuantityRow(quota: "TXL1-002", variant: "光(电)缆工程施工测量 架空", unit: "", qty: 10, coef: 1),
            QuantityRow(quota: "TXL3-187", variant: "挂钩法架设架空光缆 平原 6芯", unit: "", qty: 2, coef: 1),
            QuantityRow(quota: "TXL3-187", variant: "挂钩法架设架空光缆 平原 24芯", unit: "", qty: 3, coef: 1),
            QuantityRow(quota: "TXL4-053", variant: "架设吊线式墙壁光缆 6芯(工日X0.5)", unit: "", qty: 4, coef: 0.5),
            QuantityRow(quota: "TXL7-023", variant: "安装光分纤箱、光分路箱 架空式 二槽位（SMC）", unit: "", qty: 5, coef: 1),
            QuantityRow(quota: "TXL7-023", variant: "安装光分纤箱、光分路箱 架空式 48芯", unit: "", qty: 1, coef: 1),
            QuantityRow(quota: "TXL7-043", variant: "安装落地式光缆交接箱 288芯", unit: "", qty: 2, coef: 1),
        ]
        let res = calcProject(Project(info: info, quantities: quantities), libs)

        // LO 表二 I8 为 #N/A（母版嵌套 TEXT/HLOOKUP 在 LO 下失效），按母版本意 冬雨季 0.018 计算：D9×0.018。
        let loI8 = r2(res.table2.laborTotal * 0.018)

        func check(_ label: String, _ engine: Double, _ loVal: Double) {
            XCTAssertEqual(engine, loVal, accuracy: 0.011, label)
        }
        check("表三甲 H66(技工小计)", res.techSub, lo["表三甲!H66"]!)
        check("表三甲 I66(普工小计)", res.laborSub, lo["表三甲!I66"]!)
        check("表三甲 H68(技工合计)", res.techDays, lo["表三甲!H68"]!)
        check("表三甲 I68(普工合计)", res.laborDays, lo["表三甲!I68"]!)
        check("表三乙 J52(机械费)", res.table3B.total, lo["表三乙!J52"]!)
        check("表三丙 J57(仪表费)", res.table3C.total, lo["表三丙!J57"]!)
        check("表四甲 I63(甲供除税)", res.table4A.totalExcl, lo["表四甲（主材）!I63"]!)
        check("表四甲 J63(甲供增值税)", res.table4A.totalVat, lo["表四甲（主材）!J63"]!)
        check("表四乙 I63(乙供除税)", res.table4B.totalExcl, lo["表四乙(乙供）!I63"]!)
        check("表二 D9(人工费)", res.table2.laborTotal, lo["表二!D9"]!)
        check("表二 D13(主材费)", res.table2.mainMat, lo["表二!D13"]!)
        check("表二 D16(辅材费)", res.table2.auxMat, lo["表二!D16"]!)
        check("表二 D17(机械费)", res.table2.machineFee, lo["表二!D17"]!)
        check("表二 D18(仪表费)", res.table2.instrumentFee, lo["表二!D18"]!)
        check("表二 I14(调遣费)", res.table2.dispatchFee, 1410)
        check("表二 I8(冬雨季)", res.table2.winterFee, loI8)
        check("表二 I16(间接费)", res.table2.indirectTotal, lo["表二!I16"]!)
        check("表二 I23(利润)", res.table2.profit, lo["表二!I23"]!)
        check("表二 I24(销项税)", res.table2.outputTax, lo["表二!I24"]!)
        check("表二 D6(除税价)", res.table2.exclTax, lo["表二!D6"]!)
        check("表二 D5(含税价)", res.table2.inclTax, lo["表二!D5"]!)
        check("表一 G6(折前)", res.table1.beforeDiscount, lo["表一!G6"]!)
        check("表一 G7(折后)", res.table1.afterDiscount, lo["表一!G7"]!)
        // 增量 6 修正：表一合计含表五总计，故安全生产费口径变化同样影响表一；
        // 合计除税 = LO 值 + 折前除税价×0.005（安全生产费 1.5%→2% 的除税差额）。
        check("表一 J9(合计除税，新口径)", res.table1.sumExcl, lo["表一!J9"]! + lo["表二!D6"]! * 0.005)
        // 增量 2 口径：taxAfter 改按折后销项税额（v1 是 outputTax − 甲供增值税），故含税合计 = LO 值 + 甲供增值税；
        // 增量 6 补：再 + 折前除税价×0.005（安全生产费除税差额）− 折前除税价×0.015×0.09（旧安全生产费增值税归零）。
        check("表一 L9(合计含税，新口径)", res.table1.sumIncl,
              lo["表一!L9"]! + lo["表四甲（主材）!J63"]!
                + lo["表二!D6"]! * 0.005 - lo["表二!D6"]! * 0.015 * 0.09)
        check("表一 L12(总计含税，新口径)", res.table1.grandIncl,
              lo["表一!L12"]! + lo["表四甲（主材）!J63"]!
                + lo["表二!D6"]! * 0.005 - lo["表二!D6"]! * 0.015 * 0.09)
        // 增量 2 口径：安全生产费 1.5%+9% → 2%+0，故表五总计除税 = LO 值 + 折前除税价×0.005，
        // 总计增值税 = LO 值 − 折前除税价×0.015×0.09（旧安全生产费增值税部分归零）。
        check("表五 D23(其他费除税，新口径)", res.table5.totalExcl, lo["表五!D23"]! + lo["表二!D6"]! * 0.005)
        check("表五 E23(其他费增值税，新口径)", res.table5.totalVat, lo["表五!E23"]! - lo["表二!D6"]! * 0.015 * 0.09)
        // 增量 2 口径：汇总表 = 表一折后建安费 + 表五总计。
        // 折扣=1 时折后除税价 = LO 表二 D6，折后销项税额 = LO 表二 I24。
        check("汇总表 L11(总计含税，新口径)", res.summary.totalIncl,
              lo["表二!D6"]! + (lo["表五!D23"]! + lo["表二!D6"]! * 0.005)
                + lo["表二!I24"]! + (lo["表五!E23"]! - lo["表二!D6"]! * 0.015 * 0.09))
    }
}
