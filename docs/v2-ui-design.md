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
    │       侧边栏底部：正在编辑方案名（资料库/取费规则的编辑目标）
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
| 资料库各页 | libraries(key) | 统一页头（编辑目标方案横幅 + 可跳配置方案）+ Excel 导入/导出 + ProTable（搜索/新增/导入/导出/批量删除/复制行） |
| 取费规则 | feeRules(tab) | 页头横幅同上；费率=左树+右表（同 v1）；表五费用/关联规则=ProTable；打折规则同 v1 呈现微调 |
| 配置方案 | profiles | 卡片列表：状态徽标（新建默认/正在编辑）、工程数、来源；操作：编辑内容/设为默认/复制/导出/重命名/删除（占用时 sheet 自选切换目标，逻辑同 v1）；顶部新建（名称+模板）/导入/整库备份 |
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
