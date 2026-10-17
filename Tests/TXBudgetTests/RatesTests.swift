/// 费率模型 + 方法列渲染测试。对照 src/engine/rates.mjs / discount.mjs 的 renderMethodText。
import XCTest
@testable import TXBudget

final class RatesTests: XCTestCase {
    func testRateFieldDefs() {
        XCTAssertEqual(rateFieldDefs.count, 21)
        XCTAssertEqual(rateFieldDefs.first(where: { $0.key == "techPrice" })?.gridN, 3)
        XCTAssertEqual(rateFieldDefs.first(where: { $0.key == "winterRate" })?.gridN, 15)
        XCTAssertEqual(rateGridNToKey[3], "techPrice")
        XCTAssertEqual(rateGridNToKey[26], nil) // taxRate 不在 defs 中
    }

    func testRateGridToRates() {
        let seed = loadSeed()
        let byType = rateGridToRates(seed.rateGrid)
        // seed rateGrid 第 4 行（gridN=3，技工费）G..K 列全为 114。
        XCTAssertEqual(byType["通信线路工程"]?.techPrice, 114)
        XCTAssertEqual(byType["通信管道工程"]?.techPrice, 114)
        // 冬雨季行恒为 nil（= 按 winterTable 查表）。
        XCTAssertNil(byType["通信线路工程"]?.winterRate)
        // 空 rateGrid → 全 0 / winterRate nil。
        let empty = rateGridToRates(nil)
        XCTAssertEqual(empty["通信线路工程"]?.techPrice, 0)
        XCTAssertNil(empty["通信线路工程"]?.winterRate)
    }

    func testWinterRateForNamed() {
        var rates = Rates(byProjectType: ["通信线路工程": NamedRates()],
                          winterTable: ["Ⅲ类地区": 0.018], vatRates: VatRates())
        // winterRate nil → 查表。
        XCTAssertEqual(winterRateForNamed(rates, "通信线路工程", "Ⅲ类地区"), 0.018, accuracy: 0.000001)
        // 显式 0 是显式 0，不查表。
        var named = NamedRates()
        named.winterRate = 0
        rates.byProjectType?["通信线路工程"] = named
        XCTAssertEqual(winterRateForNamed(rates, "通信线路工程", "Ⅲ类地区"), 0)
        // 显式值覆盖。
        named.winterRate = 0.05
        rates.byProjectType?["通信线路工程"] = named
        XCTAssertEqual(winterRateForNamed(rates, "通信线路工程", "Ⅲ类地区"), 0.05)
        // 地区不在表里 → 0。
        named.winterRate = nil
        rates.byProjectType?["通信线路工程"] = named
        XCTAssertEqual(winterRateForNamed(rates, "通信线路工程", "不存在的地区"), 0)
        // rates 为 nil → 0。
        XCTAssertEqual(winterRateForNamed(nil, "通信线路工程", "Ⅲ类地区"), 0)
    }

    func testRateForNamed() {
        var named = NamedRates()
        named.techPrice = 114
        let rates = Rates(byProjectType: ["通信线路工程": named], winterTable: [:], vatRates: VatRates())
        XCTAssertEqual(rateForNamed(rates, "通信线路工程", "techPrice"), 114)
        XCTAssertNil(rateForNamed(rates, "通信线路工程", "laborPrice")) // 字段缺失 → nil
        XCTAssertNil(rateForNamed(rates, "不存在的类型", "techPrice"))
        XCTAssertNil(rateForNamed(nil, "通信线路工程", "techPrice"))
    }

    func testResolveNamedRatesUnknownType() {
        let (rate, warnings) = resolveNamedRates(libs: Libs(), projectType: "不存在的类型", region: "Ⅲ类地区")
        XCTAssertEqual(rate.techPrice, 0)
        XCTAssertEqual(rate.winterRate, 0)
        XCTAssertTrue(warnings.contains { $0.code == "unknownProjectType" })
    }

    func testResolveNamedRatesMissingRates() {
        let (rate, warnings) = resolveNamedRates(libs: Libs(), projectType: "通信线路工程", region: "Ⅲ类地区")
        XCTAssertEqual(rate.techPrice, 0)
        XCTAssertTrue(warnings.contains { $0.code == "missingRate" })
    }

    func testRenderMethodText() {
        let def = discountLineDefs.first(where: { $0.key == "techFee" })!
        XCTAssertEqual(renderMethodText(def, mode: .before, vars: ["techPrice": 114]), "技工总工日X114")
        XCTAssertEqual(renderMethodText(def, mode: .discounted, vars: ["techPrice": 114, "discountRate": 0.379]),
                       "技工总工日X114X37.9%")
        XCTAssertEqual(renderMethodText(def, mode: .restored, vars: ["techPrice": 114, "discountRate": 0.379]),
                       "技工总工日X114/37.9%")
        // 缺失变量时占位符保留。
        XCTAssertEqual(renderMethodText(def, mode: .discounted, vars: [:]), "技工总工日X{techPrice}X{discountPct}%")
        // discountPct 去浮点噪声：0.5 → 50，0.33333 → 33.3333。
        let civil = discountLineDefs.first(where: { $0.key == "civilFee" })!
        XCTAssertEqual(renderMethodText(civil, mode: .restored, vars: ["civilRate": 1.5, "discountRate": 0.5]),
                       "人工费X1.5%/50%")
    }

    func testRounding() {
        XCTAssertEqual(r2(2.4168), 2.42, accuracy: 0.000001)
        XCTAssertEqual(r2(72343.775), 72343.78, accuracy: 0.000001)
        XCTAssertEqual(r2(0), 0)
        // 100.005 的 Double 实际略小于 100.005，故 JS/Swift 的 r2 都给出 100.0（非 100.01）。
        XCTAssertEqual(r2(100.005), 100.0, accuracy: 0.000001)
        XCTAssertEqual(num(nil), 0)
        XCTAssertEqual(num(Double.nan), 0)
        XCTAssertEqual(num(5), 5)
        XCTAssertEqual(jsNumberString(114), "114")
        XCTAssertEqual(jsNumberString(0.018), "0.018")
        XCTAssertEqual(jsNumberString(Double.nan), "NaN")
    }
}
