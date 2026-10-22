#!/usr/bin/env python3
"""官方《通信451定额电子手册》v2022.12.716 单文件 HTML → 官方定额库 JSON 解析脚本
（v2.2.0，见 docs/v2.2-correction-design.md §2）。

输入（路径相对仓库根目录，即本脚本的上级目录）：
  scripts/data/official-451-manual-v2022.12.716.html   用户提供的官方手册留档
输出：
  scripts/data/official-library.json        官方库（中间格式，逐条定额 + 关联 + 标记）
  scripts/data/official-parse-report.json   解析自检报告（计数、抽查锚点、存疑清单）

解析规则（详见设计文档 §2）：
  - 只认 <table class="dTable"> 且含“定额编号”行的定额表（其余为表一~表五空白模板，跳过）；
    按 rowspan/colspan 展开网格，值列 = 编号行中各定额编码所在列。
  - 同一编码被手册拆成两张表（续表）时合并：字段取非空值、关联按名称并集，冲突记存疑保留先行值。
  - 名称 = “项目”区多行表头按列自上而下拼接：整行横跨全部值列的单元格为公共片段，
    否则为该列片段；片段先做 NFKC 归一化、去除全部空白、ø/φ→Φ、剥离脚注标记（<sup> 与 ①~⑳），
    片段间以单个空格连接（与 App 现行命名风格对齐，如“挂钩法架设架空光缆 平原 36芯以下”）。
  - 数值：纯数字 → float；“＊”/“(*)” → 设计选用（star，无定值）；带括号的数字（半角括号，
    文本经 NFKC 后全角括号已转半角）→ 数字 + paren 标记（总说明十三：带括号表示的消耗量
    系供设计选用，“＊”表示由设计确定其用量）；空 / “—” → 无此项（null），人工行记 0；
    含 “/” 等无法唯一确定的 → qty=null、保留 rawProblem 并记入存疑清单（不臆造）。
  - 源文件笔误：全文仅 1 处闭合标签误写为 </td2>（TSY3-056 技工 2.00 单元格），
    解析前统一还原 </tdN> 等笔误并计数入报告，否则该格会被静默丢失。
  - 册名（volume）取该表所在页页眉“第X册 <册名>〈XXX〉”，缺失时按编码前缀回落。
输出确定性：按手册出现顺序输出，重跑应逐字节一致。用 python3 运行，仅标准库。
"""
import json
import re
import sys
import unicodedata
from collections import OrderedDict
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "scripts" / "data" / "official-451-manual-v2022.12.716.html"
OUT = ROOT / "scripts" / "data" / "official-library.json"
REPORT = ROOT / "scripts" / "data" / "official-parse-report.json"

VOL_FALLBACK = {
    "TSD": "通信电源设备安装工程", "TSY": "有线通信设备安装工程",
    "TSW": "无线通信设备安装工程", "TXL": "通信线路工程",
    "TGD": "通信管道工程", "T5G": "移动通信设备安装工程",
}
CODE_RE = re.compile(r"^(TSD|TSY|TSW|TXL|TGD|T5G)(\d+)-(\d+)([A-Z]?)$")
SECTION_MAP = {"人工": "labor", "主要材料": "materials", "主材": "materials",
               "机械": "machines", "仪表": "instruments"}


