import Foundation

/// 方案 → 引擎 libs（对照 Electron `profileToLibs`）。rateGrid 兼容垫片不再需要：引擎直接读具名 rates。

public func profileToLibs(_ profile: ConfigurationProfile?) -> Libs? {
    guard let profile else { return nil }
    return Libs(
        quotas: profile.libraries.quotas.map { $0.toEngine() },
        materials: profile.libraries.materials.map { $0.toEngine() },
        rules: profile.libraries.rules.map { $0.toEngine() },
        rates: profile.rates.toEngine(),
        winterTable: profile.rates.winterTable,
        rateGrid: nil,
        discountRule: profile.discountRule.toEngine(),
        table5Fees: profile.table5Fees,
        dispatch: profile.dispatch,
        machinePrices: profile.libraries.machinePrices.map { $0.toEngine() },
        instrumentPrices: profile.libraries.instrumentPrices.map { $0.toEngine() },
        quotaMachines: profile.libraries.quotaMachines.map { $0.toEngine() },
        quotaInstruments: profile.libraries.quotaInstruments.map { $0.toEngine() }
    )
}

public func getProfile(_ db: DbFile, _ profileId: String?) -> ConfigurationProfile? {
    guard let profileId else { return nil }
    return db.configurationProfiles.first { $0.id == profileId }
}

public func activeProfile(_ db: DbFile) -> ConfigurationProfile? {
    getProfile(db, db.settings.activeProfileId) ?? db.configurationProfiles.first
}

/// 编辑目标方案 id：editingProfileId 命中失败 → 回落 activeProfileId → 第一个方案。
public func resolveEditingProfileId(_ db: DbFile) -> String? {
    let ids = Set(db.configurationProfiles.map { $0.id })
    if let editing = db.settings.editingProfileId, ids.contains(editing) { return editing }
    if ids.contains(db.settings.activeProfileId) { return db.settings.activeProfileId }
    return db.configurationProfiles.first?.id
}

public func resolveEditingProfile(_ db: DbFile) -> ConfigurationProfile? {
    guard let id = resolveEditingProfileId(db) else { return nil }
    return getProfile(db, id)
}

/// 计算一个工程（对照 Electron `calcFor`）：按工程 profileId 取方案，回落激活方案。
public func calcFor(_ db: DbFile, _ project: ProjectRecord) -> CalcResult? {
    guard let profile = getProfile(db, project.profileId) ?? activeProfile(db),
          let libs = profileToLibs(profile) else { return nil }
    return calcProject(project.toEngineProject(), libs)
}

/// 空白方案（对照 Electron `createProfile` 无种子分支）。
public func createProfile(name: String) -> ConfigurationProfile {
    let ts = nowISO()
    return ConfigurationProfile(
        id: newUID(), name: name, description: "", createdAt: ts, updatedAt: ts,
        source: "user-created", isBuiltIn: false, libraries: LibrarySet(),
        rates: RatesRecord(byProjectType: [:],
                           winterTable: ["Ⅰ类地区": 0.036, "Ⅱ类地区": 0.025, "Ⅲ类地区": 0.018],
                           vatRates: VatRates(jiaTax: 0.13, yiTax: 0.09, outputTax: 0.09, safetyVat: 0)),
        discountRule: DiscountRuleRecord(discountRate: 1,
                                         noDiscountKeys: defaultNoDiscountKeys,
                                         zeroAfterDiscountKeys: defaultZeroAfterDiscountKeys,
                                         methodText: ["discounted": "{base}X{rate}%", "restored": "{base}/{rate}%"]),
        table5Fees: defaultTable5Fees(),
        dispatch: defaultDispatch()
    )
}

/// 复制方案：新 id、名 +“（副本）”、isBuiltIn=false（对照 Electron `duplicateProfile`）。
public func duplicateProfile(_ profile: ConfigurationProfile) -> ConfigurationProfile {
    var copy = profile
    copy.id = newUID()
    copy.name = "\(profile.name)（副本）"
    copy.source = "user-created"
    copy.isBuiltIn = false
    let ts = nowISO()
    copy.createdAt = ts
    copy.updatedAt = ts
    return copy
}
