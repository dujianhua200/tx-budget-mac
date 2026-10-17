import Foundation
@testable import TXBudget

/// 测试用夹具解码器：reference-book.json（JS 引擎输出格式）→ Swift 引擎模型；
/// reference-layout.json（参考结算书版式）→ 比对用结构。
/// 注意：fixture 的 discountRule 无 zeroAfterDiscountKeys，解码时用引擎默认 11 项；
/// table3A 空值 null → 0（导出时 exportMoney(0) → 空，与 JS 一致）。

private func jnum(_ v: Any?) -> Double {
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String, let d = Double(s) { return d }
    return 0
}

private func jnumOpt(_ v: Any?) -> Double? {
    if v == nil || v is NSNull { return nil }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) }
    return nil
}

private func jstr(_ v: Any?, default d: String = "") -> String {
    if let s = v as? String { return s }
    return d
}

private func jdict(_ v: Any?) -> [String: Any] { v as? [String: Any] ?? [:] }
private func jarr(_ v: Any?) -> [Any] { v as? [Any] ?? [] }

enum ReferenceBookFixture {
    static func fixtureURL(name: String) -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            fatalError("fixture 缺失：\(name).json")
        }
        return url
    }

    static func jsonObject(name: String) -> [String: Any] {
        let data = try! Data(contentsOf: fixtureURL(name: name))  // swiftlint:disable:this force_try
        return (try! JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]  // swiftlint:disable:this force_try
    }

    // MARK: - 版式 fixture

    struct RefLayoutSheet {
        var columnCount: Int
        var rowCount: Int
        var widths: [Double]
        var heights: [Double]
        var merges: [String]
        var margins: [String: Double]
        var orientation: String
        var paperSize: Int
        var fitToPage: Bool
        var scale: Double
        var titleFontName: String
        var titleFontSize: Double
        var titleFontBold: Bool
    }

    struct RefLayout {
        var sheetOrder: [String]
        var sheets: [String: RefLayoutSheet]
    }

    static func loadLayout() -> RefLayout {
        let root = jsonObject(name: "reference-layout")
        let order = (root["sheetOrder"] as? [String]) ?? []
        var sheets: [String: RefLayoutSheet] = [:]
        for (name, v) in jdict(root["sheets"]) {
            let d = jdict(v)
            let tf = jdict(d["titleFont"])
            var margins: [String: Double] = [:]
            for (k, mv) in jdict(d["margins"]) { margins[k] = jnum(mv) }
            sheets[name] = RefLayoutSheet(
                columnCount: Int(jnum(d["columnCount"])),
                rowCount: Int(jnum(d["rowCount"])),
                widths: jarr(d["widths"]).map(jnum),
                heights: jarr(d["heights"]).map(jnum),
                merges: (d["merges"] as? [String]) ?? [],
                margins: margins,
                orientation: jstr(d["orientation"]),
                paperSize: Int(jnum(d["paperSize"])),
                fitToPage: (d["fitToPage"] as? Bool) ?? false,
                scale: jnum(d["scale"]),
                titleFontName: jstr(tf["name"]),
                titleFontSize: jnum(tf["size"]),
                titleFontBold: (tf["bold"] as? Bool) ?? false)
        }
        return RefLayout(sheetOrder: order, sheets: sheets)
    }

    // MARK: - 结算书 fixture → 引擎模型

    struct Book {
        var projectName: String
        var project: Project
        var result: CalcResult
    }

    static func decodeInfo(_ d: [String: Any]) -> ProjectInfo {
        var info = ProjectInfo()
        info.建设单位 = jstr(d["建设单位"])
        info.建设项目名称 = jstr(d["建设项目名称"])
        info.单项工程名称 = jstr(d["单项工程名称"])
        info.工程类型 = jstr(d["工程类型"], default: "通信线路工程")
        info.表格编号 = jstr(d["表格编号"], default: "YD-")
        info.项目编号 = jstr(d["项目编号"])
        info.编制日期 = jstr(d["编制日期"])
        info.施工距离 = jstr(d["施工距离"], default: "35KM以内")
        info.施工实际里程 = jnumOpt(d["施工实际里程"])
        info.冬雨季施工费 = jstr(d["冬雨季施工费"], default: "Ⅲ类地区")
        info.施工折扣 = jnumOpt(d["施工折扣"])
        info.甲供增值税 = jnumOpt(d["甲供增值税"])
        info.乙供增值税 = jnumOpt(d["乙供增值税"])
        info.工程负责人 = jstr(d["工程负责人"])
        info.审核 = jstr(d["审核"])
        info.编制 = jstr(d["编制"])
        info.施工单位 = d["施工单位"] as? String
        info.设计单位 = d["设计单位"] as? String
        info.监理单位 = jstr(d["监理单位"])
        return info
    }

    static func decodeRates(_ d: [String: Any]) -> ResolvedRates {
        var r = ResolvedRates()
        r.techPrice = jnum(d["techPrice"])
        r.laborPrice = jnum(d["laborPrice"])
        r.auxRate = jnum(d["auxRate"])
        r.envRate = jnum(d["envRate"])
        r.civilRate = jnum(d["civilRate"])
        r.carryRate = jnum(d["carryRate"])
        r.disturbRate = jnum(d["disturbRate"])
        r.handoverRate = jnum(d["handoverRate"])
        r.tempNearRate = jnum(d["tempNearRate"])
        r.tempFarRate = jnum(d["tempFarRate"])
        r.vehicleRate = jnum(d["vehicleRate"])
        r.nightRate = jnum(d["nightRate"])
        r.winterRate = jnum(d["winterRate"])
        r.toolRate = jnum(d["toolRate"])
        r.utilityRate = jnum(d["utilityRate"])
        r.protectRate = jnum(d["protectRate"])
        r.socialRate = jnum(d["socialRate"])
        r.housingRate = jnum(d["housingRate"])
        r.accidentRate = jnum(d["accidentRate"])
        r.mgmtRate = jnum(d["mgmtRate"])
        r.profitRate = jnum(d["profitRate"])
        r.jiaTax = jnum(d["jiaTax"])
        r.yiTax = jnum(d["yiTax"])
        r.outputTax = jnum(d["outputTax"])
        r.taxRate = jnum(d["taxRate"])
        return r
    }

    static func decodeTable2(_ d: [String: Any]) -> Table2 {
        var values: [String: Double] = [:]
        for (k, v) in d { if let n = v as? NSNumber { values[k] = n.doubleValue } }
        return Table2(values: values)
    }

    static func loadBook() -> Book {
        let root = jsonObject(name: "reference-book")
        let p = jdict(root["project"])
        let r = jdict(root["result"])
        let projectName = jstr(p["name"])
        var quantities: [QuantityRow] = []
        for q in jarr(p["quantities"]) {
            let qd = jdict(q)
            quantities.append(QuantityRow(
                id: qd["id"] as? String,
                quota: jstr(qd["quota"]),
                variant: qd["variant"] as? String,
                unit: qd["unit"] as? String,
                qty: jnumOpt(qd["qty"]),
                coef: jnumOpt(qd["coef"])))
        }
        let project = Project(info: decodeInfo(jdict(p["info"])), quantities: quantities)

        var table3A: [Table3ARow] = []
        for row in jarr(r["table3A"]) {
            let d = jdict(row)
            table3A.append(Table3ARow(
                code: jstr(d["code"]), name: jstr(d["name"]), unit: jstr(d["unit"]),
                qty: jnum(d["qty"]), techUnit: jnum(d["techUnit"]), laborUnit: jnum(d["laborUnit"]),
                tech: jnum(d["tech"]), labor: jnum(d["labor"])))
        }
        func decodeEquip(_ v: Any?) -> Table3EquipResult {
            let d = jdict(v)
            var rows: [Table3EquipRow] = []
            for row in jarr(d["rows"]) {
                let rd = jdict(row)
                rows.append(Table3EquipRow(
                    quota: jstr(rd["quota"]), quotaName: jstr(rd["quotaName"]), unit: jstr(rd["unit"]),
                    qty: jnum(rd["qty"]), equipName: jstr(rd["equipName"]), equipUnit: jstr(rd["equipUnit"]),
                    consumption: jnum(rd["consumption"]), price: jnum(rd["price"]),
                    sessions: jnum(rd["sessions"]), amount: jnum(rd["amount"])))
            }
            return Table3EquipResult(rows: rows, total: jnum(d["total"]))
        }
        func decodeTable4(_ v: Any?) -> Table4Result {
            let d = jdict(v)
            var rows: [Table4Row] = []
            for row in jarr(d["rows"]) {
                let rd = jdict(row)
                let qty = jnum(rd["qty"])
                rows.append(Table4Row(
                    key: jstr(rd["key"]), name: jstr(rd["name"]), spec: jstr(rd["spec"]),
                    unit: jstr(rd["unit"]), qty: qty, autoQty: qty, delta: 0,
                    priceExcl: jnum(rd["priceExcl"]), priceVat: jnum(rd["priceVat"]),
                    priceIncl: jnum(rd["priceIncl"]), amtExcl: jnum(rd["amtExcl"]),
                    amtVat: jnum(rd["amtVat"]), amtIncl: jnum(rd["amtIncl"]),
                    unmatched: (rd["unmatched"] as? Bool) ?? false))
            }
            return Table4Result(rows: rows, totalExcl: jnum(d["totalExcl"]),
                                totalVat: jnum(d["totalVat"]), totalIncl: jnum(d["totalIncl"]))
        }
        let t5 = jdict(r["table5"])
        var table5Rows: [Table5Row] = []
        for row in jarr(t5["rows"]) {
            let d = jdict(row)
            table5Rows.append(Table5Row(
                key: jstr(d["key"]), name: jstr(d["name"]), basis: jstr(d["basis"]),
                rate: jnumOpt(d["rate"]), vatRate: jnum(d["vatRate"]), order: jnum(d["order"]),
                note: jstr(d["note"]), enabled: (d["enabled"] as? Bool) ?? true,
                excl: jnum(d["excl"]), vat: jnum(d["vat"]), incl: jnum(d["incl"]),
                amount: jnum(d["amount"])))
        }
        let table5 = Table5Result(
            rows: table5Rows, totalExcl: jnum(t5["totalExcl"]), totalVat: jnum(t5["totalVat"]),
            totalIncl: jnum(t5["totalIncl"]), mgmt2: jnum(t5["mgmt2"]), mgmt2Vat: jnum(t5["mgmt2Vat"]),
            mgmt2Incl: jnum(t5["mgmt2Incl"]), surveyKm: jnum(t5["surveyKm"]),
            surveyFee: jnum(t5["surveyFee"]), surveyVat: jnum(t5["surveyVat"]),
            designFee: jnum(t5["designFee"]), designVat: jnum(t5["designVat"]),
            designTotal: jnum(t5["designTotal"]), designTotalVat: jnum(t5["designTotalVat"]),
            safetyFee: jnum(t5["safetyFee"]), safetyVat: jnum(t5["safetyVat"]),
            safetyIncl: jnum(t5["safetyIncl"]),
            productionPrepFee: jnum(t5["productionPrepFee"]),
            productionPrepVat: jnum(t5["productionPrepVat"]),
            productionPrepIncl: jnum(t5["productionPrepIncl"]))
        let t1 = jdict(r["table1"])
        let table1 = Table1Result(
            beforeDiscount: jnum(t1["beforeDiscount"]), afterDiscount: jnum(t1["afterDiscount"]),
            taxBefore: jnum(t1["taxBefore"]), taxAfter: jnum(t1["taxAfter"]),
            totalBefore: jnum(t1["totalBefore"]), totalAfter: jnum(t1["totalAfter"]),
            otherFee: jnum(t1["otherFee"]), otherVat: jnum(t1["otherVat"]),
            otherIncl: jnum(t1["otherIncl"]), sumExcl: jnum(t1["sumExcl"]), sumVat: jnum(t1["sumVat"]),
            sumIncl: jnum(t1["sumIncl"]), equipFee: jnum(t1["equipFee"]), equipVat: jnum(t1["equipVat"]),
            equipIncl: jnum(t1["equipIncl"]), grandExcl: jnum(t1["grandExcl"]),
            grandVat: jnum(t1["grandVat"]), grandIncl: jnum(t1["grandIncl"]))
        let dr = jdict(r["discountRule"])
        let discountRule = EffectiveDiscountRule(
            discountRate: jnumOpt(dr["discountRate"]) ?? jnum(r["discount"]),
            noDiscountKeys: (dr["noDiscountKeys"] as? [String]) ?? defaultNoDiscountKeys,
            zeroAfterDiscountKeys: (dr["zeroAfterDiscountKeys"] as? [String]) ?? defaultZeroAfterDiscountKeys)
        let result = CalcResult(
            info: decodeInfo(jdict(r["info"])),
            rate: decodeRates(jdict(r["rate"])),
            techSub: jnum(r["techSub"]), laborSub: jnum(r["laborSub"]), adjRate: jnum(r["adjRate"]),
            techDays: jnum(r["techDays"]), laborDays: jnum(r["laborDays"]),
            table3A: table3A,
            table3B: decodeEquip(r["table3B"]), table3C: decodeEquip(r["table3C"]),
            table4A: decodeTable4(r["table4A"]), table4B: decodeTable4(r["table4B"]),
            table4Equip: decodeTable4(r["table4Equip"]),
            table2Before: decodeTable2(jdict(r["table2Before"])),
            table2After: decodeTable2(jdict(r["table2After"])),
            table5: table5, table1: table1,
            summary: SummaryResult(), warnings: [],
            discount: jnum(r["discount"]), discountRule: discountRule,
            surveyKm: jnum(r["surveyKm"]), surveyRaw: jnum(r["surveyRaw"]))
        return Book(projectName: projectName, project: project, result: result)
    }
}
