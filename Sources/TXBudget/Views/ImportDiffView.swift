#if os(macOS)
import SwiftUI

/// 库 Excel 导入/导出共享组件（镜像 Electron `ImportDiffPreview.jsx` + `Settings.jsx` 接线）。
/// 解析 → 差异预览 sheet（新增/更新/跳过/错误四组 + 合并/替换 + 替换输方案名确认 +
/// 错误知晓勾选）→ 确认落库。任何导入都不在无预览、无确认的情况下覆盖现有数据。

private struct ImportPreviewState: Identifiable {
    var id = UUID()
    var classification: ImportClassification
    var parseErrors: [String]
    var rowsBefore: [ImportRow]
}

/// 落库 + 提示（LibrariesView / FeeRulesView 共用）。
func applyLibraryImport(appState: AppState, kind: ImportLibraryKind,
                        classification: ImportClassification, decisions: ImportDecisions,
                        rowsBefore: [ImportRow]) {
    var resultCount = 0
    var profileName = ""
    appState.updateDb({ d in
        guard let pIdx = editingProfileIndexForImport(d) else { return }
        let result = applyImport(kind: kind, existing: rowsBefore,
                                 classification: classification, decisions: decisions)
        writeImportRows(kind: kind, profile: &d.configurationProfiles[pIdx], rows: result)
        d.configurationProfiles[pIdx].updatedAt = nowISO()
        resultCount = result.count
        profileName = d.configurationProfiles[pIdx].name
    }, major: decisions.mode == .replace)
    if kind == .rates {
        appState.showToast("导入完成：\(kind.label)更新 \(classification.updated.count) 条（方案“\(profileName)”）。")
    } else {
        appState.showToast("导入完成：\(kind.label)现 \(resultCount) 条（方案“\(profileName)”）。")
    }
}

private func editingProfileIndexForImport(_ d: DbFile) -> Int? {
    if let id = d.settings.editingProfileId, let i = d.configurationProfiles.firstIndex(where: { $0.id == id }) {
        return i
    }
    if let i = d.configurationProfiles.firstIndex(where: { $0.id == d.settings.activeProfileId }) {
        return i
    }
    return d.configurationProfiles.indices.first
}

struct ExcelImportExportButtons: View {
    var kind: ImportLibraryKind
    var profileName: String
    var allowReplace: Bool = true
    var existingRows: () -> [ImportRow]
    var onConfirmImport: (ImportClassification, ImportDecisions, [ImportRow]) -> Void
    var exportRows: () -> [ImportRow]
    var onExported: (URL) -> Void

    @State private var preview: ImportPreviewState?
    @State private var alertText: String?

    var body: some View {
        HStack(spacing: 8) {
            Button("导入 Excel…") { startImport() }
            Button("导出 Excel…") { startExport() }
        }
        .controlSize(.small)
        .sheet(item: $preview) { state in
            ImportDiffSheet(
                kindLabel: kind.label,
                profileName: profileName,
                classification: state.classification,
                parseErrors: state.parseErrors,
                allowReplace: allowReplace,
                onConfirm: { decisions in
                    onConfirmImport(state.classification, decisions, state.rowsBefore)
                    preview = nil
                },
                onCancel: { preview = nil }
            )
        }
        .alert("导入/导出", isPresented: Binding(
            get: { alertText != nil },
            set: { if !$0 { alertText = nil } }
        )) {
            Button("知道了") { alertText = nil }
        } message: {
            Text(alertText ?? "")
        }
    }

    private func startImport() {
        guard let url = FilePanel.openFile(allowedTypes: ["xlsx"], message: "选择要导入的 Excel 文件") else { return }
        guard let data = try? Data(contentsOf: url) else {
            alertText = "文件读不出来：\(url.lastPathComponent)"
            return
        }
        let parsed = parseLibraryFile(data: data, kind: kind, fileName: url.lastPathComponent)
        if parsed.rows.isEmpty, !parsed.errors.isEmpty {
            alertText = "导入解析失败：\n\(parsed.errors.joined(separator: "\n"))"
            return
        }
        let before = existingRows()
        let classification = classifyImport(kind: kind, existing: before, incoming: parsed.rows)
        preview = ImportPreviewState(classification: classification,
                                     parseErrors: parsed.errors, rowsBefore: before)
    }

    private func startExport() {
        guard let url = FilePanel.saveFile(defaultName: "\(kind.label).xlsx", allowedTypes: ["xlsx"]) else { return }
        do {
            try exportLibraryWorkbook(kind: kind, rows: exportRows()).write(to: url)
            onExported(url)
        } catch {
            alertText = "导出失败：\(error.localizedDescription)"
        }
    }
}

/// 导入差异预览 sheet（镜像 ImportDiffPreview.jsx）。
struct ImportDiffSheet: View {
    var kindLabel: String
    var profileName: String
    var classification: ImportClassification
    var parseErrors: [String]
    var allowReplace: Bool
    var onConfirm: (ImportDecisions) -> Void
    var onCancel: () -> Void

