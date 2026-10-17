import XCTest
@testable import TXBudget

final class PlaceholderTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(TXBudget.version, "1.0.1")
    }
}
