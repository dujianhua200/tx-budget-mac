# 通信概预算 Mac 原生应用 — 架构设计（v1.0.0）

> 2026-10-17，用户拍板：Swift + SwiftUI 重写，Mac 专用。Electron 版（`dujianhua200/tx-budget`，v3.0.0）保持原样、只出 Windows 版；本仓库不碰 Electron 仓库的任何 tag/Release。
> 流程：先架构，再编码，QA 通过后发布。**本环境 Linux 无 Xcode；Swift 编译 + 单元测试走 GitHub CI（每次推送/tag 都跑，CI 绿了才发布）；真机点按走查（界面长什么样、点按顺不顺）仍需用户在 Mac 上做。**
> Electron 侧的权威对照：`~/workspace/budget-app/`（只读对照，永不修改）——引擎 `src/engine/*.mjs`、数据层 `src/lib/*.js`、v3.0 设计 `docs/v2-design.md` §13 与 §13.11、版式 `docs/print-layout-spec.md`、版式 fixture `tests/fixtures/reference-layout.json`、导出实现 `electron/printExport.cjs` + `electron/printLayout.cjs`。

## 1. 目标与非目标

- 目标：真正的原生 Mac 应用（Swift + SwiftUI，原生控件/系统字体/原生菜单/原生窗口行为），功能与 Electron v3.0 定稿一致，数据文件与 Electron v2/v3 互通（直接打开，不迁移）。
- 非目标 / 不动：计算口径（§3）、数据格式（§2，旧文件直接读）、11 张表版式结构（只按结算书版式输出）、Q2/规费等未决口径（规费子项显示保持现状，不擅自改）。
- 部署目标：**macOS 13+，Apple Silicon**（用户是 Apple Silicon Mac）。无签名，DMG 分发，用户右键 → 打开（与 Electron 版一致的交付方式）。
- 构建：SwiftPM（不手写 `.xcodeproj`，避免 pbxproj 手工错误）。`Package.swift`，`swift build` / `swift test`，CI 打包 `.app` + `.dmg`。

## 2. 数据模型（与 Electron JSON 同一格式，Codable 读写）

顶层 Db（Electron `budget-data.json`，见 `electron/main.cjs` + `src/lib/profiles.js`）：

```json
{
"version": 2,
"configurationProfiles": [ ConfigurationProfile],
"projects": [ Project],
"settings": {
"activeProfileId": "prof_default",
"editingProfileId": "prof_default",
"exportSelection": [ "报表封面", "..."],
"defaultInfo": { "工程类型": "通信线路工程", "施工折扣": 1, "...": "..."}
},
"meta": { "saveVersion": 0},
"v1Backup": { "migratedAt": "...", "v1Db": { "..."}}
}
```

- **全部字段可选、读取容错回落**：旧数据缺 `editingProfileId` → 回落 `activeProfileId` → 第一个方案；缺 `exportSelection` → 全选；缺 `lastOpenedAt` → 按原有顺序。不得因缺字段而拒绝打开旧文件；不得擅自改写旧文件结构（不做迁移）。
- `ConfigurationProfile`：`id / name / description / createdAt / updatedAt / source / isBuiltIn` + `libraries`（8 张表：`quotas / shortlist / materials / rules / machinePrices / instrumentPrices / quotaMachines / quotaInstruments`）+ `rates`（`byProjectType`（5 工程类型 × 21 具名费率字段）+ `winterTable`（Ⅰ/Ⅱ/Ⅲ类地区）+ `vatRates`（`jiaTax / yiTax / outputTax / safetyVat`））+ `discountRule`（`discountRate / noDiscountKeys / zeroAfterDiscountKeys / methodText`）+ `table5Fees`（16 项，见 §3）+ `dispatch`（`priceTable / peopleEquip / peopleLine / extraPer200km / extraPeopleStep`）。
- `Project`：`id / name / createdAt / updatedAt / profileId / lastOpenedAt` + `info`（`DEFAULT_INFO` 全字段 + 可选 `施工单位 / 设计单位`）+ `quantities`（`{id, quota, variant, unit, qty, coef}`）+ `materialAdjust`（`{key, delta}`）+ `materialPriceOverrides`（`{key, priceExcl}`）+ `ruleOverrides`（`{ruleId, enabled}`）+ `rateOverrides`（`{discount, jiaTax, yiTax, outputTax, safetyVat, taxRate?}`）+ `table5Overrides`（`{key, enabled?, amount?}`）+ `warningsDismissed`。
- `info` 字段（`DEFAULT_INFO`，见 `src/engine/calc.mjs`）：建设单位、建设项目名称、单项工程名称、合同编号、工程类型、区县、编制日期、施工折扣、段落起点、段落终点、监理单位、表格编号、单段工程名称、项目编号、施工距离（`35KM以内` / `35KM以上`）、施工实际里程、施工调遣分类、施工现场海拔、冬雨季施工费（`Ⅰ/Ⅱ/Ⅲ类地区`）、甲供增值税、乙供增值税、工程负责人、审核、编制。
- JSON 键含中文（`info.建设单位`、`rates.byProjectType` 的中文工程类型键）：Codable 用自定义 `CodingKeys`；数值一律 `Double`（JS number = 双精度）；`winterRate` 的 `null` = “按 winterTable 查表”，与 `0`（显式 0）严格区分，用 `Double?`。
- 导出勾选的 11 张表名（`SHEET_NAMES`，见 `src/lib/v3.js`）：报表封面 / 编制说明 / 建设项目总算表(汇总表) / 工程总表(表一) / 工程费用表(表二) / 工程费用表(表二)折前 / 工程量表(表三)甲 / 机械台班表(表三)乙 / 仪器仪表使用表(表三)丙 / 主要材料表(表四)甲 / 工程其他费用表(表五)甲。

