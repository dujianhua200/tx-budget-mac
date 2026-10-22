#!/usr/bin/env python3
"""按官方 451 手册校正内置完整库（v2.2.0，见 docs/v2.2-correction-design.md §4）。

输入：
  scripts/data/official-library.json            parse_official_manual.py 产物（权威）
  Sources/TXBudget/Resources/full-library.json  v2.1.0 内置库（底本，提供价格/规格/供方继承）
  scripts/data/quota-data.js                    名称→台班编码解析（与 v2.1 转换同口径）
  Tests/TXBudgetTests/Fixtures/seed.json        同上（App 现行价目名称并集）
输出（覆写）：
  Sources/TXBudget/Resources/full-library.json  校正后的内置完整库

规则摘要（详见设计文档 §4）：
  - 定额共同编码：名称/单位/技工/普工 := 官方；book/alias/coef 沿用；手册外定额整行保留。
  - 关联（共同定额）整组按官方重建：数量 star→0、paren 保留数值；
    材料 remark：star→“设计选用”、paren→“设计选用(手册括号值)”；
    spec/supply（材料）与 mcode（机械/仪表）继承同定额同名现行行，无则解析/甲供/空码；
    rawProblem（官方多值存疑）行保留现行原值、无现行则不建行；
    现行中官方没有的关联行从内置库移除并计数。
  - materials：现行保留；被规则引用缺失者补入（价 0）；与校正规则同（归一化名, spec）
    而写法不同者改名为官方写法（价格字段不动），保留行规则的引用同步改名。
  - 台班价两表整表沿用现值，一字不动（手册无价格）。
输出确定性：顺序与 id 确定（新行 id 用 *_new_<序号>），重跑应逐字节一致。
"""
import json
import re
import sys
import unicodedata
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OFFICIAL = ROOT / "scripts" / "data" / "official-library.json"
LIB = ROOT / "Sources" / "TXBudget" / "Resources" / "full-library.json"
SRC_JS = ROOT / "scripts" / "data" / "quota-data.js"
SRC_SEED = ROOT / "Tests" / "TXBudgetTests" / "Fixtures" / "seed.json"


def norm(s: str) -> str:
    s = unicodedata.normalize("NFKC", s or "")
    s = re.sub(r"[\s　]+", "", s)
    return s.replace("ø", "Φ").replace("φ", "Φ").replace("~", "-").replace("—", "-")


def num(v):
    """整数值输出为 int（与 v2.1 产物风格一致），其余保留 float。"""
    if isinstance(v, float) and v.is_integer():
        return int(v)
    return v


