"""One-time, boat-owned data migration from the audited 13 groups to local units."""
import copy
import json
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent
EVIDENCE = PACKAGE / "evidence" / "connected_groups"
old_path = EVIDENCE / "previous_13_groups.json"
if not old_path.exists():
    old_path.write_bytes((PACKAGE / "config" / "assembly.json").read_bytes())
old = json.loads(old_path.read_text(encoding="utf-8"))
templates = {g["id"]: g for g in old["groups"]}
geometry = {g["root"]: g for g in json.loads((EVIDENCE / "source_geometry.json").read_text(encoding="utf-8"))}
mesh_records = {m["name"]: m for root in geometry.values() for m in root["meshes"]}
groups = []


def add(template, gid, label, roots, requires, basis, members=(), anchor=None):
    g = copy.deepcopy(templates[template])
    g.update(id=gid, label=label, roots=list(roots), requires=list(requires), connection_basis=basis)
    if members:
        g["mesh_members"] = list(members)
    meshes = [m for root in roots for m in geometry[root]["meshes"]] + [mesh_records[n] for n in members]
    lo = [min(m["min"][a] for m in meshes) for a in range(3)]
    hi = [max(m["min"][a] + m["size"][a] for m in meshes) for a in range(3)]
    center = [(lo[a] + hi[a]) / 2 for a in range(3)]
    if anchor is None:
        anchor = center
    g["anchor_m"] = list(anchor)
    g.pop("drop_anchor", None)
    g.pop("drop_trigger_axis", None)
    g["lesson"]["focus_m"] = list(anchor)
    g["lesson"]["context_roots"] = list(dict.fromkeys(roots + ["K1"]))
    g["lesson"]["moving_meshes"] = [m["name"] for m in meshes]
    g["connection_meshes"] = [m["name"] for m in meshes[:1]]
    g["source_mesh_count"] = len(meshes)
    g["source_bounds_m"] = {"min": lo, "max": hi}
    groups.append(g)
    return g


add("keel_center", "keel_center", "中央龙骨", ["K1"], [], "单根连续中央龙骨。", anchor=[1.3715, 0.0187257, 0])
g = add("keel_ends", "keel_bow", "艏段龙骨", ["K0"], ["keel_center"], "艏段接中央龙骨前端，与艉段相隔约1.65m，单独操作。", anchor=[0.743, 0.035, 0])
g["lesson"]["title"] = "艏段短斜接靠合"
g["approach_m"] = [-0.065, 0, 0]
g = add("keel_ends", "keel_stern", "艉段龙骨", ["K2"], ["keel_center"], "艉段接中央龙骨后端，未与艏段合为同一卡。", anchor=[2.0, 0.035, 0])
g["lesson"]["title"] = "艉段短斜接靠合"
g["approach_m"] = [0.065, 0, 0]
for side, prefix, fasteners, z in [("port", "SP", "F-1", 0.035), ("starboard", "SS", "F1", -0.035)]:
    label = "左舷内板与钉固组" if side == "port" else "右舷内板与钉固组"
    g = add("shell_" + side, "shell_" + side, label, [f"{prefix}_{i:02}" for i in range(1, 9)] + [fasteners], ["keel_bow", "keel_stern"], "同侧连续板列互相邻接，钉固件归入其附着船侧；整组原位建造，不演示整壳刚体插入。", anchor=[0.901, 0.045, z])
    g["lesson"]["context_roots"] = ["K1", f"{prefix}_01", f"{prefix}_02"]
    g["lesson"]["moving_meshes"] = list(templates["shell_" + side]["lesson"]["moving_meshes"])

bulkheads = []
for index in range(1, 13):
    gid = f"bulkhead_{index:02}"
    root = f"B{index:02}"
    bulkheads.append(gid)
    p = geometry[root]["center"]
    g = add("bulkheads", gid, f"第{index}道隔舱与梁", [root], ["shell_port", "shell_starboard"], "同一道隔舱的半肋、隔板及顶部横梁相连；相邻隔舱留有独立舱距，未捆绑。", anchor=[p[0], p[1], geometry[root]["size"][2] * 0.35])
    g["lesson"]["title"] = f"第{index}道隔舱与船板连接"
    g["lesson"]["context_roots"] += [f"SP_{i:02}" for i in range(2, 8)]
    g["lesson"]["section_half_m"] = [0.10, 0.2, 0.18]

g = add("mast_beds", "mast_bed_fore", "前桅座与夹木", ["MS_fore"], ["bulkhead_01"], "前桅的宽座、夹木和纵向承座局部相接，与主桅座分开。", anchor=[0.721, 0.119, 0.03275])
g["lesson"].pop("joint_id", None)
g["lesson"].pop("joint_origin_m", None)
g["lesson"].update(kind="contact", title="前桅座与夹木就位", source_note="交付整船前桅座的真实局部。未把主桅v3扩展局部冒充前桅原件。")
g = add("mast_beds", "mast_bed_main", "主桅座与夹木", ["MS_main"], ["bulkhead_05", "bulkhead_06"], "主桅宽座与两侧夹木、承座相连，位于前桅座之后约0.73m。", anchor=[1.453, 0.1, 0.03275])
g["lesson"]["moving_meshes"] = templates["mast_beds"]["lesson"]["moving_meshes"]

