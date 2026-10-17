import Foundation

/// 保存状态机（对照 Electron `v3.js`：saveStatusInitial / saveStatusTransition / saveStatusText）。
/// saved（已保存/已自动保存）| dirty（● 未保存）| saving（保存中…）。

public enum SaveStatusKind: Equatable {
    case saved
    case dirty
    case saving
}

public struct SaveStatus: Equatable {
    public var status: SaveStatusKind
    public var at: String?
    public var auto: Bool
    public init(status: SaveStatusKind = .saved, at: String? = nil, auto: Bool = false) {
        self.status = status; self.at = at; self.auto = auto
    }

    public static func initial() -> SaveStatus { SaveStatus(status: .saved, at: nil, auto: false) }

    public func transition(_ event: SaveStatusEvent) -> SaveStatus {
        switch event {
        case .edit:
            return SaveStatus(status: .dirty, at: at, auto: false)
        case .saveStart:
            if status == .dirty { return SaveStatus(status: .saving, at: at, auto: false) }
            return self
        case .saveDone:
            return SaveStatus(status: .saved, at: Self.nowHHMM(), auto: false)
        case .autoSaveDone:
            return SaveStatus(status: .saved, at: Self.nowHHMM(), auto: true)
        }
    }

    public var text: String {
        switch status {
        case .dirty: return "● 未保存"
        case .saving: return "保存中…"
        case .saved:
            if let at { return auto ? "已自动保存 \(at)" : "✓ 已保存 \(at)" }
            return "✓ 已保存"
        }
    }

    private static func nowHHMM() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }
}

public enum SaveStatusEvent: Equatable {
    case edit
    case saveStart
    case saveDone
    case autoSaveDone
}