# ---------------------------------------------------------------- HTML 提取
class TableExtractor(HTMLParser):
    """提取每个 <table class="dTable"> 的行/单元格（文本、rowspan、colspan），
    并记录该表之前最近的页眉册名。"""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tables = []          # [{volume, rows: [[{text, rs, cs}]]}]
        self._in_table = False
        self._depth = 0
        self._rows = None
        self._row = None
        self._cell = None
        self._sup = 0
        self._volume = ""
        self._header_buf = None   # 正在收集的 pageHeader 文本

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        cls = a.get("class", "")
        if tag == "span" and "pageHeader" in cls:
            self._header_buf = ""
        if tag == "table" and "dTable" in cls.split():
            self._in_table = True
            self._depth = 1
            self._rows = []
            return
        if not self._in_table:
            return
        if tag == "table":
            self._depth += 1
        elif tag == "tr":
            self._row = []
        elif tag == "td" and self._row is not None:
            self._cell = {"text": [], "rs": int(a.get("rowspan", 1)), "cs": int(a.get("colspan", 1))}
        elif tag == "sup":
            self._sup += 1
        elif tag == "br" and self._cell is not None:
            self._cell["text"].append(" ")

    def handle_endtag(self, tag):
        if tag == "span" and self._header_buf is not None:
            m = re.search(r"第[一二三四五六七八九十]+册\s*([^〈]+)〈", self._header_buf)
            if m:
                self._volume = m.group(1).strip()
            self._header_buf = None
        if not self._in_table:
            return
        if tag == "sup" and self._sup:
            self._sup -= 1
        elif tag == "td" and self._cell is not None:
            self._cell["text"] = clean_text("".join(self._cell["text"]))
            self._row.append(self._cell)
            self._cell = None
        elif tag == "tr" and self._row is not None:
            self._rows.append(self._row)
            self._row = None
        elif tag == "table":
            self._depth -= 1
            if self._depth == 0:
                self._in_table = False
                self.tables.append({"volume": self._volume, "rows": self._rows})
                self._rows = None

    def handle_data(self, data):
        if self._header_buf is not None:
            self._header_buf += data
        if self._in_table and self._cell is not None and self._sup == 0:
            self._cell["text"].append(data)


