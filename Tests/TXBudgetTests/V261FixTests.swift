import XCTest
@testable import TXBudget

/// v2.6.1 回归（docs/v2.6-batch-design.md §11）：基准行变体补齐、短单快照、
/// 零快照修复、计算缓存键。全部用种子真实数据（Fixtures/seed.json）。
final class V261FixTests: XCTestCase {

    private func seedSet() -> LibrarySet {
        LibraryCompletionTests.loadAppSeedLibrarySet()
    }

    private func migratedSeedSet() -> LibrarySet {
        var db = DbFile(configurationProfiles: [ConfigurationProfile(libraries: seedSet())])
        _ = migrateCableMaterialUnits(&db)
        _ = migrateBaselineVariantRules(&db)
        return db.configurationProfiles[0].libraries
    }

    // MARK: - §11.1 基准行变体补齐

    func testBaselineCopyForTXL4011() {
        var set = seedSet()
        let added = repairBaselineVariantRules(in: &set)
        XCTAssertGreaterThan(added, 0)
        let copies = set.rules.filter {
            $0.quota == "TXL4-011" && $0.variant == "敷设管道光缆 12 芯以下"
        }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(copies.first?.material, "光缆")
        XCTAssertEqual(copies.first?.spec, "GYTA_12芯")
        XCTAssertEqual(copies.first?.kind, "变体")
        // 原规则保留（短单 12芯 路径不受影响）。
        XCTAssertTrue(set.rules.contains {
            $0.quota == "TXL4-011" && $0.variant == "敷设管道光缆 12芯" && $0.spec == "GYTA_12芯"
        })
        // 再跑一次为 0（天然幂等）。
        XCTAssertEqual(repairBaselineVariantRules(in: &set), 0)
    }

    func testBaselineCopySkipsNoCoreNameQuotas() {
        var set = seedSet()
        let before = set.rules.count
        _ = repairBaselineVariantRules(in: &set)
        // 无芯数基准名者（槽道光缆、墙壁光缆）不补：本来就必须选型号。
        XCTAssertFalse(set.rules.contains {
            $0.quota == "TXL5-044" && $0.variant == "槽道光缆"
        })
        XCTAssertFalse(set.rules.contains {
            $0.quota == "TXL4-053" && $0.variant == "架设吊线式墙壁光缆"
        })
        XCTAssertGreaterThan(set.rules.count, before)
    }

    func testBaselineCopyPicksLargestCoreAtOrBelowLimit() {
        var set = seedSet()
        _ = repairBaselineVariantRules(in: &set)
        // TXL2-021「36 芯以下」→ ≤36 最大变体 24芯。
        let copies = set.rules.filter {
            $0.quota == "TXL2-021" && $0.variant == "丘陵、水田、城区敷设埋式光缆 36 芯以下"
        }
        XCTAssertEqual(copies.count, 1)
        XCTAssertEqual(copies.first?.spec, "GYTA_24芯")
    }

    func testPanelLinksForTXL4011AfterMigration() {
        let set = migratedSeedSet()
        let project = Project(quantities: [
            QuantityRow(quota: "TXL4-011", variant: "敷设管道光缆 12 芯以下", qty: 10, coef: 1),
            QuantityRow(quota: "TXL4-011", variant: "敷设管道光缆 6芯", qty: 10, coef: 1),
        ])
        let base = effectiveLinks(row: project.quantities[0], project: project, libraries: set)
        let baseCable = base.materials.first { $0.rule.material == "光缆" }
        XCTAssertNotNil(baseCable, "基准行应有关联主材光缆")
        XCTAssertEqual(baseCable?.rule.spec, "GYTA_12芯")
        XCTAssertEqual(baseCable?.totalQty ?? 0, 10150, accuracy: 0.001) // 10 × 1015 m
        XCTAssertEqual(baseCable?.unit, "m")
        XCTAssertFalse(base.instruments.isEmpty, "仪器组应仍在")

        let six = effectiveLinks(row: project.quantities[1], project: project, libraries: set)
        let sixCable = six.materials.first { $0.rule.material == "光缆" }
        XCTAssertEqual(sixCable?.rule.spec, "GYTA_6芯")
        XCTAssertEqual(sixCable?.totalQty ?? 0, 10150, accuracy: 0.001)
    }

    // MARK: - §11.2 短单快照与零快照修复

    func testShortlistSuggestionSnapshotsLaborFromQuota() {
        // 夹具 LibrarySet 不含 shortlist：从种子文件真实解码短单行再拼入。
        struct ShortJSON: Decodable { var code: String; var name: String; var unit: String; var coef: Double? }
        struct ShortFile: Decodable { var shortlist: [ShortJSON] }
        let url = Bundle.module.url(forResource: "seed", withExtension: "json", subdirectory: "Fixtures")!
        let file = try! JSONDecoder().decode(ShortFile.self, from: Data(contentsOf: url))
        var set = seedSet()
        set.shortlist = file.shortlist.map {
            ShortlistRow(code: $0.code, name: $0.name, unit: $0.unit, coef: $0.coef)
        }
        let found = quotaSuggestions(set, "TXL4-011")
        let six = found.first { $0.name == "敷设管道光缆 6芯" }
        XCTAssertNotNil(six)
        XCTAssertEqual(six?.tech ?? 0, 5.5, accuracy: 0.001)
        XCTAssertEqual(six?.labor ?? 0, 10.94, accuracy: 0.001)
        let base = found.first { $0.name == "敷设管道光缆 12 芯以下" }
        XCTAssertEqual(base?.tech ?? 0, 5.5, accuracy: 0.001)
    }

    func testZeroSnapshotRepair() {
        let set = seedSet()
        var rows = [QuantityRow(quota: "TXL4-011", variant: "敷设管道光缆 6芯",
                                qty: 10, coef: 1, tech: 0, labor: 0)]
        XCTAssertEqual(repairBugZeroSnapshots(rows: &rows, libraries: set), 1)
        XCTAssertNil(rows[0].tech)
        XCTAssertNil(rows[0].labor)
        // 回落后显示值 = 库值。
        let quota = firstQuota(code: "TXL4-011", libraries: set)
        XCTAssertEqual(effectiveTech(rows[0], quota), 5.5, accuracy: 0.001)
        XCTAssertEqual(effectiveLabor(rows[0], quota), 10.94, accuracy: 0.001)
        // 用户主动改出的单项 0 不动（仅双 0 才修）。
        var rows2 = [QuantityRow(quota: "TXL4-011", variant: "敷设管道光缆 6芯",
                                 qty: 10, coef: 1, tech: 0, labor: 10.94)]
        XCTAssertEqual(repairBugZeroSnapshots(rows: &rows2, libraries: set), 0)
    }

    // MARK: - §11.3 计算缓存键

    func testCalcCacheKeyChangesOnAnyDimension() {
        let base = calcCacheKey(generation: 1, saveVersion: 7, projectId: "p1", updatedAt: "t1")
        XCTAssertNotEqual(base, calcCacheKey(generation: 2, saveVersion: 7, projectId: "p1", updatedAt: "t1"))
        XCTAssertNotEqual(base, calcCacheKey(generation: 1, saveVersion: 8, projectId: "p1", updatedAt: "t1"))
        XCTAssertNotEqual(base, calcCacheKey(generation: 1, saveVersion: 7, projectId: "p2", updatedAt: "t1"))
        XCTAssertNotEqual(base, calcCacheKey(generation: 1, saveVersion: 7, projectId: "p1", updatedAt: "t2"))
        XCTAssertEqual(base, calcCacheKey(generation: 1, saveVersion: 7, projectId: "p1", updatedAt: "t1"))
    }
}
