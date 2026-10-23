#if os(macOS)
import SwiftUI

/// 工作量 · 底部关联区（v2.4.0，docs/v2.4-workload-design.md §3）。
/// 表三甲选中一条工作量时，显示该条在当前工程下实际生效的主材 / 机械 / 仪器仪表关联
/// （判定与引擎同口径，见 Logic/WorkloadLinks.swift），并可直接改消耗量、增删关联、改主材价。
/// 写回目标 = 当前工程所属方案的库（顶部明示），不是资料库页的编辑目标方案。
struct WorkloadLinksPanel: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord
    var selectedRow: QuantityRow?

    @State private var addKind: AddKind?
    @State private var pendingDelete: PendingDelete?
    @State private var showDeleteConfirm = false
    @State private var archivePriceText: [Int: String] = [:]

    private enum AddKind: Identifiable {
        case material, machine, instrument
        var id: String { switch self { case .material: return "material"; case .machine: return "machine"; case .instrument: return "instrument" } }
    }

    private enum PendingDelete {
        case rule(index: Int, label: String)
        case machine(index: Int, label: String)
        case instrument(index: Int, label: String)
    }

    private var profile: ConfigurationProfile? { appState.projectProfile }
    private var libraries: LibrarySet { profile?.libraries ?? LibrarySet() }

    private var links: WorkloadRowLinks? {
        guard let row = selectedRow else { return nil }
        var engineProject = project.toEngineProject()
        engineProject.projectOrdinal = projectOrdinal(appState.db, project)
        return effectiveLinks(row: row, project: engineProject, libraries: libraries)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let row = selectedRow, let links {
                rowSummary(row, links.state)
                if links.state == .orphan {
                    Text("定额编号不在当前方案的定额库中：本行不参与计算，也没有生效关联。先在资料库补这条定额，或删除本行。")
                        .font(.caption).foregroundColor(.orange)
                } else {
                    linksList(links)
                }
            } else {
                Text("在表三甲点选一条工作量，这里显示它要用到的主材、机械、仪器仪表，并可直接修改消耗量、增删关联、改主材价——表三乙、表三丙、表四就是按这些关联自动生成的。")
                    .font(.callout).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(Theme.cardCorner)
        .overlay(RoundedRectangle(cornerRadius: Theme.cardCorner)
            .stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .sheet(item: $addKind) { kind in addSheet(kind) }
        .alert("删除这条关联？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("确认删除", role: .destructive) { performDelete() }
        } message: {
            Text("将从方案「\(profile?.name ?? "")」的库中删除，删除后使用该方案的全部工程都不再计这条关联。")
        }
    }

    // MARK: - 头部与行摘要

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: "link").foregroundColor(Theme.accent)
                Text("关联区 · 本条工作量的主材 / 机械 / 仪器仪表").font(.headline)
                Spacer()
                if selectedRow != nil, links?.state != .orphan {
                    Menu {
                        Button("添加主材关联…") { addKind = .material }
                        Button("添加机械关联…") { addKind = .machine }
                        Button("添加仪器仪表关联…") { addKind = .instrument }
                    } label: {
                        Label("添加关联", systemImage: "plus.circle")
                    }
                    .controlSize(.small)
                    .fixedSize()
                }
            }
            Text("这里改的是当前方案「\(profile?.name ?? "—")」库的关联，对使用该方案的全部工程生效；只改本工程请用表四材料页的工程级修正（手动调整 / 本工程单价）。")
                .font(.caption).foregroundColor(.orange)
        }
    }

    private func rowSummary(_ row: QuantityRow, _ state: WorkloadRowState) -> some View {
        HStack(spacing: 10) {
            Text(row.quota).fontWeight(.bold).monospacedDigit()
            Text(row.variant ?? "").lineLimit(1)
            Text("工程量 \(num2(row.qty)) × 系数 \(num2(row.coef ?? 1))")
                .foregroundColor(.secondary).monospacedDigit()
            if case .inactive(let reason) = state {
                Text(reason).foregroundColor(.orange)
            }
            Spacer()
        }
        .font(.callout)
    }

    // MARK: - 单列分组清单（v2.5.0 §12.3：三栏并排作废，组头行分隔，一项一行）

    /// 清单列宽（§12.2 原则：代号/规格/单位窄，名称弹性）。
    private enum ColW {
        static let code: CGFloat = 84
        static let spec: CGFloat = 96
        static let unit: CGFloat = 48
        static let per: CGFloat = 84
        static let total: CGFloat = 88
        static let price: CGFloat = 96
        static let amount: CGFloat = 92
        static let ops: CGFloat = 30
    }

    private func linksList(_ links: WorkloadRowLinks) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                linksColumnHeader
                if !links.materials.isEmpty {
                    groupBand("主材", count: links.materials.count) { addKind = .material }
                    ForEach(links.materials, id: \.ruleIndex) { link in
                        materialLine(link)
                        Divider()
                    }
                }
                if !links.machines.isEmpty {
                    groupBand("机械", count: links.machines.count) { addKind = .machine }
                    ForEach(links.machines, id: \.linkIndex) { link in
                        equipLine(link, isMachine: true)
                        Divider()
                    }
                }
                if !links.instruments.isEmpty {
                    groupBand("仪器仪表", count: links.instruments.count) { addKind = .instrument }
                    ForEach(links.instruments, id: \.linkIndex) { link in
                        equipLine(link, isMachine: false)
                        Divider()
                    }
                }
                if links.materials.isEmpty && links.machines.isEmpty && links.instruments.isEmpty {
                    Text("本条暂无关联。用右上「添加关联」从材料库 / 价目库添加。")
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private var linksColumnHeader: some View {
        HStack(spacing: 8) {
            Text("代号").frame(width: ColW.code, alignment: .leading)
            Text("名称").frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            Text("规格").frame(width: ColW.spec, alignment: .leading)
            Text("单位").frame(width: ColW.unit, alignment: .leading)
            Text("单位用量").frame(width: ColW.per, alignment: .trailing)
            Text("参考用量").frame(width: ColW.total, alignment: .trailing)
            Text("单价").frame(width: ColW.price, alignment: .trailing)
            Text("合价").frame(width: ColW.amount, alignment: .trailing)
            Text("").frame(width: ColW.ops)
        }
        .font(.caption2).foregroundColor(.secondary)
        .padding(.bottom, 2)
    }

    /// 组头行（全宽色带 + 项数 + 添加按钮）；空组不显示（添加走面板头「添加关联」菜单）。
    private func groupBand(_ title: String, count: Int,
                           add: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text("【\(title)】").font(.subheadline).fontWeight(.bold)
            Text("\(count) 项").font(.caption).foregroundColor(.secondary)
            Spacer()
            Button { add() } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .help("添加\(title)关联")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Theme.accent.opacity(0.08))
        .cornerRadius(4)
    }

    private func materialLine(_ link: EffectiveMaterialLink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("—").foregroundColor(.secondary)
                    .frame(width: ColW.code, alignment: .leading)
                HStack(spacing: 6) {
                    Text(link.rule.material).fontWeight(.semibold).lineLimit(1)
                    kindBadge(link.rule.kind)
                    if link.materialIndex == nil {
                        badge("未建档", color: .orange)
                    }
                }
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                Text(link.rule.spec.isEmpty ? "—" : link.rule.spec)
                    .foregroundColor(.secondary).lineLimit(1)
                    .frame(width: ColW.spec, alignment: .leading)
                Text(link.unit).foregroundColor(.secondary)
                    .frame(width: ColW.unit, alignment: .leading)
                DoubleField(label: "", value: consumptionBinding(link))
                    .frame(width: ColW.per)
                Text(num2(link.totalQty)).monospacedDigit()
                    .frame(width: ColW.total, alignment: .trailing)
                Group {
                    if link.materialIndex != nil {
                        DoubleField(label: "", value: priceBinding(link))
                    } else {
                        Text("—").foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(width: ColW.price)
                Text(money(link.amount)).monospacedDigit()
                    .frame(width: ColW.amount, alignment: .trailing)
                deleteButton { pendingDelete = .rule(index: link.ruleIndex,
                                                      label: link.rule.material) }
                    .frame(width: ColW.ops)
            }
            if link.rule.kind == "备选" || link.materialIndex == nil || link.inactiveReason != nil {
                HStack(spacing: 8) {
                    Text("").frame(width: ColW.code)
                    if link.materialIndex == nil {
                        Text("未建档不计价，建档单价").foregroundColor(.secondary)
                        TextField("单价", text: archiveBinding(link.ruleIndex))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 74)
                        Button("建档") { archiveMaterial(link) }
                            .controlSize(.small)
                    }
                    if link.rule.kind == "备选" { altToggle(link) }
                    if let reason = link.inactiveReason {
                        Text(reason).foregroundColor(.orange)
                    }
                    Spacer()
                }
            }
        }
        .font(.caption)
        .padding(.vertical, 3)
        .opacity(link.isEffective ? 1 : 0.55)
    }

    private func equipLine(_ link: EffectiveEquipLink, isMachine: Bool) -> some View {
        HStack(spacing: 8) {
            Text(link.mcode.isEmpty ? "—" : link.mcode).monospacedDigit()
                .frame(width: ColW.code, alignment: .leading)
            Text(link.mname).fontWeight(.semibold).lineLimit(1)
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            Text("—").foregroundColor(.secondary)
                .frame(width: ColW.spec, alignment: .leading)
            Text(link.unit).foregroundColor(.secondary)
                .frame(width: ColW.unit, alignment: .leading)
            DoubleField(label: "", value: equipQtyBinding(link, isMachine: isMachine))
                .frame(width: ColW.per)
            Text(num2(link.totalQty)).monospacedDigit()
                .frame(width: ColW.total, alignment: .trailing)
            Group {
                if let price = link.price {
                    Text(money(price)).monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Text("无价").foregroundColor(.orange)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .help("价目库无此价，按 0 计")
                }
            }
            .frame(width: ColW.price)
            Text(money(link.amount)).monospacedDigit()
                .frame(width: ColW.amount, alignment: .trailing)
            deleteButton {
                pendingDelete = isMachine
                    ? .machine(index: link.linkIndex, label: link.mname)
                    : .instrument(index: link.linkIndex, label: link.mname)
            }
            .frame(width: ColW.ops)
        }
        .font(.caption)
        .padding(.vertical, 3)
    }

    private func altToggle(_ link: EffectiveMaterialLink) -> some View {
        Group {
            if link.rule.id.isEmpty {
                Text("无 id，不可启用").foregroundColor(.secondary)
            } else {
                Toggle("启用", isOn: Binding(
                    get: { project.ruleOverrides.first { $0.ruleId == link.rule.id }?.enabled ?? false },
                    set: { v in
                        let rid = link.rule.id
                        appState.updateProject(project.id) { p in
                            if let i = p.ruleOverrides.firstIndex(where: { $0.ruleId == rid }) {
                                p.ruleOverrides[i].enabled = v
                            } else {
                                p.ruleOverrides.append(RuleOverride(ruleId: rid, enabled: v))
                            }
                        }
                    }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
        }
    }

    // MARK: - 通用小件

    private func kindBadge(_ kind: String) -> some View {
        Text(kind)
            .font(.caption2).fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Theme.accent)
            .cornerRadius(5)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2).fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color)
            .cornerRadius(5)
    }

    private func deleteButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive) {
            action()
            showDeleteConfirm = true
        } label: {
            Image(systemName: "trash").foregroundColor(.red)
        }
        .buttonStyle(.borderless)
        .help("删除这条关联")
    }

    // MARK: - 写回绑定与动作

    private func updateLibraries(_ mutate: (inout LibrarySet) -> Void) {
        guard let pid = profile?.id else { return }
        appState.updateDb { d in
            guard let i = d.configurationProfiles.firstIndex(where: { $0.id == pid }) else { return }
            mutate(&d.configurationProfiles[i].libraries)
        }
    }

    private func consumptionBinding(_ link: EffectiveMaterialLink) -> Binding<Double> {
        Binding(get: { link.rule.consumption },
                set: { v in updateLibraries { setRuleConsumption(in: &$0, ruleIndex: link.ruleIndex, v) } })
    }

    private func priceBinding(_ link: EffectiveMaterialLink) -> Binding<Double> {
        Binding(get: { link.priceExcl },
                set: { v in
                    let name = link.rule.material, spec = link.rule.spec
                    updateLibraries { setMaterialPrice(in: &$0, name: name, spec: spec, v) }
                })
    }

    private func equipQtyBinding(_ link: EffectiveEquipLink, isMachine: Bool) -> Binding<Double> {
        Binding(get: { link.consumption },
                set: { v in
                    if isMachine {
                        updateLibraries { setQuotaMachineQty(in: &$0, index: link.linkIndex, v) }
                    } else {
                        updateLibraries { setQuotaInstrumentQty(in: &$0, index: link.linkIndex, v) }
                    }
                })
    }

    private func archiveBinding(_ ruleIndex: Int) -> Binding<String> {
        Binding(get: { archivePriceText[ruleIndex] ?? "" },
                set: { archivePriceText[ruleIndex] = $0 })
    }

    private func archiveMaterial(_ link: EffectiveMaterialLink) {
        let price = Double((archivePriceText[link.ruleIndex] ?? "").trimmingCharacters(in: .whitespaces)) ?? 0
        let rule = link.rule
        updateLibraries {
            ensureMaterial(in: &$0, name: rule.material, spec: rule.spec,
                           unit: rule.unit, supply: rule.supply, priceExcl: price)
        }
        appState.showToast("已建档材料「\(rule.material)\(rule.spec.isEmpty ? "" : " \(rule.spec)")」，单价 \(money(price))")
    }

    private func performDelete() {
        guard let pending = pendingDelete else { return }
        switch pending {
        case .rule(let index, _):
            updateLibraries { removeRule(in: &$0, ruleIndex: index) }
        case .machine(let index, _):
            updateLibraries { removeQuotaMachine(in: &$0, index: index) }
        case .instrument(let index, _):
            updateLibraries { removeQuotaInstrument(in: &$0, index: index) }
        }
        pendingDelete = nil
    }

    // MARK: - 添加关联 sheet

    @ViewBuilder
    private func addSheet(_ kind: AddKind) -> some View {
        if let row = selectedRow {
            switch kind {
            case .material:
                AddMaterialLinkSheet(quota: row.quota, rowVariant: row.variant ?? "",
                                     materials: libraries.materials) { material, kindName, variant, consumption in
                    updateLibraries {
                        addMaterialRule(in: &$0, quota: row.quota, material: material,
                                        kind: kindName, variant: variant, consumption: consumption)
                    }
                }
            case .machine:
                AddEquipLinkSheet(title: "添加机械关联",
                                  rows: libraries.machinePrices.map {
                                      EquipChoice(code: $0.code, name: $0.name, unit: $0.unit, price: $0.price)
                                  }) { choice, qty in
                    if let priceRow = libraries.machinePrices.first(where: { $0.code == choice.code }) {
                        updateLibraries { addQuotaMachine(in: &$0, quota: row.quota, priceRow: priceRow, qty: qty) }
                    }
                }
            case .instrument:
                AddEquipLinkSheet(title: "添加仪器仪表关联",
                                  rows: libraries.instrumentPrices.map {
                                      EquipChoice(code: $0.code, name: $0.name, unit: $0.unit, price: $0.price)
                                  }) { choice, qty in
                    if let priceRow = libraries.instrumentPrices.first(where: { $0.code == choice.code }) {
                        updateLibraries { addQuotaInstrument(in: &$0, quota: row.quota, priceRow: priceRow, qty: qty) }
                    }
                }
            }
        }
    }
}

