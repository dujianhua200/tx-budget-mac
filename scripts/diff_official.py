#!/usr/bin/env python3
"""官方定额库 vs App 内置完整库（v2.1.0，小程序来源）全面比对（v2.2.0，见
docs/v2.2-correction-design.md §3）。

输入：
  scripts/data/official-library.json            parse_official_manual.py 产物
  Sources/TXBudget/Resources/full-library.json  App 现行内置完整库
输出：
  docs/v2.2-official-diff-report.md             人读报告（结论先行 + 逐条清单）
  scripts/data/official-diff.json               全量机读差异（供 build_corrected_library.py 与人工复核）

名称归一化（比对与校正共用，设计文档 §3.1）：NFKC → 去全部空白 → ø/φ→Φ →
波浪线/长破折号（~/～/—）统一为 -。归一化后仍不同才计“名称不符”；仅写法差异
（全半角/空格/ø/范围符号）单列不计错误；App 名称以官方名称为前缀/后缀者单列
“前缀/上下文型”（小程序多加“安装/组立”等前缀），其余为实质差异。
机械/仪表官方只有名称无编码，一律按归一化名称比对；材料按（定额, 归一化名称）比对，
App 同名多规格行优先与官方行比数量，其余规格行计“额外（规格行）”。
官方＊（star）与 App consumption=0 视为一致（设计选用）；官方括号值（paren）按数值比对；
官方 rawProblem（多值无法唯一确定）不比数量，单列存疑沿用 App 现值。
"""
import json
import re
import sys
import unicodedata
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OFFICIAL = ROOT / "scripts" / "data" / "official-library.json"
APP = ROOT / "Sources" / "TXBudget" / "Resources" / "full-library.json"
OUT_MD = ROOT / "docs" / "v2.2-official-diff-report.md"
OUT_JSON = ROOT / "scripts" / "data" / "official-diff.json"


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKC", s or "")
    s = re.sub(r"[\s　]+", "", s)
    return s.replace("ø", "Φ").replace("φ", "Φ").replace("~", "-").replace("—", "-")


def close(a, b):
    return a is not None and b is not None and abs(a - b) <= 1e-9