## 3. 计算口径（已定，不许改；移植时逐条对照 `src/engine/*.mjs`）

- 公式链：工程量（填量原量 J）—加权（AB = 量 × 系数）→ 定额（技工/普工）→ 表三甲（工日，含 ≤100×15% / ≤250×10% 调整）→ 表三乙（机械，按定额-机械对）/ 表三丙（仪表，按定额-仪表对）→ 定额主材关联（变体 / 变体* / 通用 / 备选）→ 甲供/乙供/设备主材数量 → 表四甲/表四乙（除税/增值税/含税）→ 表二（取费）→ 表一/表五/汇总表。
- **舍入 `r2`**：`Math.round((x + Number.EPSILON) * 100) / 100`。Swift 等价（金额均为非负）：`floor((x + Double.ulpOfOne) * 100 + 0.5) / 100`。`Double.ulpOfOne == Number.EPSILON == 2.22e-16`。**不许用 `Decimal` / `NSDecimalNumber` 替代**——JS 引擎是二进制浮点逐项舍入，换舍入方式会逐项漂移。
- **表二**：先算 `table2Before`（折前），再 `applyDiscount` 得 `table2After`；表一/表五/汇总表全部以两者为输入。v1 的表一折扣快捷公式已删除（实测错误），不许恢复。
- **打折**（`discount.mjs`）：明细项 ∈ `zeroAfterDiscountKeys` → 折后 = 0（折扣率 < 1 时生效；折扣率 = 1 时不生效）；∈ `noDiscountKeys` → 保持折前值；否则 × 折扣率（逐项 r2）。合计项一律由折后明细加总，不直接乘折扣率。`noDiscountKeys` 中的合计项联动子项（`mainMat` → `jiaMat/yiMat`；`regFee` → `sewageFee/socialFee/housingFee/accidentFee`）。折后销项税额 = `r2((exclTax - jiaMat) × outputTaxRate + jiaMat × jiaTax)`，基数取折后值。默认不打折清单 9 项、折后=0 清单 11 项（见 `discount.mjs` 的两个常量，逐字搬运）。
- **安全生产费**：折前建安工程费除税价 × 2%（财资〔2022〕136 号）+ 增值税 0；费率可配置（表五 `safetyFee` 项的 `rate / vatRate`）；取费基数用折前值，不随打折下调。
- **汇总表**：建安费 = 表一折后建安费 = 表二折后除税价（含主材）；v1 的 ×0.4 公式已删除。
- **表五**：按配置 `table5Fees` 逐项取费，`basis` ∈ {`preDiscountExclTax / afterDiscountExclTax / laborTotal / fixed / manual / surveyKm / sum`}；`enabled=false` 的行不输出、不计入总计；`productionPrepFee`（总计之后单独行）不计入总计；`sum` 行 = 子项和（子项被禁用按 0 计）；单项 `vatRate` 缺失时 `safetyFee` 回落 `rates.vatRates.safetyVat`，其余回落 0。16 项默认表见 `profiles.js` 的 `DEFAULT_TABLE5_FEES()`（逐字搬运，含 `order` 与 `note`）。
- **费率**：具名读取（`libs.rates` 优先；无 `rates` 但有 `rateGrid` 时经 `rateGridToRates` 转换）。`winterRate` 非 null 覆盖值直接用（0 是显式 0），null 则按地区查 `winterTable`。取值优先级：`rateOverrides`（非 null）> `info` > 配置方案 > 兜底（见 `profiles.js` 的 `resolveRates`）。
- **调遣费**：参数来自 `libs.dispatch`，缺失时用 `DEFAULT_DISPATCH()`；`approxLookup` = Excel HLOOKUP 近似匹配（取 ≤ key 的最大阈值）。
- **孤儿工程量行**（定额编号不在库中）、无效行（数量 < 0 / 系数 ≤ 0）：记 `warnings`，不参与计算，不静默丢数。数量为 0 的行不参与计算。备选规则默认不计（`enabled=false` 可开启）。材料数量用原量 J（不加权），工日用加权量 AB。
- **勘察费**：按勘察长度分段（`surveyFeeFor`，逐字搬运）；勘察长度 = 测量类定额（`TXL1-001/002/003`）原量 / 10。
- **规费子项显示**：保持现状（未裁决，不动）。

