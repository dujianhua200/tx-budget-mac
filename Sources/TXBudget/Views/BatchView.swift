#if os(macOS)
import SwiftUI

/// 批量生成：批量新建 / Excel 批量导入工程量 / 批量改价 / 批量改折扣 / 批量删除。
struct BatchView: View {
    @EnvironmentObject private var appState: AppState
    @State private var names = ""
    @State private var templateId = ""
    @State private var multiplier = 1.0
    @State private var selected: Set<String> = []
    @State private var matKey = ""
    @State private var newPrice = ""
    @State private var discount = 1.0
    @State private var message = ""
    @State private var showDeleteConfirm = false
    /// 本次导入新建的工程 id（撤销导入时删除；原生无全局撤销栈，与删除行为一致）。
    @State private var lastImportIds: [String] = []
    @State private var importAlert: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("批量生成工程").font(.headline)
                GroupBox("① 批量新建（粘贴工程名称 + 套模板）") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $names)
                            .frame(height: 120)
                            .border(Color.secondary.opacity(0.3))
                        HStack {
                            Picker("模板", selection: $templateId) {
                                Text("不套模板（空白）").tag("")
                                ForEach(appState.db.projects, id: \.id) { p in
                                    Text("套用模板：\(p.name)").tag(p.id)
                                }
                            }.frame(width: 260)
                            Text("数量倍数")
                            DoubleField(label: "", value: $multiplier)
                                .textFieldStyle(.roundedBorder).frame(width: 70)
                            Button("批量新建") { batchCreate() }
                                .buttonStyle(.borderedProminent)
                        }
                        Text("每行一个工程名称。套模板会复制模板的全部工程量、材料调整与费率；数量倍数可把模板工程量整体放大/缩小。")
                            .foregroundColor(.secondary).font(.caption)
                    }
                }
                GroupBox("② 从 Excel 批量导入工程量") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("支持 v3.0 母版“工程量”表与简易四列表（工程名称/定额编号/项目名称/数量/工日系数）。")
                            .foregroundColor(.secondary).font(.caption)
                        HStack {
                            Button("选择 Excel 文件导入") { importQuantities() }
                                .buttonStyle(.borderedProminent)
                            if !lastImportIds.isEmpty {
                                Button("撤销导入（删除本次导入的 \(lastImportIds.count) 个工程）") {
                                    appState.deleteProjects(lastImportIds)
                                    lastImportIds = []
                                    message = "已撤销导入。"
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
                GroupBox("③ 批量改价 / 改费率（勾选下方工程后应用）") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("选择材料", selection: $matKey) {
                                Text("选择材料").tag("")
                                ForEach(libraries.materials, id: \.id) { m in
                                    Text("\(m.name) \(m.spec)（\(m.supply)，现价 \(jsNumberString(m.priceExcl))）")
                                        .tag("\(m.name)|\(m.spec)")
                                }
                            }.frame(width: 320)
                            TextField("新除税单价", text: $newPrice)
                                .textFieldStyle(.roundedBorder).frame(width: 110)
                            Button("批量改价") { batchPrice() }
                        }
                        HStack {
                            Text("施工折扣")
                            DoubleField(label: "", value: $discount)
                                .textFieldStyle(.roundedBorder).frame(width: 80)
                            Button("批量改折扣") { batchDiscount() }
                        }
                        Text("改价/改费率只影响勾选的工程，不改全局默认价（全局默认价在“基础库 → 材料库/费率”中改）。")
                            .foregroundColor(.secondary).font(.caption)
                    }
                }
                GroupBox("④ 批量导出预算书") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("勾选下方工程，一键导出每个工程的完整预算书 Excel，文件名为“<工程名>_概预算.xlsx”。单个工程失败不中断其余工程。")
                            .foregroundColor(.secondary).font(.caption)
                        Button("批量导出选中工程") { batchExport() }
                            .disabled(selected.isEmpty)
                    }
                }
                GroupBox("⑤ 批量删除工程") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("勾选下方工程，删除前弹确认框并备份。")
                            .foregroundColor(.secondary).font(.caption)
                        Button("批量删除选中工程") { showDeleteConfirm = true }
                            .disabled(selected.isEmpty)
                            .tint(.red)
                    }
                }
                if !message.isEmpty {
                    Text(message).foregroundColor(.secondary)
                }
                Table(appState.db.projects, selection: $selected) {
                    TableColumn("工程名称") { p in Text(p.name) }
                    TableColumn("工程量行数") { p in Text("\(p.quantities.count)") }
                    TableColumn("总计（含税）") { p in
                        MoneyText(value: appState.calcResult(for: p)?.table1.grandIncl)
                    }
                    TableColumn("操作") { p in
                        Button("打开") { appState.openProject(p.id) }.controlSize(.small)
                    }
                }
                .tableStyle(.inset)
                .frame(minHeight: 200)
            }
        }
        .alert("导入", isPresented: Binding(
            get: { importAlert != nil },
            set: { if !$0 { importAlert = nil } }
        )) {
            Button("知道了") { importAlert = nil }
        } message: {
            Text(importAlert ?? "")
        }
        .alert("删除选中的 \(selected.count) 个工程？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                appState.deleteProjects(Array(selected))
                message = "已删除 \(selected.count) 个工程。"
                selected.removeAll()
            }
        } message: {
            Text("将删除选中工程（含工程量、材料调整与费率覆盖），删除前已备份。")
        }
    }

    private var libraries: LibrarySet {
        appState.editingProfile?.libraries ?? LibrarySet()
    }

    /// 从 Excel 批量导入工程量（镜像 Electron `Batch.jsx` 的 importExcel）。
    /// 单位/系数按激活方案的库解析：短单（code + variant）→ 定额库（code）→ 空；
    /// coef = q.coef || short.coef || 1（0 均按空处理）。
    private func importQuantities() {
        guard let url = FilePanel.openFile(allowedTypes: ["xlsx"], message: "选择要导入的 Excel 文件") else { return }
        guard let data = try? Data(contentsOf: url) else {
            importAlert = "文件读不出来：\(url.lastPathComponent)"
            return
        }
        let result: QuantitiesImportResult
        do {
            result = try parseQuantitiesFile(data: data)
        } catch {
            importAlert = "导入解析失败：\(error.localizedDescription)"
            return
        }
        guard !result.projects.isEmpty else {
            importAlert = "该文件未识别到工程量：支持 v3.0 母版“工程量”表，或简易四列（工程名称/定额编号/项目名称/数量/工日系数）。"
            return
        }
        let libs = activeProfile(appState.db)?.libraries ?? LibrarySet()
        var created: [ProjectRecord] = []
        for p in result.projects {
            var np = newProject(appState.db, name: p.name)
            np.quantities = p.quantities.map { q in
                let short = libs.shortlist.first { $0.code == q.quota && $0.name == q.variant }
                let quota = libs.quotas.first { $0.code == q.quota }
                let coef = q.coef != 0 ? q.coef : ((short?.coef ?? 0) != 0 ? (short?.coef ?? 0) : 1)
                return QuantityRow(id: newUID(), quota: q.quota, variant: q.variant,
                                   unit: short?.unit ?? quota?.unit ?? "", qty: q.qty, coef: coef)
            }
            created.append(np)
        }
        appState.updateDb { d in d.projects.insert(contentsOf: created, at: 0) }
        lastImportIds = created.map { $0.id }
        message = "已从 \(result.kind == .v3 ? "v3.0 母版" : "简易表格") 导入 \(created.count) 个工程。"
    }

    private func batchCreate() {
        let list = names.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !list.isEmpty else { return }
        let tpl = appState.db.projects.first { $0.id == templateId }
        var created: [ProjectRecord] = []
        for n in list {
            var p = newProject(appState.db, name: n, template: tpl)
            if tpl != nil, multiplier != 1 {
                // 与 Electron Batch.jsx 一致：数量×倍数后按 2 位舍入。
                p.quantities = p.quantities.map { q in
                    var row = q
                    row.qty = r2((row.qty ?? 0) * multiplier)
                    return row
                }
            }
            created.append(p)
        }
        appState.updateDb { d in d.projects.insert(contentsOf: created, at: 0) }
        names = ""
        let suffix = tpl.map { t in
            "（套用模板 \(t.name)\(multiplier != 1 ? "，数量×\(jsNumberString(multiplier))" : "")"
        } ?? ""
        message = "已批量新建 \(created.count) 个工程\(suffix)。"
    }

    private func batchPrice() {
        guard !matKey.isEmpty, let price = Double(newPrice), !selected.isEmpty else { return }
        appState.updateDb { d in
            for i in d.projects.indices where selected.contains(d.projects[i].id) {
                if let j = d.projects[i].materialPriceOverrides.firstIndex(where: { $0.key == matKey }) {
                    d.projects[i].materialPriceOverrides[j].priceExcl = price
                } else {
                    d.projects[i].materialPriceOverrides.append(MaterialPriceOverride(key: matKey, priceExcl: price))
                }
            }
        }
        message = "已将 \(selected.count) 个工程的 \(matKey) 除税单价改为 \(newPrice) 元。"
    }

    private func batchExport() {
        guard let dir = FilePanel.openDirectory(message: "选择批量导出预算书的保存目录") else { return }
        let projects = appState.db.projects.filter { selected.contains($0.id) }
        let result = appState.batchExportProjects(projects, to: dir)
        if result.failures.isEmpty {
            message = "已批量导出 \(result.succeeded) 个工程到 \(dir.path)。"
        } else {
            let names = result.failures.map { $0.0 }.joined(separator: "、")
            message = "已导出 \(result.succeeded) 个，失败 \(result.failures.count) 个（\(names)）。"
        }
    }

    private func batchDiscount() {
        guard !selected.isEmpty else { return }
        appState.updateDb { d in
            for i in d.projects.indices where selected.contains(d.projects[i].id) {
                d.projects[i].info.施工折扣 = discount
                d.projects[i].rateOverrides.discount = discount
            }
        }
        message = "已将 \(selected.count) 个工程的施工折扣改为 \(jsNumberString(discount))。"
    }
}
#endif