def main() -> int:
    official = json.loads(OFFICIAL.read_text(encoding="utf-8"))
    app = json.loads(APP.read_text(encoding="utf-8"))
    off = {q["code"]: q for q in official}
    appq = {q["code"]: q for q in app["quotas"]}

    # ---------- 覆盖 ----------
    off_only = sorted(set(off) - set(appq))
    app_only = sorted(set(appq) - set(off))
    common = sorted(set(off) & set(appq))

    # ---------- 工日 / 名称 / 单位 ----------
    labor_diffs, name_style, name_prefix, name_diffs, unit_diffs = [], [], [], [], []
    for code in common:
        o, a = off[code], appq[code]
        if not (close(o["tech"], a["tech"]) and close(o["labor"], a["labor"])):
            labor_diffs.append({"code": code, "appTech": a["tech"], "offTech": o["tech"],
                                "appLabor": a["labor"], "offLabor": o["labor"]})
        if o["name"] != a["name"]:
            no, na = norm(o["name"]), norm(a["name"])
            entry = {"code": code, "app": a["name"], "off": o["name"]}
            if no == na:
                name_style.append(entry)
            elif na.startswith(no) or na.endswith(no):
                name_prefix.append(entry)
            else:
                name_diffs.append(entry)
        if o["unit"] != a["unit"] and norm(o["unit"]) != norm(a["unit"]):
            unit_diffs.append({"code": code, "app": a["unit"], "off": o["unit"]})

    # ---------- 关联 ----------
    def app_links(table, key="quota"):
        d = {}
        for row in app[table]:
            d.setdefault(row[key], []).append(row)
        return d
    app_rules = app_links("rules")
    app_qm = app_links("quotaMachines")
    app_qi = app_links("quotaInstruments")

    link = {"materials": {"missing": [], "extra": [], "qtyDiff": [], "unitDiff": [], "problemKept": []},
            "machines": {"missing": [], "extra": [], "qtyDiff": [], "unitDiff": [], "problemKept": []},
            "instruments": {"missing": [], "extra": [], "qtyDiff": [], "unitDiff": [], "problemKept": []}}
    per_quota = {}  # code -> {sec: {missing, extra, qtyDiff}} 供按定额统计

    def note(code, sec, kind):
        per_quota.setdefault(code, {}).setdefault(sec, {"missing": 0, "extra": 0, "qtyDiff": 0})
        per_quota[code][sec][kind] += 1

    def diff_section(code, sec, off_items, app_rows, qty_of):
        app_by_name = {}
        for row in app_rows:
            app_by_name.setdefault(norm(row["material"] if sec == "materials" else row["mname"]), []).append(row)
        off_names = set()
        for it in off_items:
            n = norm(it["name"])
            off_names.add(n)
            rows = app_by_name.get(n)
            if not rows:
                link[sec]["missing"].append({"code": code, "name": it["name"], "qty": it["qty"],
                                             "star": it["star"], "paren": it["paren"]})
                note(code, sec, "missing")
                continue
            row = rows[0]
            if "rawProblem" in it:
                link[sec]["problemKept"].append({"code": code, "name": it["name"],
                                                 "raw": it["rawProblem"], "appQty": qty_of(row)})
                continue
            off_qty = 0.0 if it["star"] else it["qty"]
            if not close(off_qty, qty_of(row)):
                link[sec]["qtyDiff"].append({"code": code, "name": it["name"],
                                             "appQty": qty_of(row), "offQty": off_qty,
                                             "star": it["star"], "paren": it["paren"]})
                note(code, sec, "qtyDiff")
            if norm(it["unit"]) != norm(row["unit"]):
                link[sec]["unitDiff"].append({"code": code, "name": it["name"],
                                              "appUnit": row["unit"], "offUnit": it["unit"]})
        for n, rows in app_by_name.items():
            if n not in off_names:
                for row in rows:
                    link[sec]["extra"].append({"code": code,
                                               "name": row["material"] if sec == "materials" else row["mname"],
                                               "qty": qty_of(row),
                                               "spec": row.get("spec", "") if sec == "materials" else row.get("mcode", "")})
                    note(code, sec, "extra")
            elif len(rows) > 1:
                # 同名多行（多为材料多规格）：首行已与官方比对，其余计额外规格行
                for row in rows[1:]:
                    link[sec]["extra"].append({"code": code,
                                               "name": row["material"] if sec == "materials" else row["mname"],
                                               "qty": qty_of(row),
                                               "spec": row.get("spec", "") if sec == "materials" else row.get("mcode", ""),
                                               "sameNameExtraRow": True})
                    note(code, sec, "extra")

    for code in common:
        o = off[code]
        diff_section(code, "materials", o["materials"], app_rules.get(code, []), lambda r: r["consumption"])
        diff_section(code, "machines", o["machines"], app_qm.get(code, []), lambda r: r["qty"])
        diff_section(code, "instruments", o["instruments"], app_qi.get(code, []), lambda r: r["qty"])
    # 官方独有定额的关联全数计缺失（App 连定额都没有）
    for code in off_only:
        o = off[code]
        for sec, items in (("materials", o["materials"]), ("machines", o["machines"]), ("instruments", o["instruments"])):
            for it in items:
                link[sec]["missing"].append({"code": code, "name": it["name"], "qty": it["qty"],
                                             "star": it["star"], "paren": it["paren"], "quotaMissing": True})
                note(code, sec, "missing")

    diff = OrderedDict([
        ("officialCount", len(off)), ("appCount", len(appq)), ("commonCount", len(common)),
        ("officialOnly", off_only), ("appOnly", app_only),
        ("laborDiffs", labor_diffs), ("nameStyleOnly", name_style),
        ("namePrefixOnly", name_prefix),
        ("nameDiffs", name_diffs), ("unitDiffs", unit_diffs),
        ("links", link), ("perQuota", per_quota),
    ])
    OUT_JSON.write_text(json.dumps(diff, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")

    # ---------- 报告 ----------
    def pct(n, d):
        return f"{(100.0 * n / d):.1f}%" if d else "—"
    L = []
    L.append("# v2.2.0 官方 451 手册 vs App 内置库 差异报告\n")
    L.append("数据源：官方《通信451定额电子手册》v2022.12.716（`scripts/data/official-library.json`，"
             "由 `scripts/parse_official_manual.py` 解析，3,091 条唯一编码）vs App v2.1.0 内置完整库"
             "（`full-library.json`，小程序种子来源，3,092 条）。全量机读差异见 `scripts/data/official-diff.json`。\n")
    L.append("## 结论先行\n")
    L.append(f"- 定额覆盖：官方 3,091 条，App 3,092 条，共同 {len(common)} 条；"
             f"官方有 App 无 **{len(off_only)}** 条，App 有官方无 **{len(app_only)}** 条。")
    L.append(f"- 工日：共同定额中 **{len(labor_diffs)}** 条（{pct(len(labor_diffs), len(common))}）技工/普工与官方不符"
             "——小程序数据在这些条目上是错的，校正以官方为准。")
    L.append(f"- 名称：实质不符 **{len(name_diffs)}** 条；前缀/上下文型 {len(name_prefix)} 条"
             f"（小程序多加“安装/组立”或工作内容前缀）；仅写法差异（全半角/空格/ø→Φ/范围符号）"
             f"{len(name_style)} 条，不算错误。"
             f"单位实质不符 **{len(unit_diffs)}** 条。")
    for sec, label in (("materials", "材料"), ("machines", "机械"), ("instruments", "仪表")):
        s = link[sec]
        L.append(f"- {label}关联：缺失 **{len(s['missing'])}** 条、额外 **{len(s['extra'])}** 条、"
                 f"数量不符 **{len(s['qtyDiff'])}** 条、单位不符 {len(s['unitDiff'])} 条、"
                 f"官方多值存疑沿用现值 {len(s['problemKept'])} 条。")
    L.append("")
    L.append("## 一、定额覆盖差异\n")
    L.append(f"### 官方有、App 无（{len(off_only)} 条）\n")
    L.append("、".join(off_only) if off_only else "（无）")
    L.append(f"\n### App 有、官方无（{len(app_only)} 条）\n")
    L.append("、".join(app_only) if app_only else "（无）")
    L.append("\n> 说明：App 独有仅 TGD2-161 一条——官方 TGD2 编号自 160 直接跳号（无 161/162），"
             "该条为“砖砌通信光(电)缆通道（370mm砖砌体、人孔口圈部分）1.2m宽通道”，属手册未收的子目；"
             "现有工程可能引用，**校正保留不删**（设计文档 §4）。另注意 v2.1 时所说的“App 独有 77 条”"
             "是旧 Electron 种子（2,622 条）对小程序的比较，与本报告的比对对象（v2.1.0 内置完整库 3,092 条）不同。\n")
    L.append(f"## 二、工日差异（{len(labor_diffs)} 条，共同定额 {len(common)} 条）\n")
    L.append("| 编码 | App 技工 | 官方技工 | App 普工 | 官方普工 |")
    L.append("|---|---|---|---|---|")
    for d in labor_diffs:
        L.append(f"| {d['code']} | {d['appTech']} | {d['offTech']} | {d['appLabor']} | {d['offLabor']} |")
    L.append(f"\n## 三、名称 / 单位差异\n")
    L.append(f"### 名称实质不符（{len(name_diffs)} 条；前缀/上下文型 {len(name_prefix)} 条、写法差异 {len(name_style)} 条另计）\n")
    L.append("| 编码 | App 名称 | 官方名称 |")
    L.append("|---|---|---|")
    for d in name_diffs:
        L.append(f"| {d['code']} | {d['app']} | {d['off']} |")
    L.append(f"\n### 单位实质不符（{len(unit_diffs)} 条）\n")
    L.append("| 编码 | App 单位 | 官方单位 |")
    L.append("|---|---|---|")
    for d in unit_diffs:
        L.append(f"| {d['code']} | {d['app']} | {d['off']} |")
    L.append("\n## 四、关联差异（材料 / 机械 / 仪表）\n")
    for sec, label in (("materials", "材料"), ("machines", "机械"), ("instruments", "仪表")):
        s = link[sec]
        L.append(f"### {label}：缺失 {len(s['missing'])} / 额外 {len(s['extra'])} / 数量不符 {len(s['qtyDiff'])} / 单位不符 {len(s['unitDiff'])}\n")
        if s["qtyDiff"]:
            L.append("数量不符明细（App → 官方）：")
            L.append("")
            for d in s["qtyDiff"][:200]:
                mark = "（设计选用括号值）" if d["paren"] else ("（设计选用＊）" if d["star"] else "")
                L.append(f"- {d['code']} {d['name']}：{d['appQty']} → {d['offQty']}{mark}")
            if len(s["qtyDiff"]) > 200:
                L.append(f"- ……余 {len(s['qtyDiff']) - 200} 条见 official-diff.json")
            L.append("")
    L.append("### 按定额统计（仅列有差异的定额）\n")
    L.append("| 定额 | 材料 缺/多/量差 | 机械 缺/多/量差 | 仪表 缺/多/量差 |")
    L.append("|---|---|---|---|")
    for code in sorted(per_quota):
        pq = per_quota[code]
        def cell(sec):
            v = pq.get(sec)
            return f"{v['missing']}/{v['extra']}/{v['qtyDiff']}" if v else "0/0/0"
        L.append(f"| {code} | {cell('materials')} | {cell('machines')} | {cell('instruments')} |")
    L.append("")
    L.append("## 五、解析存疑（不臆造，校正时沿用 App 现值）\n")
    L.append("官方手册有 18 处单元格为多值写法（如 `28.28/2.02`、`(11.11/1.01)`、`102.50/103.00`、"
             "`(1.02/根横木)`），无法唯一确定数量，明细见 `scripts/data/official-parse-report.json`；"
             "涉及的关联行在校正时不覆盖，保留 App 现值。另源文件 1 处闭合标签笔误 `</td2>` "
             "（TSY3-056 技工 2.00）已在解析时还原。")
    OUT_MD.write_text("\n".join(L) + "\n", encoding="utf-8")
    print(f"覆盖: 官方独有 {len(off_only)} / App 独有 {len(app_only)} / 共同 {len(common)}")
    print(f"工日差异 {len(labor_diffs)}  名称实质差异 {len(name_diffs)}（前缀型 {len(name_prefix)}、写法 {len(name_style)}）  单位差异 {len(unit_diffs)}")
    for sec in ("materials", "machines", "instruments"):
        s = link[sec]
        print(f"{sec}: 缺失 {len(s['missing'])} 额外 {len(s['extra'])} 量差 {len(s['qtyDiff'])} 单位差 {len(s['unitDiff'])} 存疑沿用 {len(s['problemKept'])}")
    print(f"报告: {OUT_MD}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
