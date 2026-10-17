import XCTest
@testable import TXBudget

/// 导出勾选：解析 / 切换（单张 / 整组），默认全选，存 settings.exportSelection。
final class ExportSelectionTests: XCTestCase {

    func testDefaultIsAllSheets() {
        XCTAssertEqual(defaultExportSelection(), sheetNames)
        XCTAssertEqual(sheetNames.count, 11)
    }

    func testResolveNilDefaultsToAll() {
        var s = SettingsRecord()
        s.exportSelection = nil
        XCTAssertEqual(resolveExportSelection(s), sheetNames)
    }

    func testResolveFiltersUnknownKeepsOrderAndDuplicates() {
        // 只过滤不在 11 张表内的条目；保持原顺序，不去重（与实现一致）。
        var s = SettingsRecord()
        s.exportSelection = ["工程总表(表一)", "不存在的表", "工程总表(表一)", "建设项目总算表(汇总表)"]
        XCTAssertEqual(resolveExportSelection(s), ["工程总表(表一)", "工程总表(表一)", "建设项目总算表(汇总表)"])
    }

    func testToggleSheet() {
        let all = sheetNames
        let removed = toggleExportSelection(all, "工程总表(表一)")
        XCTAssertFalse(removed.contains("工程总表(表一)"))
        XCTAssertEqual(removed.count, all.count - 1)
        let added = toggleExportSelection(removed, "工程总表(表一)")
        XCTAssertEqual(added, all)
    }

    func testToggleGroup() {
        let group = exportGroups.first { $0.label == "费用表（表二）" }!
        let all = sheetNames
        let removed = toggleExportGroup(all, group.sheets)
        XCTAssertTrue(Set(removed).isDisjoint(with: Set(group.sheets)))
        let added = toggleExportGroup(removed, group.sheets)
        XCTAssertEqual(added, all)
    }

    func testBatchExportFileName() {
        XCTAssertEqual(batchExportFileName(for: "信阳联通工程"), "信阳联通工程_概预算.xlsx")
        // 文件名非法字符全部换成 _（与 Electron 一致）。
        XCTAssertEqual(batchExportFileName(for: "A/B:C*D?E\"F<G>H|I\\J"), "A_B_C_D_E_F_G_H_I_J_概预算.xlsx")
        XCTAssertEqual(batchExportFileName(for: ""), "_概预算.xlsx")
    }

    func testResolveEmptyFallsBackToAll() {
        // 空数组按“无有效勾选”处理，回落全选（与 Electron resolve 一致）。
        var s = SettingsRecord()
        s.exportSelection = []
        XCTAssertEqual(resolveExportSelection(s), sheetNames)
    }
}
