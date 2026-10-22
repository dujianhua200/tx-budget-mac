import XCTest
@testable import TXBudget

/// ProTable 纯逻辑（Logic/TableData.swift）：过滤 / 稳定排序 / 列合计。
final class TableDataTests: XCTestCase {

    private var rows: [[String: String]] {
        [
            ["id": "a", "code": "TXL3-187", "name": "挂钩法架设架空光缆", "qty": "10"],
            ["id": "b", "code": "TXL1-001", "name": "架设吊线", "qty": "2"],
            ["id": "c", "code": "TXL2-050", "name": "敷设管道光缆", "qty": "30"],
            ["id": "d", "code": "TXL1-002", "name": "架设吊线（复用）", "qty": ""],
        ]
    }

    func testFilterMatchesAnyColumnCaseInsensitive() {
        XCTAssertEqual(tableRowsFiltered(rows, query: "txl1").map { $0["id"] }, ["b", "d"])
        XCTAssertEqual(tableRowsFiltered(rows, query: "光缆").map { $0["id"] }, ["a", "c"])
        XCTAssertEqual(tableRowsFiltered(rows, query: "  吊线 ").map { $0["id"] }, ["b", "d"])
    }

    func testFilterEmptyQueryReturnsAll() {
        XCTAssertEqual(tableRowsFiltered(rows, query: "").count, 4)
        XCTAssertEqual(tableRowsFiltered(rows, query: "   ").count, 4)
    }

    func testFilterDoesNotMatchIdColumn() {
        // id 不参与搜索（避免搜 "a" 命中行 a 的 id 本身）。
        let only = [["id": "zzz", "name": "别的"]]
        XCTAssertTrue(tableRowsFiltered(only, query: "zzz").isEmpty)
    }

    func testSortNumericAscendingPutsEmptyLast() {
        let sorted = tableRowsSorted(rows, sort: TableSort(key: "qty"), numericKeys: ["qty"])
        XCTAssertEqual(sorted.map { $0["id"] }, ["b", "a", "c", "d"])
    }

    func testSortNumericDescending() {
        let sorted = tableRowsSorted(rows, sort: TableSort(key: "qty", ascending: false),
                                     numericKeys: ["qty"])
        XCTAssertEqual(sorted.map { $0["id"] }, ["c", "a", "b", "d"])
    }

    func testSortIsStableForEqualKeys() {
        let dup = [
            ["id": "1", "k": "x"],
            ["id": "2", "k": "x"],
            ["id": "3", "k": "a"],
        ]
        let sorted = tableRowsSorted(dup, sort: TableSort(key: "k"), numericKeys: [])
        XCTAssertEqual(sorted.map { $0["id"] }, ["3", "1", "2"])
    }

    func testSortTextByCode() {
        let sorted = tableRowsSorted(rows, sort: TableSort(key: "code"), numericKeys: [])
        XCTAssertEqual(sorted.map { $0["id"] }, ["b", "d", "c", "a"])
    }

    func testColumnTotalIgnoresJunk() {
        XCTAssertEqual(tableColumnTotal(rows, key: "qty"), 42)
        XCTAssertEqual(tableColumnTotal(rows, key: "missing"), 0)
        let junk = [["id": "1", "v": "abc"], ["id": "2", "v": "1.5"]]
        XCTAssertEqual(tableColumnTotal(junk, key: "v"), 1.5)
    }
}