for side, prefix, rail in [("port", "O-1", "RAIL-1"), ("starboard", "O1", "RAIL1")]:
    g = add("outer", "outer_" + side, ("左" if side == "port" else "右") + "舷外护板与压木", [prefix + "_0", prefix + "_1", rail], bulkheads, "同一船侧前后护板在中段接缝相邻，缘压木沿该侧上缘连接；左右舷不合并。", anchor=[1.343, 0.13, 0.155 if side == "port" else -0.155])
    g["lesson"]["nail_side"] = "F-1" if side == "port" else "F1"
    g["lesson"]["title"] = "外护板贴合 · 轻钉模型未单列"
    g["lesson"]["source_note"] = "WA1997 p40/PDF49区分外护层轻钉与p41主结构板跨缝斜钉。交付F±1为本包按内板贴面的结构钉；外护轻钉未单列，不复用结构钉冒充。"
    g["lesson"]["context_roots"] += [("SP_" if side == "port" else "SS_") + f"{i:02}" for i in range(3, 7)]
    g["approach_m"] = [0, 0, 0.025 if side == "port" else -0.025]

supports = geometry["DECK_SUPPORTS"]["meshes"]
bow_supports = [m["name"] for m in supports if m["center"][0] < 1]
stern_supports = [m["name"] for m in supports if m["center"][0] > 2]
g = add("deck", "deck_bow", "艏甲板与当地支承", ["D0"], ["mast_bed_fore", "bulkhead_01"], "艏甲板、x=0.30/0.52m的承梁及对应柱脚相接；艉部支承不在此卡。", members=bow_supports, anchor=[0.3, 0.3474, 0.1122])
g["lesson"]["moving_meshes"] = templates["deck"]["lesson"]["moving_meshes"]
for side, sign in [("port", 1), ("starboard", -1)]:
    members = [m["name"] for root in ["D1", "D2"] for m in geometry[root]["meshes"] if m["center"][2] * sign > 0]
    g = add("deck", "deck_walkway_" + side, ("左" if side == "port" else "右") + "舷舱口边甲板", [], bulkheads[:10] + ["mast_bed_fore", "mast_bed_main"], "同侧前后舱口边甲板在x≈1.343m相邻接续，含该侧围板；左右之间有舱口，不合成一块。", members=members)
    g["lesson"].pop("joint_id", None)
    g["lesson"].pop("joint_origin_m", None)
    g["lesson"].update(kind="planking", title="同侧舱口边板逐段就位", source_note="展示复原的边甲板与围板，按实际同侧邻接组合。板列为原位建造示意，不宣称整组刚体插入。")
g = add("deck", "deck_stern", "艉甲板与当地支承", ["D3"], bulkheads[8:], "艉甲板、x=2.50/2.625m的承梁及柱脚相接，与艏支承分离。", members=stern_supports, anchor=[2.5, 0.40, 0.2])
g["lesson"].pop("joint_id", None)
g["lesson"].pop("joint_origin_m", None)
g["lesson"].update(kind="planking", title="艉部甲板与支承就位", source_note="艉部甲板与当地支承均为交付展示复原，未复制艏部v3柱梁扩展作为艉部原件。")

for mast in ["fore", "main"]:
    g = add("masts", "mast_rig_" + mast, ("前" if mast == "fore" else "主") + "桅帆索总成", ["M_" + mast, "SAIL_" + mast, "RIG_" + mast, "RIG_HARDWARE_" + mast], ["mast_bed_" + mast, "deck_bow" if mast == "fore" else "deck_stern", "deck_walkway_port", "deck_walkway_starboard"], "同一桅杆、帆桁/帆面、相系索具与相连系桩构成一个连接网络；前主桅分开，帆索按就地展开呈现。", anchor=[0.721 if mast == "fore" else 1.453, 0.15, 0])
    g["lesson"].update(kind="rigged_mast", title=("前" if mast == "fore" else "主") + "桅定位与帆索系装", core_roots=["M_" + mast], source_note="整船交付的同桅帆索连接网络，桅高、风帆及部分系装为展示复原。帆索逐步显现，不作为整套刚体插入。")
    g["lesson"]["context_roots"] += ["MS_" + mast]
    g["lesson"]["moving_meshes"] = [m["name"] for m in geometry["M_" + mast]["meshes"]]

g = add("rudder", "rudder", "艉舵架与升降舵总成", ["RUDDER_FRAME", "RUDDER_SLIDE", "RUDDER_CAPS", "RUDDER_CAP_PEGS", "RUDDER_HOIST_ROPE"], ["deck_stern", "outer_port", "outer_starboard"], "同一艉部舵槽、舵身、导木压块与穿过提升横架的提舵索局部连结；没有把前部索具捆入。", anchor=[2.62, 0.47, 0])

actual = [m["name"] for g in groups for r in g["roots"] for m in geometry[r]["meshes"]] + [m for g in groups for m in g.get("mesh_members", [])]
expected = set(mesh_records)
assert len(groups) == 28
assert len(actual) == len(set(actual)) == len(expected) == 1286
assert set(actual) == expected
ids = {g["id"] for g in groups}
for i, g in enumerate(groups):
    assert set(g["requires"]) <= {prev["id"] for prev in groups[:i]}
    g["lesson"]["distance_m"] = min(g["lesson"]["distance_m"], 0.7)

result = {"drop_tolerance": old["drop_tolerance"], "grouping": "28 local connected assembly units; source geometry unchanged", "groups": groups}
(PACKAGE / "config" / "assembly.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(EVIDENCE / "grouping_review.json").write_text(json.dumps({"groups": [{k: g[k] for k in ["id", "label", "roots", "requires", "connection_basis", "source_mesh_count", "anchor_m"]} | {"mesh_members": g.get("mesh_members", [])} for g in groups], "unique_meshes": len(actual), "source_roots": len(geometry), "review_note": "Source hierarchy and metre-space bounds guide local assembly grouping; this is not physical collision or archaeological preassembly proof."}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Generated {len(groups)} connected operation groups; {len(actual)} unique source meshes.")
