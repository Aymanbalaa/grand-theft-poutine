# MTL: Open Île — Plan 1: Scaffold + Gray City (Milestones 1–2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Godot project where you fly a free camera over the real downtown-Montreal street grid with gray extruded buildings, generated from OpenStreetMap data by a deterministic Python pipeline.

**Architecture:** Two halves joined by a data contract. `pipeline/` (Python 3.13) downloads OSM data for a fixed bounding box, converts it to local-meter geometry, and exports 256 m glTF tiles plus `city_metadata.json` into `game/world/`. `game/` (Godot 4.5) loads the tiles, shows/hides them by camera distance, and provides a fly camera.

**Tech Stack:** Python 3.13, shapely, trimesh, numpy, requests, pytest; Godot 4.5-stable (portable, pinned, in gitignored `tools/`); OSM via Overpass API (cached in gitignored `data/`).

## Global Constraints

- Commits: small and frequent; author must be `Aymanbalaa` ONLY — **never add `Co-Authored-By`, `Claude-Session`, or any AI trailer to any commit.**
- Repo root: `C:\Users\ayman\OneDrive\Documents\SideProjects\MontrealOpenWorld`
- Python: 3.13, venv at `.venv/` (repo root), run as `.venv/Scripts/python`
- Godot: version 4.5-stable, portable zip under `tools/godot/` (gitignored). If the 4.5-stable download URL 404s, use the newest 4.x **stable** from https://github.com/godotengine/godot-builds/releases and record the chosen version in `tools/GODOT_VERSION.txt` (gitignored) AND in the README.
- Coordinates: x = meters east of origin, z = meters **south** of origin (Godot convention: north = −Z). Origin: lat 45.504, lon −73.5535. Y is up; ground is y=0 (flat in this plan; terrain comes in a later plan).
- Map bbox (south, west, north, east): `45.488, -73.582, 45.520, -73.525`
- Tile size: 256 m. Per-tile budget: ≤ 120,000 triangles (pipeline enforces via assert at export).
- Determinism: identical input file + config ⇒ byte-identical `city_metadata.json` and identical mesh stats. Sort everything by OSM id.
- Data licenses: OSM = ODbL. Keep note in README: "Map data © OpenStreetMap contributors".
- All shell commands below run from repo root unless stated. Use forward slashes in bash.

## File Structure

```
MontrealOpenWorld/
├── .gitignore
├── README.md
├── requirements.txt
├── pipeline/
│   ├── __init__.py
│   ├── config.py        # bbox, origin, tile size, road widths, palette hooks
│   ├── geo.py           # lat/lon -> local meters
│   ├── osm_parse.py     # OSM XML -> CityData (roads/buildings/areas)
│   ├── meshes.py        # CityData items -> trimesh meshes
│   ├── tiler.py         # meshes -> per-tile scenes
│   ├── export.py        # tiles -> .glb files + city_metadata.json
│   ├── download.py      # Overpass query, cached to data/
│   ├── build.py         # CLI: full run (python -m pipeline.build)
│   └── tests/
│       ├── fixtures/mini.osm.xml
│       ├── test_geo.py
│       ├── test_osm_parse.py
│       ├── test_meshes.py
│       └── test_export.py
├── game/
│   ├── project.godot
│   ├── icon.svg              # (godot default, optional)
│   ├── scenes/main.tscn
│   ├── scripts/fly_camera.gd
│   ├── scripts/tile_loader.gd
│   ├── tests/smoke_test.gd
│   ├── tests/screenshot.gd
│   └── world/                # generated tiles + metadata (committed)
├── data/                     # gitignored raw downloads
├── tools/                    # gitignored (godot binary)
└── docs/
```

---

### Task 1: Repo scaffold + Python env

**Files:**
- Create: `.gitignore`, `README.md`, `requirements.txt`, `pipeline/__init__.py`, `pipeline/tests/test_geo.py` (placeholder-free smoke), `data/.gitkeep` is NOT needed (dir is gitignored)

**Interfaces:**
- Produces: working `.venv` with deps; `pytest` runs green; directory skeleton later tasks assume.

- [ ] **Step 1: Write `.gitignore`**

```gitignore
.venv/
__pycache__/
*.pyc
data/
tools/
game/.godot/
*.import
.pytest_cache/
.superpowers/
```

- [ ] **Step 2: Write `README.md`**

```markdown
# MTL: Open Île

Open-world free-roam game set in downtown Montréal. Godot 4.5 + Python map pipeline.

- `pipeline/` — Python: OSM data → glTF city tiles (`game/world/`)
- `game/` — Godot 4.5 project

## Setup
1. `py -m venv .venv && .venv/Scripts/pip install -r requirements.txt`
2. Godot 4.5-stable portable → `tools/godot/` (see docs/superpowers/plans)
3. Generate city: `.venv/Scripts/python -m pipeline.build`
4. Open `game/` in Godot, run `scenes/main.tscn`

Map data © OpenStreetMap contributors (ODbL).
```

- [ ] **Step 3: Write `requirements.txt`**

```
shapely>=2.0
trimesh>=4.0
mapbox-earcut>=1.0
numpy>=1.26
requests>=2.31
pytest>=8.0
```

- [ ] **Step 4: Create venv, install, create package**

```bash
py -m venv .venv && .venv/Scripts/pip install -r requirements.txt
mkdir -p pipeline/tests/fixtures game/world game/scenes game/scripts game/tests data tools
touch pipeline/__init__.py pipeline/tests/__init__.py
```
Expected: pip installs all five packages without error.

