# M10a — Nav Export & Traffic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export a road + sidewalk navigation graph from the pipeline (one rebuild, tiles byte-identical) and ship pooled traffic cars that drive the real streets on the right, queue at the real signal positions, brake for the player, and collide physically with the player's car.

**Architecture:** (1) Pipeline: `pipeline/nav.py::build_nav(city, hm)` turns the already-parsed OSM roads into `game/world/nav.json` — shared `nodes` with baked heights, drivable `roads` (oneway-normalized, lanes, speed), snapped `signals`, and `walks` (analytic sidewalk offsets + footpaths + corner crossings). (2) Game: `nav_graph.gd` (pure data/queries, `RefCounted`) answers lane-centerline and exit questions; `traffic.gd` is ONE manager node with parallel state arrays over a pool of 40 `traffic_car.tscn` (`AnimatableBody3D` + `car_visual.gd`) — spawn ring, cone-following, parked-car nudge, signal phases, junction yield, pooled headlights. No per-agent scripts, no raycasts (heights ride the graph).

**Tech Stack:** Python 3 pipeline (pytest, no new deps — reuses `pipeline/meshes.py` polyline helpers), Godot 4.5 GDScript (`AnimatableBody3D`, `SpotLight3D`, `JSON`, `FileAccess`), headless `SceneTree` tests.

**Spec:** `docs/superpowers/specs/2026-09-11-m10-pedestrians-traffic-design.md` (sub-phase 10a; 10b pedestrians is a separate plan and consumes the `walks` exported here).

## Global Constraints

- Commits authored ONLY by Aymanbalaa via the repo-local git config (noreply email). NO `Co-Authored-By`/AI/session trailers, NO `--author` flags, NO git-config changes. Repeat verbatim in every subagent dispatch.
- Commit small and frequent; one commit per task minimum. Commit message prefixes in repo style: `pipeline:`, `game:`, `world:`, `docs:`.
- Deterministic pipeline: NO network in `pipeline.build`; both caches (`data/osm_downtown.osm.xml`, `data/heightmap.npy` + `heightmap_meta.json`) already exist — do NOT delete them. Iterate sorted; integer hashes only (no `math.sin`); `json.dumps(..., sort_keys=True)`.
- Rebuild rules: expect 314 tiles; after `python -m pipeline.build` the ONLY changes under `game/world/` must be `city_metadata.json` (one new key) and the new `nav.json` — every `.glb` byte-identical (`git status --short game/world/` shows nothing else). No `--import` is needed (JSON is not an imported resource; tiles are unchanged).
- Contracts untouched: `car_spawns` schema and the 120 parked cars, `car.tscn`/`car.gd` (traffic is a SEPARATE scene), `night_amount` global, vertex-alpha packing, facade `bhash`, `tile_loader.gd` material routing. `tiler.build_tiles` output must not change (Task 3 moves the junction computation into `nav.py` verbatim).
- `.gd`/`.tscn` files written WITHOUT a UTF-8 BOM (PowerShell `Set-Content` hazard — use Bash heredocs / editor tools).
- Headless smoke: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd` (console wrapper; the GUI exe returns nothing). Currently 20 gates ending `SMOKE OK: 314 tiles`. This phase adds THREE gates (`NAV OK`, `TRAFFIC OK`, `SIGNALS OK`) → 23 gates. Harness rule: headless frame:physics ≈ 2:1 — always poll a condition, never fixed-frame waits for physics.
- pytest: `.venv/Scripts/python -m pytest pipeline -q` — 100 now, target ≥ 116 at the end of Task 4.
- Perf: Traffic ≤ ~1 ms CPU/frame on the reference machine (RX 6700S). Knobs in order: `POOL_SIZE`, `SPAWN_MAX`/`DESPAWN`, `HEADLIGHTS`.
- Night regression fails the phase; screenshots judged ONLY by Reading PNGs.
- Coordinate conventions (do not re-derive): meters, x = east, z = SOUTH, y up; car forward is `-Z` (`yaw = atan2(-dx, -dz)`); right-hand of travel direction `d` is `Vector3(-d.z, 0, d.x)` (matches `pipeline/cars.py`'s `sx = x - dz*side, sz = z + dx*side`).

---

### Task 1: Parse `lanes`, `maxspeed`, `oneway=-1` (+ nav fixture)

**Files:**
- Modify: `pipeline/osm_parse.py:11-18` (Road dataclass), `:151-156` (Road construction), add two helpers next to `_parse_meters`
- Create: `pipeline/tests/fixtures/nav.osm.xml`
- Test: `pipeline/tests/test_osm_parse.py` (append 3 tests)

**Interfaces:**
- Produces: `Road.lanes: int | None`, `Road.maxspeed: float | None` (m/s), `Road.oneway_reversed: bool` — Task 2 reads all three. Existing positional construction `Road(wid, name, pts, width, road_class, oneway)` keeps working (new fields default).
- Produces: fixture `nav.osm.xml` — a 4-way junction at the origin used by every nav test:

```
                D (45.5058)
                |
   E ---------- F   <- way 202 residential oneway=-1 (nodes E->F, legal F->E)   z=-110.6
   P1 -- P2         <- way 204 footway                                          z=-55.3
A --------J-------- B   <- way 200 primary lanes=3 maxspeed=50; J = traffic_signals
   S1-S2            <- way 205 steps                                            z=+55.3
   G ---------- H   <- way 203 service (NOT drivable for nav)                   z=+110.6
                |
                C (45.5022)
                            way 201 residential C-J-D
   Q (far east, traffic_signals, no road within 3 m -> dropped)
```

- [ ] **Step 1: Write the fixture** `pipeline/tests/fixtures/nav.osm.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6" generator="fixture">
  <node id="1" lat="45.5040" lon="-73.5535"><tag k="highway" v="traffic_signals"/></node>
  <node id="2" lat="45.5040" lon="-73.5560"/>
  <node id="3" lat="45.5040" lon="-73.5510"/>
  <node id="4" lat="45.5022" lon="-73.5535"/>
  <node id="5" lat="45.5058" lon="-73.5535"/>
  <node id="6" lat="45.5050" lon="-73.5560"/>
  <node id="7" lat="45.5050" lon="-73.5510"/>
  <node id="8" lat="45.5030" lon="-73.5560"/>
  <node id="9" lat="45.5030" lon="-73.5510"/>
  <node id="10" lat="45.5045" lon="-73.5550"/>
  <node id="11" lat="45.5045" lon="-73.5520"/>
  <node id="12" lat="45.5035" lon="-73.5550"/>
  <node id="13" lat="45.5035" lon="-73.5545"/>
  <node id="14" lat="45.5040" lon="-73.5500"><tag k="highway" v="traffic_signals"/></node>
  <way id="200">
    <nd ref="2"/><nd ref="1"/><nd ref="3"/>
    <tag k="highway" v="primary"/><tag k="name" v="Rue Principale"/>
    <tag k="lanes" v="3"/><tag k="maxspeed" v="50"/>
  </way>
  <way id="201">
    <nd ref="4"/><nd ref="1"/><nd ref="5"/>
    <tag k="highway" v="residential"/><tag k="name" v="Rue Transversale"/>
  </way>
  <way id="202">
    <nd ref="6"/><nd ref="7"/>
    <tag k="highway" v="residential"/><tag k="name" v="Rue Inverse"/>
    <tag k="oneway" v="-1"/>
  </way>
  <way id="203">
    <nd ref="8"/><nd ref="9"/>
    <tag k="highway" v="service"/>
  </way>
  <way id="204">
    <nd ref="10"/><nd ref="11"/>
    <tag k="highway" v="footway"/>
  </way>
  <way id="205">
    <nd ref="12"/><nd ref="13"/>
    <tag k="highway" v="steps"/>
  </way>
</osm>
```

- [ ] **Step 2: Write the failing tests** — append to `pipeline/tests/test_osm_parse.py`:

```python
NAV = Path(__file__).parent / "fixtures" / "nav.osm.xml"

def test_lanes_and_maxspeed_parsed():
    city = parse_osm(NAV)
    main = next(r for r in city.roads if r.osm_id == 200)
    side = next(r for r in city.roads if r.osm_id == 201)
    assert main.lanes == 3
    assert abs(main.maxspeed - 50 / 3.6) < 1e-6
    assert side.lanes is None and side.maxspeed is None

def test_oneway_minus_one_flagged_reversed():
    city = parse_osm(NAV)
    inv = next(r for r in city.roads if r.osm_id == 202)
    main = next(r for r in city.roads if r.osm_id == 200)
    assert inv.oneway is True and inv.oneway_reversed is True
    assert main.oneway is False and main.oneway_reversed is False

def test_maxspeed_units():
    from pipeline.osm_parse import _parse_maxspeed, _parse_lanes
    assert abs(_parse_maxspeed("50 km/h") - 50 / 3.6) < 1e-6
    assert abs(_parse_maxspeed("30 mph") - 30 * 0.44704) < 1e-6
    assert _parse_maxspeed("walk") is None
    assert _parse_maxspeed("0") is None
    assert _parse_lanes("2") == 2
    assert _parse_lanes("abc") is None
    assert _parse_lanes("0") is None
```

- [ ] **Step 3: Run to verify failure**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_osm_parse.py -q`
Expected: 3 failures (`AttributeError: 'Road' object has no attribute 'lanes'`, `ImportError` for `_parse_maxspeed`).

- [ ] **Step 4: Implement** in `pipeline/osm_parse.py`:

Dataclass (replace lines 11-18):

```python
@dataclass
class Road:
    osm_id: int
    name: str | None
    points: list[tuple[float, float]]
    width: float
    road_class: str = "residential"
    oneway: bool = False
    lanes: int | None = None          # OSM lanes= (None when absent/junk)
    maxspeed: float | None = None     # m/s (None when absent/junk)
    oneway_reversed: bool = False     # oneway=-1: legal direction is points[::-1]
```

Helpers (add right after `_parse_meters`):

```python
def _parse_maxspeed(value: str) -> float | None:
    """OSM maxspeed -> m/s. Bare numbers and 'km/h' are km/h, 'mph' is mph;
    non-numeric ('walk', 'none') or non-positive -> None."""
    m = _NUM.search(value)
    if not m:
        return None
    n = float(m.group())
    if n <= 0:
        return None
    return n * 0.44704 if "mph" in value else n / 3.6

def _parse_lanes(value: str) -> int | None:
    m = _NUM.search(value)
    if not m:
        return None
    n = int(float(m.group()))
    return n if n > 0 else None
```

Road construction (replace the two lines at 154-156 that build `Road(...)`):

```python
                width = config.ROAD_WIDTHS.get(tags["highway"], config.DEFAULT_ROAD_WIDTH)
                ow = tags.get("oneway")
                city.roads.append(Road(
                    wid, tags.get("name"), pts, width, tags["highway"],
                    ow in ("yes", "true", "1", "-1"),
                    lanes=_parse_lanes(tags["lanes"]) if "lanes" in tags else None,
                    maxspeed=_parse_maxspeed(tags["maxspeed"]) if "maxspeed" in tags else None,
                    oneway_reversed=(ow == "-1")))
```