/// 选材添加主材关联：材料库搜索 → 选种类（通用 / 变体＝本行项目名称）→ 填消耗量。
struct AddMaterialLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    var quota: String
    var rowVariant: String
    var materials: [MaterialRow]
    var onAdd: (MaterialRow, String, String, Double) -> Void

    @State private var keyword = ""
    @State private var picked: MaterialRow?
    @State private var kindChoice = "通用"
    @State private var consumptionText = "1"

    private var filtered: [MaterialRow] {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return materials }
        return materials.filter { $0.name.contains(kw) || $0.spec.contains(kw) }
    }

    private var consumption: Double? {
        Double(consumptionText.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("为定额 \(quota) 添加主材关联").font(.title3).fontWeight(.bold)
            TextField("搜索材料名称 / 规格…", text: $keyword).textFieldStyle(.roundedBorder)
            List(filtered, id: \.id) { m in
                Button { picked = m } label: {
                    HStack(spacing: 8) {
                        Text(m.name).fontWeight(.semibold)
                        Text(m.spec).foregroundColor(.secondary)
                        Text(m.unit).foregroundColor(.secondary)
                        Text(m.supply).foregroundColor(.secondary)
                        Spacer()
                        Text(money(m.priceExcl)).monospacedDigit()
                        if picked?.id == m.id {
                            Image(systemName: "checkmark").foregroundColor(Theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 220)
            HStack(spacing: 10) {
                Text("种类")
                Picker("", selection: $kindChoice) {
                    Text("通用（整条定额都用）").tag("通用")
                    Text("变体（仅本行：\(rowVariant)）").tag("变体")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack(spacing: 8) {
                Text("单位消耗量")
                TextField("消耗量", text: $consumptionText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Spacer()
                Button("取消") { dismiss() }
                Button("添加") {
                    guard let picked, let consumption else { return }
                    onAdd(picked, kindChoice, kindChoice == "变体" ? rowVariant : "", consumption)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(picked == nil || consumption == nil)
            }
            Text("种类选“变体”时，仅项目名称与本行相同的工程量行计入这条材料（与表四口径一致）。")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 560)
    }
}

/// 价目库选行添加机械 / 仪表关联。
struct EquipChoice: Equatable {
    var code: String
    var name: String
    var unit: String
    var price: Double
}

struct AddEquipLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var rows: [EquipChoice]
    var onAdd: (EquipChoice, Double) -> Void

    @State private var keyword = ""
    @State private var picked: EquipChoice?
    @State private var qtyText = "0.1"

    private var filtered: [EquipChoice] {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else { return rows }
        return rows.filter { $0.name.contains(kw) || $0.code.contains(kw) }
    }

    private var qty: Double? { Double(qtyText.trimmingCharacters(in: .whitespaces)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3).fontWeight(.bold)
            TextField("搜索编码 / 名称…", text: $keyword).textFieldStyle(.roundedBorder)
            List(filtered, id: \.code) { r in
                Button { picked = r } label: {
                    HStack(spacing: 8) {
                        Text(r.code).fontWeight(.semibold)
                        Text(r.name)
                        Text(r.unit).foregroundColor(.secondary)
                        Spacer()
                        Text(money(r.price)).monospacedDigit()
                        if picked?.code == r.code {
                            Image(systemName: "checkmark").foregroundColor(Theme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(height: 220)
            HStack(spacing: 8) {
                Text("单位消耗量（台班）")
                TextField("消耗量", text: $qtyText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                Spacer()
                Button("取消") { dismiss() }
                Button("添加") {
                    guard let picked, let qty else { return }
                    onAdd(picked, qty)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(picked == nil || qty == nil)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
#endif
