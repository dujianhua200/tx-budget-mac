import Foundation

/// 内置完整库（v2.2.0，见 docs/v2.2-correction-design.md §4）：
/// 由 `scripts/build_corrected_library.py` 以 v2.1.0 内置库为底、按官方《通信451定额
/// 电子手册》v2022.12.716（scripts/data/official-library.json）校正重建的 LibrarySet
/// 八表 JSON（价格沿用 v2.1 来源不变），随 App 资源发布。仅供资料库页“补全并校正
/// 定额库”合并使用（Logic/LibraryCompletion.swift），不直接参与计算、不覆盖用户数据。
/// 资源缺失/损坏时返回 nil，调用方必须明确提示而不是静默失败。
///
/// v2.5.1（见 docs/v2.5.1-crash-fix.md）：**禁用 SwiftPM 的 `Bundle.module` 访问器**。
/// 该访问器在打包后的 .app 布局下找不到资源包时不是返回 nil，而是直接
/// assertionFailure 闪退（v2.5.0 真机崩溃根因）。这里改为显式候选路径 + 限深递归
/// 兜底的纯 FileManager/Data 查找，任何情况下都不 trap。
public func loadBundledFullLibrary() -> LibrarySet? {
    for url in fullLibraryLookupURLs() {
        guard let data = try? Data(contentsOf: url),
              let libs = try? JSONDecoder().decode(LibrarySet.self, from: data) else {
            continue
        }
        return libs
    }
    return nil
}

/// full-library.json 的候选查找路径（有序，纯函数，供单测钉死）：
/// 1. 主包 Resources 内的 SwiftPM 资源包副本；
/// 2. 主包 Resources 根下的松散副本（v2.5.1 起 bundle.sh 双保险落盘）；
/// 3. bundleURL 同级的资源包（开发/测试布局下资源包与包根同目录）。
public func fullLibraryCandidateURLs(resourceURL: URL?, bundleURL: URL) -> [URL] {
    var urls: [URL] = []
    if let resourceURL {
        urls.append(resourceURL
            .appendingPathComponent("TXBudget_TXBudget.bundle", isDirectory: true)
            .appendingPathComponent("full-library.json"))
        urls.append(resourceURL.appendingPathComponent("full-library.json"))
    }
    urls.append(bundleURL
        .appendingPathComponent("TXBudget_TXBudget.bundle", isDirectory: true)
        .appendingPathComponent("full-library.json"))
    return urls
}

/// 实际查找序列：候选路径在前（按序试读），其后是兜底限深递归命中的路径
/// （resourceURL 与 bundleURL 之下，最深 4 层，找任意 full-library.json）。
func fullLibraryLookupURLs() -> [URL] {
    let resourceURL = Bundle.main.resourceURL
    let bundleURL = Bundle.main.bundleURL
    var urls = fullLibraryCandidateURLs(resourceURL: resourceURL, bundleURL: bundleURL)
    var roots: [URL] = []
    if let resourceURL { roots.append(resourceURL) }
    roots.append(bundleURL)
    for root in roots {
        if let found = findFullLibraryJSON(under: root, maxDepth: 4) {
            urls.append(found)
        }
    }
    // 去重保序。
    var seen = Set<String>()
    return urls.filter { seen.insert($0.path).inserted }
}

/// 在目录下限深（maxDepth 层）广度优先找 full-library.json；找不到返回 nil，永不 trap。
func findFullLibraryJSON(under root: URL, maxDepth: Int) -> URL? {
    let fm = FileManager.default
    var queue: [(url: URL, depth: Int)] = [(root, 0)]
    var index = 0
    while index < queue.count {
        let (dir, depth) = queue[index]
        index += 1
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            continue
        }
        for entry in entries where entry.lastPathComponent == "full-library.json" {
            return entry
        }
        guard depth < maxDepth else { continue }
        for entry in entries {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: entry.path, isDirectory: &isDirectory), isDirectory.boolValue {
                queue.append((entry, depth + 1))
            }
        }
    }
    return nil
}
