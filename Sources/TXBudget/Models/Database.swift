import Foundation

/// 顶层数据文件（Electron `budget-data.json` 同一格式）。
/// 解码全部容错：缺字段回落默认值，不得因缺字段拒绝打开旧文件；不做迁移，不改写旧文件结构。

public struct MetaRecord: Equatable, Codable {
    public var saveVersion: Int
    public init(saveVersion: Int = 0) { self.saveVersion = saveVersion }
    enum CodingKeys: String, CodingKey { case saveVersion }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        saveVersion = (try? c.decodeIfPresent(Int.self, forKey: .saveVersion)) ?? 0
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(saveVersion, forKey: .saveVersion)
    }
}

/// settings：defaultInfo 以 ProjectInfo 容错解码（Electron 首次写盘时即为完整 DEFAULT_INFO 形状）；
/// company 原样透传（Electron settings.company）。
public struct SettingsRecord: Equatable, Codable {
    public var activeProfileId: String
    public var editingProfileId: String?
    public var exportSelection: [String]?
    public var defaultInfo: ProjectInfo
    public var company: String?
    public init(activeProfileId: String = "prof_default", editingProfileId: String? = nil,
                exportSelection: [String]? = nil, defaultInfo: ProjectInfo = ProjectInfo(),
                company: String? = nil) {
        self.activeProfileId = activeProfileId; self.editingProfileId = editingProfileId
        self.exportSelection = exportSelection; self.defaultInfo = defaultInfo; self.company = company
    }
    enum CodingKeys: String, CodingKey {
        case activeProfileId, editingProfileId, exportSelection, defaultInfo, company
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activeProfileId = c.decodeLenientString(forKey: .activeProfileId, default: "prof_default")
        editingProfileId = c.decodeLenientStringOptional(forKey: .editingProfileId)
        exportSelection = try? c.decodeIfPresent([String].self, forKey: .exportSelection)
        defaultInfo = (try? c.decodeIfPresent(ProjectInfo.self, forKey: .defaultInfo)) ?? ProjectInfo()
        company = c.decodeLenientStringOptional(forKey: .company)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(activeProfileId, forKey: .activeProfileId)
        try c.encodeIfPresent(editingProfileId, forKey: .editingProfileId)
        try c.encodeIfPresent(exportSelection, forKey: .exportSelection)
        try c.encode(defaultInfo, forKey: .defaultInfo)
        try c.encodeIfPresent(company, forKey: .company)
    }
}

/// 配置方案（Electron `configurationProfiles[]` 一项）。
public struct ConfigurationProfile: Equatable, Codable {
    public var id: String
    public var name: String
    public var description: String
    public var createdAt: String
    public var updatedAt: String
    public var source: String
    public var isBuiltIn: Bool
    public var libraries: LibrarySet
    public var rates: RatesRecord
    public var discountRule: DiscountRuleRecord
    public var table5Fees: [Table5Fee]
    public var dispatch: DispatchParams
    public init(id: String = "", name: String = "", description: String = "",
                createdAt: String = "", updatedAt: String = "", source: String = "",
                isBuiltIn: Bool = false, libraries: LibrarySet = LibrarySet(),
                rates: RatesRecord = RatesRecord(), discountRule: DiscountRuleRecord = DiscountRuleRecord(),
                table5Fees: [Table5Fee] = [], dispatch: DispatchParams = DispatchParams()) {
        self.id = id; self.name = name; self.description = description
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.source = source
        self.isBuiltIn = isBuiltIn; self.libraries = libraries; self.rates = rates
        self.discountRule = discountRule; self.table5Fees = table5Fees; self.dispatch = dispatch
    }
    enum CodingKeys: String, CodingKey {
        case id, name, description, createdAt, updatedAt, source, isBuiltIn,
             libraries, rates, discountRule, table5Fees, dispatch
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientString(forKey: .id)
        name = c.decodeLenientString(forKey: .name)
        description = c.decodeLenientString(forKey: .description)
        createdAt = c.decodeLenientString(forKey: .createdAt)
        updatedAt = c.decodeLenientString(forKey: .updatedAt)
        source = c.decodeLenientString(forKey: .source)
        isBuiltIn = c.decodeLenientBool(forKey: .isBuiltIn, default: false)
        libraries = (try? c.decodeIfPresent(LibrarySet.self, forKey: .libraries)) ?? LibrarySet()
        rates = (try? c.decodeIfPresent(RatesRecord.self, forKey: .rates)) ?? RatesRecord()
        discountRule = (try? c.decodeIfPresent(DiscountRuleRecord.self, forKey: .discountRule)) ?? DiscountRuleRecord()
        table5Fees = (try? c.decodeIfPresent([Table5Fee].self, forKey: .table5Fees)) ?? []
        dispatch = (try? c.decodeIfPresent(DispatchParams.self, forKey: .dispatch)) ?? DispatchParams()
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(source, forKey: .source)
        try c.encode(isBuiltIn, forKey: .isBuiltIn)
        try c.encode(libraries, forKey: .libraries)
        try c.encode(rates, forKey: .rates)
        try c.encode(discountRule, forKey: .discountRule)
        try c.encode(table5Fees, forKey: .table5Fees)
        try c.encode(dispatch, forKey: .dispatch)
    }
}

