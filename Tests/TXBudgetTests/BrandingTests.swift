import XCTest
@testable import TXBudget

/// 品牌 / 图标测试（v1.0.2 改名 + 图标，见设计文档 §10.7）。
/// 仓库文件（Assets/、scripts/bundle.sh）用 #file 定位仓库根目录，不依赖 swift test 的 cwd。
final class BrandingTests: XCTestCase {
    func testDisplayName() {
        XCTAssertEqual(appDisplayName, "滑洲智算")
    }

    func testBundleIdentifierUnchanged() {
        // 改名不改 Bundle ID / 数据目录（零迁移，用户现有数据不丢）。
        XCTAssertEqual(appBundleIdentifier, "com.zhang.txbudget")
        XCTAssertEqual(DatabaseStore.appSupportDirName, "通信概预算")
    }

    func testWorkbookDefaultCreator() {
        XCTAssertEqual(XlsxWorkbook().creator, "滑洲智算")
    }

    /// 仓库根目录：Tests/TXBudgetTests/<本文件> → 上三级（文件 → TXBudgetTests → Tests → 仓库根）。
    private var repoRoot: URL {
        URL(fileURLWithPath: #file)
            .deletingLastPathComponent() // BrandingTests.swift → TXBudgetTests
            .deletingLastPathComponent() // → Tests
            .deletingLastPathComponent() // → 仓库根
    }

    func testIconsetExists() throws {
        let iconset = repoRoot.appendingPathComponent("Assets/AppIcon.iconset")
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: iconset.path), "缺少 Assets/AppIcon.iconset")
        // 标准 10 件 PNG + Contents.json。
        let expected = [
            "icon_16x16.png", "icon_16x16@2x.png",
            "icon_32x32.png", "icon_32x32@2x.png",
            "icon_128x128.png", "icon_128x128@2x.png",
            "icon_256x256.png", "icon_256x256@2x.png",
            "icon_512x512.png", "icon_512x512@2x.png",
        ]
        for name in expected {
            let url = iconset.appendingPathComponent(name)
            XCTAssertTrue(fm.fileExists(atPath: url.path), "缺图标 \(name)")
            let data = try Data(contentsOf: url)
            XCTAssertFalse(data.isEmpty, "图标为空 \(name)")
            // PNG 魔数 89 50 4E 47 0D 0A 1A 0A。
            XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "非 PNG：\(name)")
        }
        // Contents.json 声明的文件与实际一致。
        let contentsData = try Data(contentsOf: iconset.appendingPathComponent("Contents.json"))
        let json = try JSONSerialization.jsonObject(with: contentsData) as? [String: Any]
        let images = json?["images"] as? [[String: Any]] ?? []
        XCTAssertEqual(images.count, 10)
        let declared = Set(images.compactMap { $0["filename"] as? String })
        XCTAssertEqual(declared, Set(expected))
        // 母图存在。
        XCTAssertTrue(fm.fileExists(atPath: repoRoot.appendingPathComponent("Assets/huazhou-zhisuan-icon-master.webp").path))
    }

    func testBundleScriptWiresIconAndNewName() throws {
        let script = try String(contentsOf: repoRoot.appendingPathComponent("scripts/bundle.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("iconutil -c icns"), "bundle.sh 未调 iconutil")
        XCTAssertTrue(script.contains("CFBundleIconFile"), "bundle.sh 的 Info.plist 缺 CFBundleIconFile")
        XCTAssertTrue(script.contains("AppIcon.icns"), "bundle.sh 的 Info.plist 图标文件名不对")
        XCTAssertTrue(script.contains("滑洲智算.app"), "bundle.sh 未改 .app 名")
        XCTAssertTrue(script.contains("huazhou-zhisuan-${VERSION}-mac-arm64.dmg"), "bundle.sh 未改 DMG 文件名为拼音名")
        XCTAssertTrue(script.contains("-volname \"滑洲智算\""), "bundle.sh 改了 DMG 卷名（卷名保持中文）")
        XCTAssertTrue(script.contains("<string>滑洲智算</string>"), "bundle.sh 改了 CFBundleName（保持中文）")
        XCTAssertTrue(script.contains("com.zhang.txbudget"), "bundle.sh 改了 Bundle ID（不许改）")
        XCTAssertFalse(script.contains("通信概预算.app"), "bundle.sh 仍有旧 .app 名")
    }
}