### 3.1 数值锚点（Swift 测试必须断言，来源：参考结算书实测 + Electron 测试）

| 锚点 | 期望值 | 说明 |
|---|---|---|
| 折后措施费（11 项折后=0 后加总） | 10059.14 | 参考结算书 |
| 折后除税价 | 265267.64（参考 265267.65） | 差 −0.01 为规费舍入，容差内 |
| 安全生产费 | 10250.19 | = 折前建安工程费除税价 512509.64 × 2% |
| 折扣率（参考样本） | 37.9% | 技工 114 元/工日、普工 61 元/工日、辅助材料 0.3% |
| 工程总费用（参考样本） | 275517.84 | 建安 265267.65 + 其他 10250.19 + 增值税 0 |

- Electron 测试里的期望值（`tests/engine.test.mjs / crosscheck.test.mjs / discount.test.mjs`）全部搬运为 Swift 测试；先读 Electron 测试再写 Swift 测试，不许凭印象编期望值。

## 4. 模块划分（SwiftPM）

```
Package.swift // swift-tools 5.9，platforms: [.macOS(.v13)]
Sources/TXBudget/
TXBudgetApp.swift // @main，SwiftUI App 入口
Models/
Database.swift // Db / ConfigurationProfile / Project / Settings（Codable）
LibraryModels.swift // 8 张库表行模型（Codable）
Rates.swift // Rates / VatRates / DiscountRule / Table5Fee / Dispatch（Codable）
Engine/
Rounding.swift // r2
RatesEngine.swift // RATE_FIELD_DEFS / rateGridToRates / winterRateForNamed
Discount.swift // DEFAULT_*_KEYS / DISCOUNT_LINE_DEFS / applyDiscount / renderMethodText
Calc.swift // calcProject（全部公式链 + calcTable5 + surveyFeeFor）
Logic/ // 纯逻辑（对应 Electron src/lib/v3.js，可单测）
FeeTree.swift // FEE_TREE / feeLeavesOf / feeRowsForNode / FEE_RATE_FIELD / feeBasisText
LibraryColumn.swift // LibraryColumn / LibraryColumnKind（库表列定义，Logic 层；Views 只引用，不得移回 Views）
LibraryRowCodec.swift // 库表行编解码（依赖 LibraryColumn）
Table5View.swift // table5Formula / buildTable5ViewRows
ExportSelection.swift // SHEET_NAMES / EXPORT_GROUPS / resolve/toggle
SaveStatus.swift // 保存状态机
ProjectHelpers.swift // sortProjectsRecent / discountOption / applyDiscountOption / quotaSuggestions / editingProfile 解析
Persistence/
DatabaseStore.swift // 文件读写：原子写（tmp + fsync + rename）+ 滚动备份（见 §7）+ savePatch
Export/
XlsxWriter.swift // xlsx ZIP + XML 直写（无第三方库）：inlineStr 文本 / 样式 / 工作表 / 合并 / 页边距 / 页面设置
LayoutSpec.swift // 版式常量（由 Electron reference-layout.json 搬运，见 §6）
PrintExport.swift // 11 张表逐表生成（对照 Electron printExport.cjs + printLayout.cjs）
Views/
ContentView.swift // 侧边栏 + 顶栏 + 底栏 + 导航状态
SidebarView.swift / TopBarView.swift / StatusBarView.swift
ProjectsView.swift // 工程列表（最近置顶 + 搜索）
ProjectInfoView.swift // 工程信息完整表单（分组：基本信息 / 参建单位 / 编制信息 / 取费与折扣）
WorkloadViews.swift // 工作量五标签：表三甲 / 材料汇总 / 安装设备 / 机械 / 仪器仪表
FeeView.swift // 取费左树 + 右表（费率可编辑）
Table5View.swift // 表五（启用勾选 + 公式列）
ExportView.swift // 报表导出（左树勾选 + 导出）
BatchView.swift // 批量生成
LibrariesView.swift // 基础库（10 视图，列定义对照 libraryDefs.js）
ProfilesView.swift // 配置方案（编辑目标与新建默认分离）
SettingsView.swift // 设置（整库备份 / 导入导出）
Tests/TXBudgetTests/
EngineTests.swift / DiscountTests.swift / RatesTests.swift
Table5Tests.swift / FeeTreeTests.swift / ExportSelectionTests.swift
SaveStatusTests.swift / ProjectInfoTests.swift / LayoutCompareTests.swift
XlsxWriterTests.swift / PersistenceTests.swift
PrintExportTests.swift / XlsxTestReader.swift / ReferenceBookFixture.swift
```

