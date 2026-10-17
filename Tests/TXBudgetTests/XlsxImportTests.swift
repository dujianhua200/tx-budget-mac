import XCTest
@testable import TXBudget

/// xlsx 导入测试（v1.0.2，见设计文档 §10）。
/// 夹具为真实 DEFLATE 压缩的 xlsx（Python zipfile 生成）；期望值与 Electron
///（`node /tmp/electron_check.mjs` 跑 `excel.cjs` / `libraryOps.js`）逐项对照。
/// 已知有意偏差（见 §10.3 / §10.1）：费率空数值不参与 diff（Electron 代码实际会产生
/// to=null 的 diff）；日期型单元格进文本列原生为 yyyy-MM-dd（Electron 为 JS Date.toString）。
final class XlsxImportTests: XCTestCase {
    private func fixtureData(_ name: String, ext: String = "xlsx") -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")!
        return try! Data(contentsOf: url)
    }

    private func row(_ pairs: (String, ImportValue)...) -> ImportRow {
        ImportRow(fields: Dictionary(uniqueKeysWithValues: pairs))
    }

    // MARK: - 解析

    func testParseQuotasSharedStrings() {
        let r = parseLibraryFile(data: fixtureData("import-quotas"), kind: .quotas, fileName: "import-quotas.xlsx")
        XCTAssertEqual(r.errors, [])
        XCTAssertEqual(r.rows.count, 3)
        XCTAssertEqual(r.rows[0].fields["code"], .text("T-1"))
        XCTAssertEqual(r.rows[0].fields["tech"], .number(1.5))
        XCTAssertEqual(r.rows[0].fields["labor"], .number(2.5))
        XCTAssertEqual(r.rows[0].fields["coef"], .number(1))
        XCTAssertEqual(r.rows[0].fields["book"], .text("线路册"))
        XCTAssertEqual(r.rows[1].fields["coef"], .number(0.5))
        XCTAssertEqual(r.rows[1].fields["alias"], .text("别名二"))
        XCTAssertEqual(r.rows[2].fields["unit"], .text("千米"))
    }

    func testParseQuotasAliases() {
        let r = parseLibraryFile(data: fixtureData("import-quotas-alias"), kind: .quotas, fileName: "x.xlsx")
        XCTAssertEqual(r.errors, [])
        XCTAssertEqual(r.rows.count, 1)
        XCTAssertEqual(r.rows[0].fields["code"], .text("A-1"))
        XCTAssertEqual(r.rows[0].fields["tech"], .number(1))
        XCTAssertEqual(r.rows[0].fields["labor"], .number(2))
        XCTAssertEqual(r.rows[0].fields["book"], .text("线路册"))
    }

    func testParseBadRows() {
        let r = parseLibraryFile(data: fixtureData("import-bad"), kind: .quotas, fileName: "x.xlsx")
        XCTAssertEqual(r.rows.count, 1)
        XCTAssertEqual(r.rows[0].fields["code"], .text("GOOD-1"))
        XCTAssertEqual(r.errors, ["第 2 行：技工不是有效数字", "第 3 行：定额编号必填"])
    }

    func testMissingRequiredColumn() {
        let r = parseLibraryFile(data: fixtureData("import-missing-col"), kind: .quotas, fileName: "x.xlsx")
        XCTAssertEqual(r.rows, [])
        XCTAssertEqual(r.errors, ["表头缺失必填列：定额名称（首行应为：定额编号 / 定额名称 / 单位 / 技工 / 普工 / 系数 / 分册名称 / 别名）"])
    }

    func testParseMaterialsInlineStr() {
        let r = parseLibraryFile(data: fixtureData("import-materials"), kind: .materials, fileName: "x.xlsx")
        XCTAssertEqual(r.rows.count, 2)
        XCTAssertEqual(r.rows[0].fields["priceExcl"], .number(1234.56))
        XCTAssertEqual(r.rows[0].fields["supply"], .text("甲供"))
        XCTAssertEqual(r.rows[1].fields["name"], .text("钢绞线"))
        XCTAssertEqual(r.errors, ["第 3 行：供货非法取值“自购”"])
    }

    func testParseTable5Checkbox() {
        let r = parseLibraryFile(data: fixtureData("import-table5"), kind: .table5Fees, fileName: "x.xlsx")
        XCTAssertEqual(r.rows.count, 4)
        XCTAssertEqual(r.rows[0].fields["enabled"], .bool(true))
        XCTAssertEqual(r.rows[0].fields["rate"], .number(0.02))
        XCTAssertEqual(r.rows[0].fields["amount"], .null)
        XCTAssertEqual(r.rows[1].fields["enabled"], .bool(false)) // “禁用”
        XCTAssertEqual(r.rows[2].fields["enabled"], .bool(true)) // “启用”
        XCTAssertEqual(r.rows[2].fields["amount"], .number(123))
        XCTAssertEqual(r.rows[3].fields["enabled"], .bool(true)) // 空 → 默认 true
        XCTAssertEqual(r.errors, ["第 6 行：启用应为是/否"])
    }

    func testParseRatesNullValue() {
        let r = parseLibraryFile(data: fixtureData("import-rates"), kind: .rates, fileName: "x.xlsx")
        XCTAssertEqual(r.errors, [])
        XCTAssertEqual(r.rows.count, 3)
        XCTAssertEqual(r.rows[0].fields["数值"], .number(114))
        XCTAssertEqual(r.rows[1].fields["数值"], .null)
        XCTAssertEqual(r.rows[2].fields["费率项目"], .text("不存在的费率"))
    }

    func testParseRulesKindEmpty() {
        let r = parseLibraryFile(data: fixtureData("import-rules"), kind: .rulesVariant, fileName: "x.xlsx")
        XCTAssertEqual(r.errors, [])
        XCTAssertEqual(r.rows.count, 3)
        XCTAssertEqual(r.rows[0].fields["kind"], .text("变体"))
        XCTAssertEqual(r.rows[1].fields["kind"], .text("")) // 解析阶段不补默认，归一化时补
        XCTAssertEqual(r.rows[2].fields["kind"], .text("备选"))
    }

    func testParseCorruptFile() {
        let r = parseLibraryFile(data: fixtureData("import-corrupt", ext: "bin"), kind: .quotas, fileName: "bad.xlsx")
        XCTAssertEqual(r.rows, [])
        XCTAssertEqual(r.errors.count, 1)
        XCTAssertTrue(r.errors[0].hasPrefix("文件打不开（bad.xlsx）："))
    }

    func testParseNoSheets() {
        let r = parseLibraryFile(data: fixtureData("empty-sheets"), kind: .quotas, fileName: "x.xlsx")
        XCTAssertEqual(r.rows, [])
        XCTAssertEqual(r.errors, ["文件无工作表"])
    }

    func testParseBigDeflate() {
        // 2000 行、515KB 未压缩：动态 Huffman + 滑窗（stored 路径测不到）。
        let r = parseLibraryFile(data: fixtureData("import-quotas-big"), kind: .quotas, fileName: "x.xlsx")
        XCTAssertEqual(r.errors, [])
        XCTAssertEqual(r.rows.count, 2000)
        XCTAssertEqual(r.rows[0].fields["code"], .text("BIG-0000"))
        XCTAssertEqual(r.rows[1999].fields["code"], .text("BIG-1999"))
        XCTAssertEqual(r.rows[1999].fields["name"], .text("大表定额1999号（重复文本压测滑动窗口与动态 Huffman 编码）"))
    }

    func testParseDateCell() {
        // 日期型单元格进文本列：原生 yyyy-MM-dd（Electron 为 JS Date.toString，有意偏差）。
        let r = parseLibraryFile(data: fixtureData("import-date"), kind: .quotas, fileName: "x.xlsx")
        XCTAssertEqual(r.errors, [])
        XCTAssertEqual(r.rows.count, 1)
        XCTAssertEqual(r.rows[0].fields["alias"], .text("2026-01-15"))
    }

    // MARK: - 工程量导入

    func testQuantitiesV3() throws {
        let r = try parseQuantitiesFile(data: fixtureData("quantities-v3"))
        XCTAssertEqual(r.kind, .v3)
        XCTAssertEqual(r.projects.count, 2)
        XCTAssertEqual(r.projects[0].name, "工程A")
        XCTAssertEqual(r.projects[0].quantities, [
            ImportedQuantity(quota: "TXL3-187", variant: "挂钩法架设架空光缆 平原 6芯", qty: 5, coef: 1),
            ImportedQuantity(quota: "TXL1-008", qty: 2, coef: 1),
        ])
        XCTAssertEqual(r.projects[1].name, "工程B")
        XCTAssertEqual(r.projects[1].quantities, [
            ImportedQuantity(quota: "TXL3-187", variant: "挂钩法架设架空光缆 平原 6芯", qty: 3, coef: 1),
            ImportedQuantity(quota: "TXL1-002", variant: "光(电)缆工程施工测量 架空", qty: 4, coef: 1),
        ])
    }

    func testQuantitiesSimple() throws {
        let r = try parseQuantitiesFile(data: fixtureData("quantities-simple"))
        XCTAssertEqual(r.kind, .simple)
        // 公式数量行（工程B）被丢弃，与 Electron 一致（公式单元格按 JS 对象语义，Number → NaN → 0）。
        XCTAssertEqual(r.projects.map { $0.name }, ["工程A", "工程C"])
        XCTAssertEqual(r.projects[0].quantities.count, 2)
        XCTAssertEqual(r.projects[1].quantities, [
            ImportedQuantity(quota: "TXL1-002", variant: "测量", qty: 2, coef: 1),
        ])
    }

    func testQuantitiesBadFileThrows() {
        XCTAssertThrowsError(try parseQuantitiesFile(data: fixtureData("import-corrupt", ext: "bin")))
    }

    // MARK: - 分类 / 落库

    func testClassifyQuotas() {
        let existing = [
            ImportRow(id: "q0", fields: ["code": .text("T-1"), "name": .text("定额一"), "unit": .text("米"),
                                          "tech": .number(1.5), "labor": .number(2.5), "coef": .number(1),
                                          "book": .text("线路册"), "alias": .text("")]),
            ImportRow(id: "q1", fields: ["code": .text("T-2"), "name": .text("定额二"), "unit": .text("处"),
                                          "tech": .number(0), "labor": .number(3), "coef": .number(0.5),
                                          "book": .text("线路册"), "alias": .text("别名二")]),
        ]
        var updated = existing[0]
        updated.fields["tech"] = .number(2.5)
        let incoming = [
            row(("code", .text("NEW-001")), ("name", .text("新增定额")), ("unit", .text("米")),
                ("tech", .number(1)), ("labor", .number(2)), ("coef", .number(1)),
                ("book", .text("")), ("alias", .text(""))),
            updated,
            existing[1],
            row(("code", .text("")), ("name", .text("缺编号"))),
            row(("code", .text("NEW-001")), ("name", .text("重复主键"))),
        ]
        let cls = classifyImport(kind: .quotas, existing: existing, incoming: incoming)
        XCTAssertEqual(cls.added.count, 1)
        XCTAssertEqual(cls.updated.count, 1)
        XCTAssertEqual(cls.skipped.count, 1)
        XCTAssertEqual(cls.errors.count, 2)
        XCTAssertEqual(cls.updated[0].diffs, [
            ImportFieldDiff(field: "tech", label: "技工/单位", from: .number(1.5), to: .number(2.5)),
        ])
        // 合并：未勾选字段保留旧值。
        let merged = applyImport(kind: .quotas, existing: existing, classification: cls,
                                 decisions: ImportDecisions(mode: .merge, addedKeys: ["NEW-001"],
                                                            updatedChoices: [cls.updated[0].key: ["tech": false]]))
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(merged.first { $0.id == "q0" }?.fields["tech"], .number(1.5))
        XCTAssertNotNil(merged.first { $0.fields["code"] == .text("NEW-001") }?.id)
        // 合并：默认全采用。
        let merged2 = applyImport(kind: .quotas, existing: existing, classification: cls,
                                  decisions: ImportDecisions(mode: .merge))
        XCTAssertEqual(merged2.first { $0.id == "q0" }?.fields["tech"], .number(2.5))
        // 替换：added + updated，保留旧 id，跳过行丢弃。
        let replaced = applyImport(kind: .quotas, existing: existing, classification: cls,
                                   decisions: ImportDecisions(mode: .replace))
        XCTAssertEqual(replaced.count, 2)
        XCTAssertEqual(replaced.first { $0.fields["code"] == .text("T-1") }?.id, "q0")
        XCTAssertFalse(replaced.contains { $0.fields["code"] == .text("T-2") })
        let addedId = replaced.first { $0.fields["code"] == .text("NEW-001") }?.id ?? ""
        XCTAssertFalse(addedId.isEmpty)
    }

    func testClassifyRulesNormalizeDupAndKind() {
        let parsed = parseLibraryFile(data: fixtureData("import-rules"), kind: .rulesVariant, fileName: "x.xlsx")
        let normalized = normalizeImportedRows(kind: .rulesVariant, rows: parsed.rows)
        XCTAssertEqual(normalized.map { $0.fields["kind"] }, [.text("变体"), .text("变体"), .text("备选")])
        let cls = classifyImport(kind: .rulesVariant, existing: [], incoming: parsed.rows)
        XCTAssertEqual(cls.added.count, 1)
        XCTAssertEqual(cls.errors.count, 2)
        XCTAssertEqual(cls.errors[0].errors, ["文件内业务主键重复：TXL3-187 / 光缆 / GYTS-12 / 变体 / 挂钩法架设架空光缆 平原 6芯"])
        XCTAssertEqual(cls.errors[1].errors, ["类型非法取值“备选”"])
    }

    func testClassifyRatesNullValueSkipped() {
        // 原生按注释意图：费率“数值”为空不参与 diff（Electron 代码实际会产生 to=null 的 diff，有意偏差）。
        var profile = ConfigurationProfile()
        profile.rates.byProjectType["通信线路工程"] = NamedRatesRecord(values: ["techPrice": 100])
        profile.rates.winterTable["Ⅲ类地区"] = 0.05
        let existing = existingImportRows(kind: .rates, profile: profile)
        let parsed = parseLibraryFile(data: fixtureData("import-rates"), kind: .rates, fileName: "x.xlsx")
        let cls = classifyImport(kind: .rates, existing: existing, incoming: parsed.rows)
        XCTAssertEqual(cls.updated.count, 1)
        XCTAssertEqual(cls.skipped.count, 1)
        XCTAssertEqual(cls.errors.count, 1)
        XCTAssertEqual(cls.updated[0].diffs, [
            ImportFieldDiff(field: "数值", label: "数值", from: .number(100), to: .number(114)),
        ])
        XCTAssertEqual(cls.errors[0].errors, ["未知费率项目“不存在的费率”"])
    }

    // MARK: - 导出 → 导入往返

    private func assertRoundTrip(kind: ImportLibraryKind, rows: [ImportRow]) {
        let data = exportLibraryWorkbook(kind: kind, rows: rows)
        let parsed = parseLibraryFile(data: data, kind: kind, fileName: "roundtrip.xlsx")
        XCTAssertEqual(parsed.errors, [], "\(kind)")
        XCTAssertEqual(parsed.rows.count, rows.count, "\(kind)")
        let normalized = normalizeImportedRows(kind: kind, rows: parsed.rows)
        for (got, want) in zip(normalized, rows) {
            XCTAssertEqual(got.fields, want.fields, "\(kind)")
            if kind == .rates {
                XCTAssertEqual(got.rateIdentity, want.rateIdentity, "\(kind)")
            }
        }
    }

    func testExportImportRoundTrip() {
        assertRoundTrip(kind: .quotas, rows: [
            row(("code", .text("T-1")), ("name", .text("定额一")), ("unit", .text("米")),
                ("tech", .number(1.5)), ("labor", .number(2.5)), ("coef", .number(1)),
                ("book", .text("线路册")), ("alias", .text(""))),
            row(("code", .text("T-2")), ("name", .text("定额二")), ("unit", .text("处")),
                ("tech", .number(0)), ("labor", .number(3)), ("coef", .null),
                ("book", .text("")), ("alias", .text("别名"))),
        ])
        assertRoundTrip(kind: .shortlist, rows: [
            row(("code", .text("S-1")), ("name", .text("短单")), ("unit", .text("米")), ("coef", .number(0.5))),
        ])
        assertRoundTrip(kind: .materials, rows: [
            row(("name", .text("光缆")), ("spec", .text("GYTS-12")), ("unit", .text("千米")),
                ("priceExcl", .number(1234.56)), ("supply", .text("甲供")), ("remark", .text(""))),
        ])
        assertRoundTrip(kind: .rulesVariant, rows: [
            row(("quota", .text("TXL3-187")), ("material", .text("光缆")), ("spec", .text("GYTS-12")),
                ("unit", .text("千米")), ("consumption", .number(1.02)), ("supply", .text("甲供")),
                ("kind", .text("变体")), ("variant", .text("挂钩法架设架空光缆 平原 6芯")),
                ("remark", .text("")), ("appliesTo", .text("全"))),
        ])
        assertRoundTrip(kind: .rulesAlt, rows: [
            row(("quota", .text("TXL3-187")), ("material", .text("光缆")), ("spec", .text("GYTS-12")),
                ("unit", .text("千米")), ("consumption", .number(1.02)), ("supply", .text("甲供")),
                ("kind", .text("备选")), ("variant", .text("")), ("remark", .text("")), ("appliesTo", .text("全"))),
        ])
        assertRoundTrip(kind: .machinePrices, rows: [
            row(("code", .text("M1")), ("name", .text("空压机")), ("unit", .text("台班")), ("price", .number(5.95))),
        ])
        assertRoundTrip(kind: .instrumentPrices, rows: [
            row(("code", .text("I1")), ("name", .text("OTDR")), ("unit", .text("台班")), ("price", .number(10))),
        ])
        assertRoundTrip(kind: .quotaMachines, rows: [
            row(("quota", .text("TXL1-008")), ("mcode", .text("M1")), ("mname", .text("空压机")),
                ("unit", .text("台班")), ("qty", .number(5.95))),
        ])
        assertRoundTrip(kind: .quotaInstruments, rows: [
            row(("quota", .text("TXL1-008")), ("mcode", .text("I1")), ("mname", .text("OTDR")),
                ("unit", .text("台班")), ("qty", .number(2))),
        ])
        assertRoundTrip(kind: .rates, rows: [
            ImportRow(id: "rate:通信线路工程:techPrice",
                      fields: ["工程类型": .text("通信线路工程"), "费率项目": .text("技工费"),
                               "数值": .number(114), "单位": .text("元/工日")],
                      rateIdentity: RateImportIdentity(section: "byProjectType", type: "通信线路工程", key: "techPrice")),
            ImportRow(id: "rate:winter:Ⅲ类地区",
                      fields: ["工程类型": .text("冬雨季表"), "费率项目": .text("冬雨季施工增加费（Ⅲ类地区）"),
                               "数值": .null, "单位": .text("费率")],
                      rateIdentity: RateImportIdentity(section: "winterTable", type: "Ⅲ类地区", key: "Ⅲ类地区")),
        ])
        assertRoundTrip(kind: .table5Fees, rows: [
            row(("key", .text("safetyFee")), ("name", .text("安全生产费")), ("basis", .text("preDiscountExclTax")),
                ("rate", .number(0.02)), ("vatRate", .number(0)), ("amount", .null),
                ("enabled", .bool(true)), ("order", .number(8)), ("note", .text(""))),
            row(("key", .text("landFee")), ("name", .text("建设用地及综合赔补费")), ("basis", .text("manual")),
                ("rate", .number(0)), ("vatRate", .number(0)), ("amount", .null),
                ("enabled", .bool(false)), ("order", .number(1)), ("note", .text(""))),
        ])
    }

    // MARK: - 写回

    func testWriteBackRulesSlice() {
        var profile = ConfigurationProfile()
        profile.libraries.rules = [
            RuleRow(id: "v1", quota: "Q1", kind: "变体"),
            RuleRow(id: "a1", quota: "Q2", kind: "备选"),
        ]
        let newRows = [ImportRow(id: "v2", fields: ["quota": .text("Q9"), "material": .text("M"),
                                                     "spec": .text(""), "unit": .text(""),
                                                     "consumption": .number(1), "supply": .text("甲供"),
                                                     "kind": .text("通用"), "variant": .text(""),
                                                     "remark": .text(""), "appliesTo": .text("全")])]
        writeImportRows(kind: .rulesVariant, profile: &profile, rows: newRows)
        XCTAssertEqual(profile.libraries.rules.map { $0.id }, ["a1", "v2"])
        XCTAssertEqual(profile.libraries.rules[0].kind, "备选")
    }

    func testWriteBackRates() {
        var profile = ConfigurationProfile()
        profile.rates.byProjectType["通信线路工程"] = NamedRatesRecord(values: ["techPrice": 100])
        profile.rates.winterTable["Ⅲ类地区"] = 0.05
        let rows = [
            ImportRow(fields: ["工程类型": .text("通信线路工程"), "费率项目": .text("技工费"), "数值": .number(114)],
                      rateIdentity: RateImportIdentity(section: "byProjectType", type: "通信线路工程", key: "techPrice")),
            ImportRow(fields: ["工程类型": .text("冬雨季表"), "费率项目": .text("冬雨季施工增加费（Ⅲ类地区）"), "数值": .null],
                      rateIdentity: RateImportIdentity(section: "winterTable", type: "Ⅲ类地区", key: "Ⅲ类地区")),
        ]
        writeImportRows(kind: .rates, profile: &profile, rows: rows)
        XCTAssertEqual(profile.rates.byProjectType["通信线路工程"]?.value(forKey: "techPrice") ?? nil, 114)
        XCTAssertNil(profile.rates.winterTable["Ⅲ类地区"])
    }

    // MARK: - JS 数值语义 / 业务主键

    func testJsNumberFromString() {
        XCTAssertEqual(jsNumberFromString(""), 0)
        XCTAssertEqual(jsNumberFromString("   "), 0)
        XCTAssertEqual(jsNumberFromString("0x10"), 16)
        XCTAssertEqual(jsNumberFromString("1e3"), 1000)
        XCTAssertEqual(jsNumberFromString("Infinity"), .infinity)
        XCTAssertTrue(jsNumberFromString("abc").isNaN)
        XCTAssertEqual(jsNumberFromString("  2.5  "), 2.5)
    }

    func testBusinessKeyDisplay() {
        XCTAssertEqual(businessKeyDisplay(""), "(空)")
        XCTAssertEqual(businessKeyDisplay("TXL3-187\0光缆"), "TXL3-187 / 光缆")
        XCTAssertEqual(businessKey(kind: .quotas, row: row(("code", .text(" T-1 ")))), "T-1")
    }
}
