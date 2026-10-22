#if os(macOS)
import SwiftUI

/// 取费规则（编辑目标 = settings.editingProfileId）：费率（左树+右表）/ 表五费用 / 打折规则 / 关联规则。
struct FeeRulesView: View {
    @EnvironmentObject private var appState: AppState
    var tab: FeeRuleTab

    @State private var feeProjectType = "通信线路工程"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "取费规则 · \(tab.label)",
                       subtitle: "取费规则随配置方案保存；不同方案完全隔离")
            HStack(spacing: 10) {
                Image(systemName: "pencil.circle.fill").foregroundColor(Theme.accent)
                Text("正在编辑方案：")
                    .font(.callout).foregroundColor(.secondary)
                Text(appState.editingProfile?.name ?? "—")
                    .font(.callout).fontWeight(.semibold)
                Text("（新建工程默认方案不受这里影响）")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("切换编辑方案") { appState.nav = .profiles }
                    .controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Theme.accent.opacity(0.07))
            .cornerRadius(8)
            switch tab {
            case .rates:
                ratesView
            case .table5fees:
                table5FeesView
            case .discount:
                DiscountRuleView()
            case .rulesAlt:
                rulesAltView
            }
        }
        .padding(Theme.pagePadding)
    }

    // MARK: - 费率

    private var ratesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ExcelImportExportButtons(
                kind: .rates,
                profileName: appState.editingProfile?.name ?? "—",
                allowReplace: false,
                existingRows: { [appState] in
                    existingImportRows(kind: .rates, profile: appState.editingProfile ?? ConfigurationProfile())
                },
                onConfirmImport: { classification, decisions, rowsBefore in
                    applyLibraryImport(appState: appState, kind: .rates,
                                       classification: classification, decisions: decisions,
                                       rowsBefore: rowsBefore)
                },
                exportRows: { [appState] in
                    existingImportRows(kind: .rates, profile: appState.editingProfile ?? ConfigurationProfile())
                },
                onExported: { url in
                    appState.showToast("已导出：\(url.lastPathComponent)")
                }
            )
            Text("金额列取自\(feeExampleProjectName)的折前表二。")
                .foregroundColor(.secondary).font(.caption)
            FeeTreeTableView(
                profile: appState.editingProfile,
                result: feeExampleResult,
                projectType: $feeProjectType,
                showProjectTypePicker: true,
                onRateChange: { _, rateField, value in
                    appState.updateDb { d in
                        guard let idx = editingProfileIndex(d) else { return }
                        if d.configurationProfiles[idx].rates.byProjectType[feeProjectType] == nil {
                            d.configurationProfiles[idx].rates.byProjectType[feeProjectType] = NamedRatesRecord()
                        }
                        d.configurationProfiles[idx].rates.byProjectType[feeProjectType]?.setValue(value, forKey: rateField)
                        d.configurationProfiles[idx].updatedAt = nowISO()
                    }
                }
            )
        }
    }

    private var feeExampleProject: ProjectRecord {
        let editingId = appState.db.settings.editingProfileId ?? appState.db.settings.activeProfileId
        if var p = appState.db.projects.first(where: { $0.profileId == editingId }) {
            // 预览计算统一用下拉所选工程类别，与右侧费率编辑目标一致。
            p.info.工程类型 = feeProjectType
            return p
        }
        var preview = ProjectRecord(id: "fee-preview", name: "预览", profileId: editingId)
        preview.info.工程类型 = feeProjectType
        return preview
    }

    private var feeExampleProjectName: String {
        feeExampleProject.id == "fee-preview" ? "空工程预览（金额为空）" : "工程“\(feeExampleProject.name)”"
    }

    private var feeExampleResult: CalcResult? {
        calcFor(appState.db, feeExampleProject)
    }

    // MARK: - 表五费用

    private var table5FeesView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ExcelImportExportButtons(
                kind: .table5Fees,
                profileName: appState.editingProfile?.name ?? "—",
                existingRows: { [appState] in
                    existingImportRows(kind: .table5Fees, profile: appState.editingProfile ?? ConfigurationProfile())
                },
                onConfirmImport: { classification, decisions, rowsBefore in
                    applyLibraryImport(appState: appState, kind: .table5Fees,
                                       classification: classification, decisions: decisions,
                                       rowsBefore: rowsBefore)
                },
                exportRows: { [appState] in
                    existingImportRows(kind: .table5Fees, profile: appState.editingProfile ?? ConfigurationProfile())
                },
                onExported: { url in
                    appState.showToast("已导出：\(url.lastPathComponent)")
                }
            )
            table5FeesTable
        }
    }

    private var table5FeesTable: some View {
        ProTable(
            columns: LibraryRowCodec.table5Columns,
            rows: LibraryRowCodec.table5Dicts(appState.editingProfile?.table5Fees ?? []),
            onCommit: { id, dict in
                appState.updateDb { d in
                    guard let idx = editingProfileIndex(d) else { return }
                    LibraryRowCodec.commitTable5(id: id, dict: dict, profile: &d.configurationProfiles[idx])
                    d.configurationProfiles[idx].updatedAt = nowISO()
                }
            },
            onAdd: {
                appState.updateDb { d in
                    guard let idx = editingProfileIndex(d) else { return }
                    LibraryRowCodec.addTable5(profile: &d.configurationProfiles[idx])
                    d.configurationProfiles[idx].updatedAt = nowISO()
                }
            },
            onDelete: { ids in
                appState.updateDb { d in
                    guard let idx = editingProfileIndex(d) else { return }
                    LibraryRowCodec.deleteTable5(ids: ids, profile: &d.configurationProfiles[idx])
                    d.configurationProfiles[idx].updatedAt = nowISO()
                }
            },
            emptyTitle: "暂无表五费用项",
            emptyMessage: "点“新增一行”添加费用项。"
        )
    }

    // MARK: - 关联规则（备选）

    private var rulesAltView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ExcelImportExportButtons(
                kind: .rulesAlt,
                profileName: appState.editingProfile?.name ?? "—",
                existingRows: { [appState] in
                    existingImportRows(kind: .rulesAlt, profile: appState.editingProfile ?? ConfigurationProfile())
                },
                onConfirmImport: { classification, decisions, rowsBefore in
                    applyLibraryImport(appState: appState, kind: .rulesAlt,
                                       classification: classification, decisions: decisions,
                                       rowsBefore: rowsBefore)
                },
                exportRows: { [appState] in
                    existingImportRows(kind: .rulesAlt, profile: appState.editingProfile ?? ConfigurationProfile())
                },
                onExported: { url in
                    appState.showToast("已导出：\(url.lastPathComponent)")
                }
            )
            rulesAltTable
        }
    }

    private var rulesAltTable: some View {
        ProTable(
            columns: LibraryRowCodec.columns(for: .rulesAlt),
            rows: LibraryRowCodec.dicts(for: .rulesAlt, profile: appState.editingProfile ?? ConfigurationProfile()),
            onCommit: { id, dict in
                appState.updateDb { d in
                    guard let idx = editingProfileIndex(d) else { return }
                    LibraryRowCodec.commit(id: id, dict: dict, viewKey: .rulesAlt, profile: &d.configurationProfiles[idx])
                    d.configurationProfiles[idx].updatedAt = nowISO()
                }
            },
            onAdd: {
                appState.updateDb { d in
                    guard let idx = editingProfileIndex(d) else { return }
                    LibraryRowCodec.add(viewKey: .rulesAlt, profile: &d.configurationProfiles[idx])
                    d.configurationProfiles[idx].updatedAt = nowISO()
                }
            },
            onDelete: { ids in
                appState.updateDb { d in
                    guard let idx = editingProfileIndex(d) else { return }
                    LibraryRowCodec.delete(ids: ids, viewKey: .rulesAlt, profile: &d.configurationProfiles[idx])
                    d.configurationProfiles[idx].updatedAt = nowISO()
                }
            },
            emptyTitle: "暂无关联规则",
            emptyMessage: "点“新增一行”添加备选关联规则。"
        )
    }

    private func editingProfileIndex(_ d: DbFile) -> Int? {
        if let id = d.settings.editingProfileId, let i = d.configurationProfiles.firstIndex(where: { $0.id == id }) {
            return i
        }
        if let i = d.configurationProfiles.firstIndex(where: { $0.id == d.settings.activeProfileId }) {
            return i
        }
        return d.configurationProfiles.indices.first
    }
}