- 规则：Engine/Logic 不依赖 SwiftUI（纯逻辑，可单测）；Views 只消费 Engine/Logic/Persistence 的函数。单个视图文件禁止 500+ 行（Electron v3.0 教训），工作量五标签拆独立视图。
- 文件名/类型名用英文，UI 文字用中文（与 Electron 一致）。

## 5. UI 结构（沿用 Electron v3.0 定稿 + 宇翔对照，只学结构交互，不抄宇翔界面素材）

- **导航**：左侧边栏（可收起），一次只显示一个功能。`section`/`tab` 单一事实源。
```
工程（工程列表，最近工程置顶）
当前工程（未选中工程时分组禁用，提示先选工程）
├─ 工程信息
├─ 工作量（分组，五平级标签）
│ ├─ 表三甲（编制录入定额）
│ ├─ 材料汇总（表四甲）
│ ├─ 安装设备（表四甲）
│ ├─ 机械（表三乙）
│ └─ 仪器仪表（表三丙）
├─ 费用（表二）
├─ 表五
└─ 报表导出
批量生成
基础库（定额库 / 材料库 / 仪器仪表库 / 机械库 / 映射关系）
取费规则（费率 / 表五费用 / 打折规则 / 关联规则）
配置方案
设置（整库备份 / 导入导出）
```
- **顶栏**：+ 当前工程名 + 当前方案名 + 保存状态 + 。在基础库/取费规则页时另显示“正在编辑方案：XXX”（`editingProfileId` 对应方案）。
- **底栏**：操作提示随视图变化（工作量：“输定额编号回车下一行”；取费：“点左树切换费用组”；报表导出：“勾选要出的表后点导出”；…见 `v3.js` 的 `statusHintFor`）。
- **工作量五标签**：
- 表三甲：定额编号输入带联想（编号/名称关键字候选，常用短单在前、全库在后，去重，上限 50），输完数量回车直接下一行；右侧常驻小计（建安费/除税价）。
- 材料汇总：甲供 / 乙供 / 设备三组，同导出表四甲结构；数量 = 自动计算 + 手动调整；单价只影响本工程。
- 安装设备：`supply = '设备'` 的行（`result.table4Equip`），不新增字段。
- 机械（表三乙）：由定额—机械映射自动汇总。
- 仪器仪表（表三丙）：**统一大表**，不拆碎。列：定额编号 / 项目名称 / 单位 / 数量 | 仪器仪表名称 | 单位定额值 数量 / 单价 | 合计值 数量 / 合计。
- **取费**：左树（费用层级，由表二费用结构派生，见 `v3.js` 的 `FEE_TREE`）+ 右表（费用名称 / 计算基数 / 费率 / 金额 / 计算式，费率可编辑）。左树层级：建筑安装工程费 → 直接费 → 人工费 / 材料费 / 机械使用费 / 仪器仪表费 → 措施费 → 规费 → 税金 …。
- **工程信息**：完整表单，分组（基本信息 / 参建单位 / 编制信息 / 取费与折扣）。字段：项目编号、工程名称（建设项目名称 / 单项工程名称 / 单段工程名称 三行，不合并）、建设单位、施工单位（新增可选）、设计单位（新增可选）、监理单位、编制人 / 审核人、编制日期、工程类别、取费标准（配置方案下拉，切换工程所用方案）、折扣率、打折选项单选（派生：施工折扣 = 1 → 不打折；选“不打折”置施工折扣 = 1，选“打折”恢复上次折扣率）。
- **表五**：完整表格，列：费用名称 / 计算基数 / 费率 / 金额 / 公式 / 启用勾选。公式列由 `basis + rate` 生成（manual → “手动输入”；安全生产费 → “折前建安工程费除税价 × {rate}%”）。启用沿用 `table5Overrides.enabled`。
- **配置方案**：每行（置 `editingProfileId` 并跳基础库页）/（只置 `activeProfileId`，只影响新建工程）/ 复制 / 导出 / 删除。编辑目标与新建默认彻底分离。
- **导出**：左树勾选 11 张表（分组：封面与说明 / 汇总与总表 / 费用表（表二）/ 工程量与台班（表三）/ 材料（表四）/ 其他费用（表五）），默认全选，选择存 `settings.exportSelection`。
- **保存**：显式按钮，状态机 `dirty`（● 未保存）→ `saving`（保存中…）→ `saved`（✓ 已保存 HH:MM）；800ms 自动保存保留当兜底，状态写“已自动保存 HH:MM”；关闭前有未保存仍提示。保存仍走增量补丁语义（见 §7），不改存储格式。
- **界面宽松**：一次一个功能，行高加大，关键数字加大字。不抄宇翔图标/图片/文案/配色/品牌插图；不做右键菜单；不做 `.mqf` 文件型模型。

