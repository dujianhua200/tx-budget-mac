# 滑洲智算 v2.0.0 — 界面与交互架构（全权重做）

> 2026-10-22，用户评价 v1.0.2“界面太粗糙，压根就不像软件，操作逻辑很乱，简直无法使用”，
> 明确授权：界面与操作逻辑按正规软件公司的标准由开发方全权设计，不再按此前界面要求
> （宇翔式侧边栏一次一个功能等）死守。**本文件是 v2.0.0 的界面架构，先于代码落地。**
> v1 架构（数据/引擎/导出/持久化/打包）继续有效，见 `docs/native-design.md`；
> 本文件只覆盖界面层（Views）与为界面新增的纯逻辑（Logic），与 v1 文档冲突处以本文件为准。

## 0. 不许动（正确性资产）

- 计算引擎（Engine/）与口径一字不动：安全生产费 2%、11 项措施费折后=0、表二双版本、
  汇总表口径等全部保持；136 个现有测试必须全绿（只增不减）。
- 数据格式不变（Electron JSON 兼容，零迁移）；xlsx 导出与结算书逐格一致不变
  （Arial 10、fitToPage、定额 displayName 规则）。
- 打包约定不变：DMG 名 `huazhou-zhisuan-<版本>-mac-arm64.dmg`、ad-hoc 签名、
  卷名/.app/窗口标题中文“滑洲智算”、Bundle ID 与数据目录名不变。

## 1. 设计目标

- **像正规软件**：启动有“工作台”感（工程列表），进入工程有工作区（导航 + 内容 + 状态栏），
  数字有层级（总造价常驻可见），表格是专业表格（冻结表头/斑马纹/合计行/千分位），
  每个页面有明确标题、说明与空状态引导。
- **操作逻辑收敛**：用户只做“录工程量”一个核心动作，其余（表三/表四/费用）全部自动联动预览；
  问题集中在“校验中心”一处看完；导出前有预览。
- **不丢 v1 功能**：v1 全部功能（批量、导入导出、配置方案编辑目标/新建默认分离、
  费率编辑、表五覆盖等）在新界面里都有落点，见 §7 页面映射。

## 2. 信息架构

```
窗口（默认 1280×800，最小 1080×680）
├─ 工程列表（启动页，nav = .projectList）
│   ├─ 标题区：滑洲智算 + 副题 + 搜索 + [新建工程（向导）] [批量生成]
│   ├─ 卡片模式：最近工程卡片（工程名/方案/总造价/工日/更新时间），点击打开
│   └─ 列表模式：多选表格（批量导出/批量删除），与 v1 行为一致
└─ 工程工作区（打开工程后，NavigationSplitView）
    ├─ 工具栏：[← 返回工程列表] 工程名（标题） … [定额搜索] [导入] [导出] [保存 + 状态]
    ├─ 侧边栏（系统材质，SF Symbols 图标）
    │   ├─ 工程：概览 / 工程信息 / 工作量 / 费用 / 报表导出
    │   ├─ 资料库：定额库 / 常用短单 / 材料库 / 机械库 / 仪器仪表库 /
    │   │          定额—材料映射 / 关联规则（备选）/ 定额—机械映射 / 定额—仪表映射 /
    │   │          取费规则（费率/表五费用/打折规则/关联规则）/ 配置方案
    │   └─ 系统：校验中心（问题数徽标）/ 批量生成 / 设置
    │       侧边栏底部：资料库方案名（资料库/取费规则的编辑目标；v2.0.1 起措辞）
    ├─ 内容区：当前页面
    └─ 底部状态栏（常驻）：校验问题数（点击跳校验中心）· 总造价（大数字）· 工日合计
                          · 保存状态 · 最后修改时间 · 操作提示
```

导航状态单一事实源仍为 `AppState.nav: NavDestination`（Logic/Navigation.swift）。
v2 枚举：`projectList / overview / projectInfo / workload / fees / export /
libraries(LibraryViewKey) / feeRules(FeeRuleTab) / profiles / validation / batch / settings`。
旧 `CurrentTab` 与 `.current(...)`、`.projects` 废弃（映射见 §7）。

