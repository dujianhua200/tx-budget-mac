import Foundation

/// 内置完整库（v2.2.0，见 docs/v2.2-correction-design.md §4）：
/// 由 `scripts/build_corrected_library.py` 以 v2.1.0 内置库为底、按官方《通信451定额
/// 电子手册》v2022.12.716（scripts/data/official-library.json）校正重建的 LibrarySet
/// 八表 JSON（价格沿用 v2.1 来源不变），随 App 资源包发布。仅供资料库页“补全并校正
/// 定额库”合并使用（Logic/LibraryCompletion.swift），不直接参与计算、不覆盖用户数据。
/// 资源缺失/损坏时返回 nil，调用方必须明确提示而不是静默失败。
public func loadBundledFullLibrary() -> LibrarySet? {
    guard let url = Bundle.module.url(forResource: "full-library", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let libs = try? JSONDecoder().decode(LibrarySet.self, from: data) else {
        return nil
    }
    return libs
}
