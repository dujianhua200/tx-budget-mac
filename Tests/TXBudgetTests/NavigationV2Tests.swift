import XCTest
@testable import TXBudget

/// v2 导航（docs/v2-ui-design.md §2）：标签/图标齐全、requiresProject 划分、底栏提示。
final class NavigationV2Tests: XCTestCase {

    private var allDestinations: [NavDestination] {
        var list: [NavDestination] = [
            .projectList, .overview, .projectInfo, .workload, .fees, .export,
            .profiles, .validation, .batch, .settings,
        ]
        list += LibraryViewKey.allCases.map { NavDestination.libraries($0) }
        list += FeeRuleTab.allCases.map { NavDestination.feeRules($0) }
        return list
    }

    func testAllDestinationsHaveLabelAndIcon() {
        for dest in allDestinations {
            XCTAssertFalse(dest.label.isEmpty, "缺标签：\(dest)")
            XCTAssertFalse(dest.systemImage.isEmpty, "缺图标：\(dest)")
            XCTAssertFalse(statusHintFor(dest).isEmpty, "缺底栏提示：\(dest)")
        }
    }

    func testRequiresProject() {
        for dest in [NavDestination.overview, .projectInfo, .workload, .fees, .export, .validation] {
            XCTAssertTrue(dest.requiresProject, "\(dest) 应需先打开工程")
        }
        for dest in [NavDestination.projectList, .profiles, .batch, .settings,
                     .libraries(.quotas), .feeRules(.rates)] {
            XCTAssertFalse(dest.requiresProject, "\(dest) 不应要求先打开工程")
        }
    }

    func testLibraryAndFeeTabLabels() {
        XCTAssertEqual(LibraryViewKey.quotas.label, "定额库")
        XCTAssertEqual(LibraryViewKey.materials.label, "材料库")
        XCTAssertEqual(FeeRuleTab.rates.label, "费率")
        XCTAssertEqual(FeeRuleTab.discount.label, "打折规则")
        XCTAssertEqual(NavDestination.libraries(.materials).label, "材料库")
        XCTAssertEqual(NavDestination.feeRules(.table5fees).label, "表五费用")
    }
}