## 3. 页面清单

| 页面 | nav | 内容 |
|---|---|---|
| 工程列表 | projectList | 最近工程卡片/列表、搜索、新建向导入口、批量入口 |
| 概览 | overview | KPI 卡片×4（总造价/建安费除税/设备材料费除税/总工日）、费用构成图（Swift Charts 水平条形：建安/设备/其他，含税口径）、数据问题前 5 条、快捷操作、工程摘要 |
| 工程信息 | projectInfo | 卡片式分组表单：基本信息/参建单位/编制信息/取费与折扣/增值税覆盖/表五单项覆盖（逻辑与 v1 完全一致，仅呈现重组） |
| 工作量 | workload | 主从布局：左=工程量清单（ProTable：搜索/排序/双击编辑数量系数/删除确认/孤儿行处理），顶部定额搜索添加栏；右=自动结果预览标签（表三甲/表三乙/表三丙/材料汇总/安装设备，只读、与导出同源） |
| 费用 | fees | 标签：表一（报表式总表预览：折前/折后/设备/其他/总计）/ 表二（折前=左树+右表费率可编辑，同 v1；折后=只读，金额取 table2After，计算式为折前口径并注明）/ 表五（同 v1 表五表，含启用与手动覆盖） |
| 报表导出 | export | 左：11 张表勾选（分组，同 v1 逻辑）；右：每张已勾选表的迷你预览（关键数字行，Logic 生成）+ 导出按钮 + 本次运行导出记录 |
| 资料库各页 | libraries(key) | 统一页头（“当前方案”下拉选择器横幅，v2.0.1 起）+ Excel 导入/导出 + ProTable（搜索/新增/导入/导出/批量删除/复制行） |
| 取费规则 | feeRules(tab) | 页头横幅同上；费率=左树+右表（同 v1）；表五费用/关联规则=ProTable；打折规则同 v1 呈现微调 |
| 配置方案 | profiles | 卡片列表：状态徽标（新建默认；v2.0.1 起删除“正在编辑”徽标，见 §11）、工程数、来源；操作：编辑内容/设为默认/复制/导出/重命名/删除（占用时 sheet 自选切换目标，逻辑同 v1）；顶部新建（名称+模板）/导入/整库备份 |
| 校验中心 | validation | 全部数据问题按严重度分组（错误/警告/提示）：引擎 warnings + 材料未建档 + 表五手动项未填 + 工程信息缺项 + 未录工程量；每条可点击定位到目标页面；无问题时显示通过状态 |
| 批量生成 | batch | v1 五个分组改为卡片呈现，逻辑不变 |
| 设置 | settings | 卡片呈现：整库备份/导入方案/导出方案 + 数据文件说明，逻辑不变 |

## 4. 统一专业表格组件 ProTable（Views/ProTable.swift）

供工作量与全部资料库共用（字典行 `[String: String]`，列定义复用 `LibraryColumn`）：

- 冻结表头（表头在滚动区之外，恒定可见）+ 点击列头排序（▲/▼，数字列按数值、文本列按字面，稳定排序；排序/过滤纯逻辑在 `Logic/TableData.swift`，可单测）。
- 斑马纹、行号列、行高 28、数字列右对齐 + 千分位由数据侧格式化、等宽数字（monospacedDigit）。
- 合计行（可选列集合）：加粗 + 顶边框，对全部行（非过滤子集）求和。
- 行内编辑：双击单元格进入编辑（文本/数字），回车提交并跳下一行同列，Esc 取消；
  select/checkbox 即时提交。只读列由 `readOnlyKeys` 指定；整体只读模式 `readOnly`（预览用）。
- 键盘：↑↓ 移动选择（List 原生）、Enter 编辑选中行首个可编辑列（本地事件监视，
  文本编辑中不拦截）、Delete 删除选中（`.onDeleteCommand` + 工具按钮），删除统一弹确认。
