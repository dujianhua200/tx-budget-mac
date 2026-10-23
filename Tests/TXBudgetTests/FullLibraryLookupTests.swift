import XCTest
@testable import TXBudget

/// v2.5.1 内置完整库查找（docs/v2.5.1-crash-fix.md）：弃用会 assertionFailure
/// 闪退的 SwiftPM `Bundle.module` 访问器，改为显式候选路径 + 限深递归兜底。
/// 这里钉死候选生成的顺序与递归查找的深度语义；实际加载由
/// LibraryCompletionTests.testBundledFullLibraryIntegrity 端到端覆盖。
final class FullLibraryLookupTests: XCTestCase {

    func testCandidateURLsOrderWithResourceURL() {
        let resource = URL(fileURLWithPath: "/tmp/App.app/Contents/Resources", isDirectory: true)
        let bundle = URL(fileURLWithPath: "/tmp/App.app", isDirectory: true)
        let urls = fullLibraryCandidateURLs(resourceURL: resource, bundleURL: bundle)
        XCTAssertEqual(urls.map(\.path), [
            "/tmp/App.app/Contents/Resources/TXBudget_TXBudget.bundle/full-library.json",
            "/tmp/App.app/Contents/Resources/full-library.json",
            "/tmp/App.app/TXBudget_TXBudget.bundle/full-library.json",
        ])
    }

    func testCandidateURLsWithoutResourceURL() {
        let bundle = URL(fileURLWithPath: "/tmp/build/debug", isDirectory: true)
        let urls = fullLibraryCandidateURLs(resourceURL: nil, bundleURL: bundle)
        XCTAssertEqual(urls.map(\.path), [
            "/tmp/build/debug/TXBudget_TXBudget.bundle/full-library.json",
        ])
    }

    func testFindFullLibraryJSONRecursesWithinDepthLimit() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("txbudget-lookup-\(UUID().uuidString)", isDirectory: true)
        let deep = root.appendingPathComponent("a/b/c", isDirectory: true)
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let target = deep.appendingPathComponent("full-library.json")
        try Data("{}".utf8).write(to: target)

        // a/b/c/full-library.json 位于第 3 层：深度上限 4 找得到，上限 2 找不到。
        XCTAssertEqual(findFullLibraryJSON(under: root, maxDepth: 4)?.path, target.path)
        XCTAssertNil(findFullLibraryJSON(under: root, maxDepth: 2))
        XCTAssertNil(findFullLibraryJSON(under: root.appendingPathComponent("missing"),
                                          maxDepth: 4))
    }
}
