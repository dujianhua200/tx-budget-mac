import Foundation

/// 内置完整库（v2.1.0，见 docs/v2.1-data-completion-design.md §3）：
/// 由 `scripts/convert_full_library.py` 从用户小程序种子数据（scripts/data/quota-data.js 留档）
/// 转换生成的 LibrarySet 八表 JSON，随 App 资源包发布。仅供资料库页“补全定额库”
/// 做并集合并（Logic/LibraryCompletion.swift），不直接参与计算、不覆盖用户任何数据。
/// 资源缺失/损坏时返回 nil，调用方必须明确提示而不是静默失败。
public func loadBundledFullLibrary() -> LibrarySet? {
    guard let url = Bundle.module.url(forResource: "full-library", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let libs = try? JSONDecoder().decode(LibrarySet.self, from: data) else {
        return nil
    }
    return libs
}