- 右键菜单：编辑 / 复制行（可选回调）/ 删除（确认）。
- 顶部：搜索过滤（任意列包含，大小写不敏感）、计数（显示 X / 共 N 条）、新增/删除按钮。
- 空状态：图标 + 一句话 + 主按钮（如“新增一行”）。

## 5. 视觉规范

- 系统字体层级：页面标题 `.title2` 加粗；卡片标题 `.headline`；正文 `.body`；
  说明 `.caption` 次级色；KPI 大数字 `.title` 等宽数字。
- 8pt 间距网格：页面内边距 20，卡片间距 16，卡片内边距 14。
- 卡片：圆角 10、细边框（primary 8%）、背景 `controlBackgroundColor`（深色模式自动适配）。
- 表格行高 28；accent = 图标同系深蓝（#14477E 近似），根视图 `.tint` 统一。
- 深色模式：全部颜色走系统语义色，不写死黑白（状态栏/卡片/斑马纹均语义色）。
- 窗口：默认 1280×800，最小 1080×680。

## 6. 交互规范

- ⌘S 保存（工具栏按钮带快捷键）；⌘F 页内搜索：焦点落到当前页搜索框
  （ProTable/工程列表搜索框注册 `⌘F` 快捷键按钮聚焦实现）。
- 保存状态三态（已保存/未保存/保存中）在工具栏与状态栏一致呈现（同一 `saveState.text`）。
- 删除类操作统一确认（工程、库行、方案、工程量行）。
- 撤销/重做：数据编辑层无全局撤销栈（v1 既定），本版不引入；批量导入保留“撤销导入”
  （删本次导入工程，与 v1 一致）。此范围在文档明示，不假装支持 ⌘Z。
- 新建工程向导：sheet 三步合一表单（工程名 → 配置方案 → 模板（可选）→ 创建并进入工程信息页补全）。

## 7. 与 v1 的页面映射

| v1（NavDestination / 视图） | v2 |
|---|---|
| `.projects` ProjectsView | `.projectList` ProjectListView（卡片+列表双模式 + 向导） |
| `.current(.info)` ProjectInfoView | `.projectInfo` ProjectInfoView（卡片重组，逻辑不变） |
| `.current(.workload3a)` Workload3AView | `.workload` WorkloadView 左侧（工程量清单） |
| `.current(.workload4a/.workloadEquip/.workload3b/.workload3c)` | `.workload` 右侧预览标签（复用原视图） |
| `.current(.fee)` FeeView | `.fees` 标签“表二”（FeeTreeTableView 复用） |
| `.current(.table5)` Table5View | `.fees` 标签“表五”（Table5ContentView） |
| （无） | `.fees` 标签“表一”（新增总表预览）、`.overview` 概览、`.validation` 校验中心 |
| `.current(.export)` ExportView | `.export` ExportView（+ 迷你预览 + 导出记录） |
| `.libraries(key)` LibrariesView | 同 nav，DictTableView → ProTable |
| `.feeRules(tab)` FeeRulesView | 同 nav，页头/表格组件升级，内部逻辑不变 |
| `.profiles` ProfilesView | 同 nav，表格 → 卡片列表，逻辑不变 |
| `.batch` BatchView / `.settings` SettingsView | 同 nav，卡片呈现，逻辑不变 |
| ContentView 顶栏散按钮（新建/打开/保存/工程管理/导出/退出） | 工作区工具栏（返回/定额搜索/导入/导出/保存+状态）；退出走系统菜单（退出前 flush 逻辑不变） |
| StatusBarView（仅提示文字） | 状态栏 v2（总造价/工日/校验数/保存状态/修改时间） |

## 8. 新增纯逻辑（Logic，可单测）