    @State private var addedKeys: Set<String>
    @State private var updatedChoices: [String: [String: Bool]]
    @State private var mode: ImportMode = .merge
    @State private var replaceName = ""
    @State private var ackErrors = false
    @Environment(\.dismiss) private var dismiss

    init(kindLabel: String, profileName: String, classification: ImportClassification,
         parseErrors: [String], allowReplace: Bool,
         onConfirm: @escaping (ImportDecisions) -> Void, onCancel: @escaping () -> Void) {
        self.kindLabel = kindLabel
        self.profileName = profileName
        self.classification = classification
        self.parseErrors = parseErrors
        self.allowReplace = allowReplace
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _addedKeys = State(initialValue: Set(classification.added.map { $0.key }))
        var choices: [String: [String: Bool]] = [:]
        for u in classification.updated {
            choices[u.key] = Dictionary(uniqueKeysWithValues: u.diffs.map { ($0.field, true) })
        }
        _updatedChoices = State(initialValue: choices)
    }

    private var totalErrors: Int { classification.errors.count + parseErrors.count }
    private var replaceOk: Bool { mode != .replace || replaceName.trimmingCharacters(in: .whitespaces) == profileName }
    private var canConfirm: Bool { totalErrors == 0 || ackErrors }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("导入差异预览 — \(kindLabel)").font(.headline)
            Text("新增 \(classification.added.count) 条、更新 \(classification.updated.count) 条、跳过 \(classification.skipped.count) 条、错误 \(classification.errors.count) 条\(parseErrors.isEmpty ? "" : "（解析错误 \(parseErrors.count) 条）")。任何导入都不会在无预览、无确认的情况下覆盖现有数据。")
                .foregroundColor(.secondary).font(.caption)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !parseErrors.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("解析错误：").bold()
                            // 按序号枚举：错误文本可能重复，不能用文本本身作 id。
                            ForEach(Array(parseErrors.enumerated()), id: \.offset) { item in
                                Text("• \(item.element)")
                            }
                        }
                    }
                    if !classification.errors.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("错误行（不会导入）：").bold()
                            // 按序号枚举：文件内主键重复时多条错误可同 key，不能用 key 作 id。
                            ForEach(Array(classification.errors.enumerated()), id: \.offset) { item in
                                Text("• \(businessKeyDisplay(item.element.key))：\(item.element.errors.joined(separator: "；"))")
                            }
                        }
                    }
                    Picker("", selection: $mode) {
                        Text("合并（默认）").tag(ImportMode.merge)
                        if allowReplace {
                            Text("全部替换（整表替换为文件内容）").tag(ImportMode.replace)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    if mode == .replace {
                        HStack {
                            Text("请输入当前方案名确认：")
                            TextField(profileName, text: $replaceName)
                                .textFieldStyle(.roundedBorder)
                        }
                        Text("全部替换将用文件内 \(classification.added.count + classification.updated.count) 条有效行替换整表；替换走重大操作保存（自动备份）。")
                            .foregroundColor(.red).font(.caption)
                    }
                    if mode == .merge, !classification.added.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("新增（\(classification.added.count)）").bold()
                            ForEach(classification.added, id: \.key) { a in
                                Toggle(businessKeyDisplay(a.key), isOn: Binding(
                                    get: { addedKeys.contains(a.key) },
                                    set: { v in
                                        if v { addedKeys.insert(a.key) } else { addedKeys.remove(a.key) }
                                    }
                                ))
                            }
                        }
                    }
                    if mode == .merge, !classification.updated.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("更新（\(classification.updated.count)，字段级 diff，默认全部采用新值）").bold()
                            ForEach(classification.updated, id: \.key) { u in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(businessKeyDisplay(u.key)).bold()
                                    ForEach(u.diffs, id: \.field) { d in
                                        Toggle("\(d.label)：\(displayValue(d.from)) → \(displayValue(d.to))", isOn: Binding(
                                            get: { updatedChoices[u.key]?[d.field] ?? true },
                                            set: { v in
                                                var m = updatedChoices[u.key] ?? [:]
                                                m[d.field] = v
                                                updatedChoices[u.key] = m
                                            }
                                        ))
                                    }
                                }
                            }
                        }
                    }
                    if !classification.skipped.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("跳过（\(classification.skipped.count)，与现有完全相同）").bold()
                            Text(classification.skipped.prefix(10).map { businessKeyDisplay($0.key) }.joined(separator: "、") + (classification.skipped.count > 10 ? " …" : ""))
                                .foregroundColor(.secondary)
                        }
                    }
                    if totalErrors > 0 {
                        Toggle("我已知晓并跳过错误行", isOn: $ackErrors)
                    }
                }
            }
            HStack {
                Spacer()
                Button("取消") { onCancel(); dismiss() }
                Button("确认导入") {
                    onConfirm(ImportDecisions(mode: mode, addedKeys: addedKeys, updatedChoices: updatedChoices))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canConfirm || !replaceOk)
            }
        }
        .padding()
        .frame(minWidth: 560, minHeight: 420)
    }

    private func displayValue(_ v: ImportValue) -> String {
        if v == .null || v.isEmpty { return "（空）" }
        return v.jsString
    }
}
#endif
