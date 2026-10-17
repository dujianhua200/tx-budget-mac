#if os(macOS)
import SwiftUI

/// 工程信息完整表单（分组：基本信息 / 参建单位 / 编制信息 / 取费与折扣 + 增值税覆盖 + 表五单项覆盖）。
/// 施工单位 / 设计单位为新增可选字段（旧数据缺省空）；取费标准 = 工程配置方案下拉；
/// 打折选项单选派生自施工折扣（=1 → 不打折），不新增数据字段。
struct ProjectInfoView: View {
    @EnvironmentObject private var appState: AppState
    var project: ProjectRecord
    @State private var discountHint = false
    @State private var lastRate: Double?
    @State private var confirmProfileId: String?
    @State private var showProfileConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 工程名称（列表显示）
                HStack {
                    Text("工程名称（列表显示）").frame(width: 160, alignment: .leading)
                    TextField("工程名称", text: nameBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 16, weight: .bold))
                }
                GroupBox("基本信息") {
                    VStack(alignment: .leading, spacing: 8) {
                        strField("建设项目名称", \.建设项目名称)
                        strField("单项工程名称", \.单项工程名称)
                        strField("单段工程名称", \.单段工程名称)
                        strField("项目编号", \.项目编号)
                        strField("表格编号", \.表格编号)
                        strField("合同编号", \.合同编号)
                        PickerRow("工程类别") {
                            Picker("", selection: strBinding(\.工程类型)) {
                                ForEach(projectTypes, id: \.self) { t in Text(t).tag(t) }
                            }.labelsHidden()
                        }
                        PickerRow("施工距离") {
                            Picker("", selection: strBinding(\.施工距离)) {
                                Text("35KM以内").tag("35KM以内")
                                Text("35KM以上").tag("35KM以上")
                            }.labelsHidden()
                        }
                        HStack {
                            Text("施工实际里程").frame(width: 160, alignment: .leading)
                            OptionalDoubleField(label: "", value: optDblBinding(\.施工实际里程))
                                .textFieldStyle(.roundedBorder)
                        }
                        strField("段落起点", \.段落起点)
                        strField("段落终点", \.段落终点)
                        strField("区县", \.区县)
                        HStack {
                            Text("施工现场海拔").frame(width: 160, alignment: .leading)
                            DoubleField(label: "", value: dblBinding(\.施工现场海拔))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                GroupBox("参建单位") {
                    VStack(alignment: .leading, spacing: 8) {
                        strField("建设单位", \.建设单位)
                        optStrField("施工单位", \.施工单位)
                        optStrField("设计单位", \.设计单位)
                        strField("监理单位", \.监理单位)
                    }
                }
                GroupBox("编制信息") {
                    VStack(alignment: .leading, spacing: 8) {
                        strField("编制", \.编制)
                        strField("审核", \.审核)
                        strField("编制日期", \.编制日期)
                        strField("工程负责人", \.工程负责人)
                    }
                }
                GroupBox("取费与折扣") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("施工折扣").frame(width: 160, alignment: .leading)
                            OptionalDoubleField(label: "", value: optDblBinding(\.施工折扣))
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: project.info.施工折扣) { v in
                                    if let v, v != 1 { lastRate = v }
                                }
                        }
                        PickerRow("冬雨季施工费") {
                            Picker("", selection: strBinding(\.冬雨季施工费)) {
                                Text("Ⅰ类地区").tag("Ⅰ类地区")
                                Text("Ⅱ类地区").tag("Ⅱ类地区")
                                Text("Ⅲ类地区").tag("Ⅲ类地区")
                            }.labelsHidden()
                        }
                        PickerRow("施工调遣分类") {
                            Picker("", selection: strBinding(\.施工调遣分类)) {
                                Text("施工队伍调遣人数(线路、管道）").tag("施工队伍调遣人数(线路、管道）")
                                Text("施工队伍调遣人数(无线、电源、设备）").tag("施工队伍调遣人数(无线、电源、设备）")
                            }.labelsHidden()
                        }
                        HStack {
                            Text("甲供增值税").frame(width: 160, alignment: .leading)
                            OptionalDoubleField(label: "", value: optDblBinding(\.甲供增值税))
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("乙供增值税").frame(width: 160, alignment: .leading)
                            OptionalDoubleField(label: "", value: optDblBinding(\.乙供增值税))
                                .textFieldStyle(.roundedBorder)
                        }
                        PickerRow("取费标准（配置方案）") {
                            Picker("", selection: profileBinding) {
                                ForEach(appState.db.configurationProfiles, id: \.id) { p in
                                    Text(p.name).tag(p.id)
                                }
                            }.labelsHidden()
                        }
                        HStack(alignment: .top) {
                            Text("打折选项").frame(width: 160, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Button {
                                        applyDiscount(option: "discount")
                                    } label: {
                                        Text(discountOption(project.info) == "discount" ? "◉ 打折" : "○ 打折")
                                    }.buttonStyle(.plain)
                                    Button {
                                        applyDiscount(option: "noDiscount")
                                    } label: {
                                        Text(discountOption(project.info) == "noDiscount" ? "◉ 不打折" : "○ 不打折")
                                    }.buttonStyle(.plain)
                                }
                                if discountHint {
                                    Text("请在“施工折扣”输入框输入折扣率（<1，如 0.379）。")
                                        .foregroundColor(.secondary).font(.caption)
                                }
                                Text("施工折扣 1 = 不打折；0.379 = 打 37.9%（主材费、规费不打折）。")
                                    .foregroundColor(.secondary).font(.caption)
                            }
                        }
                    }
                }
                GroupBox("增值税覆盖（本工程）") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("为空 = 用配置值；清空即恢复配置值。优先级：本工程覆盖 > 工程信息 > 配置方案。")
                            .foregroundColor(.secondary).font(.caption)
                        vatOverrideRow("甲供增值税", \.jiaTax, configValue: appState.projectProfile?.rates.vatRates.jiaTax)
                        vatOverrideRow("乙供增值税", \.yiTax, configValue: appState.projectProfile?.rates.vatRates.yiTax)
                        vatOverrideRow("销项税额税率", \.outputTax, configValue: appState.projectProfile?.rates.vatRates.outputTax ?? appState.projectProfile?.rates.vatRates.yiTax)
                    }
                }
                GroupBox("表五单项覆盖（本工程）") {
                    VStack(alignment: .leading, spacing: 8) {
                        if manualFees.isEmpty {
                            Text("当前配置无手动填项。").foregroundColor(.secondary)
                        } else {
                            ForEach(manualFees, id: \.key) { fee in
                                HStack {
                                    Text("\(fee.name)（手动填）").frame(width: 220, alignment: .leading)
                                    OptionalDoubleField(label: "", value: table5AmountBinding(fee.key))
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 140)
                                    Toggle("启用", isOn: table5EnabledBinding(fee.key))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .onAppear {
            if let d = project.info.施工折扣, d != 1 { lastRate = d }
            else { lastRate = appState.projectProfile?.discountRule.discountRate }
        }
        .alert("切换配置方案？", isPresented: $showProfileConfirm) {
            Button("取消", role: .cancel) { confirmProfileId = nil }
            Button("确认切换") {
                if let id = confirmProfileId {
                    appState.switchProjectProfile(project.id, id)
                }
                confirmProfileId = nil
            }
        } message: {
            Text("切换配置将重新计算，结果可能变化。")
        }
    }

    // MARK: - 绑定助手

    private var nameBinding: Binding<String> {
        Binding(
            get: { project.name },
            set: { v in appState.updateProject(project.id) { $0.name = v } }
        )
    }

    private func strBinding(_ kp: WritableKeyPath<ProjectInfo, String>) -> Binding<String> {
        Binding(
            get: { project.info[keyPath: kp] },
            set: { v in appState.updateProject(project.id) { $0.info[keyPath: kp] = v } }
        )
    }

    private func optStrBinding(_ kp: WritableKeyPath<ProjectInfo, String?>) -> Binding<String> {
        Binding(
            get: { project.info[keyPath: kp] ?? "" },
            set: { v in appState.updateProject(project.id) { $0.info[keyPath: kp] = v.isEmpty ? nil : v } }
        )
    }

    private func dblBinding(_ kp: WritableKeyPath<ProjectInfo, Double>) -> Binding<Double> {
        Binding(
            get: { project.info[keyPath: kp] },
            set: { v in appState.updateProject(project.id) { $0.info[keyPath: kp] = v } }
        )
    }

    private func optDblBinding(_ kp: WritableKeyPath<ProjectInfo, Double?>) -> Binding<Double?> {
        Binding(
            get: { project.info[keyPath: kp] },
            set: { v in appState.updateProject(project.id) { $0.info[keyPath: kp] = v } }
        )
    }

    private var profileBinding: Binding<String> {
        Binding(
            get: { project.profileId },
            set: { v in
                if v != project.profileId {
                    confirmProfileId = v
                    showProfileConfirm = true
                }
            }
        )
    }

    private func rateOverrideBinding(_ kp: WritableKeyPath<RateOverrides, Double?>) -> Binding<Double?> {
        Binding(
            get: { project.rateOverrides[keyPath: kp] },
            set: { v in appState.updateProject(project.id) { $0.rateOverrides[keyPath: kp] = v } }
        )
    }

    private func table5AmountBinding(_ key: String) -> Binding<Double?> {
        Binding(
            get: { project.table5Overrides.first { $0.key == key }.flatMap { $0.amount } },
            set: { v in appState.updateProject(project.id) { p in
                if let i = p.table5Overrides.firstIndex(where: { $0.key == key }) {
                    p.table5Overrides[i].amount = v
                } else {
                    p.table5Overrides.append(Table5Override(key: key, enabled: nil, amount: v))
                }
            } }
        )
    }

    private func table5EnabledBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { project.table5Overrides.first { $0.key == key }?.enabled ?? true },
            set: { v in appState.updateProject(project.id) { p in
                if let i = p.table5Overrides.firstIndex(where: { $0.key == key }) {
                    p.table5Overrides[i].enabled = v
                } else {
                    p.table5Overrides.append(Table5Override(key: key, enabled: v, amount: nil))
                }
            } }
        )
    }

    // MARK: - 行组件

    private func strField(_ label: String, _ kp: WritableKeyPath<ProjectInfo, String>) -> some View {
        HStack {
            Text(label).frame(width: 160, alignment: .leading)
            TextField(label, text: strBinding(kp)).textFieldStyle(.roundedBorder)
        }
    }

    private func optStrField(_ label: String, _ kp: WritableKeyPath<ProjectInfo, String?>) -> some View {
        HStack {
            Text(label).frame(width: 160, alignment: .leading)
            TextField(label, text: optStrBinding(kp)).textFieldStyle(.roundedBorder)
        }
    }

    private func PickerRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).frame(width: 160, alignment: .leading)
            content()
        }
    }

    private func vatOverrideRow(_ label: String, _ kp: WritableKeyPath<RateOverrides, Double?>,
                                configValue: Double?) -> some View {
        HStack {
            Text(label).frame(width: 160, alignment: .leading)
            OptionalDoubleField(label: "", value: rateOverrideBinding(kp),
                                prompt: "配置值：\(configValue.map { jsNumberString($0) } ?? "—")")
                .textFieldStyle(.roundedBorder)
        }
    }

    private var manualFees: [Table5Fee] {
        (appState.projectProfile?.table5Fees ?? []).filter { $0.basis == "manual" }
    }

    private func applyDiscount(option: String) {
        let res = applyDiscountOption(project.info, option, lastRate)
        if res.needsInput {
            discountHint = true
            return
        }
        discountHint = false
        appState.updateProject(project.id) { $0.info.施工折扣 = res.info.施工折扣 }
        if let d = res.info.施工折扣, d != 1 { lastRate = d }
    }
}
#endif