## 6. xlsx 导出（和结算书一模一样，不引第三方库，直接写 ZIP + XML）

- 实现：`XlsxWriter.swift`（ZIP + XML 直写：`[Content_Types].xml` / `_rels/.rels` / `xl/workbook.xml` / `xl/_rels/workbook.xml.rels` / `xl/styles.xml` / `xl/worksheets/sheetN.xml`）。文本用 inlineStr（无 `sharedStrings.xml`）。ZIP 用 `Compression` 框架（`compression_encode_buffer`，zlib/deflate）或手写 stored（不压缩）条目——**优先手写 stored 条目**（零依赖、最易验证正确；文件稍大可接受）。CRC32 按 IEEE 多项式实现并单测。
- 版式规格：以 Electron `docs/print-layout-spec.md` + `tests/fixtures/reference-layout.json` 为准（列宽 / 行高 / 合并 / 字体 / 页边距 / 页面设置）。**注意 §13.6 的 13 处列宽修正已包含在 fixture 中**（汇总表 E/F/H、表一 E、表三甲 E/H、表三乙 H、表三丙 H/J、表四甲 F、表五甲 F/G）；移植时以 fixture 数值为准，不许用旧的默认填充值 9.13671875。另有表五表头合并区 `C3:D4`（与参考一致）。
- 全局版式：A4（paperSize 9）、横向、缩放 100%、`fitToPage` 关闭；无打印区域 / 无重复标题行 / 无 Excel 页眉页脚（表头、表尾、页码全部是单元格内文本）；标题行 18pt 加粗居中（封面 36pt）；信息行 9pt；表尾 10pt；数据行高 16.55pt 为主；边框：表头行上下 medium，数据行 thin；页码为单元格内文字 `第X页 共Y页`，逐页生成；表尾在固定行，数据区与表尾之间用空白行填充；唯一手动分页符在表三甲第 29 行之后。
- 措辞：与结算书逐字一致，含折行位置：`不需要安装\n的设备、工\n器具费`、`危险作业意外伤害保险\n费`、`需要安装\n的设备费`、`建筑安装\n工程费`。标题用“预算”口径字样（不照抄参考文件的“结算”字样）。
- 字体：各表表名标题 + 编制说明 → **Noto Sans CJK SC**；其余宋体/黑体照旧（数据 宋体 10、表尾 宋体 10、封面 宋体 36 bold 等）。数值单元格写数值型（不许写文本型字符串）。
- 逐表生成：对照 Electron `electron/printExport.cjs` + `electron/printLayout.cjs` 逐表搬运（11 张表：封面 / 编制说明 / 汇总表 / 表一 / 表二折后 / 表二折前 / 表三甲 / 表三乙 / 表三丙 / 表四甲 / 表五甲）。表二双表版式一致，仅“依据和计算方法”列与数值不同；折后表计算方法列体现打折关系（`技工总工日X114X37.9%`、`人工费X1.5%/37.9%`、`(1-4之和)/37.9%`）。
- **定额项目显示名（v1.0.1 修，A1）**：`displayName(quota, variant)`——variant 是**完整变体项目名称**（如“挂钩法架设架空光缆 平原 6芯”），非空时直接用 variant（替换定额库名），为空时用定额库名。**不许拼接** `quota.name + variant`（定额库名含“36 芯以下”时会与 variant 重复）。Electron `printExport.cjs:615-617` 有同一行拼接 bug（不在原生修复范围，原生与 Electron 在此处有意不同）。
- **Normal 字体与分页（v1.0.1 修，A2）**：styles.xml 的 font[0]（Normal）= **Arial 10**（结算书口径；xlsx 列宽单位按 Normal 字体度量，Calibri 11 会使打印每表多出一页）；`<sheetPr><pageSetUpPr fitToPage="false"/></sheetPr>`（fitToPage 是 pageSetUpPr 的属性，pageSetup 元素不许带它）；`dimension` 按实际写入行列算（不许用版式 maxRow 虚报）。
- 测试：`LayoutCompareTests`（逐项比对版式 fixture：列宽 / 行高 / 字体 / 合并 / 页边距，差一处即失败）+ `XlsxWriterTests`（ZIP 结构、CRC32、inlineStr 转义、样式去重）+ `PrintExportTests`（逐表值断言 + 子集导出 + 有 profile 时重分组）+ LibreOffice 往返 0 不一致（**本地手动验**：CI 的 macOS runner 无 LibreOffice，CI 内用解包数值断言替代）。

