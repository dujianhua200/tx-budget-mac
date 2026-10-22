#if os(macOS)
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 共享小组件：数字输入框、文件面板、确认框。

/// 数字输入框（字符串中转，支持空值与非法输入不崩溃）。
struct DoubleField: View {
    var label: String
    @Binding var value: Double
    var prompt: String = ""

    @State private var text: String = ""
    @State private var initialized = false

    var body: some View {
        TextField(label, text: $text, prompt: Text(prompt))
            .onAppear {
                if !initialized { text = jsNumberString(value); initialized = true }
            }
            .onChange(of: text) { newValue in
                if let v = Double(newValue.trimmingCharacters(in: .whitespaces)) {
                    value = v
                }
            }
            .onChange(of: value) { newValue in
                // 外部变化时同步（避免循环：仅当文本与新值不一致时写回）。
                if Double(text) != newValue { text = jsNumberString(newValue) }
            }
    }
}

/// 可空数字输入框（空 = nil，如 winterRate 的 null = 按地区查表）。
struct OptionalDoubleField: View {
    var label: String
    @Binding var value: Double?
    var prompt: String = ""

    @State private var text: String = ""
    @State private var initialized = false

    var body: some View {
        TextField(label, text: $text, prompt: Text(prompt))
            .onAppear {
                if !initialized { text = value.map { jsNumberString($0) } ?? ""; initialized = true }
            }
            .onChange(of: text) { newValue in
                let t = newValue.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { value = nil } else if let v = Double(t) { value = v }
            }
    }
}

/// 金额文本（千分位 + 2 位小数）。
struct MoneyText: View {
    var value: Double?
    var bold: Bool = false
    var body: some View {
        Text(money(value)).fontWeight(bold ? .bold : .regular)
    }
}

struct Num2Text: View {
    var value: Double?
    var body: some View { Text(num2(value)) }
}

/// 文件面板（AppKit，macOS 原生对话框）。
enum FilePanel {
    @MainActor
    static func openFile(allowedTypes: [String], message: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedTypes.compactMap { UTType(filenameExtension: $0) }
        if let message { panel.message = message }
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func openDirectory(message: String? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let message { panel.message = message }
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    static func saveFile(defaultName: String, allowedTypes: [String]) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = allowedTypes.compactMap { UTType(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// 带序号的行包装：供 Table 在无唯一 id 的行（如表三乙/丙多行同一定额编号）时使用。
struct IndexedRow<T>: Identifiable {
    var id: Int
    var row: T
}

func indexed<T>(_ rows: [T]) -> [IndexedRow<T>] {
    rows.enumerated().map { IndexedRow(id: $0.offset, row: $0.element) }
}

/// 资料库 / 取费规则共用的“当前方案”选择器横幅（v2.0.1）。
/// 原设计把 editingProfileId 做成隐藏的全局模式（配置方案页一个无法消除的
/// “正在编辑”徽标），用户无从理解；v2.0.1 改为编辑现场可见、可直接切换的
/// 下拉选择器：选哪套，资料库与取费规则就编辑哪套。
struct ProfilePickerBanner: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.circle.fill").foregroundColor(Theme.accent)
            Text("当前方案：")
                .font(.callout).foregroundColor(.secondary)
            Picker("当前方案", selection: editingProfileBinding) {
                ForEach(appState.db.configurationProfiles, id: \.id) { p in
                    Text(p.name).tag(p.id)
                }
            }
            .labelsHidden()
            .frame(width: 200)
            Text("（资料库与取费规则编辑的就是该方案；“新建默认”只影响新建工程）")
                .font(.caption).foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.accent.opacity(0.07))
        .cornerRadius(8)
    }

    private var editingProfileBinding: Binding<String> {
        Binding(
            get: { appState.db.settings.editingProfileId ?? appState.db.settings.activeProfileId },
            set: { appState.setEditingProfile($0) }
        )
    }
}

/// 简单确认框（标题 + 影响说明 + 确认/取消）。
struct ConfirmBox: View {
    var title: String
    var impact: String
    var confirmLabel: String
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(impact).font(.body).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button(confirmLabel, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .padding()
        .frame(minWidth: 420)
    }
}
#endif
