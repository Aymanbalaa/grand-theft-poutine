from __future__ import annotations
import math
from collections import defaultdict
from pipeline import config
from pipeline.meshes import _densify, _polyline_slice, _clear_intervals

# Navigation graph for traffic (roads) and pedestrians (walks).
# Everything here is derived from the same Road polylines + heightmap the mesh
# builders use, so agents that follow these polylines sit on the baked ribbons
# without raycasts. Deterministic: sorted iteration, integer hashes, rounding.

ROAD_Y = 0.05                                             # road_mesh's surface offset
WALK_Y = 0.05 + config.SIDEWALK_RAISE                     # sidewalk_mesh's top surface (+ per-road jitter)
SIDE_OFFSET_EXTRA = config.CURB_RUN + config.SIDEWALK_WIDTH / 2.0   # + w/2 = sidewalk centerline

def road_junctions(roads) -> frozenset:
    """Rounded (x, z) vertices shared by >= 2 sidewalk/roadmark-class roads.
    Moved verbatim from tiler.build_tiles so nav walks trim exactly like the
    sidewalk meshes (tiler imports this)."""
    counts: dict[tuple[float, float], int] = defaultdict(int)
    for r in roads:
        if r.road_class in config.SIDEWALK_CLASSES or r.road_class in config.ROADMARK_CLASSES:
            for x, z in r.points:
                counts[(round(x, 2), round(z, 2))] += 1
    return frozenset(k for k, v in counts.items() if v >= 2)

class _Nodes:
    """Interns [x, y, z] rows by rounded (x, z, kind) so shared OSM vertices
    become shared node indices (implicit adjacency)."""
    def __init__(self) -> None:
        self.rows: list[list[float]] = []
        self._index: dict[tuple, int] = {}

    def get(self, x: float, z: float, y: float, kind: str) -> int:
        key = (round(x, 1), round(z, 1), kind)
        i = self._index.get(key)
        if i is None:
            i = len(self.rows)
            self._index[key] = i
            self.rows.append([round(x, 1), round(y, 2), round(z, 1)])
        return i

class _Grid:
    """Spatial hash of node indices (cell = 8 m) for radius queries."""
    def __init__(self, cell: float = 8.0) -> None:
        self.cell = cell
        self.cells: dict[tuple[int, int], list[int]] = defaultdict(list)

    def add(self, x: float, z: float, i: int) -> None:
        self.cells[(math.floor(x / self.cell), math.floor(z / self.cell))].append(i)

    def near(self, x: float, z: float, radius: float):
        cx, cz = math.floor(x / self.cell), math.floor(z / self.cell)
        n = int(math.ceil(radius / self.cell))
        for dx in range(-n, n + 1):
            for dz in range(-n, n + 1):
                yield from self.cells.get((cx + dx, cz + dz), ())

def _ground(hm, x: float, z: float) -> float:
    return hm.sample(x, z) if hm is not None else 0.0

def _dedupe(idx: list[int]) -> list[int]:
    out: list[int] = []
    for i in idx:
        if not out or out[-1] != i:
            out.append(i)
    return out

def _road_speed(r) -> float:
    if r.maxspeed is not None and r.maxspeed > 0:
        return round(r.maxspeed, 2)
    cls = r.road_class[:-5] if r.road_class.endswith("_link") else r.road_class
    return config.NAV_SPEED_DEFAULTS.get(cls, config.NAV_SPEED_DEFAULTS["residential"])

def _build_roads(roads, hm, nodes: _Nodes) -> list[dict]:
    out: list[dict] = []
    for r in sorted(roads, key=lambda r: r.osm_id):
        if r.road_class not in config.NAV_DRIVABLE_CLASSES or len(r.points) < 2:
            continue
        pts = _densify(r.points)
        if r.oneway_reversed:
            pts = pts[::-1]
        idx = _dedupe([nodes.get(x, z, _ground(hm, x, z) + ROAD_Y, "road") for x, z in pts])
        if len(idx) < 2:
            continue
        lanes = r.lanes if (r.lanes is not None and r.lanes > 0) else (1 if r.oneway else 2)
        out.append({"id": r.osm_id, "n": idx, "cls": r.road_class, "w": r.width,
                    "oneway": 1 if r.oneway else 0, "lanes": lanes, "speed": _road_speed(r)})
    return out

def _snap_signals(signals, nodes: _Nodes, roads_out: list[dict]) -> list[int]:
    grid = _Grid()
    seen: set[int] = set()
    for rd in roads_out:
        for i in rd["n"]:
            if i not in seen:
                seen.add(i)
                x, _, z = nodes.rows[i]
                grid.add(x, z, i)
    out: set[int] = set()
    for sx, sz in signals:
        best, best_d = None, config.NAV_SIGNAL_SNAP
        for i in grid.near(sx, sz, config.NAV_SIGNAL_SNAP):
            x, _, z = nodes.rows[i]
            d = math.hypot(x - sx, z - sz)
            if d < best_d:
                best, best_d = i, d
        if best is not None:
            out.add(best)
    return sorted(out)

def _build_walks(roads, hm, nodes: _Nodes, path_radius: float | None) -> list[dict]:
    return []   # Task 3

def build_nav(city, hm=None, path_radius: float | None = None) -> dict:
    """Road + walk graph. `path_radius`: when set, footpath ways whose first
    point is farther than this from the origin are skipped (size guard)."""
    nodes = _Nodes()
    roads_out = _build_roads(city.roads, hm, nodes)
    signals = _snap_signals(city.signals, nodes, roads_out)
    walks = _build_walks(city.roads, hm, nodes, path_radius)
    return {"nodes": nodes.rows, "roads": roads_out, "signals": signals, "walks": walks}
