import Foundation

/// 库表列定义（对照 Electron `libraryDefs.js` 的 columns：text | number | select | checkbox）。
/// public：LibraryRowCodec（Logic 层）的公开 API 以它为入参/返回值。
/// 注意：本类型属 Logic 层（不依赖 SwiftUI），Views 只消费；不得移回 Views（曾误放在
/// Views/LibrariesView.swift 的 `#if os(macOS)` 守卫内，导致 Logic 依赖 macOS 专属文件，
/// Linux 下全量测试编不过）。
public enum LibraryColumnKind: Equatable {
    case text
    case number
    case select
    case checkbox
}

public struct LibraryColumn: Equatable {
    public var key: String
    public var label: String
    public var kind: LibraryColumnKind
    public var options: [String] = []
    public init(key: String, label: String, kind: LibraryColumnKind, options: [String] = []) {
        self.key = key; self.label = label; self.kind = kind; self.options = options
    }
}