/// 工程记录（Electron `projects[]` 一项；扁平结构，与 Electron JSON 键一一对应）。
public struct ProjectRecord: Equatable, Codable {
    public var id: String
    public var name: String
    public var createdAt: String
    public var updatedAt: String
    public var profileId: String
    public var lastOpenedAt: Double?
    public var info: ProjectInfo
    public var quantities: [QuantityRow]
    public var materialAdjust: [MaterialAdjust]
    public var materialPriceOverrides: [MaterialPriceOverride]
    public var ruleOverrides: [RuleOverride]
    public var rateOverrides: RateOverrides
    public var table5Overrides: [Table5Override]
    public var warningsDismissed: [String]
    public init(id: String = "", name: String = "", createdAt: String = "", updatedAt: String = "",
                profileId: String = "", lastOpenedAt: Double? = nil, info: ProjectInfo = ProjectInfo(),
                quantities: [QuantityRow] = [], materialAdjust: [MaterialAdjust] = [],
                materialPriceOverrides: [MaterialPriceOverride] = [], ruleOverrides: [RuleOverride] = [],
                rateOverrides: RateOverrides = RateOverrides(), table5Overrides: [Table5Override] = [],
                warningsDismissed: [String] = []) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.updatedAt = updatedAt
        self.profileId = profileId; self.lastOpenedAt = lastOpenedAt; self.info = info
        self.quantities = quantities; self.materialAdjust = materialAdjust
        self.materialPriceOverrides = materialPriceOverrides; self.ruleOverrides = ruleOverrides
        self.rateOverrides = rateOverrides; self.table5Overrides = table5Overrides
        self.warningsDismissed = warningsDismissed
    }
    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, updatedAt, profileId, lastOpenedAt, info, quantities,
             materialAdjust, materialPriceOverrides, ruleOverrides, rateOverrides,
             table5Overrides, warningsDismissed
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.decodeLenientString(forKey: .id)
        name = c.decodeLenientString(forKey: .name)
        createdAt = c.decodeLenientString(forKey: .createdAt)
        updatedAt = c.decodeLenientString(forKey: .updatedAt)
        profileId = c.decodeLenientString(forKey: .profileId)
        lastOpenedAt = c.decodeLenientDouble(forKey: .lastOpenedAt)
        info = (try? c.decodeIfPresent(ProjectInfo.self, forKey: .info)) ?? ProjectInfo()
        quantities = (try? c.decodeIfPresent([QuantityRow].self, forKey: .quantities)) ?? []
        materialAdjust = (try? c.decodeIfPresent([MaterialAdjust].self, forKey: .materialAdjust)) ?? []
        materialPriceOverrides = (try? c.decodeIfPresent([MaterialPriceOverride].self, forKey: .materialPriceOverrides)) ?? []
        ruleOverrides = (try? c.decodeIfPresent([RuleOverride].self, forKey: .ruleOverrides)) ?? []
        rateOverrides = (try? c.decodeIfPresent(RateOverrides.self, forKey: .rateOverrides)) ?? RateOverrides()
        table5Overrides = (try? c.decodeIfPresent([Table5Override].self, forKey: .table5Overrides)) ?? []
        warningsDismissed = (try? c.decodeIfPresent([String].self, forKey: .warningsDismissed)) ?? []
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(profileId, forKey: .profileId)
        try c.encodeIfPresent(lastOpenedAt, forKey: .lastOpenedAt)
        try c.encode(info, forKey: .info)
        try c.encode(quantities, forKey: .quantities)
        try c.encode(materialAdjust, forKey: .materialAdjust)
        try c.encode(materialPriceOverrides, forKey: .materialPriceOverrides)
        try c.encode(ruleOverrides, forKey: .ruleOverrides)
        try c.encode(rateOverrides, forKey: .rateOverrides)
        try c.encode(table5Overrides, forKey: .table5Overrides)
        try c.encode(warningsDismissed, forKey: .warningsDismissed)
    }

    /// 转引擎 Project（calcProject 输入）。
    public func toEngineProject() -> Project {
        Project(info: info, quantities: quantities, materialAdjust: materialAdjust,
                materialPriceOverrides: materialPriceOverrides, ruleOverrides: ruleOverrides,
                rateOverrides: rateOverrides, table5Overrides: table5Overrides)
    }
}

public struct DbFile: Equatable, Codable {
    public var version: Int
    public var configurationProfiles: [ConfigurationProfile]
    public var projects: [ProjectRecord]
    public var settings: SettingsRecord
    public var meta: MetaRecord
    /// v1 迁移快照（原样透传，解码后原样再编码，不丢数据；无则为 .null）。
    public var v1Backup: JSONValue
    public init(version: Int = 2, configurationProfiles: [ConfigurationProfile] = [],
                projects: [ProjectRecord] = [], settings: SettingsRecord = SettingsRecord(),
                meta: MetaRecord = MetaRecord(), v1Backup: JSONValue = .null) {
        self.version = version; self.configurationProfiles = configurationProfiles
        self.projects = projects; self.settings = settings; self.meta = meta; self.v1Backup = v1Backup
    }
    enum CodingKeys: String, CodingKey {
        case version, configurationProfiles, projects, settings, meta, v1Backup
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? 2
        configurationProfiles = (try? c.decodeIfPresent([ConfigurationProfile].self, forKey: .configurationProfiles)) ?? []
        projects = (try? c.decodeIfPresent([ProjectRecord].self, forKey: .projects)) ?? []
        settings = (try? c.decodeIfPresent(SettingsRecord.self, forKey: .settings)) ?? SettingsRecord()
        meta = (try? c.decodeIfPresent(MetaRecord.self, forKey: .meta)) ?? MetaRecord()
        v1Backup = (try? c.decodeIfPresent(JSONValue.self, forKey: .v1Backup)) ?? .null
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(configurationProfiles, forKey: .configurationProfiles)
        try c.encode(projects, forKey: .projects)
        try c.encode(settings, forKey: .settings)
        try c.encode(meta, forKey: .meta)
        try c.encode(v1Backup, forKey: .v1Backup)
    }
}
