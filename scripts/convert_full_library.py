#!/usr/bin/env python3
"""小程序种子数据 → 滑洲智算内置完整库 转换脚本（v2.1.0，见 docs/v2.1-data-completion-design.md）。

输入（路径相对仓库根目录，即本脚本的上级目录）：
  scripts/data/quota-data.js                    用户小程序种子（2026-10-22 导出包留档）
  Tests/TXBudgetTests/Fixtures/seed.json        App 现行种子（仅用于无编码条目的名称→编码解析）
输出：
  Sources/TXBudget/Resources/full-library.json  LibrarySet 八表格式的完整库（随 App 内置）

规则摘要（详见设计文档 §4）：
  - quotas: tech=skilled, labor=unskilled, book=volume, alias=vol, coef=1
  - 关联表: qty=qtyPerUnit；条目自带 price 不入关联表（价格只走价目表）
  - 无 model 条目: 名称 NFKC 归一化去空白后与价目表名称逐字比对，唯一命中才采用其编码；
    仍无编码者保留行、mcode 置空（不臆造编码）
  - rules: kind="通用", variant="", appliesTo="全"（引擎对“通用”按定额全部工程量取量）；
    (quota, material, spec) 同键保留首行；supply 缺失按甲供
  - materials: 由 defaultMaterials 按 (name, spec) 去重；priceExcl=0；supply 不一致或全缺失取甲供
  - 台班价: MACHINES / INSTRUMENTS 全量转入（合并时只补 App 缺失编码，见 Logic/LibraryCompletion.swift）
输出确定性：顺序与 id 确定，重跑应逐字节一致。用 python3 运行，无第三方依赖。
"""
import json
import re
import sys
import unicodedata
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_JS = ROOT / "scripts" / "data" / "quota-data.js"
SRC_SEED = ROOT / "Tests" / "TXBudgetTests" / "Fixtures" / "seed.json"
OUT = ROOT / "Sources" / "TXBudget" / "Resources" / "full-library.json"


def extract_const(js_text: str, name: str):
    """从 quota-data.js 中提取 `const NAME = [ ... ];` 的 JSON 数组（括号配平扫描，字符串感知）。"""
    m = re.search(r"const\s+%s\s*=\s*" % re.escape(name), js_text)
    if not m:
        raise SystemExit(f"未找到 const {name}")
    start = js_text.index("[", m.end())
    depth = 0
    in_str = False
    esc = False
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


def norm_name(s: str) -> str:
    return re.sub(r"\s+", "", unicodedata.normalize("NFKC", s or ""))


def build_name_map(pairs):
    """名称（归一化）→ 编码集合；只收唯一命中的名称。"""
    d = {}
    for code, name in pairs:
        d.setdefault(norm_name(name), set()).add(code)
    return {k: next(iter(v)) for k, v in d.items() if len(v) == 1}