/// 打折规则：折扣率 + 不打折 / 折后=0 两列勾选（同一项不可同时勾选两列）。
struct DiscountRuleView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("打折规则随配置方案保存与导出。折扣率 1 = 不打折；勾选的费用项不打折（折后 = 折前）；勾选“折后=0”的费用项在打折时折后为 0（折扣率 = 1 时不生效）；同一项不可同时勾选两列。")
                .foregroundColor(.secondary).font(.caption)
            HStack {
                Text("折扣率")
                DoubleField(label: "", value: discountRateBinding)
                    .textFieldStyle(.roundedBorder).frame(width: 120)
                Text("当前：\(ratePercentText(appState.editingProfile?.discountRule.discountRate ?? 1))")
                    .foregroundColor(.secondary)
            }
            Table(indexedLeafDefs) {
                TableColumn("不打折费用项") { r in
                    Toggle(r.row.label, isOn: noDiscountBinding(r.row.key))
                }
                TableColumn("折后=0") { r in
                    Toggle("", isOn: zeroBinding(r.row.key)).labelsHidden()
                }
                TableColumn("说明") { r in
                    Text(r.row.methodBefore).foregroundColor(.secondary)
                }
            }
            .tableStyle(.inset)
        }
    }

    private var indexedLeafDefs: [IndexedRow<DiscountLineDef>] {
        indexed(discountLineDefs.filter { $0.kind == .leaf })
    }

    private var discountRateBinding: Binding<Double> {
        Binding(
            get: { appState.editingProfile?.discountRule.discountRate ?? 1 },
            set: { v in appState.updateDb { d in
                guard let idx = editingProfileIndex(d) else { return }
                d.configurationProfiles[idx].discountRule.discountRate = v
                d.configurationProfiles[idx].updatedAt = nowISO()
            } }
        )
    }

    private func noDiscountBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { appState.editingProfile?.discountRule.noDiscountKeys?.contains(key) ?? false },
            set: { v in appState.updateDb { d in
                guard let idx = editingProfileIndex(d) else { return }
                var keys = Set(d.configurationProfiles[idx].discountRule.noDiscountKeys ?? [])
                var zero = Set(d.configurationProfiles[idx].discountRule.zeroAfterDiscountKeys ?? [])
                if v {
                    keys.insert(key)
                    zero.remove(key)
                } else {
                    keys.remove(key)
                }
                d.configurationProfiles[idx].discountRule.noDiscountKeys = Array(keys)
                d.configurationProfiles[idx].discountRule.zeroAfterDiscountKeys = Array(zero)
                d.configurationProfiles[idx].updatedAt = nowISO()
            } }
        )
    }

    private func zeroBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { appState.editingProfile?.discountRule.zeroAfterDiscountKeys?.contains(key) ?? false },
            set: { v in appState.updateDb { d in
                guard let idx = editingProfileIndex(d) else { return }
                var zero = Set(d.configurationProfiles[idx].discountRule.zeroAfterDiscountKeys ?? [])
                var keys = Set(d.configurationProfiles[idx].discountRule.noDiscountKeys ?? [])
                if v {
                    zero.insert(key)
                    keys.remove(key)
                } else {
                    zero.remove(key)
                }
                d.configurationProfiles[idx].discountRule.zeroAfterDiscountKeys = Array(zero)
                d.configurationProfiles[idx].discountRule.noDiscountKeys = Array(keys)
                d.configurationProfiles[idx].updatedAt = nowISO()
            } }
        )
    }

    private func editingProfileIndex(_ d: DbFile) -> Int? {
        if let id = d.settings.editingProfileId, let i = d.configurationProfiles.firstIndex(where: { $0.id == id }) {
            return i
        }
        if let i = d.configurationProfiles.firstIndex(where: { $0.id == d.settings.activeProfileId }) {
            return i
        }
        return d.configurationProfiles.indices.first
    }
}
#endif