def extract_const(js_text: str, name: str):
    m = re.search(r"const\s+%s\s*=\s*" % re.escape(name), js_text)
    start = js_text.index("[", m.end())
    depth, in_str, esc = 0, False, False
    for i in range(start, len(js_text)):
        ch = js_text[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        else:
            if ch == '"':
                in_str = True
            elif ch == "[":
                depth += 1
            elif ch == "]":
                depth -= 1
                if depth == 0:
                    return json.loads(js_text[start:i + 1])
    raise SystemExit(f"const {name} 数组未闭合")


def build_name_map(pairs):
    d = {}
    for code, name in pairs:
        d.setdefault(norm(name), set()).add(code)
    return {k: next(iter(v)) for k, v in d.items() if len(v) == 1}


def main() -> int:
    official = json.loads(OFFICIAL.read_text(encoding="utf-8"))
    lib = json.loads(LIB.read_text(encoding="utf-8"))
    off = {q["code"]: q for q in official}
    js = SRC_JS.read_text(encoding="utf-8")
    machines = extract_const(js, "MACHINES")
    instruments = extract_const(js, "INSTRUMENTS")
    seed = json.loads(SRC_SEED.read_text(encoding="utf-8"))
    mach_map = build_name_map([(m["code"], m["name"]) for m in machines]
                              + [(p["code"], p["name"]) for p in seed["machinePrices"]])
    inst_map = build_name_map([(m["code"], m["name"]) for m in instruments]
                              + [(p["code"], p["name"]) for p in seed["instrumentPrices"]])

    rep = {"quotasCorrected": 0, "quotasKeptExtra": 0, "quotasAdded": 0,
           "rulesRebuilt": 0, "rulesKeptProblem": 0, "rulesDropped": 0, "rulesProblemNoBase": 0,
           "qmRebuilt": 0, "qmDropped": 0, "qiRebuilt": 0, "qiDropped": 0,
           "materialsAdded": 0, "materialsRenamed": 0, "materialsDeduped": 0}

    # ---------------- 定额 ----------------
    quotas_out = []
    lib_codes = set()
    for q in lib["quotas"]:
        lib_codes.add(q["code"])
        o = off.get(q["code"])
        if o is None:
            rep["quotasKeptExtra"] += 1
            quotas_out.append(q)
            continue
        nq = OrderedDict(q)
        changed = (nq["name"] != o["name"] or nq["unit"] != o["unit"]
                   or float(nq["tech"]) != float(o["tech"]) or float(nq["labor"]) != float(o["labor"]))
        nq["name"], nq["unit"] = o["name"], o["unit"]
        nq["tech"], nq["labor"] = num(o["tech"]), num(o["labor"])
        if changed:
            rep["quotasCorrected"] += 1
        quotas_out.append(nq)
    for code, o in off.items():
        if code not in lib_codes:
            quotas_out.append(OrderedDict([
                ("id", f"fl_quota_{code}"), ("code", code), ("name", o["name"]),
                ("unit", o["unit"]), ("tech", num(o["tech"])), ("labor", num(o["labor"])),
                ("coef", 1), ("book", o["volume"]), ("alias", code.split("-")[0].rstrip("0123456789")),
            ]))
            rep["quotasAdded"] += 1
    common = set(off) & lib_codes

    # ---------------- 现行关联分组 ----------------
    def group(rows):
        d = {}
        for r in rows:
            d.setdefault(r["quota"], []).append(r)
        return d
    lib_rules, lib_qm, lib_qi = group(lib["rules"]), group(lib["quotaMachines"]), group(lib["quotaInstruments"])

    counters = {"rule": 0, "qm": 0, "qi": 0, "mat": 0}

    def new_id(kind):
        counters[kind] += 1
        return f"fl_{kind}_new_{counters[kind]}"

    # ---------------- 材料规则重建 ----------------
    rules_out = []
    kept_rule_objids = set()  # 原样保留的行（手册外定额整组 + 存疑沿用行）：不驱动材料改名
    for q in quotas_out:
        code = q["code"]
        if code not in common:
            for r in lib_rules.get(code, []):
                kept_rule_objids.add(id(r))
            rules_out.extend(lib_rules.get(code, []))  # 手册外定额：整组保留
            continue
        cur = lib_rules.get(code, [])
        used = set()
        for it in off[code]["materials"]:
            matches = [r for r in cur if norm(r["material"]) == norm(it["name"])]
            matches.sort(key=lambda r: 0 if r["spec"] == "" else 1)
            chosen = matches[0] if matches else None
            if "rawProblem" in it:
                if chosen is not None:
                    used.add(id(chosen))
                    kept_rule_objids.add(id(chosen))
                    rules_out.append(chosen)
                    rep["rulesKeptProblem"] += 1
                else:
                    rep["rulesProblemNoBase"] += 1
                continue
            if chosen is not None:
                used.add(id(chosen))
            remark = "设计选用" if it["star"] else ("设计选用(手册括号值)" if it["paren"] else "")
            rules_out.append(OrderedDict([
                ("id", chosen["id"] if chosen else new_id("rule")),
                ("quota", code), ("material", it["name"]),
                ("spec", chosen["spec"] if chosen else ""),
                ("unit", it["unit"]),
                ("consumption", num(0 if it["star"] else it["qty"])),
                ("supply", chosen["supply"] if chosen else "甲供"),
                ("kind", "通用"), ("variant", ""), ("remark", remark), ("appliesTo", "全"),
            ]))
            rep["rulesRebuilt"] += 1
        rep["rulesDropped"] += sum(1 for r in cur if id(r) not in used)

    # ---------------- 机械/仪表关联重建 ----------------
    def rebuild_assoc(lib_group, off_key, name_map, kind, rep_rebuilt, rep_dropped):
        out = []
        for q in quotas_out:
            code = q["code"]
            if code not in common:
                out.extend(lib_group.get(code, []))
                continue
            cur = lib_group.get(code, [])
            used = set()
            for it in off[code][off_key]:
                matches = [r for r in cur if norm(r["mname"]) == norm(it["name"])]
                chosen = matches[0] if matches else None
                if "rawProblem" in it:
                    if chosen is not None:
                        used.add(id(chosen))
                        out.append(chosen)
                    continue
                if chosen is not None:
                    used.add(id(chosen))
                mcode = (chosen["mcode"] if chosen and chosen["mcode"]
                         else name_map.get(norm(it["name"]), ""))
                out.append(OrderedDict([
                    ("id", chosen["id"] if chosen else new_id(kind)),
                    ("quota", code), ("mcode", mcode), ("mname", it["name"]),
                    ("unit", it["unit"]), ("qty", num(0 if it["star"] else it["qty"])),
                ]))
                rep[rep_rebuilt] += 1
            rep[rep_dropped] += sum(1 for r in cur if id(r) not in used)
        return out
    qm_out = rebuild_assoc(lib_qm, "machines", mach_map, "qm", "qmRebuilt", "qmDropped")
    qi_out = rebuild_assoc(lib_qi, "instruments", inst_map, "qi", "qiRebuilt", "qiDropped")

    # ---------------- materials 表 ----------------
    # 第一遍只由校正规则驱动：条目改名为官方写法 / 缺失补入（价格字段不动）。
    # 保留行规则绝不驱动改名（其旧写法会被动同步到条目现名，见第二遍），否则
    # 同名材料在“官方写法 ↔ 小程序写法”之间来回翻转、构建不幂等。
    materials_out = [OrderedDict(m) for m in lib["materials"]]
    mat_index = {}
    for m in materials_out:
        mat_index.setdefault((norm(m["name"]), m["spec"]), m)
    canonical = {}  # (norm, spec) -> 官方写法名（校正规则口径）
    for r in rules_out:
        if id(r) in kept_rule_objids:
            continue
        key = (norm(r["material"]), r["spec"])
        canonical[key] = r["material"]
        entry = mat_index.get(key)
        if entry is not None:
            if entry["name"] != r["material"]:
                entry["name"] = r["material"]
                rep["materialsRenamed"] += 1
            continue
        entry = OrderedDict([
            ("id", new_id("mat")), ("name", r["material"]), ("spec", r["spec"]),
            ("unit", r["unit"]), ("priceExcl", 0), ("supply", r["supply"]), ("remark", ""),
        ])
        materials_out.append(entry)
        mat_index[key] = entry
        rep["materialsAdded"] += 1
    # 第二遍：保留行规则若引用已被改名的材料，同步改名为条目现名，保持可查价。
    for r in rules_out:
        if id(r) not in kept_rule_objids:
            continue
        new_name = canonical.get((norm(r["material"]), r["spec"]))
        if new_name and r["material"] != new_name:
            r["material"] = new_name
    # 去重：v2.1 材料表有同（归一化名, spec）双写法条目（如“石棉水泥板（δ10）”与
    # “石棉水泥板 δ10”），改名后与官方条目同键并存会让 App 合并出现改名振荡；
    # 按（归一化名, spec）只保留首条，其余删除并计数（价格均为 0，非零价冲突停机）。
    deduped, seen_mat = [], {}
    for m in materials_out:
        k = (norm(m["name"]), m["spec"])
        if k in seen_mat:
            if m["priceExcl"] not in (0, seen_mat[k]["priceExcl"]):
                raise SystemExit(f"材料去重价格冲突，需人工裁决：{m['name']}")
            rep["materialsDeduped"] += 1
            continue
        seen_mat[k] = m
        deduped.append(m)
    materials_out = deduped

    tables = OrderedDict([
        ("quotas", quotas_out), ("shortlist", lib["shortlist"]), ("materials", materials_out),
        ("rules", rules_out), ("machinePrices", lib["machinePrices"]),
        ("instrumentPrices", lib["instrumentPrices"]),
        ("quotaMachines", qm_out), ("quotaInstruments", qi_out),
    ])
    lines = ["{"]
    items = list(tables.items())
    for ti, (key, rows) in enumerate(items):
        lines.append(f'  "{key}": [')
        for ri, row in enumerate(rows):
            suffix = "," if ri < len(rows) - 1 else ""
            lines.append("    " + json.dumps(row, ensure_ascii=False) + suffix)
        lines.append("  ]" + ("," if ti < len(items) - 1 else ""))
    lines.append("}")
    LIB.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"written: {LIB} ({LIB.stat().st_size} bytes)")
    for key, rows in tables.items():
        print(f"  {key}: {len(rows)}")
    print(json.dumps(rep, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