def main() -> int:
    js = SRC_JS.read_text(encoding="utf-8")
    quota = extract_const(js, "QUOTA")
    machines = extract_const(js, "MACHINES")
    instruments = extract_const(js, "INSTRUMENTS")
    seed = json.loads(SRC_SEED.read_text(encoding="utf-8"))

    # 名称→编码解析表：小程序自身价目 + App 现行价目（并集，均要求名称唯一对应一个编码）
    mach_name2code = build_name_map(
        [(m["code"], m["name"]) for m in machines]
        + [(p["code"], p["name"]) for p in seed["machinePrices"]])
    inst_name2code = build_name_map(
        [(m["code"], m["name"]) for m in instruments]
        + [(p["code"], p["name"]) for p in seed["instrumentPrices"]])

    report = {
        "resolvedMachines": 0, "emptyCodeMachines": 0,
        "resolvedInstruments": 0, "emptyCodeInstruments": 0,
        "ruleConflicts": [], "materialsMultiSupply": 0,
    }

    def resolve(entry, name2code, kind):
        model = entry.get("model") or ""
        if model:
            return model
        code = name2code.get(norm_name(entry.get("name", "")))
        if code:
            report["resolved" + kind] += 1
            return code
        report["emptyCode" + kind] += 1
        return ""

    quotas_out, qm_out, qi_out, rules_out = [], [], [], []
    rule_seen = {}          # (quota, material, spec) -> consumption（保留首行）
    mat_acc = OrderedDict()  # (name, spec) -> {unit, supplies:set}
    for q in quota:
        code = q["code"]
        quotas_out.append(OrderedDict([
            ("id", f"fl_quota_{code}"), ("code", code), ("name", q.get("name", "")),
            ("unit", q.get("unit", "")), ("tech", q.get("skilled", 0)),
            ("labor", q.get("unskilled", 0)), ("coef", 1),
            ("book", q.get("volume", "")), ("alias", q.get("vol", "")),
        ]))
        for e in q.get("defaultMachines") or []:
            qm_out.append(OrderedDict([
                ("id", f"fl_qm_{len(qm_out)}"), ("quota", code),
                ("mcode", resolve(e, mach_name2code, "Machines")),
                ("mname", e.get("name", "")), ("unit", e.get("unit", "")),
                ("qty", e.get("qtyPerUnit", 0)),
            ]))
        for e in q.get("defaultInstruments") or []:
            qi_out.append(OrderedDict([
                ("id", f"fl_qi_{len(qi_out)}"), ("quota", code),
                ("mcode", resolve(e, inst_name2code, "Instruments")),
                ("mname", e.get("name", "")), ("unit", e.get("unit", "")),
                ("qty", e.get("qtyPerUnit", 0)),
            ]))
        for e in q.get("defaultMaterials") or []:
            key = (code, e.get("name", ""), e.get("spec", ""))
            supply = e.get("supply") or "甲供"
            if key in rule_seen:
                if abs(rule_seen[key] - (e.get("qtyPerUnit", 0))) > 1e-9:
                    report["ruleConflicts"].append(
                        {"key": key, "kept": rule_seen[key], "dropped": e.get("qtyPerUnit", 0)})
                continue
            rule_seen[key] = e.get("qtyPerUnit", 0)
            rules_out.append(OrderedDict([
                ("id", f"fl_rule_{len(rules_out)}"), ("quota", code),
                ("material", e.get("name", "")), ("spec", e.get("spec", "")),
                ("unit", e.get("unit", "")), ("consumption", e.get("qtyPerUnit", 0)),
                ("supply", supply), ("kind", "通用"), ("variant", ""),
                ("remark", ""), ("appliesTo", "全"),
            ]))
            mk = (e.get("name", ""), e.get("spec", ""))
            acc = mat_acc.setdefault(mk, {"unit": e.get("unit", ""), "supplies": set()})
            if e.get("supply"):
                acc["supplies"].add(e["supply"])

    materials_out = []
    for (name, spec), acc in mat_acc.items():
        supplies = acc["supplies"]
        if len(supplies) == 1:
            supply = next(iter(supplies))
        else:
            if len(supplies) > 1:
                report["materialsMultiSupply"] += 1
            supply = "甲供"
        materials_out.append(OrderedDict([
            ("id", f"fl_mat_{len(materials_out)}"), ("name", name), ("spec", spec),
            ("unit", acc["unit"]), ("priceExcl", 0), ("supply", supply), ("remark", ""),
        ]))

    mp_out = [OrderedDict([("id", f"fl_mp_{m['code']}"), ("code", m["code"]),
                           ("name", m.get("name", "")), ("unit", "台班"),
                           ("price", m.get("price", 0))]) for m in machines]
    ip_out = [OrderedDict([("id", f"fl_ip_{m['code']}"), ("code", m["code"]),
                           ("name", m.get("name", "")), ("unit", "台班"),
                           ("price", m.get("price", 0))]) for m in instruments]

    tables = OrderedDict([
        ("quotas", quotas_out), ("shortlist", []), ("materials", materials_out),
        ("rules", rules_out), ("machinePrices", mp_out), ("instrumentPrices", ip_out),
        ("quotaMachines", qm_out), ("quotaInstruments", qi_out),
    ])

    # 一行一条记录地写出（确定性、可抽查）。
    lines = ["{"]
    items = list(tables.items())
    for ti, (key, rows) in enumerate(items):
        lines.append(f'  "{key}": [')
        for ri, row in enumerate(rows):
            suffix = "," if ri < len(rows) - 1 else ""
            lines.append("    " + json.dumps(row, ensure_ascii=False) + suffix)
        lines.append("  ]" + ("," if ti < len(items) - 1 else ""))
    lines.append("}")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")

    print(f"written: {OUT} ({OUT.stat().st_size} bytes)")
    for key, rows in tables.items():
        print(f"  {key}: {len(rows)}")
    print(f"  无编码按名称解析: 机械 {report['resolvedMachines']} / 仪表 {report['resolvedInstruments']}")
    print(f"  仍无编码保留空码: 机械 {report['emptyCodeMachines']} / 仪表 {report['emptyCodeInstruments']}")
    print(f"  材料 supply 多值材料数: {report['materialsMultiSupply']}")
    for c in report["ruleConflicts"]:
        print(f"  规则同键消耗冲突（保留首行）: {c['key']} kept={c['kept']} dropped={c['dropped']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