## 7. 持久化（与 Electron 同一文件，互通）

- **同一路径**：Electron 的 `userData`（bundle id `com.zhang.txbudget`，productName `通信概预算`）→ macOS 下为 `~/Library/Application Support/通信概预算/budget-data.json`。**原生版用同一 bundle id `com.zhang.txbudget` 与同一数据路径**，v2/v3 数据文件直接打开；用户在 Mac 上用原生版替换 Electron 版（Electron 版只留 Windows）。
- **原子写**：写临时文件 → fsync → POSIX `rename(2)` 覆盖（见 `electron/dbStore.cjs` 的 `atomicWriteFileSync`）。**不许用“先删目标再移动”**（中间有文件缺失窗口）；`FileManager.replaceItemAt` 在 Linux corelibs 上不可靠（实测报“文件不存在”），故直接用 `rename(2)`，两平台同一代码路径。
- **备份**：滚动备份 `budget-data.backup-<戳>.json`（保留 5 份，最小间隔 1 小时，重大操作强制备份）；v1 迁移快照 `budget-data.v1-backup-*.json` 永不自动删除；滚动清理只碰 `budget-data.backup-*`。
- **增量保存语义**：沿用 `applySavePatch` 白名单（`profile / project / configurationProfiles / projects / settings / settingsPatch`）+ `baseVersion` 冲突检测（`meta.saveVersion` 不匹配时返回冲突，不改数据）。保存队列节流 800ms（自动保存兜底）+ 显式保存按钮排空队列。
- **保存失败与加载失败（v1.0.1 修）**：保存失败后状态仍为 dirty（显示“● 未保存”，可重试），不许误报“✓ 已保存”；加载失败时阻塞自动保存（防空白库覆盖原文件），显式保存 / 成功重载时解除。
- **退出落盘（v1.0.1 修，与本节原“关闭前有未保存仍提示”有偏差）**：退出时同步 flush（`NSApplication.willTerminateNotification` 观察者 + 工具栏“退出”按钮先 flush 再 terminate），保证 800ms 窗口内的编辑不丢；不弹关闭提示——自动保存 + 退出 flush 后退出时恒为已保存，弹窗纯属干扰。**该偏差待用户确认是否仍要弹窗**。
- **导入/导出**：配置方案文件（`{profileFormat: 1, exportedAt, profile}`，导入校验格式 + 必备字段，成功赋新 id、`source='imported'`）；整库备份/导入导出（设置页）。