- [ ] **Step 5: Run the full pytest**

Run: `.venv/Scripts/python -m pytest pipeline -q`
Expected: 103 passed (100 + 3). `test_counts` on `mini.osm.xml` still sees 3 roads.

- [ ] **Step 6: Commit**

```bash
git add pipeline/osm_parse.py pipeline/tests/test_osm_parse.py pipeline/tests/fixtures/nav.osm.xml
git commit -m "pipeline: parse lanes, maxspeed and oneway=-1 on roads + nav fixture"
```

---

### Task 2: `pipeline/nav.py` — nodes, drivable roads, snapped signals

**Files:**
- Modify: `pipeline/config.py` (append an `# --- M10a nav graph ---` block after the M9b manhole block)
- Create: `pipeline/nav.py`
- Test: `pipeline/tests/test_nav.py` (create)

**Interfaces:**
- Consumes: `Road.lanes/maxspeed/oneway_reversed` (Task 1); `pipeline.meshes._densify(points, max_len=24.0)`; `Heightmap.sample(x, z)`.
- Produces: `build_nav(city, hm=None, path_radius=None) -> dict` with keys `nodes`, `roads`, `signals`, `walks` (Task 3 fills `walks`; here it is `[]`). `road_junctions(roads) -> frozenset` (Task 3 wires it into `tiler`). Internal `_Nodes` store and `_Grid` spatial hash reused by Task 3.
- Node y convention: road nodes `ground + 0.05` (identical to `road_mesh`'s `h()`); rounding x/z 0.1 m, y 0.01 m.

- [ ] **Step 1: Config constants** — append to `pipeline/config.py`:

```python
# --- M10a nav graph (pipeline/nav.py -> game/world/nav.json) ---
NAV_FILE = "nav.json"
NAV_DRIVABLE_CLASSES = ("motorway", "trunk", "primary", "secondary", "tertiary",
                        "residential", "unclassified", "living_street",
                        "motorway_link", "trunk_link", "primary_link",
                        "secondary_link", "tertiary_link")   # no "service" (parking aisles/driveways)
NAV_PATH_CLASSES = ("footway", "pedestrian", "path", "steps", "living_street")
NAV_SPEED_DEFAULTS = {   # m/s, used when maxspeed is absent; *_link uses its parent class
    "motorway": 25.0, "trunk": 20.0, "primary": 14.0, "secondary": 12.5,
    "tertiary": 11.0, "residential": 8.5, "unclassified": 8.5, "living_street": 5.0,
}
NAV_SIGNAL_SNAP = 3.0      # m: OSM signal -> nearest road node, else dropped
NAV_CROSS_RADIUS = 12.0    # m: sidewalk endpoints this close to a junction/way-end get crossings
NAV_CROSS_MAX = 17.5       # m: max crossing length (excludes diagonal jaywalks ~20 m)
NAV_MAX_BYTES = 8 * 1024 * 1024
```

- [ ] **Step 2: Write the failing tests** `pipeline/tests/test_nav.py`:

```python
import json
import math
from pathlib import Path
import numpy as np
import pytest
from pipeline import config
from pipeline.nav import build_nav, road_junctions
from pipeline.osm_parse import parse_osm
from pipeline.terrain import Heightmap

NAV = Path(__file__).parent / "fixtures" / "nav.osm.xml"

def _city():
    return parse_osm(NAV)

def _road(nav, osm_id):
    return next(r for r in nav["roads"] if r["id"] == osm_id)

def test_top_level_schema():
    nav = build_nav(_city())
    assert set(nav) == {"nodes", "roads", "signals", "walks"}
    assert all(len(p) == 3 for p in nav["nodes"])
    for r in nav["roads"]:
        assert set(r) == {"id", "n", "cls", "w", "oneway", "lanes", "speed"}
        assert len(r["n"]) >= 2
        assert all(0 <= i < len(nav["nodes"]) for i in r["n"])

def test_only_drivable_classes_become_roads():
    nav = build_nav(_city())
    assert sorted(r["id"] for r in nav["roads"]) == [200, 201, 202]   # no service/footway/steps

def test_oneway_minus_one_is_reversed():
    nav = build_nav(_city())
    inv = _road(nav, 202)
    first, last = nav["nodes"][inv["n"][0]], nav["nodes"][inv["n"][-1]]
    assert inv["oneway"] == 1
    assert first[0] > last[0]          # legal direction runs east (F) -> west (E)
    assert _road(nav, 200)["oneway"] == 0

def test_lanes_and_speed():
    nav = build_nav(_city())
    assert _road(nav, 200)["lanes"] == 3 and _road(nav, 200)["speed"] == round(50 / 3.6, 2)
    assert _road(nav, 201)["lanes"] == 2 and _road(nav, 201)["speed"] == config.NAV_SPEED_DEFAULTS["residential"]
    assert _road(nav, 202)["lanes"] == 1

def test_roads_are_densified_and_share_junction_node():
    nav = build_nav(_city())
    main, side = _road(nav, 200), _road(nav, 201)
    assert len(main["n"]) > 3                      # ~390 m at <=24 m stations
    shared = set(main["n"]) & set(side["n"])
    assert len(shared) == 1
    x, _, z = nav["nodes"][next(iter(shared))]
    assert math.hypot(x, z) < 0.2                  # the junction is node J at the origin

def test_signal_snaps_to_junction_node_and_far_one_dropped():
    nav = build_nav(_city())
    assert len(nav["signals"]) == 1
    x, _, z = nav["nodes"][nav["signals"][0]]
    assert math.hypot(x, z) < 0.2

def test_road_node_heights_follow_heightmap():
    hm = Heightmap(grid=np.full((4, 4), 5.0, dtype=np.float32),
                   x0=-3000.0, z0=-3000.0, step_x=2000.0, step_z=2000.0)
    nav = build_nav(_city(), hm=hm)
    for r in nav["roads"]:
        for i in r["n"]:
            assert nav["nodes"][i][1] == 5.05

def test_road_junctions_matches_tiler_rule():
    j = road_junctions(_city().roads)
    assert len(j) == 1 and all(abs(v) < 0.2 for v in next(iter(j)))

def test_deterministic():
    city = _city()
    a = json.dumps(build_nav(city), sort_keys=True)
    b = json.dumps(build_nav(city), sort_keys=True)
    assert a == b
```

- [ ] **Step 3: Run to verify failure**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_nav.py -q`
Expected: `ModuleNotFoundError: No module named 'pipeline.nav'`.

- [ ] **Step 4: Implement** `pipeline/nav.py`:

```python
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
```

- [ ] **Step 5: Run the nav tests**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_nav.py -q`
Expected: 9 passed.

- [ ] **Step 6: Commit**

```bash
git add pipeline/config.py pipeline/nav.py pipeline/tests/test_nav.py
git commit -m "pipeline: nav graph builder - shared nodes, drivable roads, snapped signals"
```

---

### Task 3: Walks — sidewalk offsets, footpaths, corner crossings; tiler reuses `road_junctions`

**Files:**
- Modify: `pipeline/nav.py` (replace the `_build_walks` stub)
- Modify: `pipeline/tiler.py:11` (import) and `:47-52` (junction computation)
- Test: `pipeline/tests/test_nav.py` (append 6 tests)

**Interfaces:**
- Consumes: `_Nodes`, `_Grid`, `road_junctions`, `_clear_intervals(points, junctions, trim)`, `_polyline_slice(points, start, end)`, `_densify`.
- Produces: `walks` records `{"n": [...], "kind": "side" | "path" | "cross"}`; walk node y = `ground(station) + 0.05 + jitter + SIDEWALK_RAISE` for `side`, `ground + 0.05` for `path`. 10b's pedestrians consume exactly this.

- [ ] **Step 1: Write the failing tests** — append to `pipeline/tests/test_nav.py`:

```python
def _walk_nodes(nav, kind):
    return [[nav["nodes"][i] for i in w["n"]] for w in nav["walks"] if w["kind"] == kind]

def test_side_walks_offset_both_sides():
    nav = build_nav(_city())
    sides = _walk_nodes(nav, "side")
    # primary w=10 runs along z=0: sidewalk centerlines at |z| = 5 + 0.18 + 1.0 = 6.18
    zs = sorted({round(p[2], 1) for w in sides for p in w if abs(p[0]) > 20 and abs(p[2]) < 8})
    assert zs == [-6.2, 6.2]
    # residential w=6 runs along x=0: |x| = 3 + 1.18 = 4.18
    xs = sorted({round(p[0], 1) for w in sides for p in w if abs(p[2]) > 20 and abs(p[0]) < 8})
    assert xs == [-4.2, 4.2]

def test_side_walks_trimmed_at_junction_and_ends():
    nav = build_nav(_city())
    for w in _walk_nodes(nav, "side"):
        for x, _, z in w:
            assert math.hypot(x, z) >= config.SIDEWALK_END_TRIM - 0.5

def test_crossings_at_junction_and_dead_ends():
    nav = build_nav(_city())
    crosses = _walk_nodes(nav, "cross")
    assert all(len(w) == 2 for w in crosses)
    for (xa, _, za), (xb, _, zb) in crosses:
        assert math.hypot(xa - xb, za - zb) <= config.NAV_CROSS_MAX + 1e-6
    at_j = [w for w in crosses if all(math.hypot(x, z) <= config.NAV_CROSS_RADIUS for x, _, z in w)]
    assert len(at_j) >= 4                      # straight crossings + same-side continuations, no diagonals
    # dead end of the primary at x ~ -195: its two sidewalk ends are joined
    west = [w for w in crosses if all(x < -150 and abs(z) < 8 for x, _, z in w)]
    assert len(west) == 1                      # (way 202's dead end sits at z ~ -110, excluded)

def test_paths_include_footway_and_steps():
    nav = build_nav(_city())
    assert len(_walk_nodes(nav, "path")) == 2

def test_walk_heights_follow_heightmap():
    hm = Heightmap(grid=np.full((4, 4), 5.0, dtype=np.float32),
                   x0=-3000.0, z0=-3000.0, step_x=2000.0, step_z=2000.0)
    nav = build_nav(_city(), hm=hm)
    for w in nav["walks"]:
        for i in w["n"]:
            y = nav["nodes"][i][1]
            if w["kind"] == "path":
                assert y == 5.05
            else:
                assert abs(y - 5.17) <= 0.003      # +-2 mm per-road jitter, like sidewalk_mesh

def test_path_radius_prunes_far_footpaths():
    nav = build_nav(_city(), path_radius=10.0)
    assert _walk_nodes(nav, "path") == []
    assert len(_walk_nodes(nav, "side")) > 0
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_nav.py -q`
Expected: 5 new failures (walks empty); `test_path_radius_prunes_far_footpaths` passes vacuously — fine.

- [ ] **Step 3: Implement** — replace the `_build_walks` stub in `pipeline/nav.py`:

```python
def _side_points(pts: list[tuple[float, float]], side: float, off: float
                 ) -> list[tuple[float, float]]:
    """Each station moved `off` m laterally. side=+1.0 / -1.0 with the same
    perpendicular sense as sidewalk_mesh (side * (-dz, dx)); a station uses the
    segment that starts there, the last station the segment before it."""
    out: list[tuple[float, float]] = []
    n = len(pts)
    for k, (x, z) in enumerate(pts):
        (x1, z1), (x2, z2) = (pts[k], pts[k + 1]) if k < n - 1 else (pts[k - 1], pts[k])
        dx, dz = x2 - x1, z2 - z1
        seg = math.hypot(dx, dz)
        if seg < 1e-6:
            out.append((x, z))
            continue
        out.append((x + side * -dz / seg * off, z + side * dx / seg * off))
    return out

def _build_walks(roads, hm, nodes: _Nodes, path_radius: float | None) -> list[dict]:
    junctions = road_junctions(roads)
    walks: list[dict] = []
    ends: list[int] = []
    for r in sorted(roads, key=lambda r: r.osm_id):
        if len(r.points) < 2:
            continue
        if r.road_class in config.SIDEWALK_CLASSES and r.width > 0:
            intervals = [iv for iv in _clear_intervals(r.points, junctions, config.SIDEWALK_END_TRIM)
                         if iv[1] - iv[0] >= 4.0]
            jitter = ((r.osm_id * 2654435761) % 5 - 2) * 0.001     # same as sidewalk_mesh
            off = r.width / 2.0 + SIDE_OFFSET_EXTRA
            for lo, hi in intervals:
                pts = _densify(_polyline_slice(r.points, lo, hi))
                if len(pts) < 2:
                    continue
                for side in (1.0, -1.0):
                    idx = []
                    for (x, z), (ox, oz) in zip(pts, _side_points(pts, side, off)):
                        y = _ground(hm, x, z) + WALK_Y + jitter        # sampled at the centerline station
                        idx.append(nodes.get(ox, oz, y, "walk"))
                    idx = _dedupe(idx)
                    if len(idx) >= 2:
                        walks.append({"n": idx, "kind": "side"})
                        ends += [idx[0], idx[-1]]
        elif r.road_class in config.NAV_PATH_CLASSES:
            if path_radius is not None and math.hypot(*r.points[0]) > path_radius:
                continue
            pts = _densify(r.points)
            idx = _dedupe([nodes.get(x, z, _ground(hm, x, z) + ROAD_Y, "walk") for x, z in pts])
            if len(idx) >= 2:
                walks.append({"n": idx, "kind": "path"})
    # crossings: pair up sidewalk endpoints clustered around junction vertices
    # and sidewalk-road way ends (dead ends get a turn-around link)
    anchors: set[tuple[float, float]] = set(junctions)
    for r in roads:
        if r.road_class in config.SIDEWALK_CLASSES and len(r.points) >= 2:
            anchors.add((round(r.points[0][0], 2), round(r.points[0][1], 2)))
            anchors.add((round(r.points[-1][0], 2), round(r.points[-1][1], 2)))
    grid = _Grid()
    for i in sorted(set(ends)):
        x, _, z = nodes.rows[i]
        grid.add(x, z, i)
    pairs: set[tuple[int, int]] = set()
    for ax, az in sorted(anchors):
        near = sorted(i for i in set(grid.near(ax, az, config.NAV_CROSS_RADIUS))
                      if math.hypot(nodes.rows[i][0] - ax, nodes.rows[i][2] - az) <= config.NAV_CROSS_RADIUS)
        for k, a in enumerate(near):
            xa, _, za = nodes.rows[a]
            for b in near[k + 1:]:
                xb, _, zb = nodes.rows[b]
                if math.hypot(xa - xb, za - zb) <= config.NAV_CROSS_MAX:
                    pairs.add((a, b))
    for a, b in sorted(pairs):
        walks.append({"n": [a, b], "kind": "cross"})
    return walks
```

- [ ] **Step 4: Wire `tiler` to the shared junction rule** — in `pipeline/tiler.py` add `from pipeline.nav import road_junctions` after the `pipeline.meshes` import (line 11), and replace lines 47-52:

```python
    counts: dict[tuple[float, float], int] = defaultdict(int)
    for r in city.roads:
        if r.road_class in config.SIDEWALK_CLASSES or r.road_class in config.ROADMARK_CLASSES:
            for x, z in r.points:
                counts[(round(x, 2), round(z, 2))] += 1
    junctions = frozenset(k for k, v in counts.items() if v >= 2)
```

with:

```python
    junctions = road_junctions(city.roads)
```

(`defaultdict` stays imported in tiler if still used elsewhere; remove the import only if `grep -n defaultdict pipeline/tiler.py` shows no other use.)

- [ ] **Step 5: Run the full pytest**

Run: `.venv/Scripts/python -m pytest pipeline -q`
Expected: 118 passed (103 + 9 + 6). If `test_side_walks_offset_both_sides` fails on the exact set, print the offending values — the offsets must be ±6.18/±4.18 rounded to 0.1 (= 6.2/4.2); any other value means the perpendicular sense or `SIDE_OFFSET_EXTRA` is wrong, not the test.

- [ ] **Step 6: Commit**

```bash
git add pipeline/nav.py pipeline/tiler.py pipeline/tests/test_nav.py
git commit -m "pipeline: nav walks - sidewalk offsets, footpaths, corner crossings; tiler shares road_junctions"
```

---

### Task 4: Export `nav.json`, rebuild the world (tiles byte-identical)

**Files:**
- Modify: `pipeline/export.py` (import + write + size guard + `nav_file` key)
- Test: `pipeline/tests/test_export.py` (append 2 tests)
- Rebuild output: `game/world/nav.json` (new), `game/world/city_metadata.json` (one new key)

**Interfaces:**
- Produces: `game/world/nav.json` — compact JSON (`separators=(",", ":")`, `sort_keys=True`); `city_metadata.json["nav_file"] == "nav.json"`. Task 5's `NavGraph.load_from("res://world/nav.json")` reads it.

- [ ] **Step 1: Write the failing tests** — append to `pipeline/tests/test_export.py`:

```python
def test_export_writes_nav(tmp_path):
    city = parse_osm(FIX)
    meta = export_city(city, tmp_path)
    assert meta["nav_file"] == config.NAV_FILE
    nav = json.loads((tmp_path / config.NAV_FILE).read_text(encoding="utf-8"))
    assert set(nav) == {"nodes", "roads", "signals", "walks"}
    assert len(nav["roads"]) >= 1

def test_export_nav_size_guard_raises(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "NAV_MAX_BYTES", 1)
    city = parse_osm(FIX)
    with pytest.raises(ValueError, match="nav.json"):
        export_city(city, tmp_path)
```

- [ ] **Step 2: Run to verify failure**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_export.py -q`
Expected: 2 failures (`KeyError: 'nav_file'`, no `ValueError`).

- [ ] **Step 3: Implement** in `pipeline/export.py` — add `from pipeline.nav import build_nav` to the imports, and insert before `(out / "city_metadata.json").write_text(...)`:

```python
    nav_bytes = _nav_bytes(city, hm)
    (out / config.NAV_FILE).write_bytes(nav_bytes)
    meta["nav_file"] = config.NAV_FILE
```

and add the helper above `export_city`:

```python
def _nav_bytes(city: CityData, hm) -> bytes:
    """Serialize the nav graph; if over budget, drop footpaths beyond the
    downtown radius (roads/signals are never pruned), else fail loudly."""
    for path_radius in (None, config.MANHOLE_RADIUS):
        data = json.dumps(build_nav(city, hm=hm, path_radius=path_radius),
                          sort_keys=True, separators=(",", ":")).encode("utf-8")
        if len(data) <= config.NAV_MAX_BYTES:
            return data
    raise ValueError(f"{config.NAV_FILE}: {len(data)} bytes over NAV_MAX_BYTES")
```

- [ ] **Step 4: Run the full pytest**

Run: `.venv/Scripts/python -m pytest pipeline -q`
Expected: 120 passed. (`test_export_deterministic` still byte-compares `city_metadata.json` — unchanged semantics.)

- [ ] **Step 5: Commit the pipeline change**

```bash
git add pipeline/export.py pipeline/tests/test_export.py
git commit -m "pipeline: export nav.json (size-guarded) and reference it from city_metadata"
```

- [ ] **Step 6: Rebuild the world** (both caches exist in `data/`; no network):

Run: `.venv/Scripts/python -m pipeline.build`
Expected: console ends with `exported 314 tiles, ... -> game/world`. Then:

Run: `git status --short game/world/`
Expected EXACTLY two lines: ` M game/world/city_metadata.json` and `?? game/world/nav.json`. Any `.glb` listed = tile bytes changed = STOP and diff (`git diff --stat game/world/`) — the Task 3 tiler refactor must be a no-op.

Run: `ls -l game/world/nav.json` and `.venv/Scripts/python -c "import json;d=json.load(open('game/world/nav.json'));print(len(d['nodes']),len(d['roads']),len(d['signals']),len(d['walks']))"`
Expected: size ≤ 8 MB; counts roughly nodes > 50k, roads > 3000, signals > 1500 (of 2157 — many OSM signals sit on footway/crossing nodes off the drivable roads and are dropped by the 3 m snap), walks > 20k. Record the four numbers for the HANDOFF.

Run: `git diff game/world/city_metadata.json | grep '^[+-]' | grep -v '^[+-][+-]'`
Expected: exactly one added line containing `"nav_file": "nav.json"`.

- [ ] **Step 7: Confirm the game still boots headless**

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`
Expected: unchanged 20 gates, `SMOKE OK: 314 tiles`.

- [ ] **Step 8: Commit the world**

```bash
git add game/world/nav.json game/world/city_metadata.json
git commit -m "world: M10a rebuild - nav.json road/walk graph (tiles byte-identical)"
```

---

### Task 5: `nav_graph.gd` + headless `nav_test.gd`

**Files:**
- Create: `game/scripts/nav_graph.gd`
- Create: `game/tests/nav_test.gd`

**Interfaces:**
- Consumes: `res://world/nav.json` (Task 4).
- Produces (all used by Task 6/7 and by 10b):
  - `static func load_from(path: String) -> NavGraph`
  - `nodes: PackedVector3Array`, `roads: Array` of `{n, cum, cls, w, oneway, lanes, speed, stops}`, `walks: Array` of `{n, cum, kind}`, `signals: Dictionary` (node → true)
  - `road_length(ri) -> float`, `road_point(ri, dir, lat, t) -> Vector3`, `road_tangent(ri, dir, t) -> Vector3` (horizontal unit, in travel direction), `end_node(ri, dir) -> int`
  - `walk_length(wi)`, `walk_point(wi, dir, t)`, `walk_tangent(wi, dir, t)`, `walk_end_node(wi, dir)`
  - `exits(node, ri, dir, allow_reverse := false) -> Array` of `[road_idx, dir, t_start]`; `walk_exits(node, wi, dir, allow_reverse := false)` same shape
  - `next_stop(ri, dir, t) -> Array` = `[distance_ahead, node]` or `[]`; `is_junction(node) -> bool`
  - `lane_offset(ri, lane) -> float`, `signal_group(node, heading) -> int`, `signal_green(node, group, time) -> bool`
  - `static func yaw_for(d: Vector3) -> float`, `static func pick(seed: int, n: int) -> int`
  - `t` is ALWAYS measured along the travel direction (`dir = 1` forward along `n`, `-1` reverse; `s = t` or `len - t` internally).

- [ ] **Step 1: Write the failing headless test** `game/tests/nav_test.gd`:

```gdscript
extends SceneTree
# tools/godot/godot_console.exe --headless --path game --script res://tests/nav_test.gd
# Pure-data checks on the exported nav graph + a seeded walker that must not dead-end.

func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	quit(1)

func _init() -> void:
	var g := NavGraph.load_from("res://world/nav.json")
	if g.nodes.size() < 10000 or g.roads.size() < 1000 or g.walks.size() < 1000 or g.signals.size() < 500:
		_fail("graph too small: nodes=%d roads=%d walks=%d signals=%d" % [g.nodes.size(), g.roads.size(), g.walks.size(), g.signals.size()])
		return
	# endpoints: t=0 / t=len map onto the end nodes, both directions
	var road: Dictionary = g.roads[0]
	var n: PackedInt32Array = road["n"]
	var L := g.road_length(0)
	if g.road_point(0, 1, 0.0, 0.0).distance_to(g.nodes[n[0]]) > 0.01 \
			or g.road_point(0, 1, 0.0, L).distance_to(g.nodes[n[n.size() - 1]]) > 0.01 \
			or g.road_point(0, -1, 0.0, 0.0).distance_to(g.nodes[n[n.size() - 1]]) > 0.01:
		_fail("road_point endpoints wrong")
		return
	# lateral offset is to the RIGHT of travel: forward -Z => +X
	var d := Vector3(0, 0, -1)
	if absf(NavGraph.yaw_for(d)) > 1e-6:
		_fail("yaw_for(-Z) must be 0")
		return
	# seeded road walker: 200 m without dead-ending, only legal transitions
	var ri := 0
	var dir := 1
	var t := 0.0
	var travelled := 0.0
	var hops := 0
	while travelled < 200.0 and hops < 200:
		var step := minf(5.0, g.road_length(ri) - t)
		t += step
		travelled += step
		if t >= g.road_length(ri) - 1e-4:
			var ex := g.exits(g.end_node(ri, dir), ri, dir)
			if ex.is_empty():
				ex = g.exits(g.end_node(ri, dir), ri, dir, true)
			if ex.is_empty():
				_fail("road walker dead-ended at road %d" % ri)
				return
			var e: Array = ex[NavGraph.pick(hops * 7 + 1, ex.size())]
			if g.roads[e[0]]["oneway"] == 1 and e[1] != 1:
				_fail("exit drives a oneway backwards")
				return
			ri = e[0]; dir = e[1]; t = e[2]
			hops += 1
	if travelled < 200.0:
		_fail("road walker only travelled %.1f m" % travelled)
		return
	# seeded walk walker (sidewalks/paths/crossings) 200 m
	var wi := 0
	dir = 1; t = 0.0; travelled = 0.0; hops = 0
	while travelled < 200.0 and hops < 400:
		var step := minf(3.0, g.walk_length(wi) - t)
		t += step
		travelled += step
		if t >= g.walk_length(wi) - 1e-4:
			var ex := g.walk_exits(g.walk_end_node(wi, dir), wi, dir)
			if ex.is_empty():
				ex = g.walk_exits(g.walk_end_node(wi, dir), wi, dir, true)
			if ex.is_empty():
				_fail("walk walker dead-ended at walk %d" % wi)
				return
			var e: Array = ex[NavGraph.pick(hops * 13 + 5, ex.size())]
			wi = e[0]; dir = e[1]; t = e[2]
			hops += 1
	if travelled < 200.0:
		_fail("walk walker only travelled %.1f m" % travelled)
		return
	# signals: some node has two non-empty groups (a real cross street), and the
	# two groups are never green together over a 16 s sweep
	var probe := -1
	for node in g.signals:
		var heads: Array = g.exits(node, -1, 0, true)
		var g0 := 0
		var g1 := 0
		for e in heads:
			if g.signal_group(node, g.road_tangent(e[0], e[1], e[2])) == 0: g0 += 1
			else: g1 += 1
		if g0 > 0 and g1 > 0:
			probe = node
			break
	if probe < 0:
		_fail("no signal node with two approach groups")
		return
	var a_green := false; var a_red := false; var b_green := false; var b_red := false
	var tt := 0.0
	while tt < NavGraph.SIGNAL_PERIOD:
		var ga := g.signal_green(probe, 0, tt)
		var gb := g.signal_green(probe, 1, tt)
		if ga and gb:
			_fail("both signal groups green at t=%.1f" % tt)
			return
		a_green = a_green or ga; a_red = a_red or not ga
		b_green = b_green or gb; b_red = b_red or not gb
		tt += 0.5
	if not (a_green and a_red and b_green and b_red):
		_fail("signal phases do not alternate")
		return
	print("NAV GRAPH OK: nodes=%d roads=%d walks=%d signals=%d" % [g.nodes.size(), g.roads.size(), g.walks.size(), g.signals.size()])
	quit(0)
```

- [ ] **Step 2: Run to verify failure**

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/nav_test.gd`
Expected: parse error `Identifier "NavGraph" not declared`.

- [ ] **Step 3: Implement** `game/scripts/nav_graph.gd`:

```gdscript
class_name NavGraph
extends RefCounted
# Road + sidewalk navigation graph exported by pipeline/nav.py (world/nav.json).
# Pure data + pure queries: no scene nodes, no physics, no raycasts. Node y is
# baked from the pipeline heightmap, so polyline followers sit on the road /
# sidewalk ribbons even outside the 280 m tile-collision ring.
#
# Conventions: t is measured along the TRAVEL direction of a polyline
# (dir = 1 follows n[] forward, -1 backward). Right of travel = (-d.z, 0, d.x).
# Car forward is -Z: yaw = atan2(-d.x, -d.z) (pipeline/cars.py convention).

const SIGNAL_PERIOD := 16.0
const GREEN_A_END := 7.5
const GREEN_B_START := 8.0
const GREEN_B_END := 15.5
const LANE_MIN := 1.0
const LANE_MAX := 1.75

var nodes := PackedVector3Array()
var roads: Array = []        # {n: PackedInt32Array, cum: PackedFloat32Array, cls, w, oneway, lanes, speed, stops: Array[[t_fwd, node]]}
var walks: Array = []        # {n, cum, kind}
var signals: Dictionary = {} # node -> true
var _road_out: Dictionary = {}  # node -> Array of [road_idx, dir, t_start]
var _walk_out: Dictionary = {}  # node -> Array of [walk_idx, dir, t_start]
var _arms: Dictionary = {}      # node -> road arms touching (endpoint = 1, interior = 2)
var _axis: Dictionary = {}      # signal node -> reference tangent for group split

static func load_from(path: String) -> NavGraph:
	var g := NavGraph.new()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("NavGraph: %s missing" % path)
		return g
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		g._build(data)
	return g

static func yaw_for(d: Vector3) -> float:
	return atan2(-d.x, -d.z)

static func pick(seed: int, n: int) -> int:
	if n <= 0:
		return -1
	return int((absi(seed) * 2654435761) % 2147483647) % n

# ---- build ---------------------------------------------------------------

func _build(data: Dictionary) -> void:
	for p in data.get("nodes", []):
		nodes.append(Vector3(p[0], p[1], p[2]))
	for s in data.get("signals", []):
		signals[int(s)] = true
	for rd in data.get("roads", []):
		var n := _ints(rd["n"])
		var cum := _cumulative(n)
		var ri := roads.size()
		var oneway := int(rd["oneway"])
		roads.append({"n": n, "cum": cum, "cls": rd["cls"], "w": float(rd["w"]),
			"oneway": oneway, "lanes": maxi(1, int(rd["lanes"])), "speed": float(rd["speed"]), "stops": []})
		var length := cum[cum.size() - 1]
		var last := n.size() - 1
		for k in n.size():
			var node := n[k]
			_arms[node] = int(_arms.get(node, 0)) + (1 if (k == 0 or k == last) else 2)
			if k < last:
				_push(_road_out, node, [ri, 1, cum[k]])
			if k > 0 and oneway == 0:
				_push(_road_out, node, [ri, -1, length - cum[k]])
	for wd in data.get("walks", []):
		var n := _ints(wd["n"])
		var cum := _cumulative(n)
		var wi := walks.size()
		walks.append({"n": n, "cum": cum, "kind": wd["kind"]})
		var length := cum[cum.size() - 1]
		var last := n.size() - 1
		for k in n.size():
			if k < last:
				_push(_walk_out, n[k], [wi, 1, cum[k]])
			if k > 0:
				_push(_walk_out, n[k], [wi, -1, length - cum[k]])
	# stop nodes per road (signals + junctions), in forward t order
	for road in roads:
		var n: PackedInt32Array = road["n"]
		var cum: PackedFloat32Array = road["cum"]
		var stops: Array = road["stops"]
		for k in n.size():
			if signals.has(n[k]) or is_junction(n[k]):
				stops.append([cum[k], n[k]])
	# signal axis: tangent of the first road leaving the node (deterministic)
	for node in signals:
		var outs: Array = _road_out.get(node, [])
		_axis[node] = road_tangent(outs[0][0], outs[0][1], outs[0][2]) if not outs.is_empty() else Vector3(0, 0, -1)

func _ints(arr: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in arr:
		out.append(int(v))
	return out

func _cumulative(n: PackedInt32Array) -> PackedFloat32Array:
	var cum := PackedFloat32Array()
	cum.append(0.0)
	for k in range(1, n.size()):
		cum.append(cum[k - 1] + nodes[n[k - 1]].distance_to(nodes[n[k]]))
	return cum

func _push(map: Dictionary, node: int, entry: Array) -> void:
	if not map.has(node):
		map[node] = []
	(map[node] as Array).append(entry)

# ---- polyline sampling ---------------------------------------------------

func _poly_point(poly: Dictionary, s: float) -> Vector3:
	var n: PackedInt32Array = poly["n"]
	var cum: PackedFloat32Array = poly["cum"]
	var k := clampi(cum.bsearch(s, true) - 1, 0, n.size() - 2)
	var seg := cum[k + 1] - cum[k]
	var f := 0.0 if seg <= 0.0 else clampf((s - cum[k]) / seg, 0.0, 1.0)
	return nodes[n[k]].lerp(nodes[n[k + 1]], f)

func _poly_tangent(poly: Dictionary, s: float) -> Vector3:
	var n: PackedInt32Array = poly["n"]
	var cum: PackedFloat32Array = poly["cum"]
	var k := clampi(cum.bsearch(s, true) - 1, 0, n.size() - 2)
	var d := nodes[n[k + 1]] - nodes[n[k]]
	d.y = 0.0
	return d.normalized() if d.length_squared() > 1e-8 else Vector3(0, 0, -1)

func _length(poly: Dictionary) -> float:
	var cum: PackedFloat32Array = poly["cum"]
	return cum[cum.size() - 1]

func _travel_s(poly: Dictionary, dir: int, t: float) -> float:
	return t if dir == 1 else _length(poly) - t

func road_length(ri: int) -> float:
	return _length(roads[ri])

func road_tangent(ri: int, dir: int, t: float) -> Vector3:
	var poly: Dictionary = roads[ri]
	return _poly_tangent(poly, _travel_s(poly, dir, t)) * float(dir)

func road_point(ri: int, dir: int, lat: float, t: float) -> Vector3:
	var poly: Dictionary = roads[ri]
	var s := _travel_s(poly, dir, t)
	var d := _poly_tangent(poly, s) * float(dir)
	return _poly_point(poly, s) + Vector3(-d.z, 0.0, d.x) * lat

func end_node(ri: int, dir: int) -> int:
	var n: PackedInt32Array = roads[ri]["n"]
	return n[n.size() - 1] if dir == 1 else n[0]

func walk_length(wi: int) -> float:
	return _length(walks[wi])

func walk_tangent(wi: int, dir: int, t: float) -> Vector3:
	var poly: Dictionary = walks[wi]
	return _poly_tangent(poly, _travel_s(poly, dir, t)) * float(dir)

func walk_point(wi: int, dir: int, t: float) -> Vector3:
	var poly: Dictionary = walks[wi]
	return _poly_point(poly, _travel_s(poly, dir, t))

func walk_end_node(wi: int, dir: int) -> int:
	var n: PackedInt32Array = walks[wi]["n"]
	return n[n.size() - 1] if dir == 1 else n[0]

# ---- topology ------------------------------------------------------------

func _exits_from(map: Dictionary, node: int, idx: int, dir: int, allow_reverse: bool) -> Array:
	var out: Array = []
	for e in map.get(node, []):
		if not allow_reverse and e[0] == idx and e[1] == -dir:
			continue   # U-turn onto the polyline we arrived on
		out.append(e)
	return out

func exits(node: int, ri: int, dir: int, allow_reverse := false) -> Array:
	return _exits_from(_road_out, node, ri, dir, allow_reverse)

func walk_exits(node: int, wi: int, dir: int, allow_reverse := false) -> Array:
	return _exits_from(_walk_out, node, wi, dir, allow_reverse)

func is_junction(node: int) -> bool:
	return int(_arms.get(node, 0)) >= 3

func next_stop(ri: int, dir: int, t: float) -> Array:
	# [distance_ahead, node] of the next signal/junction node (a node just
	# passed within 1 m is still reported with a small negative distance), or [].
	var road: Dictionary = roads[ri]
	var stops: Array = road["stops"]
	if dir == 1:
		for st in stops:
			var d: float = st[0] - t
			if d > -1.0:
				return [d, st[1]]
	else:
		var s := road_length(ri) - t
		for k in range(stops.size() - 1, -1, -1):
			var d: float = s - stops[k][0]
			if d > -1.0:
				return [d, stops[k][1]]
	return []

# ---- lanes & signals -----------------------------------------------------

func lane_offset(ri: int, lane: int) -> float:
	var road: Dictionary = roads[ri]
	var w: float = road["w"]
	if road["oneway"] == 0:
		return clampf(w / 4.0, LANE_MIN, LANE_MAX)      # one lane per direction, right of centerline
	var lanes: int = road["lanes"]
	return w / 2.0 - w * (float(lane) + 0.5) / float(lanes)   # lane 0 = rightmost

func signal_group(node: int, heading: Vector3) -> int:
	var axis: Vector3 = _axis.get(node, Vector3(0, 0, -1))
	return 0 if absf(heading.dot(axis)) > 0.7071 else 1

func signal_green(node: int, group: int, time: float) -> bool:
	var t := fposmod(time + float(node) * 5.3, SIGNAL_PERIOD)   # per-node offset: the city is not synchronized
	if group == 0:
		return t < GREEN_A_END
	return t >= GREEN_B_START and t < GREEN_B_END
```

- [ ] **Step 4: Run the nav test**

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/nav_test.gd`
Expected: `NAV GRAPH OK: nodes=... roads=... walks=... signals=...`, exit 0. If the walk walker dead-ends, it means a `cross` pair or a `side` interval is isolated — allowed only if `allow_reverse` also fails, which cannot happen on a 2-node polyline; investigate before changing the test.

- [ ] **Step 5: Commit**

```bash
git add game/scripts/nav_graph.gd game/tests/nav_test.gd
git commit -m "game: NavGraph - nav.json loader with lane, exit, stop and signal-phase queries + headless test"
```

---

### Task 6: `traffic_car.tscn` + `traffic.gd` (spawn ring, lane following, cone braking, parked-car nudge) + smoke gates `NAV OK` / `TRAFFIC OK`

**Files:**
- Create: `game/scenes/traffic_car.tscn`
- Create: `game/scripts/traffic.gd`
- Modify: `game/scenes/main.tscn` (add `Traffic` node after `Cars`), `game/scripts/main.gd` (`agents_context()`, `_last_car`)
- Modify: `game/tests/smoke_test.gd` (two gates after `CARS OK`)

**Interfaces:**
- Consumes: `NavGraph` (Task 5); `car_visual.gd` with `color_index` set BEFORE the node enters the tree (its `_car := get_parent() as Car` becomes null on an `AnimatableBody3D` — harmless, `_process` returns early in model mode).
- Produces (read by smoke test, Task 7, Task 8, and 10b):
  - `Traffic.graph: NavGraph`, `enabled: bool`
  - `graph_counts() -> Dictionary {nodes, roads, walks, signals}`, `active_count() -> int`, `agent_positions() -> PackedVector3Array` (size `POOL_SIZE`, inactive slots = `Vector3(0, -9999, 0)`), `agent_forward(i) -> Vector3`, `agent_speed(i) -> float`, `clear_all()`
  - `obstacles: PackedVector3Array` — extra points (10b pedestrians) the cone brakes for
  - `main.agents_context() -> Dictionary {player: Vector3, player_on_foot: bool, car?: Vector3}`
  - `_stop_rules(i, fwd, pos, target) -> float` is the seam Task 7 fills (this task ships it as a pass-through).

- [ ] **Step 1: Scene** `game/scenes/traffic_car.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/car_visual.gd" id="2"]

[sub_resource type="BoxShape3D" id="box"]
size = Vector3(1.9, 1.1, 4.3)

[node name="TrafficCar" type="AnimatableBody3D"]
sync_to_physics = true

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.55, 0)
shape = SubResource("box")

[node name="Visual" type="Node3D" parent="."]
script = ExtResource("2")
```

- [ ] **Step 2: Smoke gates first (they fail until the manager exists)** — in `game/tests/smoke_test.gd`, insert right after `print("CARS OK: %d" % cars.get_child_count())`:

```gdscript
	var traffic := root.get_node_or_null("Traffic")
	if traffic == null:
		push_error("FAIL: Traffic node missing from main scene")
		quit(1)
		return
	var gc: Dictionary = traffic.call("graph_counts")
	if gc.get("nodes", 0) < 10000 or gc.get("roads", 0) < 1000 or gc.get("walks", 0) < 1000 or gc.get("signals", 0) < 500:
		push_error("FAIL: nav graph too small: %s" % str(gc))
		quit(1)
		return
	print("NAV OK: %d nodes, %d roads, %d walks, %d signals" % [gc["nodes"], gc["roads"], gc["walks"], gc["signals"]])
	var enough := false
	for i in 2400:  # spawn ticks are physics-time; poll, never fixed waits
		await process_frame
		if traffic.call("active_count") >= 20:
			enough = true
			break
	if not enough:
		push_error("FAIL: traffic never reached 20 active agents (active=%d)" % traffic.call("active_count"))
		quit(1)
		return
	var before: PackedVector3Array = traffic.call("agent_positions")
	var moved := false
	for i in 900:
		await process_frame
		var now: PackedVector3Array = traffic.call("agent_positions")
		for k in now.size():
			if before[k].y > -9000.0 and now[k].y > -9000.0 and before[k].distance_to(now[k]) > 5.0:
				moved = true
				break
		if moved:
			break
	if not moved:
		push_error("FAIL: no traffic agent moved > 5 m")
		quit(1)
		return
	print("TRAFFIC OK: %d active" % traffic.call("active_count"))
```

- [ ] **Step 3: Run to verify failure**

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`
Expected: `FAIL: Traffic node missing from main scene`, exit 1.

- [ ] **Step 4: Implement** `game/scripts/traffic.gd`:

```gdscript
extends Node3D
class_name Traffic
# Pooled traffic on the nav graph's lane centerlines (right-hand traffic).
# ONE manager, parallel state arrays, no per-agent scripts, no raycasts:
# heights ride the graph so agents stay valid outside the 280 m collision
# ring. Bodies are AnimatableBody3D (sync_to_physics) so the player's
# kinematic car collides with them; agents only ever brake, never react.
# Update runs in _physics_process (like car.gd) so the physics server sees
# consistent kinematic motion.

const SCENE := preload("res://scenes/traffic_car.tscn")
const POOL_SIZE := 40
const SPAWN_MIN := 80.0
const SPAWN_MAX := 220.0
const DESPAWN := 280.0
const SPAWN_INTERVAL := 0.5
const SPAWN_PER_TICK := 4          # burst-fill an empty pool in ~2.5 s
const SPAWN_GAP := 15.0
const SPAWN_CELL := 64.0
const CONE_LEN := 15.0
const CONE_HALF_W := 2.5
const CAR_LEN := 4.3
const HEADWAY_SEC := 2.0
const HEADWAY_MIN := 6.0
const ACCEL := 9.0                 # mirrors car.gd so traffic reads like the player's car
const BRAKE := 16.0
const SOFT_BRAKE := 4.0            # comfortable stop at lines/junctions
const STOP_LINE := 6.0
const JUNCTION_R := 8.0
const JUNCTION_SLOW := 15.0
const TURN_CHANCE := 0.35
const STUCK_SEC := 20.0
const PASS_AHEAD := 12.0
const PASS_NUDGE := 1.0
const LAT_RATE := 3.0
const CURVE_LOOKAHEAD := 8.0
const HEADLIGHTS := 8
const HEADLIGHT_REASSIGN := 0.25
const INACTIVE_POS := Vector3(0, -9999, 0)

@export var enabled := true

var graph: NavGraph
var obstacles := PackedVector3Array()   # extra brake points (10b pedestrians)

var _bodies: Array[AnimatableBody3D] = []
var _shapes: Array[CollisionShape3D] = []
var _active := PackedByteArray()
var _road := PackedInt32Array()
var _dir := PackedInt32Array()
var _lane := PackedInt32Array()
var _t := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _seed := PackedInt32Array()
var _stuck := PackedFloat32Array()
var _lat := PackedFloat32Array()
var _pos := PackedVector3Array()
var _fwd := PackedVector3Array()
var _hold := PackedInt32Array()        # junction node this agent occupies, or -1
var _occupant: Dictionary = {}         # junction node -> agent idx
var _parked := PackedVector3Array()    # all 120 parked cars (metadata)
var _parked_near := PackedVector3Array()
var _cells: Dictionary = {}            # Vector2i -> Array of [road_idx, t_forward]
var _lights: Array[SpotLight3D] = []
var _light_agent := PackedInt32Array()
var _spawn_accum := 0.0
var _light_accum := 1.0
var _rng := 20260911
var _time := 0.0

# ---- accessors (smoke test / 10b) -----------------------------------------

func graph_counts() -> Dictionary:
	if graph == null:
		return {}
	return {"nodes": graph.nodes.size(), "roads": graph.roads.size(),
		"walks": graph.walks.size(), "signals": graph.signals.size()}

func active_count() -> int:
	var c := 0
	for i in POOL_SIZE:
		if _active[i] == 1:
			c += 1
	return c

func agent_positions() -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in POOL_SIZE:
		out.append(_pos[i] if _active[i] == 1 else INACTIVE_POS)
	return out

func agent_forward(i: int) -> Vector3:
	return _fwd[i]

func agent_speed(i: int) -> float:
	return _speed[i] if _active[i] == 1 else 0.0

func clear_all() -> void:
	for i in POOL_SIZE:
		if _active[i] == 1:
			_deactivate(i)

# ---- setup ------------------------------------------------------------------

func _ready() -> void:
	add_to_group("traffic")
	graph = NavGraph.load_from("res://world/nav.json")
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if f != null:
		var meta: Variant = JSON.parse_string(f.get_as_text())
		if typeof(meta) == TYPE_DICTIONARY:
			for cs in meta.get("car_spawns", []):
				_parked.append(Vector3(cs["x"], cs["y"], cs["z"]))
	_active.resize(POOL_SIZE); _road.resize(POOL_SIZE); _dir.resize(POOL_SIZE)
	_lane.resize(POOL_SIZE); _t.resize(POOL_SIZE); _speed.resize(POOL_SIZE)
	_seed.resize(POOL_SIZE); _stuck.resize(POOL_SIZE); _lat.resize(POOL_SIZE)
	_pos.resize(POOL_SIZE); _fwd.resize(POOL_SIZE); _hold.resize(POOL_SIZE)
	for i in POOL_SIZE:
		var body := SCENE.instantiate() as AnimatableBody3D
		(body.get_node("Visual") as Node3D).set("color_index", i % 6)
		add_child(body)
		body.visible = false
		var shape := body.get_node("CollisionShape3D") as CollisionShape3D
		shape.disabled = true
		(body.get_node("Visual") as Node3D).set_process(false)   # model mode never needs it
		_bodies.append(body)
		_shapes.append(shape)
		_active[i] = 0
		_hold[i] = -1
		_pos[i] = INACTIVE_POS
	_build_spawn_cells()
	for k in HEADLIGHTS:
		var l := SpotLight3D.new()
		l.light_color = Color(1, 0.93, 0.8)
		l.light_energy = 0.0
		l.spot_range = 32.0
		l.spot_angle = 45.0
		l.shadow_enabled = false
		l.light_volumetric_fog_energy = 1.5
		add_child(l)
		_lights.append(l)
		_light_agent.append(-1)

func _build_spawn_cells() -> void:
	# Bucket every road node (as [road, t_forward]) into 64 m cells so spawning
	# can sample the ring around the camera instead of the whole 4.4 km world.
	for ri in graph.roads.size():
		var n: PackedInt32Array = graph.roads[ri]["n"]
		var cum: PackedFloat32Array = graph.roads[ri]["cum"]
		for k in n.size():
			var p := graph.nodes[n[k]]
			var cell := Vector2i(floori(p.x / SPAWN_CELL), floori(p.z / SPAWN_CELL))
			if not _cells.has(cell):
				_cells[cell] = []
			(_cells[cell] as Array).append([ri, cum[k]])

func _rand01() -> float:
	_rng = int((_rng * 1103515245 + 12345) % 2147483648)
	return float(_rng) / 2147483648.0

func _rand_int(n: int) -> int:
	return int(_rand01() * float(n)) % maxi(n, 1)

# ---- frame ------------------------------------------------------------------

func _context() -> Dictionary:
	var main := get_parent()
	if main != null and main.has_method("agents_context"):
		return main.call("agents_context")
	return {}

func _physics_process(delta: float) -> void:
	_time += delta
	if not enabled or graph == null or graph.roads.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cam_pos := cam.global_position
	var ctx := _context()
	_spawn_accum += delta
	if _spawn_accum >= SPAWN_INTERVAL:
		_spawn_accum = 0.0
		_refresh_parked_near(cam_pos)
		_spawn_some(cam, ctx)
	for i in POOL_SIZE:
		if _active[i] == 0:
			continue
		_step_agent(i, delta, ctx)
		if _active[i] == 1 and (_pos[i].distance_to(cam_pos) > DESPAWN or _stuck[i] > STUCK_SEC):
			_deactivate(i)
	_update_headlights(delta, cam_pos)

# ---- spawning ----------------------------------------------------------------

func _refresh_parked_near(cam_pos: Vector3) -> void:
	_parked_near.clear()
	for p in _parked:
		if p.distance_to(cam_pos) < DESPAWN + 50.0:
			_parked_near.append(p)

func _free_slot() -> int:
	for i in POOL_SIZE:
		if _active[i] == 0:
			return i
	return -1

func _clear_of_others(pos: Vector3, ctx: Dictionary) -> bool:
	for j in POOL_SIZE:
		if _active[j] == 1 and _pos[j].distance_to(pos) < SPAWN_GAP:
			return false
	for p in _parked_near:
		if p.distance_to(pos) < SPAWN_GAP:
			return false
	if ctx.has("car") and (ctx["car"] as Vector3).distance_to(pos) < SPAWN_GAP:
		return false
	return true

func _spawn_some(cam: Camera3D, ctx: Dictionary) -> void:
	var cam_pos := cam.global_position
	var cam_fwd := -cam.global_transform.basis.z
	var spawned := 0
	var attempts := 0
	while spawned < SPAWN_PER_TICK and attempts < 24:
		attempts += 1
		var slot := _free_slot()
		if slot < 0:
			return
		var ang := _rand01() * TAU
		var rad := SPAWN_MIN + _rand01() * (SPAWN_MAX - SPAWN_MIN)
		var probe := cam_pos + Vector3(cos(ang), 0.0, sin(ang)) * rad
		var cands: Array = _cells.get(Vector2i(floori(probe.x / SPAWN_CELL), floori(probe.z / SPAWN_CELL)), [])
		if cands.is_empty():
			continue
		var c: Array = cands[_rand_int(cands.size())]
		var ri: int = c[0]
		var road: Dictionary = graph.roads[ri]
		var length := graph.road_length(ri)
		if length < 10.0:
			continue
		var dir := 1 if (road["oneway"] == 1 or _rand01() < 0.5) else -1
		var t: float = c[1] if dir == 1 else length - c[1]
		t = clampf(t, 0.0, length - 0.1)
		var lane := _rand_int(road["lanes"]) if road["oneway"] == 1 else 0
		var lat := graph.lane_offset(ri, lane)
		var pos := graph.road_point(ri, dir, lat, t)
		var d := pos.distance_to(cam_pos)
		if d < SPAWN_MIN or d > SPAWN_MAX:
			continue
		if attempts < 12 and (pos - cam_pos).normalized().dot(cam_fwd) > 0.3:
			continue   # first tries prefer spawning behind the camera
		if not _clear_of_others(pos, ctx):
			continue
		_activate(slot, ri, dir, lane, t, lat)
		spawned += 1

func _activate(i: int, ri: int, dir: int, lane: int, t: float, lat: float) -> void:
	_active[i] = 1
	_road[i] = ri; _dir[i] = dir; _lane[i] = lane; _t[i] = t; _lat[i] = lat
	_speed[i] = float(graph.roads[ri]["speed"]) * 0.5
	_seed[i] = int((_rng + i * 7919) % 2147483647)
	_stuck[i] = 0.0
	_hold[i] = -1
	_fwd[i] = graph.road_tangent(ri, dir, t)
	_pos[i] = graph.road_point(ri, dir, lat, t)
	var body := _bodies[i]
	body.global_transform = Transform3D(Basis.from_euler(Vector3(0.0, NavGraph.yaw_for(_fwd[i]), 0.0)), _pos[i])
	body.visible = true
	_shapes[i].set_deferred("disabled", false)

func _deactivate(i: int) -> void:
	_active[i] = 0
	_release(i)
	_bodies[i].visible = false
	_shapes[i].set_deferred("disabled", true)
	_pos[i] = INACTIVE_POS

# ---- agent step ----------------------------------------------------------------

func _stop_speed(gap: float) -> float:
	return sqrt(maxf(0.0, 2.0 * SOFT_BRAKE * gap))

func _cone_gap(pos: Vector3, fwd: Vector3, right: Vector3, o: Vector3) -> float:
	var rel := o - pos
	if absf(rel.y) > 4.0:
		return INF   # overpass / underpass
	var f := rel.dot(fwd)
	if f <= 0.0 or f > CONE_LEN + CAR_LEN or absf(rel.dot(right)) > CONE_HALF_W:
		return INF
	return f - CAR_LEN

func _nearest_gap(i: int, pos: Vector3, fwd: Vector3, right: Vector3, ctx: Dictionary) -> float:
	var best := INF
	for j in POOL_SIZE:
		if j != i and _active[j] == 1:
			best = minf(best, _cone_gap(pos, fwd, right, _pos[j]))
	if ctx.has("car"):
		best = minf(best, _cone_gap(pos, fwd, right, ctx["car"]))
	if ctx.get("player_on_foot", false):
		best = minf(best, _cone_gap(pos, fwd, right, ctx["player"]))
	for o in obstacles:
		best = minf(best, _cone_gap(pos, fwd, right, o))
	return best

func _parked_ahead(pos: Vector3, fwd: Vector3, right: Vector3) -> bool:
	for p in _parked_near:
		var rel := p - pos
		var f := rel.dot(fwd)
		if f > -2.0 and f < PASS_AHEAD and absf(rel.dot(right)) < 2.0 and absf(rel.y) < 4.0:
			return true
	return false

func _release(i: int) -> void:
	var node := _hold[i]
	if node >= 0:
		if _occupant.get(node, -1) == i:
			_occupant.erase(node)
		_hold[i] = -1

func _stop_rules(_i: int, _fwd: Vector3, _pos_now: Vector3, target: float) -> float:
	return target   # Task 7: signals + junction yield

func _maybe_turn(_i: int, _node: int) -> void:
	pass            # Task 7: turn at interior junctions

func _step_agent(i: int, delta: float, ctx: Dictionary) -> void:
	var ri := _road[i]
	var dir := _dir[i]
	var t := _t[i]
	var road: Dictionary = graph.roads[ri]
	var length := graph.road_length(ri)
	var fwd := graph.road_tangent(ri, dir, t)
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var pos := graph.road_point(ri, dir, _lat[i], t)
	var target: float = road["speed"]
	# curve ahead on this road
	var turn := fwd.angle_to(graph.road_tangent(ri, dir, minf(t + CURVE_LOOKAHEAD, length)))
	target *= clampf(1.0 - turn / 1.2, 0.35, 1.0)
	# turn onto the (single) exit at the road end
	if length - t < CURVE_LOOKAHEAD:
		var ex := graph.exits(graph.end_node(ri, dir), ri, dir)
		if ex.size() == 1:
			target *= clampf(1.0 - fwd.angle_to(graph.road_tangent(ex[0][0], ex[0][1], ex[0][2])) / 1.2, 0.35, 1.0)
		elif ex.is_empty():
			target = minf(target, 2.0)
	target = _stop_rules(i, fwd, pos, target)
	# anything in the cone ahead
	var gap := _nearest_gap(i, pos, fwd, right, ctx)
	if gap < INF:
		target = minf(target, maxf(0.0, (gap - HEADWAY_MIN) / HEADWAY_SEC))
	# parked car in the lane: nudge toward the centerline while passing
	var lane_off := graph.lane_offset(ri, _lane[i])
	var want := maxf(0.6, lane_off - PASS_NUDGE) if _parked_ahead(pos, fwd, right) else lane_off
	_lat[i] = move_toward(_lat[i], want, LAT_RATE * delta)
	# integrate
	var sp := clampf(target, _speed[i] - BRAKE * delta, _speed[i] + ACCEL * delta)
	_speed[i] = sp
	_stuck[i] = _stuck[i] + delta if sp < 0.2 else 0.0
	var stop := graph.next_stop(ri, dir, t)
	var t_new := t + sp * delta
	if not stop.is_empty() and stop[0] > 0.0 and t_new - t >= stop[0] and t + stop[0] < length - 0.5:
		_maybe_turn(i, stop[1])          # may rewrite _road/_dir/_t
		if _road[i] != ri or _dir[i] != dir:
			_settle(i)
			return
	t = t_new
	if t >= length:
		var node := graph.end_node(ri, dir)
		var ex := graph.exits(node, ri, dir)
		if ex.is_empty():
			ex = graph.exits(node, ri, dir, true)
		if ex.is_empty():
			_deactivate(i)
			return
		_seed[i] = int((_seed[i] * 1103515245 + 12345) % 2147483648)
		var e: Array = ex[NavGraph.pick(_seed[i], ex.size())]
		_release(i)
		_enter_road(i, e[0], e[1], e[2] + (t - length))
		return
	_t[i] = t
	_settle(i)

func _enter_road(i: int, ri: int, dir: int, t: float) -> void:
	var road: Dictionary = graph.roads[ri]
	_road[i] = ri
	_dir[i] = dir
	_t[i] = clampf(t, 0.0, graph.road_length(ri))
	_lane[i] = (_seed[i] % int(road["lanes"])) if road["oneway"] == 1 else 0
	_settle(i)

func _settle(i: int) -> void:
	# write pose from (road, dir, lat, t) to the body
	var ri := _road[i]
	var dir := _dir[i]
	var t := _t[i]
	_fwd[i] = graph.road_tangent(ri, dir, t)
	_pos[i] = graph.road_point(ri, dir, _lat[i], t)
	_bodies[i].global_transform = Transform3D(Basis.from_euler(Vector3(0.0, NavGraph.yaw_for(_fwd[i]), 0.0)), _pos[i])

# ---- pooled headlights ------------------------------------------------------------

func _update_headlights(delta: float, cam_pos: Vector3) -> void:
	_light_accum += delta
	var sun := get_tree().get_first_node_in_group("sun")
	var night: float = 0.0 if sun == null else sun.night_amount
	var energy := 20.0 * smoothstep(0.4, 0.55, night)
	if _light_accum >= HEADLIGHT_REASSIGN:
		_light_accum = 0.0
		var near: Array = []
		for i in POOL_SIZE:
			if _active[i] == 1:
				near.append([_pos[i].distance_squared_to(cam_pos), i])
		near.sort_custom(func(a, b): return a[0] < b[0])
		for k in HEADLIGHTS:
			_light_agent[k] = near[k][1] if k < near.size() else -1
	for k in HEADLIGHTS:
		var a := _light_agent[k]
		var l := _lights[k]
		if a < 0 or _active[a] == 0 or energy <= 0.0:
			l.light_energy = 0.0
			continue
		l.light_energy = energy
		var yaw := NavGraph.yaw_for(_fwd[a])
		l.global_transform = Transform3D(Basis.from_euler(Vector3(-0.13, yaw, 0.0)), _pos[a] + _fwd[a] * 2.0 + Vector3(0, 0.72, 0))
```

- [ ] **Step 5: Wire the scene and main.gd**

`game/scenes/main.tscn`: add an ext_resource line next to the others at the top (use the next free numeric id; check with `grep -n ext_resource game/scenes/main.tscn`), e.g. `[ext_resource type="Script" path="res://scripts/traffic.gd" id="15"]`, bump `load_steps` by 1, and insert after the `Cars` node:

```
[node name="Traffic" type="Node3D" parent="."]
script = ExtResource("15")
```

`game/scripts/main.gd`: add `var _last_car: Car = null` under `_driving`, set `_last_car = car` as the first line inside `_enter_car` after the early return, and add:

```gdscript
func agents_context() -> Dictionary:
	# Read by Traffic/Pedestrians each physics frame: what the agents must brake for.
	var ctx := {"player": _player.global_position, "player_on_foot": _player.visible}
	var car := _driving if _driving != null else _last_car
	if car != null:
		ctx["car"] = car.global_position
	return ctx
```

- [ ] **Step 6: Run smoke**

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`
Expected: `NAV OK: ...`, `TRAFFIC OK: N active` (N ≥ 20), then the existing gates through `SMOKE OK: 314 tiles`. If `ENTER OK`/`DRIVE OK` become flaky because an agent drives through `Cars[0]`, insert `traffic.call("clear_all"); traffic.set("enabled", false)` right after the `TRAFFIC OK` print (after Task 7's `SIGNALS OK` once it exists) — later gates never need traffic.

- [ ] **Step 7: Run the nav test again and the headless model tests** (unchanged, just proving nothing regressed):

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/nav_test.gd`
Expected: `NAV GRAPH OK`.

- [ ] **Step 8: Commit**

```bash
git add game/scenes/traffic_car.tscn game/scripts/traffic.gd game/scenes/main.tscn game/scripts/main.gd game/tests/smoke_test.gd
git commit -m "game: pooled traffic agents on nav lanes - spawn ring, cone braking, parked-car nudge; NAV/TRAFFIC smoke gates"
```

---

### Task 7: Signals, junction yield, turns at interior junctions + `SIGNALS OK` gate

**Files:**
- Modify: `game/scripts/traffic.gd` (replace `_stop_rules` and `_maybe_turn` stubs; add `signal_probe()`)
- Modify: `game/tests/smoke_test.gd` (gate after `TRAFFIC OK`)

**Interfaces:**
- Consumes: `NavGraph.next_stop/signal_group/signal_green/is_junction/exits`, `_occupant`/`_hold`/`_release` from Task 6.
- Produces: `signal_probe() -> Dictionary {a_green, a_red, b_green, b_red, both}` for the smoke gate.

- [ ] **Step 1: Gate first** — in `smoke_test.gd`, right after `print("TRAFFIC OK: ...")`:

```gdscript
	var sp: Dictionary = traffic.call("signal_probe")
	if not (sp.get("a_green", false) and sp.get("a_red", false) and sp.get("b_green", false) and sp.get("b_red", false)) or sp.get("both", true):
		push_error("FAIL: signal phases wrong: %s" % str(sp))
		quit(1)
		return
	print("SIGNALS OK")
	traffic.call("clear_all")
	traffic.set("enabled", false)   # later gates (ENTER/DRIVE/EXIT) must not meet traffic
```

- [ ] **Step 2: Run to verify failure**

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`
Expected: error `Invalid call. Nonexistent function 'signal_probe'` (or `FAIL: signal phases wrong`), exit non-zero.

- [ ] **Step 3: Implement** — replace the two stubs in `traffic.gd`:

```gdscript
func _stop_rules(i: int, fwd: Vector3, pos_now: Vector3, target: float) -> float:
	# Signals: stop at a red's stop line unless the bumper is already past it.
	# Unsignalized junctions: slow to half within 15 m; the first agent inside
	# the 8 m radius owns the node, others hold at the stop line until it leaves.
	var stop := graph.next_stop(_road[i], _dir[i], _t[i])
	if stop.is_empty():
		if _hold[i] >= 0 and pos_now.distance_to(graph.nodes[_hold[i]]) > JUNCTION_R + 2.0:
			_release(i)
		return target
	var d: float = stop[0]
	var node: int = stop[1]
	if graph.signals.has(node):
		var grp := graph.signal_group(node, fwd)
		if not graph.signal_green(node, grp, _time) and d > STOP_LINE - 1.0:
			target = minf(target, _stop_speed(d - STOP_LINE))
	else:
		if d < JUNCTION_SLOW:
			target = minf(target, float(graph.roads[_road[i]]["speed"]) * 0.5)
		if d < JUNCTION_R:
			var owner: int = _occupant.get(node, -1)
			if owner < 0 or _active[owner] == 0:
				_occupant[node] = i
				_hold[i] = node
			elif owner != i and d > STOP_LINE - 1.0:
				target = minf(target, _stop_speed(d - STOP_LINE))
	if _hold[i] >= 0 and _hold[i] != node and pos_now.distance_to(graph.nodes[_hold[i]]) > JUNCTION_R + 2.0:
		_release(i)
	return target

func _maybe_turn(i: int, node: int) -> void:
	# Passing an interior junction: with TURN_CHANCE take a side exit
	# (never the continuation, never the reverse).
	if not graph.is_junction(node):
		return
	_seed[i] = int((_seed[i] * 1103515245 + 12345) % 2147483648)
	if float(_seed[i] % 1000) / 1000.0 >= TURN_CHANCE:
		return
	var options: Array = []
	for e in graph.exits(node, _road[i], _dir[i]):
		if not (e[0] == _road[i] and e[1] == _dir[i]):
			options.append(e)
	if options.is_empty():
		return
	var e: Array = options[NavGraph.pick(_seed[i], options.size())]
	_release(i)
	_enter_road(i, e[0], e[1], e[2])

func signal_probe() -> Dictionary:
	# Sweep one 16 s cycle on the first signal node that has two approach groups.
	var out := {"a_green": false, "a_red": false, "b_green": false, "b_red": false, "both": false}
	if graph == null:
		return out
	var probe := -1
	for node in graph.signals:
		var g0 := 0
		var g1 := 0
		for e in graph.exits(node, -1, 0, true):
			if graph.signal_group(node, graph.road_tangent(e[0], e[1], e[2])) == 0:
				g0 += 1
			else:
				g1 += 1
		if g0 > 0 and g1 > 0:
			probe = node
			break
	if probe < 0:
		return out
	var tt := 0.0
	while tt < NavGraph.SIGNAL_PERIOD:
		var ga := graph.signal_green(probe, 0, tt)
		var gb := graph.signal_green(probe, 1, tt)
		out["both"] = out["both"] or (ga and gb)
		out["a_green"] = out["a_green"] or ga
		out["a_red"] = out["a_red"] or not ga
		out["b_green"] = out["b_green"] or gb
		out["b_red"] = out["b_red"] or not gb
		tt += 0.5
	return out
```

Also, since `_stop_rules` now releases stale holds, delete nothing else — `_deactivate` still calls `_release`.

- [ ] **Step 4: Run smoke**

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`
Expected: `... TRAFFIC OK: N active`, `SIGNALS OK`, then all prior gates, `SMOKE OK: 314 tiles` (23 gates).

- [ ] **Step 5: Windowed sanity run (GPU)** — launch the game for ~60 s and watch an intersection near spawn:

Run: `tools/godot/godot_console.exe --path game` (close the window when done)
Check: cars stay on the right, queue behind each other, stop at a red then go, do not pile up permanently at a 4-way (yield releases). Note the frame rate with **F** fly-cam over a busy street vs. `Traffic.enabled = false` (toggle via the Remote tree or temporarily set the export to false): the delta must be well under ~1 ms. Record the observation for the HANDOFF; if agents pile permanently at one junction, the most likely cause is a hold never released (an owner deactivated by the stuck timer while others wait) — `_stop_rules` already treats an inactive owner as free; confirm `_release` runs in `_deactivate`.

- [ ] **Step 6: Commit**

```bash
git add game/scripts/traffic.gd game/tests/smoke_test.gd
git commit -m "game: traffic obeys signal phases, yields at junctions, turns at interior junctions; SIGNALS smoke gate"
```

---

### Task 8: Screenshot poses (signal + crosswalk, day/night, with settle) and capture

**Files:**
- Modify: `game/tests/screenshot.gd` (`settle` support + 4 poses)
- Output: `docs/screenshots/m10a_*.png` (13 baseline + `signal`, `signal_night`, `crosswalk`, `crosswalk_night`)

**Interfaces:**
- Consumes: `game/world/nav.json` (to choose real intersections), `Traffic` spawning relative to the ACTIVE camera (the fly cam during fixed poses).

- [ ] **Step 1: Pick two real intersections** with a throwaway query (not committed):

```bash
.venv/Scripts/python - <<'EOF'
import json, math
d = json.load(open("game/world/nav.json"))
nodes = d["nodes"]
arms = {}
for r in d["roads"]:
    n = r["n"]
    for k, i in enumerate(n):
        arms[i] = arms.get(i, 0) + (1 if k in (0, len(n) - 1) else 2)
sig = [i for i in d["signals"] if arms.get(i, 0) >= 4]
sig.sort(key=lambda i: math.hypot(nodes[i][0], nodes[i][2]))
print("signal 4-way nearest origin:", [(i, nodes[i]) for i in sig[:3]])
junc = [i for i, a in arms.items() if a >= 4 and i not in d["signals"]]
junc.sort(key=lambda i: math.hypot(nodes[i][0] + 273, nodes[i][2] + 60))
print("unsignalized 4-way nearest onfoot_day:", [(i, nodes[i]) for i in junc[:3]])
EOF
```

Take the first of each: `(SX, SY, SZ)` for the signal, `(CX, CY, CZ)` for the crosswalk corner.

- [ ] **Step 2: Add `settle` support and the poses** in `game/tests/screenshot.gd`. In the fixed-pose branch replace `for i in 15:` with `for i in int(pose.get("settle", 15)):`. Append to `POSES` (fill the numbers from Step 1; camera 6 m up, 28 m back toward +z, looking at the junction node 1 m up):

```gdscript
	{"name": "signal",          "pos": Vector3(SX, SY + 6, SZ + 28), "look": Vector3(SX, SY + 1, SZ), "time": 0.4,  "settle": 720},
	{"name": "signal_night",    "pos": Vector3(SX, SY + 6, SZ + 28), "look": Vector3(SX, SY + 1, SZ), "time": 0.95, "settle": 720},
	{"name": "crosswalk",       "pos": Vector3(CX + 20, CY + 5, CZ + 20), "look": Vector3(CX, CY + 1, CZ), "time": 0.4,  "settle": 720},
	{"name": "crosswalk_night", "pos": Vector3(CX + 20, CY + 5, CZ + 20), "look": Vector3(CX, CY + 1, CZ), "time": 0.95, "settle": 720},
```

(720 frames ≈ 12 s windowed: agents spawn ≥ 80 m out and drive in at 8–14 m/s.)

- [ ] **Step 3: Capture**

Run: `tools/godot/godot_console.exe --path game --script res://tests/screenshot.gd`
Expected: `saved shot_<name>.png` × 17 in `%APPDATA%/Godot/app_userdata/MTL Open Ile/`. Copy them: `for f in "$APPDATA/Godot/app_userdata/MTL Open Ile"/shot_*.png; do n=$(basename "$f" .png); cp "$f" "docs/screenshots/m10a_${n#shot_}.png"; done`.

- [ ] **Step 4: Review every PNG with the Read tool** (all 17). Required observations, written down for the HANDOFF:
  - `signal`/`signal_night`: several cars visible on the right side of their lanes; at least one queued at the intersection; at night, moving headlight cones on the nearest cars; lamps/windows/sky identical in character to `m9c2_night`.
  - `crosswalk*`: cars turning/passing through a 4-way without a permanent pile-up.
  - `driving_day`/`driving_night`: unchanged framing; any traffic present is not intersecting the player's car.
  - `night`, `dusk`, `overview`, `onfoot_night`: **no regression** vs `docs/screenshots/m9c2_*.png` (compare side by side by Reading both).
  If cars appear only far away, raise `settle` to 1200 before touching spawn radii. If any pose shows cars floating/sunk > 0.3 m, that is a node-height bug: check `ROAD_Y` (0.05) and that roads use densified stations (Task 2).

- [ ] **Step 5: Commit**

```bash
git add game/tests/screenshot.gd docs/screenshots/m10a_*.png
git commit -m "docs: M10a traffic screenshots (signal/crosswalk poses, day+night) + settle support"
```

---

### Task 9: Docs, HANDOFF, gate

**Files:**
- Modify: `README.md` (Roadmap: add M8/M9 lines if missing, then M10a), `docs/superpowers/HANDOFF.md` (rewrite the State paragraph + next steps)

- [ ] **Step 1: README roadmap** — append after the M7 line (keep existing lines; add the M8/M9 arcs in one line each if they are not there yet):

```markdown
- [x] **M10a** — Traffic: pipeline exports a road + sidewalk nav graph (`nav.json`, tiles byte-identical); 40 pooled cars drive real lanes on the right, queue at real signal positions, yield at junctions, brake for you, and collide with your car; pooled headlights at night
```

Also in "How it works", after the tiles bullet, one sentence: `nav.json` carries road/sidewalk polylines with baked heights so traffic and (M10b) pedestrians never raycast.

- [ ] **Step 2: HANDOFF rewrite** — replace the `**State (...)**` paragraph with the M10a state: what shipped (Tasks 1-8 in one paragraph, same density as the m9c3 entry), the numbers (nav.json size + counts from Task 4, smoke 23 gates ending `SMOKE OK: 314 tiles`, pytest count), the windowed perf observation from Task 7 Step 5, carry-forwards (spawn pop-in at 80 m with no fade; near-misses with parked cars on 6 m residential streets; signal heads static; `_nearest_gap` is O(POOL²) — fine at 40, revisit if the pool grows), and `NEXT: USER GATE (m10a screenshots) → tag m10a-traffic, push → M10b pedestrians plan (spec section 3; walks already exported; NavGraph.walk_* + Traffic.obstacles are the hooks)`. Update the "Environment gotchas" smoke expectation line to 23 gates and mention `nav_test.gd`.

- [ ] **Step 3: Final verification** (all three, outputs pasted into the gate message):

```
.venv/Scripts/python -m pytest pipeline -q
tools/godot/godot_console.exe --headless --path game --script res://tests/nav_test.gd
tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd
git status --short            # clean except the docs being committed
git log --format='%an <%ae>%n%b' -12 | grep -ci "co-authored\|claude-session"   # must print 0
```

- [ ] **Step 4: Commit and hand to the user gate**

```bash
git add README.md docs/superpowers/HANDOFF.md
git commit -m "docs: M10a traffic HANDOFF + README roadmap"
```

Then present the user gate: the 4 new screenshots + `night`/`driving_night` regressions, the smoke/pytest lines, and ask for pass/fail. On pass: `git tag m10a-traffic && git push && git push --tags`.

---

## Self-review (done while writing)

- **Spec coverage (10a):** nav schema incl. densified road nodes + heights (T2), oneway normalization/lanes/speed (T1/T2), signal snap (T2), walks side/path/cross + dead-end link + trim (T3), size guard + `nav_file` + byte-identical tiles (T4), NavGraph queries incl. `next_road` semantics (`exits`) and walk equivalents (T5), pool/spawn ring/behind-camera/despawn/stuck (T6), lanes + parked nudge + cone/headway + accel mirroring (T6), signals 16 s / groups / stop line / single-group nodes (T7 — single-group nodes cycle group 0 only, as specified), junction slow + yield (T7), AnimatableBody collision (T6 scene), pooled 8 headlights (T6), `agents_context` (T6), smoke gates `NAV/TRAFFIC/SIGNALS` + `nav_test.gd` (T5-T7), poses + night regression check (T8), perf budget observation (T7 step 5), HANDOFF/gate/tag (T9). Pedestrian-specific items (walk following, knockdown) are 10b by design.
- **Placeholders:** none; the only user-filled values are the two intersection coordinates in T8, produced by the given script.
- **Type consistency:** `exits(...)` entries are `[road_idx, dir, t_start]` everywhere (T5 build, T5 test, T6 `_step_agent`, T7 `_maybe_turn`/`signal_probe`); `next_stop` returns `[d, node]`; `agent_positions()` inactive sentinel `Vector3(0,-9999,0)` matches the smoke gate's `y > -9000` filter; `graph_counts()` keys match the gate; `_stop_rules(i, fwd, pos_now, target)` signature identical in T6 stub and T7 body.