- [ ] **Step 5: Verify pytest runs (no tests yet)**

Run: `.venv/Scripts/python -m pytest pipeline -q`
Expected: `no tests ran` exit code 5 — that's fine, tooling works.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Scaffold repo: pipeline package, Python env, gitignore"
```

---

### Task 2: Godot 4.5 portable install + empty project boots

**Files:**
- Create: `game/project.godot`, `tools/godot/` (binary, gitignored)

**Interfaces:**
- Produces: `tools/godot/godot.exe` (console binary renamed) runnable headless; `game/` opens as a valid Godot 4.5 project. Later tasks run `tools/godot/godot.exe --headless --path game ...`.

- [ ] **Step 1: Download + unzip Godot**

```bash
curl -L -o tools/godot.zip https://github.com/godotengine/godot-builds/releases/download/4.5-stable/Godot_v4.5-stable_win64.exe.zip
cd tools && unzip -o godot.zip -d godot_tmp && mkdir -p godot && cp godot_tmp/*console.exe godot/godot.exe && cp godot_tmp/Godot_v4.5-stable_win64.exe godot/godot_gui.exe && rm -rf godot_tmp godot.zip && cd ..
echo "4.5-stable" > tools/GODOT_VERSION.txt
```
If the URL 404s: list releases at https://github.com/godotengine/godot-builds/releases, pick newest 4.x stable, adjust names, update README + `tools/GODOT_VERSION.txt`.

- [ ] **Step 2: Verify**

Run: `tools/godot/godot.exe --version`
Expected: prints `4.5.stable...`

- [ ] **Step 3: Write `game/project.godot`**

```ini
; Engine configuration file.
config_version=5

[application]
config/name="MTL Open Ile"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.5")

[rendering]
renderer/rendering_method="forward_plus"
```

- [ ] **Step 4: Verify project imports headless**

Run: `tools/godot/godot.exe --headless --path game --import`
Expected: exits 0 (warnings about missing main scene are OK at this stage; `main.tscn` arrives in Task 8).

- [ ] **Step 5: Commit**

```bash
git add game/project.godot README.md && git commit -m "Add Godot 4.5 project shell (binary lives untracked in tools/)"
```

---

### Task 3: `geo.py` — lat/lon → local meters

**Files:**
- Create: `pipeline/config.py`, `pipeline/geo.py`
- Test: `pipeline/tests/test_geo.py`

**Interfaces:**
- Produces: `latlon_to_xz(lat: float, lon: float) -> tuple[float, float]` (uses config origin; x east, z south) and `config.BBOX = (45.488, -73.582, 45.520, -73.525)`, `config.ORIGIN = (45.504, -73.5535)`, `config.TILE_SIZE = 256.0`, `config.ROAD_WIDTHS: dict[str, float]`, `config.DEFAULT_ROAD_WIDTH = 6.0`, `config.LEVEL_HEIGHT = 3.2`, `config.DEFAULT_BUILDING_HEIGHT = 10.0`, `config.MAX_TILE_TRIS = 120000`.

- [ ] **Step 1: Write failing test `pipeline/tests/test_geo.py`**

```python
import math
from pipeline.geo import latlon_to_xz
from pipeline import config

def test_origin_maps_to_zero():
    x, z = latlon_to_xz(*config.ORIGIN)
    assert abs(x) < 1e-6 and abs(z) < 1e-6

def test_north_is_negative_z():
    _, z = latlon_to_xz(config.ORIGIN[0] + 0.01, config.ORIGIN[1])
    assert z < -1000  # ~1.11 km north => z ≈ -1110

def test_east_is_positive_x_scaled_by_latitude():
    x, _ = latlon_to_xz(config.ORIGIN[0], config.ORIGIN[1] + 0.01)
    expected = 0.01 * 111320.0 * math.cos(math.radians(config.ORIGIN[0]))
    assert abs(x - expected) < 1.0
```

- [ ] **Step 2: Run to verify it fails**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_geo.py -q`
Expected: FAIL (ModuleNotFoundError / ImportError).

- [ ] **Step 3: Write `pipeline/config.py`**

```python
# Map bounding box (south, west, north, east) — downtown core + Old Port + Habitat 67 + Biosphere
BBOX = (45.488, -73.582, 45.520, -73.525)
# Local origin (lat, lon) — near Place Ville Marie
ORIGIN = (45.504, -73.5535)
TILE_SIZE = 256.0

ROAD_WIDTHS = {
    "motorway": 14.0, "trunk": 12.0, "primary": 10.0, "secondary": 8.0,
    "tertiary": 7.0, "residential": 6.0, "unclassified": 5.0, "service": 4.0,
    "pedestrian": 5.0, "footway": 2.0, "cycleway": 2.5, "living_street": 5.0,
    "motorway_link": 8.0, "trunk_link": 8.0, "primary_link": 7.0, "secondary_link": 6.0,
}
DEFAULT_ROAD_WIDTH = 6.0
LEVEL_HEIGHT = 3.2
DEFAULT_BUILDING_HEIGHT = 10.0
MAX_TILE_TRIS = 120000
```

- [ ] **Step 4: Write `pipeline/geo.py`**

```python
import math
from pipeline import config

M_PER_DEG_LAT = 110574.0
M_PER_DEG_LON_EQUATOR = 111320.0

def latlon_to_xz(lat: float, lon: float) -> tuple[float, float]:
    """Project WGS84 to local meters. x = east, z = SOUTH (Godot: north = -Z)."""
    olat, olon = config.ORIGIN
    x = (lon - olon) * M_PER_DEG_LON_EQUATOR * math.cos(math.radians(olat))
    z = -(lat - olat) * M_PER_DEG_LAT
    return x, z
```

- [ ] **Step 5: Run tests, expect PASS**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_geo.py -q`
Expected: `3 passed`

- [ ] **Step 6: Commit**

```bash
git add pipeline/config.py pipeline/geo.py pipeline/tests/test_geo.py
git commit -m "Add local projection and pipeline config"
```

---

### Task 4: `osm_parse.py` — OSM XML → CityData

**Files:**
- Create: `pipeline/osm_parse.py`, `pipeline/tests/fixtures/mini.osm.xml`
- Test: `pipeline/tests/test_osm_parse.py`

**Interfaces:**
- Consumes: `latlon_to_xz` from Task 3.
- Produces (dataclasses in `osm_parse.py`):
  - `Road(osm_id: int, name: str | None, points: list[tuple[float, float]], width: float)`
  - `Building(osm_id: int, footprint: list[tuple[float, float]], height: float)`
  - `Area(osm_id: int, kind: str, outline: list[tuple[float, float]])`  # kind: "water" | "green"
  - `CityData(roads: list[Road], buildings: list[Building], areas: list[Area])`
  - `parse_osm(xml_path: str | Path) -> CityData` — lists sorted by `osm_id`.

- [ ] **Step 1: Write fixture `pipeline/tests/fixtures/mini.osm.xml`**

Small hand-made map near the origin: two crossing named streets, a building with `height`, a building with `building:levels`, a water pond. (Coordinates ≈ origin so x/z are small.)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6" generator="fixture">
  <node id="1" lat="45.5040" lon="-73.5560"/>
  <node id="2" lat="45.5040" lon="-73.5510"/>
  <node id="3" lat="45.5020" lon="-73.5535"/>
  <node id="4" lat="45.5060" lon="-73.5535"/>
  <node id="10" lat="45.5044" lon="-73.5545"/>
  <node id="11" lat="45.5044" lon="-73.5540"/>
  <node id="12" lat="45.5048" lon="-73.5540"/>
  <node id="13" lat="45.5048" lon="-73.5545"/>
  <node id="20" lat="45.5034" lon="-73.5545"/>
  <node id="21" lat="45.5034" lon="-73.5540"/>
  <node id="22" lat="45.5037" lon="-73.5540"/>
  <node id="23" lat="45.5037" lon="-73.5545"/>
  <node id="30" lat="45.5052" lon="-73.5525"/>
  <node id="31" lat="45.5052" lon="-73.5518"/>
  <node id="32" lat="45.5056" lon="-73.5518"/>
  <node id="33" lat="45.5056" lon="-73.5525"/>
  <way id="100">
    <nd ref="1"/><nd ref="2"/>
    <tag k="highway" v="primary"/><tag k="name" v="Rue Sainte-Catherine"/>
  </way>
  <way id="101">
    <nd ref="3"/><nd ref="4"/>
    <tag k="highway" v="residential"/><tag k="name" v="Rue de la Montagne"/>
  </way>
  <way id="102">
    <nd ref="10"/><nd ref="11"/><nd ref="12"/><nd ref="13"/><nd ref="10"/>
    <tag k="building" v="yes"/><tag k="height" v="44"/>
  </way>
  <way id="103">
    <nd ref="20"/><nd ref="21"/><nd ref="22"/><nd ref="23"/><nd ref="20"/>
    <tag k="building" v="apartments"/><tag k="building:levels" v="5"/>
  </way>
  <way id="104">
    <nd ref="30"/><nd ref="31"/><nd ref="32"/><nd ref="33"/><nd ref="30"/>
    <tag k="natural" v="water"/>
  </way>
</osm>
```

- [ ] **Step 2: Write failing test `pipeline/tests/test_osm_parse.py`**

```python
from pathlib import Path
from pipeline.osm_parse import parse_osm

FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"

def test_counts():
    city = parse_osm(FIX)
    assert len(city.roads) == 2
    assert len(city.buildings) == 2
    assert len(city.areas) == 1

def test_road_names_and_width():
    city = parse_osm(FIX)
    ste_cath = next(r for r in city.roads if r.name == "Rue Sainte-Catherine")
    assert ste_cath.width == 10.0  # primary
    assert len(ste_cath.points) == 2

def test_building_heights():
    city = parse_osm(FIX)
    hs = sorted(b.height for b in city.buildings)
    assert hs == [16.0, 44.0]  # 5 levels * 3.2, explicit 44

def test_footprint_is_closed_ring_dropped_dup():
    city = parse_osm(FIX)
    for b in city.buildings:
        assert len(b.footprint) == 4  # closing duplicate removed

def test_sorted_by_id():
    city = parse_osm(FIX)
    assert [r.osm_id for r in city.roads] == sorted(r.osm_id for r in city.roads)
```

- [ ] **Step 3: Run to verify it fails**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_osm_parse.py -q`
Expected: FAIL (ImportError).

- [ ] **Step 4: Write `pipeline/osm_parse.py`**

```python
from __future__ import annotations
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from pipeline import config
from pipeline.geo import latlon_to_xz

@dataclass
class Road:
    osm_id: int
    name: str | None
    points: list[tuple[float, float]]
    width: float

@dataclass
class Building:
    osm_id: int
    footprint: list[tuple[float, float]]
    height: float

@dataclass
class Area:
    osm_id: int
    kind: str  # "water" | "green"
    outline: list[tuple[float, float]]

@dataclass
class CityData:
    roads: list[Road] = field(default_factory=list)
    buildings: list[Building] = field(default_factory=list)
    areas: list[Area] = field(default_factory=list)

_NUM = re.compile(r"[-+]?\d*\.?\d+")

def _parse_meters(value: str) -> float | None:
    m = _NUM.search(value)
    return float(m.group()) if m else None

def _building_height(tags: dict[str, str]) -> float:
    if "height" in tags:
        h = _parse_meters(tags["height"])
        if h:
            return h
    if "building:levels" in tags:
        lv = _parse_meters(tags["building:levels"])
        if lv:
            return lv * config.LEVEL_HEIGHT
    return config.DEFAULT_BUILDING_HEIGHT

def _area_kind(tags: dict[str, str]) -> str | None:
    if tags.get("natural") == "water" or tags.get("waterway") == "riverbank":
        return "water"
    if tags.get("leisure") in ("park", "garden") or tags.get("landuse") in ("grass", "forest", "recreation_ground"):
        return "green"
    return None

def parse_osm(xml_path: str | Path) -> CityData:
    nodes: dict[int, tuple[float, float]] = {}
    city = CityData()
    for _, el in ET.iterparse(str(xml_path), events=("end",)):
        if el.tag == "node":
            nodes[int(el.get("id"))] = (float(el.get("lat")), float(el.get("lon")))
        elif el.tag == "way":
            wid = int(el.get("id"))
            tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
            refs = [int(nd.get("ref")) for nd in el.findall("nd")]
            pts = [latlon_to_xz(*nodes[r]) for r in refs if r in nodes]
            if len(pts) >= 2 and "highway" in tags:
                width = config.ROAD_WIDTHS.get(tags["highway"], config.DEFAULT_ROAD_WIDTH)
                city.roads.append(Road(wid, tags.get("name"), pts, width))
            elif len(pts) >= 4 and refs[0] == refs[-1]:
                ring = pts[:-1]
                if "building" in tags:
                    city.buildings.append(Building(wid, ring, _building_height(tags)))
                else:
                    kind = _area_kind(tags)
                    if kind:
                        city.areas.append(Area(wid, kind, ring))
            el.clear()
    city.roads.sort(key=lambda r: r.osm_id)
    city.buildings.sort(key=lambda b: b.osm_id)
    city.areas.sort(key=lambda a: a.osm_id)
    return city
```

- [ ] **Step 5: Run tests, expect PASS**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_osm_parse.py -q`
Expected: `5 passed`

- [ ] **Step 6: Commit**

```bash
git add pipeline/osm_parse.py pipeline/tests/fixtures/mini.osm.xml pipeline/tests/test_osm_parse.py
git commit -m "Parse OSM XML into roads, buildings, and areas"
```

---

### Task 5: `meshes.py` — geometry → trimesh meshes

**Files:**
- Create: `pipeline/meshes.py`
- Test: `pipeline/tests/test_meshes.py`

**Interfaces:**
- Consumes: `Road`, `Building`, `Area` from Task 4.
- Produces:
  - `building_mesh(b: Building) -> trimesh.Trimesh | None` — extruded footprint, base y=0, top y=height. Returns None for degenerate polygons.
  - `road_mesh(r: Road) -> trimesh.Trimesh | None` — flat ribbon at y=0.05, per-segment quads.
  - `area_mesh(a: Area) -> trimesh.Trimesh | None` — flat polygon at y=0.02.
  - All meshes use +Y up (trimesh Z-up is converted here — **meshes returned are already Y-up, Godot-ready**).

- [ ] **Step 1: Write failing test `pipeline/tests/test_meshes.py`**

```python
import numpy as np
from pipeline.osm_parse import Building, Road, Area
from pipeline.meshes import building_mesh, road_mesh, area_mesh

SQ = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)]

def test_building_mesh_bounds():
    m = building_mesh(Building(1, SQ, 30.0))
    assert m is not None and m.is_volume
    lo, hi = m.bounds
    assert abs(lo[1] - 0.0) < 1e-6 and abs(hi[1] - 30.0) < 1e-6  # Y is up
    assert abs(hi[0] - 10.0) < 1e-6 and abs(hi[2] - 10.0) < 1e-6

def test_degenerate_building_returns_none():
    assert building_mesh(Building(2, [(0, 0), (1, 0), (2, 0), (3, 0)], 10.0)) is None

def test_road_mesh_is_flat_ribbon():
    m = road_mesh(Road(3, "x", [(0.0, 0.0), (100.0, 0.0)], 8.0))
    lo, hi = m.bounds
    assert abs(hi[1] - lo[1]) < 1e-6            # flat
    assert abs((hi[2] - lo[2]) - 8.0) < 1e-6    # width across z
    assert len(m.faces) == 2                     # one quad = 2 tris

def test_area_mesh_flat():
    m = area_mesh(Area(4, "water", SQ))
    lo, hi = m.bounds
    assert abs(hi[1] - lo[1]) < 1e-6
```

- [ ] **Step 2: Run to verify it fails**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_meshes.py -q`
Expected: FAIL (ImportError).

- [ ] **Step 3: Write `pipeline/meshes.py`**

```python
from __future__ import annotations
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString
from trimesh.creation import extrude_polygon, triangulate_polygon
from pipeline.osm_parse import Building, Road, Area

# trimesh extrudes along +Z; rotate so extrusion axis becomes +Y (and XY plane -> XZ plane).
_ZUP_TO_YUP = np.array([
    [1, 0, 0, 0],
    [0, 0, 1, 0],
    [0, 1, 0, 0],
    [0, 0, 0, 1],
], dtype=float)

def _to_yup(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    mesh.apply_transform(_ZUP_TO_YUP)
    mesh.fix_normals()
    return mesh

def building_mesh(b: Building) -> trimesh.Trimesh | None:
    poly = Polygon(b.footprint)
    if not poly.is_valid:
        poly = poly.buffer(0)
    if poly.is_empty or poly.area < 1.0 or poly.geom_type != "Polygon":
        return None
    return _to_yup(extrude_polygon(poly, b.height))

def road_mesh(r: Road) -> trimesh.Trimesh | None:
    line = LineString(r.points)
    if line.length < 1.0:
        return None
    verts, faces = [], []
    for (x1, z1), (x2, z2) in zip(r.points[:-1], r.points[1:]):
        d = np.array([x2 - x1, z2 - z1])
        n = np.linalg.norm(d)
        if n < 1e-6:
            continue
        px, pz = -d[1] / n, d[0] / n  # left-hand perpendicular in xz
        hw = r.width / 2.0
        i = len(verts)
        verts += [
            [x1 + px * hw, 0.05, z1 + pz * hw], [x1 - px * hw, 0.05, z1 - pz * hw],
            [x2 + px * hw, 0.05, z2 + pz * hw], [x2 - px * hw, 0.05, z2 - pz * hw],
        ]
        faces += [[i, i + 2, i + 1], [i + 1, i + 2, i + 3]]
    if not faces:
        return None
    return trimesh.Trimesh(vertices=np.array(verts), faces=np.array(faces), process=False)

def area_mesh(a: Area) -> trimesh.Trimesh | None:
    poly = Polygon(a.outline)
    if not poly.is_valid:
        poly = poly.buffer(0)
    if poly.is_empty or poly.area < 1.0 or poly.geom_type != "Polygon":
        return None
    v2d, faces = triangulate_polygon(poly)
    verts = np.column_stack([v2d[:, 0], np.full(len(v2d), 0.02), v2d[:, 1]])
    return trimesh.Trimesh(vertices=verts, faces=faces, process=False)
```

- [ ] **Step 4: Run tests, expect PASS**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_meshes.py -q`
Expected: `4 passed`

- [ ] **Step 5: Commit**

```bash
git add pipeline/meshes.py pipeline/tests/test_meshes.py
git commit -m "Generate building, road, and area meshes"
```

---

### Task 6: `tiler.py` + `export.py` — tiles, GLB files, metadata

**Files:**
- Create: `pipeline/tiler.py`, `pipeline/export.py`
- Test: `pipeline/tests/test_export.py`

**Interfaces:**
- Consumes: `CityData` (Task 4), mesh functions (Task 5), `config.TILE_SIZE`, `config.MAX_TILE_TRIS`.
- Produces:
  - `tiler.assign_tile(x: float, z: float) -> tuple[int, int]` — floor-division by TILE_SIZE.
  - `tiler.build_tiles(city: CityData) -> dict[tuple[int, int], trimesh.Scene]` — scenes with geometry nodes named `buildings`, `roads`, `areas` (concatenated meshes per category; categories may be absent if empty). Mesh assignment key: first point of the feature.
  - `export.export_city(city: CityData, out_dir: str | Path) -> dict` — writes `tile_{tx}_{tz}.glb` for each tile + `city_metadata.json`; returns the metadata dict:
    ```json
    {
      "origin": {"lat": 45.504, "lon": -73.5535},
      "tile_size": 256.0,
      "tiles": [{"tx": 0, "tz": 0, "file": "tile_0_0.glb"}],
      "spawn": {"x": 0.0, "z": 0.0},
      "streets": [{"name": "Rue Sainte-Catherine", "points": [[x, z], [x, z]]}]
    }
    ```
    `streets` = named roads only, sorted by (name, first point). Tiles sorted by (tx, tz). JSON written with `sort_keys=True, indent=1` for byte-determinism.

- [ ] **Step 1: Write failing test `pipeline/tests/test_export.py`**

```python
import json
from pathlib import Path
from pipeline.osm_parse import parse_osm
from pipeline.tiler import assign_tile, build_tiles
from pipeline.export import export_city

FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"

def test_assign_tile():
    assert assign_tile(0.0, 0.0) == (0, 0)
    assert assign_tile(-0.1, 300.0) == (-1, 1)

def test_build_tiles_has_categories():
    city = parse_osm(FIX)
    tiles = build_tiles(city)
    assert len(tiles) >= 1
    names = {n for scene in tiles.values() for n in scene.geometry}
    assert "buildings" in names and "roads" in names

def test_export_writes_glb_and_metadata(tmp_path):
    city = parse_osm(FIX)
    meta = export_city(city, tmp_path)
    files = sorted(p.name for p in tmp_path.glob("*.glb"))
    assert files == sorted(t["file"] for t in meta["tiles"])
    assert (tmp_path / "city_metadata.json").exists()
    assert any(s["name"] == "Rue Sainte-Catherine" for s in meta["streets"])

def test_export_deterministic(tmp_path):
    city = parse_osm(FIX)
    export_city(city, tmp_path / "a")
    export_city(city, tmp_path / "b")
    ja = (tmp_path / "a" / "city_metadata.json").read_bytes()
    jb = (tmp_path / "b" / "city_metadata.json").read_bytes()
    assert ja == jb
```

- [ ] **Step 2: Run to verify it fails**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_export.py -q`
Expected: FAIL (ImportError).

- [ ] **Step 3: Write `pipeline/tiler.py`**

```python
from __future__ import annotations
import math
from collections import defaultdict
import trimesh
from pipeline import config
from pipeline.osm_parse import CityData
from pipeline.meshes import building_mesh, road_mesh, area_mesh

def assign_tile(x: float, z: float) -> tuple[int, int]:
    return (math.floor(x / config.TILE_SIZE), math.floor(z / config.TILE_SIZE))

def build_tiles(city: CityData) -> dict[tuple[int, int], trimesh.Scene]:
    buckets: dict[tuple[int, int], dict[str, list]] = defaultdict(lambda: defaultdict(list))
    for b in city.buildings:
        m = building_mesh(b)
        if m is not None:
            buckets[assign_tile(*b.footprint[0])]["buildings"].append(m)
    for r in city.roads:
        m = road_mesh(r)
        if m is not None:
            buckets[assign_tile(*r.points[0])]["roads"].append(m)
    for a in city.areas:
        m = area_mesh(a)
        if m is not None:
            buckets[assign_tile(*a.outline[0])]["areas"].append(m)
    tiles: dict[tuple[int, int], trimesh.Scene] = {}
    for key in sorted(buckets):
        scene = trimesh.Scene()
        total_tris = 0
        for cat in ("buildings", "roads", "areas"):
            if buckets[key][cat]:
                merged = trimesh.util.concatenate(buckets[key][cat])
                total_tris += len(merged.faces)
                scene.add_geometry(merged, geom_name=cat, node_name=cat)
        assert total_tris <= config.MAX_TILE_TRIS, f"tile {key}: {total_tris} tris over budget"
        tiles[key] = scene
    return tiles
```

- [ ] **Step 4: Write `pipeline/export.py`**

```python
from __future__ import annotations
import json
from pathlib import Path
from pipeline import config
from pipeline.osm_parse import CityData
from pipeline.tiler import build_tiles

def export_city(city: CityData, out_dir: str | Path) -> dict:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    tiles = build_tiles(city)
    tile_entries = []
    for (tx, tz), scene in sorted(tiles.items()):
        fname = f"tile_{tx}_{tz}.glb"
        scene.export(out / fname)
        tile_entries.append({"tx": tx, "tz": tz, "file": fname})
    streets = sorted(
        (
            {"name": r.name, "points": [[round(x, 2), round(z, 2)] for x, z in r.points]}
            for r in city.roads if r.name
        ),
        key=lambda s: (s["name"], s["points"][0]),
    )
    meta = {
        "origin": {"lat": config.ORIGIN[0], "lon": config.ORIGIN[1]},
        "tile_size": config.TILE_SIZE,
        "tiles": tile_entries,
        "spawn": {"x": 0.0, "z": 0.0},
        "streets": streets,
    }
    (out / "city_metadata.json").write_text(
        json.dumps(meta, sort_keys=True, indent=1), encoding="utf-8"
    )
    return meta
```

- [ ] **Step 5: Run tests, expect PASS**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_export.py -q`
Expected: `4 passed`

- [ ] **Step 6: Run full suite + commit**

Run: `.venv/Scripts/python -m pytest pipeline -q` → all pass.

```bash
git add pipeline/tiler.py pipeline/export.py pipeline/tests/test_export.py
git commit -m "Tile city geometry and export GLB tiles with metadata"
```

---

### Task 7: `download.py` + `build.py` — real Montreal data end-to-end

**Files:**
- Create: `pipeline/download.py`, `pipeline/build.py`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `download.fetch_osm(dest: str | Path) -> Path` — downloads bbox OSM XML from Overpass into `data/osm_downtown.osm.xml` unless it already exists (cache); returns the path.
  - CLI `python -m pipeline.build [--input PATH] [--out PATH]` — defaults: cached download → `game/world/`. Prints summary stats.
  - Real generated tiles + metadata committed under `game/world/`.

- [ ] **Step 1: Write `pipeline/download.py`**

```python
from __future__ import annotations
from pathlib import Path
import requests
from pipeline import config

OVERPASS_URL = "https://overpass-api.de/api/interpreter"

def _query() -> str:
    s, w, n, e = config.BBOX
    bbox = f"{s},{w},{n},{e}"
    return f"""
[out:xml][timeout:300];
(
  way["highway"]({bbox});
  way["building"]({bbox});
  way["natural"="water"]({bbox});
  way["waterway"="riverbank"]({bbox});
  way["leisure"~"park|garden"]({bbox});
  way["landuse"~"grass|forest|recreation_ground"]({bbox});
);
(._;>;);
out body;
"""

def fetch_osm(dest: str | Path = "data/osm_downtown.osm.xml") -> Path:
    dest = Path(dest)
    if dest.exists() and dest.stat().st_size > 1000:
        print(f"cached: {dest}")
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    print("downloading from Overpass (may take a couple of minutes)...")
    resp = requests.post(OVERPASS_URL, data={"data": _query()}, timeout=600)
    resp.raise_for_status()
    dest.write_bytes(resp.content)
    print(f"saved {len(resp.content) / 1e6:.1f} MB -> {dest}")
    return dest
```

- [ ] **Step 2: Write `pipeline/build.py`**

```python
from __future__ import annotations
import argparse
from pathlib import Path
from pipeline.download import fetch_osm
from pipeline.osm_parse import parse_osm
from pipeline.export import export_city

def main() -> None:
    ap = argparse.ArgumentParser(description="Build MTL Open Ile city tiles")
    ap.add_argument("--input", default=None, help="OSM XML path (default: cached download)")
    ap.add_argument("--out", default="game/world", help="output directory")
    args = ap.parse_args()
    xml = Path(args.input) if args.input else fetch_osm()
    city = parse_osm(xml)
    print(f"parsed: {len(city.roads)} roads, {len(city.buildings)} buildings, {len(city.areas)} areas")
    meta = export_city(city, args.out)
    print(f"exported {len(meta['tiles'])} tiles, {len(meta['streets'])} named streets -> {args.out}")

if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run pipeline on the fixture first (fast sanity)**

Run: `.venv/Scripts/python -m pipeline.build --input pipeline/tests/fixtures/mini.osm.xml --out data/tmp_fixture_out`
Expected: prints `parsed: 2 roads, 2 buildings, 1 areas`, exports ≥1 tile.

- [ ] **Step 4: Run pipeline on real Montreal**

Run: `.venv/Scripts/python -m pipeline.build`
Expected: download (~50–150 MB), then parse counts in the thousands (roughly: >2,000 roads, >5,000 buildings), tiles ≈ 15×15 grid ballpark. If a tile trips the 120k-tri assert, raise `MAX_TILE_TRIS` is NOT the fix — reduce with `building buffer(0) simplify(0.5)` in `building_mesh` (add `poly = poly.simplify(0.5)` after validity fix) and rerun.

- [ ] **Step 5: Sanity-check output size**

Run: `du -sh game/world && ls game/world | head -5`
Expected: total under ~150 MB (low-poly GLBs are small; if wildly larger, investigate before committing).

- [ ] **Step 6: Commit (pipeline code + generated world)**

```bash
git add pipeline/download.py pipeline/build.py game/world
git commit -m "Add Overpass download + CLI build; generate downtown Montreal tiles"
```

---

### Task 8: Godot — tile loader + fly camera

**Files:**
- Create: `game/scenes/main.tscn`, `game/scripts/fly_camera.gd`, `game/scripts/tile_loader.gd`, `game/tests/smoke_test.gd`

**Interfaces:**
- Consumes: `game/world/tile_*.glb` + `game/world/city_metadata.json` (Task 7 contract).
- Produces: runnable main scene; `TileLoader` node exposes `loaded_tile_count() -> int` (used by smoke test and later plans).

- [ ] **Step 1: Write `game/scripts/fly_camera.gd`**

```gdscript
extends Camera3D

const SPEED := 30.0
const FAST_MULT := 4.0
const MOUSE_SENS := 0.002

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * MOUSE_SENS)
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): dir -= transform.basis.z
	if Input.is_physical_key_pressed(KEY_S): dir += transform.basis.z
	if Input.is_physical_key_pressed(KEY_A): dir -= transform.basis.x
	if Input.is_physical_key_pressed(KEY_D): dir += transform.basis.x
	if Input.is_physical_key_pressed(KEY_E): dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): dir -= Vector3.UP
	var speed := SPEED * (FAST_MULT if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	position += dir.normalized() * speed * delta if dir != Vector3.ZERO else Vector3.ZERO
```

- [ ] **Step 2: Write `game/scripts/tile_loader.gd`**

```gdscript
extends Node3D
class_name TileLoader

@export var view_distance := 800.0
var _tiles: Array[Dictionary] = []   # {node: Node3D, center: Vector3}
var _tile_size := 256.0
var _camera: Camera3D

func _ready() -> void:
	var meta_file := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	assert(meta_file != null, "city_metadata.json missing — run the pipeline first")
	var meta: Dictionary = JSON.parse_string(meta_file.get_as_text())
	_tile_size = meta["tile_size"]
	for t in meta["tiles"]:
		var path := "res://world/%s" % t["file"]
		var scene := load(path) as PackedScene
		if scene == null:
			push_warning("missing tile scene: " + path)
			continue
		var node := scene.instantiate() as Node3D
		add_child(node)
		var cx := (float(t["tx"]) + 0.5) * _tile_size
		var cz := (float(t["tz"]) + 0.5) * _tile_size
		_tiles.append({"node": node, "center": Vector3(cx, 0.0, cz)})

func _process(_delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return
	var cam_pos := _camera.global_position
	for t in _tiles:
		var visible_now: bool = t["center"].distance_to(cam_pos) < view_distance + _tile_size
		(t["node"] as Node3D).visible = visible_now

func loaded_tile_count() -> int:
	return _tiles.size()
```

- [ ] **Step 3: Write `game/scenes/main.tscn`**

```ini
[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/fly_camera.gd" id="1"]
[ext_resource type="Script" path="res://scripts/tile_loader.gd" id="2"]

[sub_resource type="Environment" id="env1"]
background_mode = 1
background_color = Color(0.75, 0.82, 0.9, 1)
ambient_light_source = 2
ambient_light_color = Color(0.8, 0.8, 0.85, 1)
ambient_light_energy = 0.6

[node name="Main" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("env1")

[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866, -0.353, 0.353, 0, 0.707, 0.707, -0.5, -0.612, 0.612, 0, 0, 0)
shadow_enabled = true

[node name="TileLoader" type="Node3D" parent="."]
script = ExtResource("2")

[node name="Camera" type="Camera3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 150, 200)
far = 4000.0
script = ExtResource("1")
```

- [ ] **Step 4: Write `game/tests/smoke_test.gd`**

```gdscript
extends SceneTree
# Headless smoke test: main scene loads, tiles instantiate.
# Run: tools/godot/godot.exe --headless --path game --script res://tests/smoke_test.gd

func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	if scene == null:
		push_error("FAIL: main.tscn did not load")
		quit(1)
		return
	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame
	await process_frame
	var loader := root.get_node("TileLoader") as TileLoader
	if loader == null or loader.loaded_tile_count() == 0:
		push_error("FAIL: no tiles loaded")
		quit(1)
		return
	print("SMOKE OK: %d tiles" % loader.loaded_tile_count())
	quit(0)
```

- [ ] **Step 5: Import assets then run smoke test**

```bash
tools/godot/godot.exe --headless --path game --import
tools/godot/godot.exe --headless --path game --script res://tests/smoke_test.gd
```
Expected: last line `SMOKE OK: <N> tiles` with N > 100, exit code 0.
(If GLB import fails, check the trimesh export named the geometries — Godot needs valid glTF; run `tools/godot/godot.exe --headless --path game --import 2>&1 | grep -i error`.)

- [ ] **Step 6: Commit**

```bash
git add game/scenes game/scripts game/tests
git commit -m "Add fly camera, tile loader, and headless smoke test"
```

---

### Task 9: Visual verification + milestone tag

**Files:**
- Create: `game/tests/screenshot.gd`

**Interfaces:**
- Consumes: main scene (Task 8).
- Produces: `docs/screenshots/m2_*.png` committed; tag `m2-gray-city`.

- [ ] **Step 1: Write `game/tests/screenshot.gd`**

```gdscript
extends SceneTree
# Capture screenshots from fixed camera poses. NOT headless — needs a GPU.
# Run: tools/godot/godot.exe --path game --script res://tests/screenshot.gd

const POSES := [
	{"name": "overview", "pos": Vector3(0, 600, 400), "look": Vector3(0, 0, 0)},
	{"name": "street",   "pos": Vector3(50, 40, 100),  "look": Vector3(0, 10, -200)},
	{"name": "oldport",  "pos": Vector3(800, 120, 900), "look": Vector3(400, 0, 400)},
]

func _init() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var root := scene.instantiate()
	get_root().add_child(root)
	var cam := root.get_node("Camera") as Camera3D
	cam.set_script(null)  # disable fly controls
	await process_frame
	for pose in POSES:
		cam.position = pose["pos"]
		cam.look_at(pose["look"])
		for i in 5:
			await process_frame
		var img := get_root().get_viewport().get_texture().get_image()
		img.save_png("user://shot_%s.png" % pose["name"])
		print("saved shot_%s.png" % pose["name"])
	quit(0)
```

- [ ] **Step 2: Run it and collect PNGs**

```bash
tools/godot/godot.exe --path game --script res://tests/screenshot.gd
mkdir -p docs/screenshots
cp "$APPDATA/Godot/app_userdata/MTL Open Ile/shot_"*.png docs/screenshots/ 2>/dev/null || cp ~/AppData/Roaming/Godot/app_userdata/"MTL Open Ile"/shot_*.png docs/screenshots/
```
Expected: three PNGs. **Look at them** (Read tool): you should see a street grid and gray building blocks — recognizably downtown Montreal from the overview pose. If images are empty/black, increase warm-up frames to 15 and rerun.

- [ ] **Step 3: Rename per milestone + commit + tag**

```bash
cd docs/screenshots && for f in shot_*.png; do mv "$f" "m2_${f#shot_}"; done && cd ../..
git add docs/screenshots && git commit -m "Add gray-city milestone screenshots"
git tag m2-gray-city
```

- [ ] **Step 4: Full verification sweep**

```bash
.venv/Scripts/python -m pytest pipeline -q
tools/godot/godot.exe --headless --path game --script res://tests/smoke_test.gd
git log --oneline | head -20 && git log --format='%an %ae' | sort -u
```
Expected: all tests pass; smoke OK; every commit authored solely by Aymanbalaa (no other author lines).

---

## Self-Review Notes

- **Spec coverage (this plan = milestones 1–2 only):** repo scaffold ✔ (T1), Godot boots ✔ (T2), pipeline skeleton→real run ✔ (T3–T7), gray city renders with fly cam ✔ (T8), visual check ✔ (T9). Deliberately deferred to later plans (per spec milestones): character, vehicles, HUD, palette/landmarks/terrain/minimap/day-night, audio/credits. Multipolygon water (St. Lawrence) is a known gap — noted for Milestone 5 plan.
- **Type consistency check:** `latlon_to_xz` (T3) used by T4; `Road/Building/Area/CityData` (T4) used by T5/T6; `assign_tile/build_tiles` (T6 tiler) used by `export_city` (T6); metadata schema (T6) consumed by `tile_loader.gd` (T8) — field names `tile_size`, `tiles[].tx/tz/file` match. `loaded_tile_count()` used by smoke test (T8).
- **Placeholder scan:** none — every code step has complete content.