- `Logic/TableData.swift`：表格过滤（任意值包含）、稳定排序（数字/文本）、列合计。
- `Logic/Validation.swift`：`collectValidationIssues(db, project, profile, result)` —
  聚合引擎 warnings（orphanQty/invalidQty/duplicateCode/missingRate*/unknownProjectType/
  invalidDiscount/unknownTable5Basis）、材料未建档（table4 unmatched）、表五手动项未填金额、
  工程信息缺项、未录工程量；`ValidationIssue{severity, title, detail, target, rowId}`，
  严重度排序 错误 > 警告 > 提示。
- `Logic/Dashboard.swift`：KPI 派生（总造价/建安除税/设备材料除税/工日）+
  费用构成段（建安含税/设备含税/其他含税，占比以三段之和为分母）。
- `Logic/ExportPreview.swift`：每张报表的迷你预览关键行（纯函数，数据全部来自 CalcResult，
  与导出同源同值，只做展示格式化）。

## 9. 影响面

- 改动：`Logic/Navigation.swift`（枚举重构 + 标签/图标/提示）、`Views/` 全部视图
  （ContentView/AppState/各页）、`TXBudget.version` → 2.0.0、README 一行。
- 不改：Engine/、Models/、Persistence/、Export/、Logic 其余文件（FeeTree/LibraryRowCodec/
  LibraryImport/ProfileLibs/ProjectHelpers 等原样复用）、scripts/bundle.sh、CI workflow。
- 测试：现有 136 全绿为底线；新增 Navigation/TableData/Validation/Dashboard/ExportPreview
  测试，总数只增不减。PlaceholderTests 的版本断言随版本号更新为 2.0.0。
- 风险：SwiftUI 视图层无法在本环境（Linux）编译渲染，只能靠 CI（macOS runner）
  编译 + 单元测试兜底；视觉最终验收在用户真机。视图代码只用 macOS 13 API
  （NavigationSplitView/Charts 均为 13+），不用 macOS 14+ 专属 API。

## 10. 发布

达标后打 tag `v2.0.0` 走现有 CI（swift test → release build → bundle（拼音 DMG 名 +
ad-hoc 签名 + 签名校验）→ Release），核实资产 name/label/size/state。

## 11. v2.0.1 变更：编辑目标从隐藏模式改为可见选择器

**报障（2026-10-22，用户）**：配置方案页“一直显示正在编辑，怎么弄都不行”。

**根因**：`ProfilesView.statusBadges` 按 `(editingProfileId ?? activeProfileId) == p.id`
显示“正在编辑”徽标——`editingProfileId` 为空时回落到默认方案，**恒有恰好一个方案
戴着徽标、无法消除**；而这个状态决定资料库/取费规则页编辑哪套方案的库与费率，
全软件却没有任何地方解释它。只有「编辑内容」能移动它，「设为默认」只动
`activeProfileId`（新建默认）。这是个隐藏的全局模式，属设计缺陷，非数据损坏。

**改法（隐藏模式 → 可见控件，写回逻辑一字不动）**：

- `ProfilesView`：删除“正在编辑”徽标（只保留“新建默认”）；副标题下加一行说明：
  点「编辑内容」后资料库与取费规则编辑的就是该方案，「设为默认」只影响新建工程。
  「编辑内容」行为（`setEditingProfile` + 跳资料库页）不变，toast 措辞同步。
- `LibrariesView` / `FeeRulesView`：页首静态横幅“正在编辑方案：X”改为共享组件
  `ProfilePickerBanner`（Views/SharedViews.swift）——真正的方案下拉选择器，
  标签“当前方案：”，绑定 `editingProfileId ?? activeProfileId`，变更走
  `setEditingProfile`。用户在编辑现场即可见、可切换，不再依赖配置页徽标。
- 全软件措辞统一：侧边栏底部改为“资料库方案：X”；设置页“正在编辑方案”改为
  “资料库方案”、“导出正在编辑的方案”改为“导出当前资料库方案”；工程内表二
  （FeeView）提示改为“费率将写入资料库方案“X””（其写回目标逻辑不动，仍为
  editingProfileId 回落 active）；导航提示文案同步。