def clean_text(s: str) -> str:
    s = unicodedata.normalize("NFKC", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip()


def tight(s: str) -> str:
    """名称类文本：去全部空白、去脚注圆圈数字、ø/φ→Φ（与 App 现行命名风格对齐）。"""
    s = unicodedata.normalize("NFKC", s or "")
    s = re.sub(r"[\s　]+", "", s)
    s = re.sub(r"[①-⑳]", "", s)
    return s.replace("ø", "Φ").replace("φ", "Φ")


# ---------------------------------------------------------------- 网格展开
def expand(rows):
    """rowspan/colspan 展开为网格：grid[r][c] = 文本（被跨格覆盖的位置取源格文本）。"""
    grid = []
    spans = {}  # (r, c) -> text，待填充的跨行占用
    for r, row in enumerate(rows):
        grow = []
        c = 0
        for cell in row:
            while (r, c) in spans:
                grow.append(spans.pop((r, c)))
                c += 1
            for dc in range(cell["cs"]):
                grow.append(cell["text"])
                for dr in range(1, cell["rs"]):
                    spans[(r + dr, c + dc)] = cell["text"]
            c += cell["cs"]
        while (r, c) in spans:
            grow.append(spans.pop((r, c)))
            c += 1
        grid.append(grow)
    width = max((len(g) for g in grid), default=0)
    for g in grid:
        g.extend([""] * (width - len(g)))
    return grid


def parse_value(raw: str):
    """单元格数量 → (qty, star, paren, problem)。raw 已 NFKC + 空白折叠。"""
    s = (raw or "").strip()
    if s in ("", "—", "-"):
        return None, False, False, None
    if s in ("*", "(*)"):
        return None, True, False, None
    m = re.fullmatch(r"\((\d+(?:\.\d+)?)\)", s)
    if m:
        return float(m.group(1)), False, True, None
    if re.fullmatch(r"\d+(?:\.\d+)?", s):
        return float(s), False, False, None
    return None, False, False, f"无法唯一确定的数量值：{s!r}"


# ---------------------------------------------------------------- 单表解析
def parse_table(tbl, uncertain):
    grid = expand(tbl["rows"])
    if not grid:
        return []
    # 定位编号行（首列去空白 == 定额编号）
    code_row = None
    for r, grow in enumerate(grid):
        if grow and tight(grow[0]) == "定额编号":
            code_row = r
            break
    if code_row is None:
        return []  # 非定额表（表一~表五模板等）
    grow = grid[code_row]
    cols = []  # (col_index, code)
    for c in range(3, len(grow)):
        code = tight(grow[c])
        if not code:
            continue
        if not CODE_RE.match(code):
            uncertain.append({"where": f"表@行{code_row}", "issue": f"编号列出现非编码文本：{code!r}"})
            continue
        cols.append((c, code))
    if not cols:
        return []
    col_idx = [c for c, _ in cols]

    # 定额单位行与表头（名称/单位/数量）行
    unit_row = name_row = None
    for r in range(code_row + 1, len(grid)):
        t = tight(grid[r][0]) if grid[r] else ""
        if t == "定额单位":
            unit_row = r
        elif t == "名称":
            name_row = r
            break
    if unit_row is None or name_row is None:
        uncertain.append({"where": cols[0][1], "issue": "未找到定额单位行或名称表头行"})
        return []

    # 名称片段：编号行与单位行之间的行，按列拼接
    frags = {c: [] for c in col_idx}
    for r in range(code_row + 1, unit_row):
        for c in col_idx:
            f = tight(grid[r][c])
            if f and (not frags[c] or frags[c][-1] != f):
                frags[c].append(f)

    quotas = OrderedDict()
    for c, code in cols:
        volume = tbl["volume"] or VOL_FALLBACK.get(CODE_RE.match(code).group(1), "")
        quotas[code] = {
            "code": code, "name": " ".join(frags[c]), "unit": tight(grid[unit_row][c]),
            "tech": None, "labor": None, "volume": volume,
            "materials": [], "machines": [], "instruments": [],
        }

    # 正文：名称行之后，按第 0 列章节标签分段
    section = None
    labor_rows = {"技工": "tech", "普工": "labor"}
    for r in range(name_row + 1, len(grid)):
        grow = grid[r]
        label = tight(grow[0]) if grow else ""
        if label in SECTION_MAP:
            section = SECTION_MAP[label]
        item_name = tight(grow[1]) if len(grow) > 1 else ""
        item_unit = tight(grow[2]) if len(grow) > 2 else ""
        if section == "labor" and item_name in labor_rows:
            field = labor_rows[item_name]
            for c, code in cols:
                qty, star, paren, prob = parse_value(grow[c])
                if prob or star:
                    uncertain.append({"where": code, "issue": f"人工{item_name}数量异常：{grow[c]!r}"})
                # 人工行的空/“—”表示无此工（0 工日），与 App 现值口径一致，不记存疑。
                quotas[code][field] = qty if qty is not None else 0.0
            continue
        if section in ("materials", "machines", "instruments"):
            if not item_name:
                # 整行皆空是排版空行；有值无名才记存疑
                if any((grow[c] or "").strip() for c in col_idx):
                    uncertain.append({"where": cols[0][1], "issue": f"{section} 区出现有值无名的行（第 {r} 行）"})
                continue
            for c, code in cols:
                qty, star, paren, prob = parse_value(grow[c])
                if prob:
                    uncertain.append({"where": code, "issue": f"{item_name}：{prob}"})
                    quotas[code][section].append(OrderedDict([
                        ("name", item_name), ("unit", item_unit),
                        ("qty", None), ("star", False), ("paren", False),
                        ("rawProblem", grow[c]),
                    ]))
                    continue
                if qty is None and not star:
                    continue  # 该列无此项（空/—）
                quotas[code][section].append(OrderedDict([
                    ("name", item_name), ("unit", item_unit),
                    ("qty", qty), ("star", star), ("paren", paren),
                ]))
    return list(quotas.values())


def merge_split(qa, qb, uncertain):
    """同一编码被手册拆成两张表（续表）时的合并：字段取非空值，冲突记存疑保留先行值；
    材料/机械/仪表按（名称）并集，同名同值跳过、同名异值记存疑保留先行值。"""
    for f in ("name", "unit", "volume"):
        if not qa[f] and qb[f]:
            qa[f] = qb[f]
        elif qa[f] and qb[f] and qa[f] != qb[f]:
            uncertain.append({"where": qa["code"], "issue": f"拆分表{f}不一致：{qa[f]!r} vs {qb[f]!r}（保留先行）"})
    for f in ("tech", "labor"):
        if qa[f] is None and qb[f] is not None:
            qa[f] = qb[f]
        elif qa[f] is not None and qb[f] is not None and abs(qa[f] - qb[f]) > 1e-9:
            uncertain.append({"where": qa["code"], "issue": f"拆分表{f}不一致：{qa[f]} vs {qb[f]}（保留先行）"})
    for sec in ("materials", "machines", "instruments"):
        have = {it["name"]: it for it in qa[sec]}
        for it in qb[sec]:
            old = have.get(it["name"])
            if old is None:
                qa[sec].append(it)
                have[it["name"]] = it
            elif (old["qty"], old["star"], old["paren"]) != (it["qty"], it["star"], it["paren"]):
                uncertain.append({"where": qa["code"],
                                  "issue": f"拆分表{sec}同名异值：{it['name']} {old['qty']} vs {it['qty']}（保留先行）"})


# ---------------------------------------------------------------- 主流程
def main() -> int:
    html = SRC.read_text(encoding="utf-8", errors="replace")
    # 源文件笔误修正（见文件头说明）：还原 </tdN> 等误写闭合标签并计数。
    html, typo_fixes = re.subn(r"</(td|tr|table)\d+>", r"</\1>", html)
    ex = TableExtractor()
    ex.feed(html)
    uncertain = []
    all_quotas = []
    seen = {}
    split_merged = 0
    for tbl in ex.tables:
        for q in parse_table(tbl, uncertain):
            if q["code"] in seen:
                merge_split(seen[q["code"]], q, uncertain)
                split_merged += 1
                continue
            seen[q["code"]] = q
            all_quotas.append(q)

    counts = {}
    for q in all_quotas:
        m = CODE_RE.match(q["code"])
        counts[m.group(1)] = counts.get(m.group(1), 0) + 1

    # 抽查锚点（与任务给定样例 TXL3-187 对照）+ 结构锚点（笔误格 TSY3-056 技工 2.00）
    anchors = {}
    probe = {q["code"]: q for q in all_quotas}
    if "TXL3-187" in probe:
        q = probe["TXL3-187"]
        anchors["TXL3-187"] = {
            "name": q["name"], "unit": q["unit"], "tech": q["tech"], "labor": q["labor"],
            "materials": [(m["name"], m["qty"], m["star"]) for m in q["materials"]],
        }
    if "TSY3-056" in probe:
        anchors["TSY3-056-tech"] = probe["TSY3-056"]["tech"]
    missing_labor = [q["code"] for q in all_quotas if q["tech"] is None or q["labor"] is None]
    report = OrderedDict([
        ("source", SRC.name),
        ("sourceTypoFixes", typo_fixes),
        ("quotaTables", sum(1 for t in ex.tables if any(
            tight(r[0]["text"]) == "定额编号" for r in t["rows"] if r))),
        ("splitTablesMerged", split_merged),
        ("uniqueCodes", len(all_quotas)),
        ("countsByVolume", counts),
        ("missingLabor", missing_labor),
        ("anchors", anchors),
        ("uncertain", uncertain),
    ])
    OUT.write_text(json.dumps(all_quotas, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"官方库: {len(all_quotas)} 条  分册: {counts}")
    print(f"定额表: {report['quotaTables']} 张（含拆分续表合并 {split_merged} 条）  笔误修正: {typo_fixes}")
    print(f"无人工数据: {len(missing_labor)} 条 {missing_labor[:10]}")
    print(f"存疑: {len(uncertain)} 条")
    for u in uncertain[:20]:
        print("  ?", u["where"], u["issue"])
    print(f"锚点 TXL3-187: {json.dumps(anchors.get('TXL3-187'), ensure_ascii=False)}")
    print(f"锚点 TSY3-056 技工: {anchors.get('TSY3-056-tech')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
