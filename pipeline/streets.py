from __future__ import annotations
import math
from pipeline import config
from pipeline.geo import latlon_to_xz

def build_street_grid(roads) -> dict:
    cell = config.STREET_GRID_CELL
    names: list[str] = []
    name_idx: dict[str, int] = {}
    best: dict[tuple[int, int], tuple[float, int]] = {}
    for r in sorted((r for r in roads if r.name), key=lambda r: (r.name, r.osm_id)):
        if r.name not in name_idx:
            name_idx[r.name] = len(names)
            names.append(r.name)
        idx = name_idx[r.name]
        for (x1, z1), (x2, z2) in zip(r.points[:-1], r.points[1:]):
            seg = math.hypot(x2 - x1, z2 - z1)
            steps = max(1, math.ceil(seg / (cell / 2.0)))
            for i in range(steps + 1):
                x = x1 + (x2 - x1) * i / steps
                z = z1 + (z2 - z1) * i / steps
                key = (math.floor(x / cell), math.floor(z / cell))
                cx = (key[0] + 0.5) * cell
                cz = (key[1] + 0.5) * cell
                d = math.hypot(x - cx, z - cz)
                if key not in best or d < best[key][0] - 1e-9:
                    best[key] = (d, idx)
    grid = {f"{k[0]},{k[1]}": v[1] for k, v in sorted(best.items())}
    return {"cell": cell, "names": names, "grid": grid}

def district_polys() -> list[dict]:
    out = []
    for d in config.DISTRICTS:
        s, w, n, e = d["box"]
        corners = [latlon_to_xz(n, w), latlon_to_xz(n, e),
                   latlon_to_xz(s, e), latlon_to_xz(s, w)]
        out.append({"name": d["name"],
                    "poly": [[round(x, 1), round(z, 1)] for x, z in corners]})
    return out