- 版本 `TXBudget.version` → 2.0.1（PlaceholderTests 断言同步）。纯 Views/文案
  改动（Navigation.swift 仅改提示字符串），引擎、数据格式、导出不动；测试
  160 全绿为底线。

## 12. v2.5.0 修订：按宇翔式专业布局修工作量页五处（2026-10-23 用户反馈）

用户发宇翔软件三张截图定标准，五处修改。引擎口径、导出、数据格式一律不动；
表三甲新列的数值必须与引擎/导出的表三甲逐项一致。

### 12.1 表三甲补列 + 汇总条（任务 A）

工程量清单列改为（顺序）：编号 / 项目名称 / 单位 / 数量 / 系数 /
技工 / 普工 / 技工合计 / 普工合计 / 状态。

- 技工 / 普工列 = 该行定额的**单位工日**（只读）：取定额库中与引擎
  `quotaByCode` 同口径的首条匹配（编号重复时引擎按首条，界面同）；孤儿行显示“—”。
- 技工合计 / 普工合计列 = 本行对引擎表三甲的**贡献**（只读），纯 Logic
  `table3ARowContribution`（Logic/WorkloadLinks.swift 同文件）：
  行参与计算时（`workloadRowState == .active`，与引擎逐行有效性同口径）
  = 数量 × 系数 × 单位工日；不参与（孤儿/数量 0/负数/系数无效）= 0。
  对齐依据：引擎按定额聚合 `加权量 = Σ 数量×系数`，每定额
  `技工 = r2(加权量 × 技工)`——逐行贡献之和与引擎每定额值仅差 r2 舍入
  （每组 ≤0.005）；“工日X0.5”类条目在本软件里由**行系数 0.5** 承载
  （见 CrosscheckTests 的 TXL4-053 夹具），故贡献公式必须含系数，不许用
  “数量×单位工日”漏掉系数。
- 底部汇总条（工作量页自有，不用 ProTable 的字符串合计行）：主数字取引擎
  `CalcResult.techSub / laborSub`（表三甲小计，与逐行贡献之和同口径）；
  当工日调整率 adjRate ≠ 0 时同条加注“调整后总工日 技 X / 普 Y
  （与导出表三甲合计行一致）”——调整后值即状态栏/概览 KPI 用的
  techDays/laborDays。汇总条数字一律取引擎结果，不在界面侧另算总额。

### 12.2 ProTable 列宽可拖动 + 持久化 + 新默认（任务 B）

- ProTable 新增可选参数 `tableId`：传入才启用列宽拖动与持久化
  （资料库各表、工作量表三甲传入；其他使用方零影响）。
  列头每列右缘有 6pt 拖动手柄（悬停变 ↔ 光标）：拖动改宽（36–640 夹紧）；
  **双击手柄恢复该列默认宽**。宽度存 UserDefaults
  键 `protable.widths.<tableId>`（[列key: 宽] JSON），重启保持。
  解析顺序：用户宽 > 调用方 `columnWidths` > 按 kind 默认。
- kind 默认调整：text 150 / number 88 / select 116 / checkbox 44。
  具体表以调用方 `columnWidths` 给定：表三甲 编号 92、数量 84、单位 56、
  系数 64、技工/普工 64、合计 88、状态 92；项目名称为**弹性列**
  （新增参数 `flexibleKey`：该列 minWidth 取解析宽、下限 260，吃掉剩余宽度，
  表头/行/合计行同口径）。排序、行内编辑、右键菜单行为不许回归。

### 12.3 底部关联区改单列分组清单（任务 C）

三栏并排作废。改为一张纵向单列清单：一列贯通，组头行分隔——
【主材】【机械】【仪器仪表】，无该组关联时不显示该组（组头含“＋添加”）；
每项一行，列为：代号 / 名称 / 规格 / 单位 / 单位用量 / 参考用量 / 单价 / 合价 / 操作。
列头行在选中行摘要之下、清单之上（小字 caption）。列宽同 12.2 原则
（代号 84、规格 96、单位 48、单位用量 84、参考用量 88、单价 88、合价 92、
名称弹性）。v2.4.0 的全部编辑能力与口径原样保留（消耗量行内改、删带确认、
按组新增、主材改价/未建档建档、备选启用开关、未生效灰显+原因、顶部橙色
生效范围明示行、孤儿行提示）；种类徽标与未建档标记并入名称列尾随，
未生效原因/未建档提示作行下副行。主材“代号”列无编码，显示“—”。