## 8. CI + 发布（v1.0.0）

- 工作流 `.github/workflows/build.yml`：**每次推送（main 分支）+ tag（`v*`）都跑**，另保留 `workflow_dispatch` 手动触发。**CI 绿了才发布**。
- 每次推送都跑编译 + 测试；打 tag 时另出 Release。
- 步骤：`macos-15` runner → `swift test` → `swift build -c release` → `scripts/bundle.sh`（组装 `.app`：`Contents/MacOS/TXBudget` + `Info.plist`（bundle id `com.zhang.txbudget`，`LSMinimumSystemVersion 13.0`，`CFBundleName 通信概预算`）→ `hdiutil` 生成 `.dmg`）→ 上传 artifact；tag 触发时创建 Release（`softprops/action-gh-release`），资产 `tx-budget-mac-<version>-mac-arm64.dmg`（无签名）。
- 发布：QA 通过后打 tag `v1.0.0`，Release 出 macOS `.dmg`。**不要动 Electron 仓库的任何 tag/Release。**
- 验证：每次阶段交付后由推送自动触发 CI（编译 + 测试）；发布前用 tag 触发完整流程并核实 Release 资产。
- **验证分工**：GitHub CI 验的是“能编过 + 逻辑/导出正确”（xcodebuild 编译 + XCTest 单元测试：计算引擎、导出布局对比等）；真机点按走查（界面长什么样、点按顺不顺）仍需用户在 Mac 上做。“编不了”不等于“没法验”——CI 覆盖编译与逻辑验证。

## 9. 阶段计划与验收

| 阶段 | 内容 | 验收 |
|---|---|---|
| 1 | 架构（本文档）+ 仓库 + CI 骨架 | 本文档合并；CI 推送触发通过（骨架编译 + 占位测试） |
| 2 | 计算引擎移植（Engine + Logic）+ Swift 测试 | 引擎测试全过，含 §3.1 锚点；与 Electron 测试期望值逐项对齐 |
| 3 | 数据模型（Codable）+ 持久化 + SwiftUI 界面 | 能读写 Electron v2/v3 真实数据文件（用 Electron 测试夹具验证）；原子写 + 备份单测；CI 编译通过；用户真机点按走查（侧边栏、保存、配置方案、工作量五标签、导出勾选） |
| 4 | xlsx 导出 + `LibraryColumn` 结构小修 | 布局对比测试全过；LibreOffice 往返 0 不一致（本地手动验）；导出与结算书逐项对齐；`LibraryColumn` / `LibraryColumnKind` 移入 Logic，Views 只留引用 |
| 5 | 发布 v1.0.0 | tag → CI → Release 资产核实 |
| 6 | v1.0.1：全面自查 + 修到交付标准 | A1 定额名重复（displayName 用 variant 替换）/ A2 打印超范围（Normal Arial 10 + pageSetUpPr + dimension 按实际行列）/ P0 批量导出真实实现 / P1 被占用方案删除自选切换目标 / P1 保存安全（失败保持 dirty、加载失败阻塞自动保存、rename 原子写、退出 flush）；Swift 测试 108 过 / LO 渲染最小工程 11 页、整本 12 页（表三甲 2 页）、0 不一致 |

- 每个阶段交付时附：改了什么、测试通过数、提交 SHA、CI 状态。最终汇报同前。
- **实机点按走查由用户做**（CI 验的是能编过 + 逻辑/导出正确；界面长什么样、点按顺不顺仍需用户真机验收——如实说明，不许声称本地验过界面）。
