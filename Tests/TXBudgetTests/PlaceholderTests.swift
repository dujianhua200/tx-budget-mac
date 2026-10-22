import XCTest
@testable import TXBudget

final class PlaceholderTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(TXBudget.version, "2.3.0")
    }
}
