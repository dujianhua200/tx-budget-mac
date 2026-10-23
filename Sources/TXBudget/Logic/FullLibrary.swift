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

/// full-library.json 的候选查找路径（有序，纯函数，供单测钉死）。
/// 资源包目录名有两种形态（SwiftPM 版本/平台差异，scripts/bundle.sh 打包时
/// 同样双名兼容）：`TXBudget_TXBudget.bundle` 与 `TXBudget_TXBudget.resources`，
/// 候选对两名全覆盖。基目录依次为：
/// 1. 主包 Resources（打包 .app：资源包副本 + v2.5.1 松散副本）；
/// 2. bundleURL（开发/测试布局下资源包与包根同目录）；
/// 3. bundleURL 上一级（SPM 构建产物布局：资源包与 .xctest 测试包同级；
///    v2.6.0 首跑 CI 在 macOS 上即因只试 .bundle 名 + 缺此基目录而找不到）。
public func fullLibraryCandidateURLs(resourceURL: URL?, bundleURL: URL) -> [URL] {
    let bundleNames = ["TXBudget_TXBudget.bundle", "TXBudget_TXBudget.resources"]
    var urls: [URL] = []
    if let resourceURL {
        for name in bundleNames {
            urls.append(resourceURL
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("full-library.json"))
        }
        urls.append(resourceURL.appendingPathComponent("full-library.json"))
    }
    for base in [bundleURL, bundleURL.deletingLastPathComponent()] {
        for name in bundleNames {
            urls.append(base
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("full-library.json"))
        }
    }
    return urls
}

/// 实际查找序列：候选路径在前（按序试读），其后是兜底限深递归命中的路径
/// （resourceURL 与 bundleURL 之下最深 4 层；bundleURL 上一级最深 2 层——
/// SPM 构建产物布局下资源包与测试包同级，2 层即达包内文件；
/// 源码树根的 .build 最深 5 层，见 buildDirAnchor 说明）。
func fullLibraryLookupURLs() -> [URL] {
    let resourceURL = Bundle.main.resourceURL
    let bundleURL = Bundle.main.bundleURL
    var urls = fullLibraryCandidateURLs(resourceURL: resourceURL, bundleURL: bundleURL)
    var roots: [(url: URL, depth: Int)] = []
    if let resourceURL { roots.append((resourceURL, 4)) }
    roots.append((bundleURL, 4))
    roots.append((bundleURL.deletingLastPathComponent(), 2))
    if let buildDir = sourceTreeBuildDirectory() {
        roots.append((buildDir, 5))
    }
    for (root, depth) in roots {
        if let found = findFullLibraryJSON(under: root, maxDepth: depth) {
            urls.append(found)
        }
    }
    // 去重保序。
    var seen = Set<String>()
    return urls.filter { seen.insert($0.path).inserted }
}

/// 源码树根的 .build 目录（存在才返回）：以本源文件编译时路径（#filePath）
/// 上溯四级（Logic → TXBudget → Sources → 仓库根）定位。用途 = 复刻 SwiftPM
/// 生成访问器的“构建绝对路径”兜底：macOS `swift test` 时 Bundle.main 是
/// xctest 工具自身的包（/Applications/Xcode…/usr/bin），与构建产物无关，
/// 只有源码锚点能找到 .build 下的资源包（v2.6.0 CI 实测定位）。
/// 打包后的 .app 在用户机器上该路径不存在（构建机路径），fileExists 门跳过。
func sourceTreeBuildDirectory() -> URL? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let buildDir = root.appendingPathComponent(".build", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: buildDir.path, isDirectory: &isDirectory),
          isDirectory.boolValue else { return nil }
    return buildDir
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
