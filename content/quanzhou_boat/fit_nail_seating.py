"""Boat-specific offline seating audit. Reads the unchanged GLB, writes transform data.

One CPU thread, no renderer. Each source head/shaft moves together along its
existing shaft axis until the head bears on timber and the shaft is seated.
"""
import json
import mmap
import struct
import time
from pathlib import Path

import numpy as np

BASE = Path(__file__).resolve().parent
handle = (BASE / "assets/quanzhou_complete.glb").open("rb")
blob = mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ)
json_length = struct.unpack_from("<I", blob, 12)[0]
doc = json.loads(blob[20:20 + json_length])
binary = 28 + json_length
nodes = doc["nodes"]
parents = {child: i for i, n in enumerate(nodes) for child in n.get("children", [])}
names = {n.get("name", "").replace(".", "_"): i for i, n in enumerate(nodes)}
worlds = {}


def world(i):
    if i in worlds:
        return worlds[i]
    n = nodes[i]
    if "matrix" in n:
        m = np.array(n["matrix"], dtype=float).reshape(4, 4).T
    else:
        x, y, z, w = n.get("rotation", [0, 0, 0, 1])
        rotation = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                             [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                             [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
        m = np.eye(4)
        m[:3, :3] = rotation @ np.diag(n.get("scale", [1, 1, 1]))
        m[:3, 3] = n.get("translation", [0, 0, 0])
    if i in parents:
        m = world(parents[i]) @ m
    worlds[i] = m
    return m


def accessor(i):
    a = doc["accessors"][i]
    view = doc["bufferViews"][a["bufferView"]]
    dtype = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}[a["componentType"]]
    width = {"SCALAR": 1, "VEC3": 3}[a["type"]]
    stride = view.get("byteStride", np.dtype(dtype).itemsize * width)
    return np.ndarray((a["count"], width), dtype=dtype, buffer=blob,
                      offset=binary+view.get("byteOffset", 0)+a.get("byteOffset", 0),
                      strides=(stride, np.dtype(dtype).itemsize))


def descendants(root):
    result = []
    stack = [names[root]]
    while stack:
        i = stack.pop()
        if "mesh" in nodes[i]:
            result.append(i)
        stack.extend(nodes[i].get("children", []))
    return result


def geometry(i):
    vertices, triangles = [], []
    m = world(i)
    for p in doc["meshes"][nodes[i]["mesh"]]["primitives"]:
        v = accessor(p["attributes"]["POSITION"]).astype(float) @ m[:3, :3].T + m[:3, 3]
        index = accessor(p["indices"]).reshape(-1).astype(int)
        vertices.append(v)
        triangles.append(v[index.reshape(-1, 3)])
    return np.concatenate(vertices), np.concatenate(triangles)


def ray_hit(origin, direction, timber):
    closest = None
    for name, tri, low, high in timber:
        end = origin + direction * 0.13
        if np.any(np.minimum(origin, end) > high) or np.any(np.maximum(origin, end) < low):
            continue
        a, e1, e2 = tri[:, 0], tri[:, 1]-tri[:, 0], tri[:, 2]-tri[:, 0]
        p = np.cross(direction, e2)
        determinant = np.einsum("ij,ij->i", e1, p)
        good = np.abs(determinant) > 1e-13
        inv = np.zeros_like(determinant)
        inv[good] = 1 / determinant[good]
        tvec = origin-a
        u = np.einsum("ij,ij->i", tvec, p)*inv
        q = np.cross(tvec, e1)
        v = q @ direction*inv
        t = np.einsum("ij,ij->i", e2, q)*inv
        good &= (u >= -1e-8) & (v >= -1e-8) & (u+v <= 1+1e-8) & (t >= 0) & (t <= .13)
        if not np.any(good):
            continue
        hit_index = np.flatnonzero(good)[np.argmin(t[good])]
        distance = float(t[hit_index])
        if closest is None or distance < closest[0]:
            normal = np.cross(e1[hit_index], e2[hit_index])
            normal /= np.linalg.norm(normal)
            closest = (distance, origin+direction*distance, normal, name)
    return closest


rows, skipped = [], []
for side, prefix in [("F-1", "SP"), ("F1", "SS")]:
    timber = []
    for band in range(1, 9):
        for i in descendants(f"{prefix}_{band:02}"):
            vertices, tri = geometry(i)
            timber.append((nodes[i]["name"], tri, vertices.min(0), vertices.max(0)))
    for i in descendants(side):
        name = nodes[i]["name"].replace(".", "_")
        if not name.startswith("Driven iron shank"):
            continue
        head_name = "Iron fastening head" + name[len("Driven iron shank"):]
        shaft, _ = geometry(i)
        head, _ = geometry(names[head_name])
        sc = (shaft.min(0)+shaft.max(0))/2
        hc = (head.min(0)+head.max(0))/2
        axis = hc-sc
        length = float(np.linalg.norm(axis)*2)
        axis /= np.linalg.norm(axis)
        hit = ray_hit(hc+axis*.03, -axis, timber)
        if hit is None:
            skipped.append({"shank": name, "reason": "no timber triangle hit"})
            continue
        _, surface, normal, wood_name = hit
        if normal @ axis < 0:
            normal = -normal
        cosine = float(normal @ axis)
        gap = float(((head-surface) @ normal).min())
        shaft_out = float(((shaft-surface) @ normal).max())
        shift = max(0., gap-.0001, shaft_out-.0001)/max(cosine, .001)
        if cosine < .25 or shift > .015 or shift > length*.7:
            skipped.append({"shank": name, "reason": "unsafe or ambiguous axial seating", "shift": shift, "cosine": cosine})
            continue
        delta = -axis*shift
        head_top_after = float(((head+delta-surface) @ normal).max())
        if head_top_after < .0002:
            skipped.append({"shank": name, "reason": "seating would bury the entire head"})
            continue
        rows.append({"shank": name, "head": head_name, "delta_world_m": delta.tolist(),
                     "wood_mesh": wood_name, "wood_surface_m": surface.tolist(), "surface_normal": normal.tolist(),
                     "head_center_source_m": hc.tolist(), "axis_out": axis.tolist(), "source_length_m": length,
                     "head_bearing_gap_before_m": gap, "head_bearing_gap_after_m": gap-shift*cosine,
                     "head_top_after_m": head_top_after,
                     "shaft_projection_before_m": max(0., float(((shaft-surface) @ normal).max())),
                     "shaft_projection_after_m": max(0., float(((shaft+delta-surface) @ normal).max())),
                     "axial_shift_m": shift})
        time.sleep(.001)  # Keep this one-off CPU-only audit cooperative with other apps.
output = {"schema": 1, "source_asset": "assets/quanzhou_complete.glb", "method": "Actual GLB timber triangles; along the unchanged shaft axis, seat the head against timber and bury the shaft to <=0.1mm plane tolerance while retaining visible head geometry. No geometry scaling or hidden fasteners.", "pairs": rows, "unresolved": skipped}
(BASE / "config/nail_seating.json").write_text(json.dumps(output, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
print(json.dumps({"pairs": len(rows), "unresolved": len(skipped), "max_shift_m": max(r["axial_shift_m"] for r in rows), "max_shaft_before_m": max(r["shaft_projection_before_m"] for r in rows), "max_shaft_after_m": max(r["shaft_projection_after_m"] for r in rows)}, indent=2))
