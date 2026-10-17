import XCTest
@testable import TXBudget

/// 保存状态机：dirty → saving → saved（✓ 已保存 HH:MM）。
final class SaveStatusTests: XCTestCase {

    func testInitialIsSavedWithoutTime() {
        let s = SaveStatus.initial()
        XCTAssertEqual(s.status, .saved)
        XCTAssertEqual(s.text, "✓ 已保存")
    }

    func testEditMarksDirty() {
        let s = SaveStatus.initial().transition(.edit)
        XCTAssertEqual(s.status, .dirty)
        XCTAssertEqual(s.text, "● 未保存")
    }

    func testSaveStartOnlyFromDirty() {
        XCTAssertEqual(SaveStatus.initial().transition(.saveStart).status, .saved)
        let dirty = SaveStatus.initial().transition(.edit)
        XCTAssertEqual(dirty.transition(.saveStart).status, .saving)
        XCTAssertEqual(dirty.transition(.saveStart).text, "保存中…")
    }

    func testSaveDoneStampsTime() {
        let s = SaveStatus.initial().transition(.edit).transition(.saveStart).transition(.saveDone)
        XCTAssertEqual(s.status, .saved)
        XCTAssertTrue(s.text.hasPrefix("✓ 已保存 "))
        XCTAssertFalse(s.auto)
    }

    func testAutoSaveDoneMarksAuto() {
        let s = SaveStatus.initial().transition(.edit).transition(.autoSaveDone)
        XCTAssertEqual(s.status, .saved)
        XCTAssertTrue(s.text.hasPrefix("已自动保存 "))
        XCTAssertTrue(s.auto)
    }

    func testEditAfterSavedKeepsOldTime() {
        let saved = SaveStatus.initial().transition(.edit).transition(.saveDone)
        let dirty = saved.transition(.edit)
        XCTAssertEqual(dirty.status, .dirty)
        XCTAssertEqual(dirty.at, saved.at)
    }
}