### 12.4 双击选型号（变体切换）（任务 D）

- 纯 Logic `variantOptions(quota:libraries:)`（Logic/WorkloadLinks.swift）：
  取 rules 中该编码 kind ∈ {变体, 变体*} 的 distinct variant（非空，
  首现顺序）；首项为**基准项 = 定额库原名**（首条匹配行的 name，引擎口径下
  行变体取此名时只有通用规则生效——即“无变体（通用）”状态，与添加栏
  新行 variant = 定额名的既有行为一致），已在 distinct 列表中则不重复；
  变体名用全名列项，不截断。
- 表三甲双击一行（双击命中的是非编辑列即可，含项目名称列）：可选变体
  ≥2 时弹“请选择型号”列表（当前变体打勾），选中即写回该行 variant
  （工程量/系数不变），底部关联区与表三乙/丙、表四随引擎重算；
  含当前行变体不在清单内时先追加为清单末项（保证当前状态可见可回）。
  可选变体 <2 时不弹，toast 提示“该定额无可选型号”。
  ProTable 为此新增可选回调 `onRowDoubleClick`：仅非编辑列的双击触发
  （可编辑列双击仍进编辑，行为不回归）。

### 12.5 方案与模板进菜单栏（任务 E）

- TXBudgetApp 新增 `.commands`：「方案」菜单——当前资料库方案单选组
  （打勾切换，走 `setEditingProfile`）、编辑方案…/新建方案…（跳配置方案页，
  复用其既有表单）、复制当前方案（复用 `duplicateProfile` + `addProfile`）、
  导入方案文件…/导出当前方案…（复用 AppState 新收敛的
  `importProfileViaPanel` / `exportEditingProfileViaPanel`，与设置页同一份
  实现，设置页改为调用之）、分隔后：补全并校正定额库…/按官方清理…
  （作用于当前资料库方案，见下条单一呈现者）。
- 补全/清理的确认与预览只保留一份呈现实现：原 LibrariesView 内的流程
  （试算→确认 alert、清理 dry-run 预览 sheet、备份→执行→完成报告）抽成
  `LibraryMaintenanceControls`（对话框宿主，无按钮形态），由 ContentView
  根部常驻挂载，观察 AppState 的 `libraryMaintenanceRequest`；
  资料库页的两个按钮改为只发请求（文案与说明保留在页内），呈现不再双份，
  避免菜单与页面同时弹窗。
- 「模板」：本软件现有模板概念有二——(1) 新建向导/批量页的“套用已有
  工程为模板”（无独立模板库数据模型）；(2) `settings.defaultInfo`
  = 新建工程的默认工程信息（此前无编辑界面）。菜单「模板」放一项
  「工程信息模板…」：跳设置页新增的「工程信息模板」卡片区（编辑
  defaultInfo 的工程类型/施工折扣/施工距离/施工调遣分类/冬雨季施工费/
  甲供·乙供增值税，选项与工程信息表单同源），菜单跳转时设置页该卡片
  高亮提示。不新造数据模型；“套用模板”仍在向导与批量页内。

### 12.6 影响面与测试

- 新增 Logic：`table3ARowContribution`、`variantOptions`（均在
  WorkloadLinks.swift），测试对照引擎：含系数行（含 0.5）贡献 = 引擎
  表三甲逐项；变体清单与切换后表四主材规格/用量端到端（种子 TXL3-187：
  6芯→12芯 后 光缆 规格 GYTS_12芯、量 1.007×工程量）。
- v2.4.0 的 WorkloadLinksTests、192 基线全部不许失效；版本 → 2.5.0。
