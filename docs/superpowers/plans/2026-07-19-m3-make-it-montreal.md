# MTL: Open Île — Plan 2: Make it Montreal (Milestone 3, visual pass)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the gray city into a recognizable stylized Montreal: palette by building type and road class, the St. Lawrence river (multipolygon relations), Mont Royal terrain (HRDEM with synthetic fallback), five procedural hero landmarks, a day/night cycle, and a minimap.

**Architecture:** All color/geometry work happens in `pipeline/` (vertex colors baked into the GLB tiles; Godot applies one shared vertex-color material via `material_override`). Terrain is a per-tile grid mesh sampled from a cached heightmap; buildings/roads/areas are displaced onto it. Landmarks are procedural trimesh models exported as separate GLBs and placed at true coordinates. Day/night and minimap are small game-side scripts.

**Tech Stack:** Python 3.13 (shapely, trimesh, numpy, requests, pytest; new: pillow, rasterio-lazy), Godot 4.5-stable.

**Design decision (recorded):** Hero landmarks are *modeled low-poly from reference* (the spec's allowed alternative to Sketchfab models). Sketchfab downloads need browser auth + per-model license review, which can't be automated safely; procedural models are deterministic, license-clean, and match the low-poly art style.

## Global Constraints

- Commits: small and frequent; author must be `Aymanbalaa` ONLY (repo-local git config already set) — **never add `Co-Authored-By`, `Claude-Session`, or any AI trailer to any commit.**
- Repo root: `C:\Users\ayman\OneDrive\Documents\SideProjects\MontrealOpenWorld`. All commands run from repo root; bash syntax.
- Python: `.venv/Scripts/python`; tests: `.venv/Scripts/python -m pytest pipeline -q` must be green at the end of every task.
- Godot binary: `tools/godot/godot.exe` (4.5-stable). Headless smoke: `tools/godot/godot.exe --headless --path game --script res://tests/smoke_test.gd` → expect `SMOKE OK: <N> tiles`. After regenerating `game/world/`, run `tools/godot/godot.exe --headless --path game --import` first (takes minutes).
- Coordinates: x = meters east, z = meters **south** of origin (lat 45.504, lon −73.5535). Y up. Bbox (s, w, n, e): `45.488, -73.582, 45.520, -73.525`. Tile size 256 m; ≤120,000 tris per tile.
- Determinism: same inputs ⇒ byte-identical `city_metadata.json`. Never call `random`/time in the pipeline; derive jitter from OSM ids.
- Colors are authored as sRGB 0–255 tuples in `config.py`; Godot material sets `vertex_color_is_srgb = true`.
- Overpass instances are flaky; the cached download at `data/osm_downtown.osm.xml` is only deleted ONCE (Task 10) because the query changes. Don't re-trigger otherwise.

## File Structure

```
pipeline/
├── config.py         # + palettes, terrain params, landmark anchors
├── download.py       # + relation queries, <?xml sanity check, retry fix
├── osm_parse.py      # + road_class/btype fields, multipolygon relation assembly
├── meshes.py         # + vertex colors, terrain-aware displacement, terrain tile mesh
├── tiler.py          # + per-tile area clipping, terrain grid, budget raise (not assert)
├── terrain.py        # NEW: Heightmap (sample/save/load), HRDEM fetch, synthetic fallback
├── landmarks.py      # NEW: 5 procedural landmark builders + export
├── minimap.py        # NEW: PNG map render (pillow)
├── export.py         # + hm param, landmark exclusion+export, minimap, metadata blocks
├── build.py          # + fetch_heightmap step
└── tests/
    ├── fixtures/river.osm.xml   # NEW: multipolygon fixture
    ├── test_osm_parse.py        # + relation/ring tests
    ├── test_meshes.py           # + color/displacement/terrain tests
    ├── test_terrain.py          # NEW
    ├── test_landmarks.py        # NEW
    ├── test_minimap.py          # NEW
    └── test_export.py           # + budget-raise, landmark, minimap tests
game/
├── scenes/main.tscn             # + day/night wiring, fog, minimap UI, ground lowered
├── scripts/tile_loader.gd       # + vertex-color material override, landmark loading
├── scripts/day_night.gd         # NEW
├── scripts/minimap.gd           # NEW
└── tests/screenshot.gd          # + mountain & biosphere poses
```

---

### Task 1: Carry OSM classes into the data model

**Files:**
- Modify: `pipeline/osm_parse.py`
- Test: `pipeline/tests/test_osm_parse.py`

**Interfaces:**
- Produces: `Road.road_class: str` (raw `highway` value, default `"residential"`), `Building.btype: str` (raw `building` value, default `"yes"`). Defaults keep all existing constructor calls valid.

- [ ] **Step 1: Add failing tests** — append to `pipeline/tests/test_osm_parse.py`:

```python
def test_road_class_and_btype_carried():
    city = parse_osm(FIX)
    ste_cath = next(r for r in city.roads if r.name == "Rue Sainte-Catherine")
    assert ste_cath.road_class == "primary"
    assert sorted(b.btype for b in city.buildings) == ["apartments", "yes"]
```

- [ ] **Step 2: Run** `.venv/Scripts/python -m pytest pipeline/tests/test_osm_parse.py -q` — expect FAIL (`AttributeError: road_class`).

- [ ] **Step 3: Implement** — in `pipeline/osm_parse.py`, add fields with defaults:

```python
@dataclass
class Road:
    osm_id: int
    name: str | None
    points: list[tuple[float, float]]
    width: float
    road_class: str = "residential"

@dataclass
class Building:
    osm_id: int
    footprint: list[tuple[float, float]]
    height: float
    btype: str = "yes"
```

and in `parse_osm` pass them through:

```python
city.roads.append(Road(wid, tags.get("name"), pts, width, tags["highway"]))
...
city.buildings.append(Building(wid, ring, _building_height(tags), tags.get("building", "yes")))
```

- [ ] **Step 4: Run** `.venv/Scripts/python -m pytest pipeline -q` — expect all green.
- [ ] **Step 5: Commit** `git add pipeline && git commit -m "pipeline: carry highway class and building type into data model"`

---

### Task 2: Palette + vertex colors on all meshes

**Files:**
- Modify: `pipeline/config.py`, `pipeline/meshes.py`
- Test: `pipeline/tests/test_meshes.py`

**Interfaces:**
- Produces: `config.BUILDING_PALETTE/BUILDING_CATEGORIES/ROAD_COLORS/DEFAULT_ROAD_COLOR/AREA_COLORS`; `meshes._paint(mesh, rgb, factor=1.0) -> Trimesh` (sets `visual.vertex_colors`, returns mesh); `meshes.building_color(b) -> tuple`; every mesh returned by `building_mesh`/`road_mesh`/`area_mesh` has per-vertex RGBA. Later tasks (5, 7, 8) reuse `_paint`.

- [ ] **Step 1: Add failing tests** — append to `pipeline/tests/test_meshes.py`:

```python
def test_building_vertex_colors_by_type_with_jitter():
    a = building_mesh(Building(1, SQ, 30.0, "apartments"))
    b = building_mesh(Building(2, SQ, 30.0, "apartments"))
    office = building_mesh(Building(3, SQ, 30.0, "office"))
    assert a.visual.vertex_colors.shape == (len(a.vertices), 4)
    assert not np.array_equal(a.visual.vertex_colors[0], b.visual.vertex_colors[0])  # id jitter
    assert not np.array_equal(a.visual.vertex_colors[0], office.visual.vertex_colors[0])

def test_road_and_area_colors():
    from pipeline import config
    r = road_mesh(Road(4, "x", [(0.0, 0.0), (10.0, 0.0)], 8.0, "footway"))
    assert tuple(r.visual.vertex_colors[0][:3]) == config.ROAD_COLORS["footway"]
    w = area_mesh(Area(5, "water", SQ))
    assert tuple(w.visual.vertex_colors[0][:3]) == config.AREA_COLORS["water"]
```

- [ ] **Step 2: Run** — expect FAIL (no `visual.vertex_colors` set / wrong colors).

- [ ] **Step 3: Implement** — append to `pipeline/config.py`:

```python
# --- M3 visual pass: stylized Montreal palette (sRGB 0-255) ---
BUILDING_PALETTE = {
    "residential": (166, 100, 80),   # Montreal brick
    "commercial":  (141, 148, 158),  # downtown glass/steel
    "church":      (105, 100, 96),   # greystone
    "industrial":  (122, 105, 88),
    "civic":       (176, 164, 140),  # sandstone
    "default":     (168, 168, 164),
}
BUILDING_CATEGORIES = {
    "apartments": "residential", "residential": "residential", "house": "residential",
    "detached": "residential", "terrace": "residential", "dormitory": "residential",
    "retail": "commercial", "commercial": "commercial", "office": "commercial", "hotel": "commercial",
    "church": "church", "cathedral": "church", "chapel": "church", "monastery": "church",
    "industrial": "industrial", "warehouse": "industrial",
    "university": "civic", "school": "civic", "college": "civic", "hospital": "civic",
    "public": "civic", "civic": "civic", "government": "civic", "museum": "civic",
}
ROAD_COLORS = {
    "motorway": (52, 52, 56), "trunk": (52, 52, 56),
    "motorway_link": (52, 52, 56), "trunk_link": (52, 52, 56),
    "primary": (64, 64, 68), "secondary": (64, 64, 68),
    "primary_link": (64, 64, 68), "secondary_link": (64, 64, 68),
    "pedestrian": (150, 140, 124), "footway": (150, 140, 124), "cycleway": (96, 116, 96),
}
DEFAULT_ROAD_COLOR = (78, 78, 82)
AREA_COLORS = {"water": (62, 110, 138), "green": (88, 132, 76)}
```

In `pipeline/meshes.py` add (near top, after imports):

```python
from pipeline import config

def _jitter(osm_id: int) -> float:
    """Deterministic per-id shade factor in [0.88, 1.08]."""
    return 0.88 + 0.2 * ((osm_id * 2654435761) % 1000) / 1000.0

def _paint(mesh: trimesh.Trimesh, rgb: tuple, factor: float = 1.0) -> trimesh.Trimesh:
    c = np.clip(np.array(rgb, dtype=float) * factor, 0, 255).astype(np.uint8)
    mesh.visual.vertex_colors = np.tile(
        np.array([c[0], c[1], c[2], 255], dtype=np.uint8), (len(mesh.vertices), 1)
    )
    return mesh

def building_color(b: Building) -> tuple:
    cat = config.BUILDING_CATEGORIES.get(b.btype, "default")
    return config.BUILDING_PALETTE[cat]
```

Change the three mesh functions' returns:

```python
# building_mesh:
    return _paint(_to_yup(extrude_polygon(poly, b.height)), building_color(b), _jitter(b.osm_id))
# road_mesh:
    mesh = trimesh.Trimesh(vertices=np.array(verts), faces=np.array(faces), process=False)
    return _paint(mesh, config.ROAD_COLORS.get(r.road_class, config.DEFAULT_ROAD_COLOR))
# area_mesh:
    mesh = trimesh.Trimesh(vertices=verts, faces=faces, process=False)
    return _paint(mesh, config.AREA_COLORS[a.kind])
```

- [ ] **Step 4: Run** `.venv/Scripts/python -m pytest pipeline -q` — all green.
- [ ] **Step 5: Commit** `git commit -am "pipeline: bake stylized palette as vertex colors"`

---

### Task 3: Game applies vertex-color material to tiles

**Files:**
- Modify: `game/scripts/tile_loader.gd`

**Interfaces:**
- Produces: `TileLoader._city_mat: StandardMaterial3D` and `TileLoader._apply_city_material(node: Node) -> void` — Task 8 reuses it for landmarks.

- [ ] **Step 1: Implement** — in `game/scripts/tile_loader.gd`, add after `var _camera: Camera3D`:

```gdscript
var _city_mat := _make_city_material()

static func _make_city_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	return m

func _apply_city_material(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _city_mat
```

and in `_ready`, right after `add_child(node)`:

```gdscript
		_apply_city_material(node)
```

- [ ] **Step 2: Run smoke** `tools/godot/godot.exe --headless --path game --script res://tests/smoke_test.gd` — expect `SMOKE OK: 255 tiles`.
- [ ] **Step 3: Commit** `git commit -am "game: shared vertex-color material override for tiles"`

---

### Task 4: Multipolygon water/parks — download + parse

**Files:**
- Modify: `pipeline/download.py`, `pipeline/osm_parse.py`
- Create: `pipeline/tests/fixtures/river.osm.xml`
- Test: `pipeline/tests/test_osm_parse.py`

**Interfaces:**
- Produces: `Area.holes: list[list[tuple[float, float]]]` (default `[]`); `osm_parse._assemble_rings(ways: list[list[int]]) -> list[list[int]]` (closed rings, closing dup removed); relations of `type=multipolygon` with water/green tags become `Area` entries clipped to the padded bbox. `config.BBOX_PAD_M = 100.0`.
- This task also lands two carry-forward fixes in `download.py` (XML sanity check; no sleep after final attempt).

- [ ] **Step 1: Write fixture** `pipeline/tests/fixtures/river.osm.xml` — a water multipolygon whose outer ring is split across two ways (second reversed) with one island hole; plus one giant outer way reaching far outside the bbox to prove clipping:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<osm version="0.6" generator="fixture">
  <node id="1" lat="45.5000" lon="-73.5560"/>
  <node id="2" lat="45.5000" lon="-73.5510"/>
  <node id="3" lat="45.5020" lon="-73.5510"/>
  <node id="4" lat="45.5020" lon="-73.5560"/>
  <node id="10" lat="45.5008" lon="-73.5540"/>
  <node id="11" lat="45.5008" lon="-73.5532"/>
  <node id="12" lat="45.5013" lon="-73.5532"/>
  <node id="13" lat="45.5013" lon="-73.5540"/>
  <node id="20" lat="45.4000" lon="-73.9000"/>
  <node id="21" lat="45.4000" lon="-73.5300"/>
  <node id="22" lat="45.4950" lon="-73.5300"/>
  <node id="23" lat="45.4950" lon="-73.9000"/>
  <way id="200"><nd ref="1"/><nd ref="2"/><nd ref="3"/></way>
  <way id="201"><nd ref="1"/><nd ref="4"/><nd ref="3"/></way>
  <way id="202"><nd ref="10"/><nd ref="11"/><nd ref="12"/><nd ref="13"/><nd ref="10"/></way>
  <way id="203"><nd ref="20"/><nd ref="21"/><nd ref="22"/><nd ref="23"/><nd ref="20"/></way>
  <relation id="900">
    <member type="way" role="outer" ref="200"/>
    <member type="way" role="outer" ref="201"/>
    <member type="way" role="inner" ref="202"/>
    <tag k="type" v="multipolygon"/>
    <tag k="natural" v="water"/>
  </relation>
  <relation id="901">
    <member type="way" role="outer" ref="203"/>
    <tag k="type" v="multipolygon"/>
    <tag k="natural" v="water"/>
  </relation>
</osm>
```

- [ ] **Step 2: Add failing tests** — append to `pipeline/tests/test_osm_parse.py`:

```python
from pipeline.osm_parse import _assemble_rings

RIVER = Path(__file__).parent / "fixtures" / "river.osm.xml"

def test_assemble_rings_stitches_and_reverses():
    rings = _assemble_rings([[1, 2, 3], [1, 4, 3]])   # second must be reversed to close
    assert len(rings) == 1 and sorted(rings[0]) == [1, 2, 3, 4]

def test_assemble_rings_drops_unclosed():
    assert _assemble_rings([[1, 2, 3], [5, 6]]) == []

def test_multipolygon_water_with_hole():
    city = parse_osm(RIVER)
    lake = next(a for a in city.areas if a.holes)
    assert lake.kind == "water" and len(lake.holes) == 1
    assert len(lake.holes[0]) >= 3

def test_relation_clipped_to_bbox():
    from pipeline import config
    city = parse_osm(RIVER)
    pad = config.BBOX_PAD_M + 1.0
    from pipeline.geo import latlon_to_xz
    s, w, n, e = config.BBOX
    x_min, z_min = latlon_to_xz(n, w)
    x_max, z_max = latlon_to_xz(s, e)
    for a in city.areas:
        for x, z in a.outline:
            assert x_min - pad <= x <= x_max + pad and z_min - pad <= z <= z_max + pad
```

- [ ] **Step 3: Run** — expect FAIL (`ImportError: _assemble_rings`).

- [ ] **Step 4: Implement parse** — in `pipeline/config.py` add `BBOX_PAD_M = 100.0`. In `pipeline/osm_parse.py`:

Add to `Area`:

```python
@dataclass
class Area:
    osm_id: int
    kind: str  # "water" | "green"
    outline: list[tuple[float, float]]
    holes: list[list[tuple[float, float]]] = field(default_factory=list)
```

Add imports and helpers:

```python
from shapely.geometry import Polygon, box
from shapely.ops import unary_union

def _assemble_rings(ways: list[list[int]]) -> list[list[int]]:
    """Stitch open way ref-lists into closed rings (closing dup removed).
    Unclosable leftovers are dropped with a warning (carry-forward guard)."""
    segs = sorted((list(w) for w in ways if len(w) >= 2), key=lambda s: s[0])
    rings: list[list[int]] = []
    while segs:
        ring = segs.pop(0)
        progress = True
        while ring[0] != ring[-1] and progress:
            progress = False
            for i, s in enumerate(segs):
                if s[0] == ring[-1]:
                    ring += s[1:]; segs.pop(i); progress = True; break
                if s[-1] == ring[-1]:
                    ring += s[-2::-1]; segs.pop(i); progress = True; break
        if ring[0] == ring[-1] and len(ring) >= 4:
            rings.append(ring[:-1])
        else:
            print(f"warning: dropped unclosed multipolygon ring ({len(ring)} refs)")
    return rings

def _clip_box() -> "box":
    s, w, n, e = config.BBOX
    x1, z1 = latlon_to_xz(n, w)
    x2, z2 = latlon_to_xz(s, e)
    p = config.BBOX_PAD_M
    return box(x1 - p, z1 - p, x2 + p, z2 + p)

def _add_relation_areas(city: CityData, rel_id: int, kind: str,
                        outer_ways: list[list[int]], inner_ways: list[list[int]],
                        nodes: dict[int, tuple[float, float]]) -> None:
    def to_xz(ring: list[int]) -> list[tuple[float, float]]:
        pts = [latlon_to_xz(*nodes[r]) for r in ring if r in nodes]
        if len(pts) < len(ring):
            print(f"warning: ring in relation {rel_id} missing {len(ring) - len(pts)} nodes")
        return pts
    outers = [p for p in (to_xz(r) for r in _assemble_rings(outer_ways)) if len(p) >= 3]
    inners = [p for p in (to_xz(r) for r in _assemble_rings(inner_ways)) if len(p) >= 3]
    if not outers:
        return
    geom = unary_union([Polygon(o).buffer(0) for o in outers])
    if inners:
        geom = geom.difference(unary_union([Polygon(i).buffer(0) for i in inners]))
    geom = geom.intersection(_clip_box())
    polys = [g for g in getattr(geom, "geoms", [geom])
             if g.geom_type == "Polygon" and g.area >= 1.0]
    for i, g in enumerate(sorted(polys, key=lambda g: (-g.area, g.bounds))):
        city.areas.append(Area(
            rel_id * 1000 + i, kind,
            [(x, z) for x, z in g.exterior.coords[:-1]],
            [[(x, z) for x, z in h.coords[:-1]] for h in g.interiors],
        ))
```

In `parse_osm`: keep a refs map for ALL ways and handle relations. Replace the way branch's opening with:

```python
        elif el.tag == "way":
            wid = int(el.get("id"))
            tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
            refs = [int(nd.get("ref")) for nd in el.findall("nd")]
            way_refs[wid] = refs
            ...
```

(add `way_refs: dict[int, list[int]] = {}` next to `nodes`), and add a relation branch before the `el.clear()` logic:

```python
        elif el.tag == "relation":
            tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
            if tags.get("type") == "multipolygon":
                kind = _area_kind(tags)
                if kind:
                    outer_w: list[list[int]] = []
                    inner_w: list[list[int]] = []
                    for m in el.findall("member"):
                        if m.get("type") != "way":
                            continue
                        refs = way_refs.get(int(m.get("ref")))
                        if refs:
                            (inner_w if m.get("role") == "inner" else outer_w).append(refs)
                    _add_relation_areas(city, int(el.get("id")), kind, outer_w, inner_w, nodes)
        if el.tag in ("node", "way", "relation"):
            el.clear()
```

(Relations appear after ways in Overpass `out body` output, so `way_refs` is complete by then.)

- [ ] **Step 5: Implement download fixes** — in `pipeline/download.py`, add relation lines to `_query()` after the way lines:

```
  relation["natural"="water"]({bbox});
  relation["waterway"="riverbank"]({bbox});
  relation["leisure"~"park|garden"]({bbox});
  relation["landuse"~"grass|forest|recreation_ground"]({bbox});
```

and replace the retry body so a non-XML 200 is rejected and there is no sleep after the final attempt:

```python
    for attempt in range(6):
        url = OVERPASS_URLS[attempt % len(OVERPASS_URLS)]
        print(f"downloading from {url} (attempt {attempt + 1}, may take a couple of minutes)...")
        try:
            resp = requests.post(url, data={"data": _query()}, headers=HEADERS, timeout=600)
            resp.raise_for_status()
            if not resp.content.lstrip().startswith(b"<?xml"):
                raise RuntimeError(f"non-XML response: {resp.content[:80]!r}")
        except (requests.RequestException, RuntimeError) as exc:
            print(f"  failed: {exc}")
            last_error = exc
            if attempt < 5:
                time.sleep(10 * (attempt + 1))
            continue
        dest.write_bytes(resp.content)
        print(f"saved {len(resp.content) / 1e6:.1f} MB -> {dest}")
        return dest
    raise RuntimeError(f"all Overpass endpoints failed after 6 attempts: {last_error}")
```

**Do NOT delete the cached XML in this task** — the fresh download happens once in Task 10.

- [ ] **Step 6: Run** `.venv/Scripts/python -m pytest pipeline -q` — all green.
- [ ] **Step 7: Commit** `git commit -am "pipeline: multipolygon water/park relations, download hardening" && git add pipeline/tests/fixtures/river.osm.xml && git commit --amend --no-edit`

---

### Task 5: Area meshes with holes + per-tile clipping + budget raise

**Files:**
- Modify: `pipeline/meshes.py`, `pipeline/tiler.py`
- Test: `pipeline/tests/test_meshes.py`, `pipeline/tests/test_export.py`

**Interfaces:**
- Produces: `meshes.area_piece_mesh(geom, kind: str, y: float = 0.02) -> Trimesh | None` — triangulates a shapely Polygon/MultiPolygon (interiors honored) flat at `y`, painted `AREA_COLORS[kind]`. `area_mesh(a)` delegates to it. `build_tiles` clips each area polygon per overlapping tile; over-budget tiles now `raise ValueError`.

- [ ] **Step 1: Add failing tests**:

Append to `pipeline/tests/test_meshes.py`:

```python
def test_area_mesh_with_hole_has_fewer_area():
    from shapely.geometry import Polygon
    full = area_mesh(Area(6, "water", SQ))
    hole = [(4.0, 4.0), (6.0, 4.0), (6.0, 6.0), (4.0, 6.0)]
    holed = area_mesh(Area(7, "water", SQ, [hole]))
    assert holed is not None and holed.area < full.area
```

Append to `pipeline/tests/test_export.py`:

```python
import pytest
from pipeline import config
from pipeline.osm_parse import Area

def test_big_area_clipped_across_tiles():
    big = Area(1, "water", [(-10.0, -10.0), (500.0, -10.0), (500.0, 500.0), (-10.0, 500.0)])
    from pipeline.osm_parse import CityData
    tiles = build_tiles(CityData(areas=[big]))
    assert len(tiles) >= 4  # spans tiles (-1..1, -1..1)
    for scene in tiles.values():
        assert "areas" in scene.geometry

def test_tile_budget_raises(monkeypatch):
    monkeypatch.setattr(config, "MAX_TILE_TRIS", 1)
    city = parse_osm(FIX)
    with pytest.raises(ValueError, match="over budget"):
        build_tiles(city)
```

- [ ] **Step 2: Run** — expect FAIL (holes ignored → equal area; big area lands in 1 tile; budget uses `assert`).

- [ ] **Step 3: Implement** — in `pipeline/meshes.py` replace `area_mesh` with:

```python
def area_piece_mesh(geom, kind: str, y: float = 0.02) -> trimesh.Trimesh | None:
    polys = [g for g in getattr(geom, "geoms", [geom])
             if g.geom_type == "Polygon" and not g.is_empty and g.area >= 1.0]
    parts = []
    for p in polys:
        v2d, faces = triangulate_polygon(p)
        verts = np.column_stack([v2d[:, 0], np.full(len(v2d), y), v2d[:, 1]])
        parts.append(trimesh.Trimesh(vertices=verts, faces=faces, process=False))
    if not parts:
        return None
    return _paint(trimesh.util.concatenate(parts), config.AREA_COLORS[kind])

def area_mesh(a: Area) -> trimesh.Trimesh | None:
    if len(a.outline) < 3:
        return None
    poly = Polygon(a.outline, a.holes)
    if not poly.is_valid:
        poly = poly.buffer(0)
    return area_piece_mesh(poly, a.kind)
```

In `pipeline/tiler.py` replace the areas loop and the budget assert:

```python
from shapely.geometry import Polygon, box as shp_box
from pipeline.meshes import building_mesh, road_mesh, area_piece_mesh

    for a in city.areas:
        if len(a.outline) < 3:
            continue
        poly = Polygon(a.outline, a.holes)
        if not poly.is_valid:
            poly = poly.buffer(0)
        if poly.is_empty:
            continue
        minx, minz, maxx, maxz = poly.bounds
        tx0, tz0 = assign_tile(minx, minz)
        tx1, tz1 = assign_tile(maxx, maxz)
        for tx in range(tx0, tx1 + 1):
            for tz in range(tz0, tz1 + 1):
                cell = shp_box(tx * config.TILE_SIZE, tz * config.TILE_SIZE,
                               (tx + 1) * config.TILE_SIZE, (tz + 1) * config.TILE_SIZE)
                m = area_piece_mesh(poly.intersection(cell), a.kind)
                if m is not None:
                    buckets[(tx, tz)]["areas"].append(m)
```

```python
        if total_tris > config.MAX_TILE_TRIS:
            raise ValueError(f"tile {key}: {total_tris} tris over budget")
```

(remove the `assert` line; `area_mesh` import from tiler is no longer needed).

- [ ] **Step 4: Run** `.venv/Scripts/python -m pytest pipeline -q` — all green.
- [ ] **Step 5: Commit** `git commit -am "pipeline: area holes, per-tile area clipping, budget raise instead of assert"`

---

### Task 6: Heightmap — HRDEM fetch with synthetic fallback

**Files:**
- Create: `pipeline/terrain.py`, `pipeline/tests/test_terrain.py`
- Modify: `requirements.txt`

**Interfaces:**
- Produces:
  - `terrain.Heightmap` — fields `grid: np.ndarray [nz, nx] float32` (meters, origin-relative), `x0, z0, step_x, step_z: float`; methods `sample(x, z) -> float` (bilinear, clamped at edges), `save(npy_path, meta_path, source)`, classmethod `load(npy_path, meta_path) -> Heightmap`.
  - `terrain.synthetic_heightmap() -> Heightmap` — Gaussian Mont Royal at the true summit + gentle SE tilt, origin-normalized.
  - `terrain.fetch_heightmap(dest_npy="data/heightmap.npy", dest_meta="data/heightmap_meta.json") -> Heightmap` — cached; tries HRDEM (STAC + rasterio, lazy import), falls back to synthetic on ANY failure.
  - `config.TERRAIN_STEP = 8.0`, `config.TERRAIN_TILE_QUADS = 32`, `config.TERRAIN_COLOR_LOW = (150, 146, 138)`, `config.TERRAIN_COLOR_HIGH = (96, 124, 82)`, `config.TERRAIN_COLOR_BLEND = (25.0, 90.0)`, `config.TERRAIN_WATER_DROP = 3.0`, `config.TERRAIN_WATER_COLOR = (52, 84, 104)`.

- [ ] **Step 1: Add config** — append to `pipeline/config.py`:

```python
# --- Terrain ---
TERRAIN_STEP = 8.0            # heightmap grid spacing (m)
TERRAIN_TILE_QUADS = 32       # terrain quads per tile edge (32 -> 2048 tris/tile)
TERRAIN_COLOR_LOW = (150, 146, 138)   # urban ground
TERRAIN_COLOR_HIGH = (96, 124, 82)    # wooded slopes
TERRAIN_COLOR_BLEND = (25.0, 90.0)    # y-range over which low blends to high
TERRAIN_WATER_DROP = 3.0      # terrain depression under water polygons (m)
TERRAIN_WATER_COLOR = (52, 84, 104)
MONT_ROYAL_SUMMIT = (45.5063, -73.5872)  # just west of bbox; east flank is in-map
```

- [ ] **Step 2: Write failing tests** — `pipeline/tests/test_terrain.py`:

```python
import numpy as np
from pipeline.terrain import Heightmap, synthetic_heightmap

def test_sample_bilinear_and_clamp():
    hm = Heightmap(grid=np.array([[0.0, 10.0], [20.0, 30.0]], dtype=np.float32),
                   x0=0.0, z0=0.0, step_x=10.0, step_z=10.0)
    assert hm.sample(0.0, 0.0) == 0.0
    assert hm.sample(10.0, 10.0) == 30.0
    assert abs(hm.sample(5.0, 0.0) - 5.0) < 1e-5
    assert abs(hm.sample(5.0, 5.0) - 15.0) < 1e-5
    assert hm.sample(-100.0, -100.0) == 0.0     # clamped
    assert hm.sample(1000.0, 1000.0) == 30.0    # clamped

def test_synthetic_mont_royal():
    from pipeline.geo import latlon_to_xz
    hm = synthetic_heightmap()
    assert abs(hm.sample(0.0, 0.0)) < 1.0          # downtown ~0
    sx, sz = latlon_to_xz(45.5063, -73.5872)
    assert hm.sample(sx, sz) > 100.0                # mountain flank high

def test_save_load_roundtrip(tmp_path):
    hm = synthetic_heightmap()
    hm.save(tmp_path / "h.npy", tmp_path / "h.json", source="synthetic")
    hm2 = Heightmap.load(tmp_path / "h.npy", tmp_path / "h.json")
    assert np.array_equal(hm.grid, hm2.grid)
    assert hm2.sample(100.0, 100.0) == hm.sample(100.0, 100.0)
```

- [ ] **Step 3: Run** — expect FAIL (no module `pipeline.terrain`).

- [ ] **Step 4: Implement** — `pipeline/terrain.py`:

```python
from __future__ import annotations
import json
import math
from dataclasses import dataclass
from pathlib import Path
import numpy as np
import requests
from pipeline import config
from pipeline.geo import latlon_to_xz

STAC_URLS = [
    "https://datacube.services.geo.ca/stac/api/search",
    "https://datacube.services.geo.ca/api/search",
]
STAC_COLLECTIONS = ["hrdem-mosaic-2m", "hrdem-mosaic-1m"]

@dataclass
class Heightmap:
    grid: np.ndarray  # [nz, nx] float32, meters relative to origin elevation
    x0: float
    z0: float
    step_x: float
    step_z: float

    def sample(self, x: float, z: float) -> float:
        nz, nx = self.grid.shape
        fx = min(max((x - self.x0) / self.step_x, 0.0), nx - 1 - 1e-9)
        fz = min(max((z - self.z0) / self.step_z, 0.0), nz - 1 - 1e-9)
        ix, iz = int(fx), int(fz)
        tx, tz = fx - ix, fz - iz
        g = self.grid
        return float(
            g[iz, ix] * (1 - tx) * (1 - tz) + g[iz, ix + 1] * tx * (1 - tz)
            + g[iz + 1, ix] * (1 - tx) * tz + g[iz + 1, ix + 1] * tx * tz
        )

    def save(self, npy_path: str | Path, meta_path: str | Path, source: str) -> None:
        np.save(str(npy_path), self.grid)
        Path(meta_path).write_text(json.dumps({
            "x0": self.x0, "z0": self.z0,
            "step_x": self.step_x, "step_z": self.step_z, "source": source,
        }, sort_keys=True), encoding="utf-8")

    @classmethod
    def load(cls, npy_path: str | Path, meta_path: str | Path) -> "Heightmap":
        meta = json.loads(Path(meta_path).read_text(encoding="utf-8"))
        return cls(np.load(str(npy_path)), meta["x0"], meta["z0"],
                   meta["step_x"], meta["step_z"])

def _grid_frame() -> tuple[float, float, float, float, int, int]:
    """Padded-bbox frame: (x0, z0, step_x, step_z, nx, nz). Row 0 = north edge."""
    s, w, n, e = config.BBOX
    pad_lat = config.BBOX_PAD_M / 110574.0
    pad_lon = config.BBOX_PAD_M / (111320.0 * math.cos(math.radians(config.ORIGIN[0])))
    x0, z0 = latlon_to_xz(n + pad_lat, w - pad_lon)
    x1, z1 = latlon_to_xz(s - pad_lat, e + pad_lon)
    nx = int((x1 - x0) / config.TERRAIN_STEP) + 1
    nz = int((z1 - z0) / config.TERRAIN_STEP) + 1
    return x0, z0, (x1 - x0) / (nx - 1), (z1 - z0) / (nz - 1), nx, nz

def synthetic_heightmap() -> Heightmap:
    x0, z0, sx_, sz_, nx, nz = _grid_frame()
    xs = x0 + np.arange(nx) * sx_
    zs = z0 + np.arange(nz) * sz_
    X, Z = np.meshgrid(xs, zs)
    mx, mz = latlon_to_xz(*config.MONT_ROYAL_SUMMIT)
    grid = 200.0 * np.exp(-((X - mx) ** 2 + (Z - mz) ** 2) / (2 * 700.0 ** 2))
    grid += -3.0 * (X + Z) / 2000.0  # gentle tilt down toward the river (SE)
    hm = Heightmap(grid.astype(np.float32), x0, z0, sx_, sz_)
    hm.grid -= hm.sample(0.0, 0.0)
    return hm

def _fetch_hrdem() -> Heightmap:
    import rasterio  # lazy: heavy optional dependency
    from rasterio.enums import Resampling
    from rasterio.vrt import WarpedVRT

    s, w, n, e = config.BBOX
    pad_lat = config.BBOX_PAD_M / 110574.0
    pad_lon = config.BBOX_PAD_M / (111320.0 * math.cos(math.radians(config.ORIGIN[0])))
    body = {"collections": None, "bbox": [w - pad_lon, s - pad_lat, e + pad_lon, n + pad_lat], "limit": 10}
    href = None
    last = None
    for url in STAC_URLS:
        for coll in STAC_COLLECTIONS:
            try:
                body["collections"] = [coll]
                feats = requests.post(url, json=body, timeout=60).json().get("features", [])
                for f in feats:
                    for key, asset in f.get("assets", {}).items():
                        if "dtm" in key.lower():
                            href = asset["href"]
                            break
                    if href:
                        break
            except Exception as exc:  # noqa: BLE001 - any failure -> next endpoint
                last = exc
            if href:
                break
        if href:
            break
    if not href:
        raise RuntimeError(f"no HRDEM DTM asset found via STAC ({last})")
    print(f"HRDEM: reading {href}")
    x0, z0, sx_, sz_, nx, nz = _grid_frame()
    with rasterio.open(href) as src, WarpedVRT(src, crs="EPSG:4326") as vrt:
        win = vrt.window(w - pad_lon, s - pad_lat, e + pad_lon, n + pad_lat)
        data = vrt.read(1, window=win, out_shape=(nz, nx),
                        resampling=Resampling.bilinear).astype(np.float32)
    valid = data > -1000.0
    if not valid.any():
        raise RuntimeError("HRDEM window contained no valid samples")
    data[~valid] = data[valid].min()
    hm = Heightmap(data, x0, z0, sx_, sz_)
    hm.grid -= hm.sample(0.0, 0.0)
    return hm

def fetch_heightmap(dest_npy: str | Path = "data/heightmap.npy",
                    dest_meta: str | Path = "data/heightmap_meta.json") -> Heightmap:
    dest_npy, dest_meta = Path(dest_npy), Path(dest_meta)
    if dest_npy.exists() and dest_meta.exists():
        print(f"cached heightmap: {dest_npy}")
        return Heightmap.load(dest_npy, dest_meta)
    dest_npy.parent.mkdir(parents=True, exist_ok=True)
    try:
        hm = _fetch_hrdem()
        source = "hrdem"
    except Exception as exc:  # noqa: BLE001 - fallback keeps the build running
        print(f"HRDEM unavailable ({exc}); using synthetic Mont Royal heightmap")
        hm = synthetic_heightmap()
        source = "synthetic"
    hm.save(dest_npy, dest_meta, source)
    print(f"heightmap saved ({source}): {hm.grid.shape}")
    return hm
```

- [ ] **Step 5: Add deps** — append to `requirements.txt`: `pillow>=10.0` and `rasterio>=1.4.2`, then `.venv/Scripts/pip install pillow "rasterio>=1.4.2"`. **If the rasterio wheel fails to install on this machine, remove the rasterio line again and continue** — `terrain.py` imports it lazily and the synthetic fallback covers the build.
- [ ] **Step 6: Run** `.venv/Scripts/python -m pytest pipeline -q` — all green (tests never touch the network).
- [ ] **Step 7: Commit** `git add pipeline requirements.txt && git commit -m "pipeline: heightmap module with HRDEM fetch and synthetic fallback"`

---

### Task 7: Terrain meshes + displacement onto terrain

**Files:**
- Modify: `pipeline/meshes.py`, `pipeline/tiler.py`, `pipeline/export.py`, `pipeline/build.py`, `game/scenes/main.tscn`
- Test: `pipeline/tests/test_meshes.py`, `pipeline/tests/test_export.py`

**Interfaces:**
- Consumes: `terrain.Heightmap` (Task 6).
- Produces:
  - `building_mesh(b, hm: Heightmap | None = None)` — with `hm`: extrudes `height + 2.0` and shifts so base sits 2 m below terrain at the footprint centroid (no floating edges on slopes); without `hm`: behavior unchanged.
  - `road_mesh(r, hm=None)` — segments densified to ≤24 m; vertex y = `0.05 + hm.sample(x, z)` (0.05 flat when `hm is None`).
  - `area_piece_mesh(geom, kind, y=0.02, hm=None, flat_y=None)` — green: per-vertex drape (`hm.sample + 0.02`); water: flat at `flat_y` when given.
  - `terrain_tile_mesh(tx, tz, hm, water_geom=None, green_geom=None) -> Trimesh` — (QUADS+1)² grid; y from `hm`; vertices inside `water_geom` dropped by `TERRAIN_WATER_DROP` and painted `TERRAIN_WATER_COLOR`; inside `green_geom` painted `TERRAIN_COLOR_HIGH`; else low→high blend over `TERRAIN_COLOR_BLEND`.
  - `build_tiles(city, hm=None)` — with `hm`: adds `"terrain"` geometry to every tile in the bbox tile range ∪ content tiles; skips separate green area meshes (terrain is painted green instead); water areas flat at `min(hm.sample over outline) + 0.02`.
  - `export_city(city, out_dir, hm=None)`; `build.py` calls `fetch_heightmap()` and passes it.

- [ ] **Step 1: Add failing tests**:

Append to `pipeline/tests/test_meshes.py`:

```python
from pipeline.terrain import Heightmap
from pipeline.meshes import terrain_tile_mesh

def _flat_hm(h: float) -> Heightmap:
    return Heightmap(grid=np.full((4, 4), h, dtype=np.float32),
                     x0=-512.0, z0=-512.0, step_x=341.33, step_z=341.33)

def test_building_displaced_onto_terrain():
    m = building_mesh(Building(1, SQ, 30.0, "yes"), hm=_flat_hm(50.0))
    lo, hi = m.bounds
    assert abs(lo[1] - 48.0) < 1e-4   # base sunk 2 m below terrain
    assert abs(hi[1] - 80.0) < 1e-4   # top = terrain + height

def test_road_densified_and_draped():
    m = road_mesh(Road(2, "x", [(0.0, 0.0), (100.0, 0.0)], 8.0), hm=_flat_hm(10.0))
    assert len(m.faces) == 10          # 100 m -> 5 segments of <=24 m -> 10 tris
    assert abs(m.bounds[0][1] - 10.05) < 1e-4

def test_terrain_tile_mesh_grid():
    from pipeline import config
    m = terrain_tile_mesh(0, 0, _flat_hm(5.0))
    q = config.TERRAIN_TILE_QUADS
    assert len(m.vertices) == (q + 1) ** 2
    assert len(m.faces) == q * q * 2
    assert abs(m.bounds[0][1] - 5.0) < 1e-4
```

Update the now-stale existing test in `pipeline/tests/test_meshes.py` (densification changes the face count even without terrain):

```python
def test_road_mesh_is_flat_ribbon():
    m = road_mesh(Road(3, "x", [(0.0, 0.0), (100.0, 0.0)], 8.0))
    lo, hi = m.bounds
    assert abs(hi[1] - lo[1]) < 1e-6            # flat
    assert abs((hi[2] - lo[2]) - 8.0) < 1e-6    # width across z
    assert len(m.faces) == 10                    # 5 densified segments * 2 tris
```

Append to `pipeline/tests/test_export.py`:

```python
def test_build_tiles_with_heightmap_has_terrain_everywhere():
    import numpy as np
    from pipeline.terrain import Heightmap
    hm = Heightmap(grid=np.zeros((4, 4), dtype=np.float32),
                   x0=-3000.0, z0=-3000.0, step_x=2000.0, step_z=2000.0)
    city = parse_osm(FIX)
    tiles = build_tiles(city, hm=hm)
    assert len(tiles) >= 200  # full bbox range gets terrain tiles
    assert all("terrain" in scene.geometry for scene in tiles.values())
```

- [ ] **Step 2: Run** — expect FAIL.

- [ ] **Step 3: Implement `pipeline/meshes.py`**:

```python
import math
from pipeline.terrain import Heightmap

def _densify(points: list[tuple[float, float]], max_len: float = 24.0) -> list[tuple[float, float]]:
    out = [points[0]]
    for (x1, z1), (x2, z2) in zip(points[:-1], points[1:]):
        d = math.hypot(x2 - x1, z2 - z1)
        steps = max(1, math.ceil(d / max_len))
        for i in range(1, steps + 1):
            out.append((x1 + (x2 - x1) * i / steps, z1 + (z2 - z1) * i / steps))
    return out
```

`building_mesh(b, hm=None)`:

```python
def building_mesh(b: Building, hm: Heightmap | None = None) -> trimesh.Trimesh | None:
    if len(b.footprint) < 3 or b.height <= 0:
        return None
    poly = Polygon(b.footprint)
    if not poly.is_valid:
        poly = poly.buffer(0)
    if poly.is_empty or poly.area < 1.0 or poly.geom_type != "Polygon":
        return None
    if hm is None:
        mesh = _to_yup(extrude_polygon(poly, b.height))
    else:
        c = poly.centroid
        mesh = _to_yup(extrude_polygon(poly, b.height + 2.0))
        mesh.apply_translation([0.0, hm.sample(c.x, c.y) - 2.0, 0.0])
    return _paint(mesh, building_color(b), _jitter(b.osm_id))
```

`road_mesh(r, hm=None)` — densify first, y per endpoint:

```python
def road_mesh(r: Road, hm: Heightmap | None = None) -> trimesh.Trimesh | None:
    if len(r.points) < 2 or r.width <= 0:
        return None
    line = LineString(r.points)
    if line.length < 1.0:
        return None
    pts = _densify(r.points)
    def h(x: float, z: float) -> float:
        return 0.05 + (hm.sample(x, z) if hm is not None else 0.0)
    verts, faces = [], []
    for (x1, z1), (x2, z2) in zip(pts[:-1], pts[1:]):
        d = np.array([x2 - x1, z2 - z1])
        n = np.linalg.norm(d)
        if n < 1e-6:
            continue
        px, pz = -d[1] / n, d[0] / n
        hw = r.width / 2.0
        i = len(verts)
        y1, y2 = h(x1, z1), h(x2, z2)
        verts += [
            [x1 + px * hw, y1, z1 + pz * hw], [x1 - px * hw, y1, z1 - pz * hw],
            [x2 + px * hw, y2, z2 + pz * hw], [x2 - px * hw, y2, z2 - pz * hw],
        ]
        faces += [[i, i + 2, i + 1], [i + 1, i + 2, i + 3]]
    if not faces:
        return None
    mesh = trimesh.Trimesh(vertices=np.array(verts), faces=np.array(faces), process=False)
    return _paint(mesh, config.ROAD_COLORS.get(r.road_class, config.DEFAULT_ROAD_COLOR))
```

`area_piece_mesh` gains drape/flat modes:

```python
def area_piece_mesh(geom, kind: str, y: float = 0.02,
                    hm: Heightmap | None = None,
                    flat_y: float | None = None) -> trimesh.Trimesh | None:
    polys = [g for g in getattr(geom, "geoms", [geom])
             if g.geom_type == "Polygon" and not g.is_empty and g.area >= 1.0]
    parts = []
    for p in polys:
        v2d, faces = triangulate_polygon(p)
        if flat_y is not None:
            ys = np.full(len(v2d), flat_y)
        elif hm is not None:
            ys = np.array([hm.sample(px, pz) + y for px, pz in v2d])
        else:
            ys = np.full(len(v2d), y)
        verts = np.column_stack([v2d[:, 0], ys, v2d[:, 1]])
        parts.append(trimesh.Trimesh(vertices=verts, faces=faces, process=False))
    if not parts:
        return None
    return _paint(trimesh.util.concatenate(parts), config.AREA_COLORS[kind])
```

`terrain_tile_mesh`:

```python
def terrain_tile_mesh(tx: int, tz: int, hm: Heightmap,
                      water_geom=None, green_geom=None) -> trimesh.Trimesh:
    from shapely.geometry import Point
    q = config.TERRAIN_TILE_QUADS
    ts = config.TILE_SIZE
    n = q + 1
    verts = np.zeros((n * n, 3))
    colors = np.zeros((n * n, 4), dtype=np.uint8)
    lo_y, hi_y = config.TERRAIN_COLOR_BLEND
    c_lo = np.array(config.TERRAIN_COLOR_LOW, dtype=float)
    c_hi = np.array(config.TERRAIN_COLOR_HIGH, dtype=float)
    c_wet = np.array(config.TERRAIN_WATER_COLOR, dtype=float)
    for iz in range(n):
        for ix in range(n):
            x = tx * ts + ix * ts / q
            z = tz * ts + iz * ts / q
            yv = hm.sample(x, z)
            pt = Point(x, z)
            if water_geom is not None and water_geom.contains(pt):
                yv -= config.TERRAIN_WATER_DROP
                rgb = c_wet
            elif green_geom is not None and green_geom.contains(pt):
                rgb = c_hi
            else:
                t = min(max((yv - lo_y) / (hi_y - lo_y), 0.0), 1.0)
                rgb = c_lo * (1 - t) + c_hi * t
            k = iz * n + ix
            verts[k] = [x, yv, z]
            colors[k] = [*rgb.astype(np.uint8), 255]
    faces = []
    for iz in range(q):
        for ix in range(q):
            a = iz * n + ix
            faces += [[a, a + 1, a + n], [a + 1, a + n + 1, a + n]]
    mesh = trimesh.Trimesh(vertices=verts, faces=np.array(faces), process=False)
    mesh.visual.vertex_colors = colors
    return mesh
```

- [ ] **Step 4: Implement `pipeline/tiler.py`** — `build_tiles(city, hm=None)`:

```python
from shapely.prepared import prep
from shapely.ops import unary_union
from pipeline.geo import latlon_to_xz
from pipeline.meshes import building_mesh, road_mesh, area_piece_mesh, terrain_tile_mesh

def _bbox_tile_range() -> list[tuple[int, int]]:
    s, w, n, e = config.BBOX
    x0, z0 = latlon_to_xz(n, w)
    x1, z1 = latlon_to_xz(s, e)
    tx0, tz0 = assign_tile(x0, z0)
    tx1, tz1 = assign_tile(x1 - 1e-6, z1 - 1e-6)
    return [(tx, tz) for tx in range(tx0, tx1 + 1) for tz in range(tz0, tz1 + 1)]

def build_tiles(city: CityData, hm=None) -> dict[tuple[int, int], trimesh.Scene]:
    ...
    # buildings/roads: pass hm through -> building_mesh(b, hm), road_mesh(r, hm)
    # areas loop (from Task 5): when hm is not None, skip kind == "green"
    # (terrain vertices are painted green instead) and compute for water:
    #   flat_y = min(hm.sample(x, z) for x, z in a.outline) + 0.02
    #   pieces use area_piece_mesh(..., flat_y=flat_y)
    # when hm is None: unchanged Task 5 behavior.

    water_geom = green_geom = None
    keys = set(buckets)
    if hm is not None:
        def _union(kind: str):
            polys = []
            for a in city.areas:
                if a.kind != kind or len(a.outline) < 3:
                    continue
                p = Polygon(a.outline, a.holes)
                polys.append(p if p.is_valid else p.buffer(0))
            return prep(unary_union(polys)) if polys else None
        water_geom = _union("water")
        green_geom = _union("green")
        keys |= set(_bbox_tile_range())
    tiles: dict[tuple[int, int], trimesh.Scene] = {}
    for key in sorted(keys):
        scene = trimesh.Scene()
        total_tris = 0
        for cat in ("buildings", "roads", "areas"):
            if buckets[key][cat]:
                merged = trimesh.util.concatenate(buckets[key][cat])
                total_tris += len(merged.faces)
                scene.add_geometry(merged, geom_name=cat, node_name=cat)
        if hm is not None:
            t = terrain_tile_mesh(key[0], key[1], hm, water_geom, green_geom)
            total_tris += len(t.faces)
            scene.add_geometry(t, geom_name="terrain", node_name="terrain")
        if total_tris > config.MAX_TILE_TRIS:
            raise ValueError(f"tile {key}: {total_tris} tris over budget")
        tiles[key] = scene
    return tiles
```

(`prep(...)` objects expose `.contains`, matching `terrain_tile_mesh`. Note: `prepared` geoms can't be passed to `intersection` — only used for containment.)

- [ ] **Step 5: Wire through** — `pipeline/export.py`: `def export_city(city, out_dir, hm=None)` → `tiles = build_tiles(city, hm=hm)`. `pipeline/build.py`:

```python
from pipeline.terrain import fetch_heightmap
...
    city = parse_osm(xml)
    print(f"parsed: {len(city.roads)} roads, {len(city.buildings)} buildings, {len(city.areas)} areas")
    hm = fetch_heightmap()
    meta = export_city(city, args.out, hm=hm)
```

- [ ] **Step 6: Lower the backdrop plane** — in `game/scenes/main.tscn`, change the Ground transform to y = −40 (terrain now carries the ground; the plane is only a far backdrop and must not poke through the depressed river):

```
[node name="Ground" type="MeshInstance3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, -40, 0)
mesh = SubResource("ground_mesh")
```

- [ ] **Step 7: Run** `.venv/Scripts/python -m pytest pipeline -q` — all green.
- [ ] **Step 8: Commit** `git commit -am "pipeline: terrain tile meshes and terrain-aware displacement"`

---

### Task 8: Procedural hero landmarks

**Files:**
- Create: `pipeline/landmarks.py`, `pipeline/tests/test_landmarks.py`
- Modify: `pipeline/config.py`, `pipeline/export.py`, `game/scripts/tile_loader.gd`

**Interfaces:**
- Consumes: `meshes._paint`, `terrain.Heightmap`, `geo.latlon_to_xz`.
- Produces:
  - `config.LANDMARKS: list[dict]` with keys `key, name, lat, lon, clear` (clear = exclusion radius m).
  - `landmarks.BUILDERS: dict[str, Callable[[float], list[trimesh.Trimesh]]]` — each takes `base_y` and returns parts centered on local (0, base_y, 0).
  - `landmarks.export_landmarks(out_dir: Path, hm: Heightmap | None) -> list[dict]` — writes `landmarks/<key>.glb`, returns metadata entries `{key, name, file, x, z}`.
  - `export.export_city` drops buildings within `clear` of any anchor and adds `meta["landmarks"]`.
  - `TileLoader` loads each landmark GLB (always visible, city material applied).

- [ ] **Step 1: Verify anchor coordinates against real OSM data** (true-coords requirement). Run:

```bash
.venv/Scripts/python - <<'PY'
import xml.etree.ElementTree as ET
names = ["Place Ville", "Notre-Dame", "Biosph", "Habitat 67", "Five Roses"]
nodes, hits = {}, []
for _, el in ET.iterparse("data/osm_downtown.osm.xml", events=("end",)):
    if el.tag == "node":
        nodes[int(el.get("id"))] = (float(el.get("lat")), float(el.get("lon")))
    elif el.tag == "way":
        tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
        nm = tags.get("name", "")
        if any(k.lower() in nm.lower() for k in names):
            pts = [nodes[int(nd.get("ref"))] for nd in el.findall("nd") if int(nd.get("ref")) in nodes]
            if pts:
                lat = sum(p[0] for p in pts) / len(pts)
                lon = sum(p[1] for p in pts) / len(pts)
                hits.append((nm, round(lat, 5), round(lon, 5)))
    if el.tag in ("node", "way"):
        el.clear()
for h in sorted(set(hits)):
    print(h)
PY
```

Use the printed centroids to fill `config.LANDMARKS` (starting values below; replace any that differ by more than ~0.0005°). Then append to `pipeline/config.py`:

```python
# --- Hero landmarks (true coords; clear = radius m of auto-buildings removed) ---
LANDMARKS = [
    {"key": "pvm",        "name": "Place Ville Marie",      "lat": 45.5017, "lon": -73.5685, "clear": 70},
    {"key": "notre_dame", "name": "Basilique Notre-Dame",   "lat": 45.5045, "lon": -73.5562, "clear": 55},
    {"key": "biosphere",  "name": "Biosphère",              "lat": 45.5141, "lon": -73.5330, "clear": 55},
    {"key": "habitat67",  "name": "Habitat 67",             "lat": 45.5005, "lon": -73.5450, "clear": 90},
    {"key": "five_roses", "name": "Farine Five Roses",      "lat": 45.4922, "lon": -73.5545, "clear": 60},
]
```

- [ ] **Step 2: Write failing tests** — `pipeline/tests/test_landmarks.py`:

```python
import trimesh
from pathlib import Path
from pipeline import config
from pipeline.landmarks import BUILDERS, export_landmarks

def test_all_landmarks_have_builders():
    assert set(BUILDERS) == {lm["key"] for lm in config.LANDMARKS}

def test_builder_heights():
    def top(key):
        m = trimesh.util.concatenate(BUILDERS[key](0.0))
        return m.bounds[1][1]
    assert 180.0 <= top("pvm") <= 200.0
    assert 60.0 <= top("notre_dame") <= 80.0
    assert all(len(m.visual.vertex_colors) == len(m.vertices)
               for m in BUILDERS["habitat67"](0.0))

def test_export_landmarks_writes_glbs(tmp_path):
    entries = export_landmarks(tmp_path, hm=None)
    assert len(entries) == len(config.LANDMARKS)
    for e in entries:
        assert (tmp_path / e["file"]).exists()
        assert isinstance(e["x"], float) and isinstance(e["z"], float)

def test_landmark_buildings_excluded(monkeypatch, tmp_path):
    from pipeline.osm_parse import parse_osm
    from pipeline.export import export_city
    FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"
    city = parse_osm(FIX)
    n_before = len(city.buildings)
    # anchor on top of fixture building 102 (nodes ~45.5046, -73.55425)
    monkeypatch.setattr(config, "LANDMARKS",
        [{"key": "pvm", "name": "t", "lat": 45.5046, "lon": -73.55425, "clear": 60}])
    meta = export_city(city, tmp_path)
    assert len(meta["landmarks"]) == 1
    assert len(city.buildings) == n_before - 1
```

- [ ] **Step 3: Run** — expect FAIL (no module).

- [ ] **Step 4: Implement** — `pipeline/landmarks.py`:

```python
from __future__ import annotations
from pathlib import Path
import numpy as np
import trimesh
from shapely.geometry import Polygon
from trimesh.creation import box as tm_box, icosphere, extrude_polygon
from pipeline import config
from pipeline.geo import latlon_to_xz
from pipeline.meshes import _paint, _ZUP_TO_YUP

GLASS = (120, 135, 150)
STONE = (110, 106, 100)
DARK_ROOF = (70, 66, 62)
CONCRETE = (196, 190, 180)
STEEL = (140, 150, 155)
MILL = (150, 140, 130)
SIGN_RED = (200, 40, 40)

def _box(sx: float, sy: float, sz: float, cx: float, base_y: float, cz: float,
         rgb: tuple) -> trimesh.Trimesh:
    b = tm_box((sx, sy, sz))
    b.apply_translation([cx, base_y + sy / 2.0, cz])
    return _paint(b, rgb)

def _prism(width: float, height: float, length: float, cx: float, base_y: float,
           cz: float, rgb: tuple) -> trimesh.Trimesh:
    """Triangular roof prism: cross-section in XY (y up), extruded along Z."""
    m = extrude_polygon(Polygon([(-width / 2, 0), (width / 2, 0), (0, height)]), length)
    m.apply_translation([cx, 0, -length / 2.0])
    m.apply_translation([0, base_y, cz])
    return _paint(m, rgb)

def pvm(base_y: float) -> list[trimesh.Trimesh]:
    parts = [_box(90, 5, 90, 0, base_y, 0, CONCRETE)]           # podium
    parts.append(_box(62, 183, 18, 0, base_y + 5, 0, GLASS))    # cruciform tower
    parts.append(_box(18, 183, 62, 0, base_y + 5, 0, GLASS))
    return parts

def notre_dame(base_y: float) -> list[trimesh.Trimesh]:
    parts = [
        _box(12, 66, 12, -12, base_y, -26, STONE),  # west tower
        _box(12, 66, 12, 12, base_y, -26, STONE),   # east tower
        _box(34, 22, 58, 0, base_y, 8, STONE),      # nave
        _prism(34, 12, 58, 0, base_y + 22, 8, DARK_ROOF),
    ]
    return parts

def biosphere(base_y: float) -> list[trimesh.Trimesh]:
    s = icosphere(subdivisions=2, radius=38.0)
    s.apply_translation([0, base_y + 20.0, 0])  # sphere sunk into the ground
    return [_paint(s, STEEL)]

def habitat67(base_y: float) -> list[trimesh.Trimesh]:
    parts = []
    for tier, count in enumerate((15, 10, 6)):
        for i in range(count):
            x = -70.0 + i * (140.0 / max(count - 1, 1)) + ((i * 37) % 7) - 3.0
            z = float(((i * 53 + tier * 29) % 11) - 5)
            parts.append(_box(12, 4, 7, x, base_y + tier * 4.5, z, CONCRETE))
    return parts

def five_roses(base_y: float) -> list[trimesh.Trimesh]:
    parts = [
        _box(28, 35, 22, -18, base_y, 0, MILL),
        _box(36, 28, 20, 16, base_y, 2, MILL),
        _box(2, 8, 2, -26, base_y + 35, 0, MILL),   # sign posts
        _box(2, 8, 2, -10, base_y + 35, 0, MILL),
        _box(42, 7, 1.5, -18, base_y + 41, 0, SIGN_RED),  # FARINE FIVE ROSES panel
    ]
    return parts

BUILDERS = {
    "pvm": pvm, "notre_dame": notre_dame, "biosphere": biosphere,
    "habitat67": habitat67, "five_roses": five_roses,
}

def export_landmarks(out_dir: str | Path, hm) -> list[dict]:
    out = Path(out_dir) / "landmarks"
    out.mkdir(parents=True, exist_ok=True)
    entries = []
    for lm in config.LANDMARKS:
        x, z = latlon_to_xz(lm["lat"], lm["lon"])
        base_y = hm.sample(x, z) if hm is not None else 0.0
        mesh = trimesh.util.concatenate(BUILDERS[lm["key"]](base_y))
        mesh.apply_translation([x, 0, z])
        scene = trimesh.Scene()
        scene.add_geometry(mesh, geom_name=lm["key"], node_name=lm["key"])
        fname = f"landmarks/{lm['key']}.glb"
        scene.export(Path(out_dir) / fname)
        entries.append({"key": lm["key"], "name": lm["name"], "file": fname,
                        "x": round(x, 1), "z": round(z, 1)})
    return entries
```

- [ ] **Step 5: Wire into export** — in `pipeline/export.py`:

```python
import math
from pipeline.geo import latlon_to_xz
from pipeline.landmarks import export_landmarks

def _drop_landmark_buildings(city: CityData) -> None:
    anchors = [(latlon_to_xz(lm["lat"], lm["lon"]), lm["clear"]) for lm in config.LANDMARKS]
    def keep(b) -> bool:
        cx = sum(p[0] for p in b.footprint) / len(b.footprint)
        cz = sum(p[1] for p in b.footprint) / len(b.footprint)
        return all(math.hypot(cx - ax, cz - az) > r for (ax, az), r in anchors)
    city.buildings = [b for b in city.buildings if keep(b)]
```

In `export_city`, call `_drop_landmark_buildings(city)` BEFORE `build_tiles`, then `landmark_entries = export_landmarks(out, hm)` and add `"landmarks": landmark_entries` to `meta`.

- [ ] **Step 6: Game loads landmarks** — in `game/scripts/tile_loader.gd`, at the end of `_ready` (after the tile loop):

```gdscript
	for lm in meta.get("landmarks", []):
		var lm_scene := load("res://world/%s" % lm["file"]) as PackedScene
		if lm_scene == null:
			push_warning("missing landmark: " + str(lm["file"]))
			continue
		var lm_node := lm_scene.instantiate() as Node3D
		add_child(lm_node)
		_apply_city_material(lm_node)
```

(Landmarks are not added to `_tiles`, so they never get distance-culled.)

- [ ] **Step 7: Run** `.venv/Scripts/python -m pytest pipeline -q` — all green. (Old metadata has no `landmarks` key; `meta.get` keeps smoke green until Task 10 regenerates.)
- [ ] **Step 8: Commit** `git add pipeline game && git commit -m "pipeline+game: five procedural hero landmarks at true coordinates"`

---

### Task 9: Minimap render in the pipeline

**Files:**
- Create: `pipeline/minimap.py`, `pipeline/tests/test_minimap.py`
- Modify: `pipeline/export.py`

**Interfaces:**
- Produces: `minimap.render_minimap(city, out_path: Path, size: int = 2048) -> dict` — returns `{"file": "minimap.png", "world_origin": [x0, z0], "world_size": [w, h], "px": size}` (all floats rounded to 1 decimal); PNG has dark bg, water/green polygons, roads by class color, gold landmark dots. `export_city` adds it as `meta["minimap"]`.

- [ ] **Step 1: Write failing tests** — `pipeline/tests/test_minimap.py`:

```python
from pathlib import Path
from PIL import Image
from pipeline.osm_parse import parse_osm
from pipeline.minimap import render_minimap

FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"

def test_minimap_renders(tmp_path):
    city = parse_osm(FIX)
    block = render_minimap(city, tmp_path / "minimap.png", size=512)
    img = Image.open(tmp_path / "minimap.png")
    assert img.size == (512, 512)
    assert block["px"] == 512 and block["file"] == "minimap.png"
    colors = {c for _, c in img.getcolors(maxcolors=100000)}
    assert (62, 110, 138) in colors      # water drawn
    assert len(colors) >= 3              # bg + water + roads at least

def test_minimap_deterministic(tmp_path):
    city = parse_osm(FIX)
    render_minimap(city, tmp_path / "a.png", size=256)
    render_minimap(city, tmp_path / "b.png", size=256)
    assert (tmp_path / "a.png").read_bytes() == (tmp_path / "b.png").read_bytes()
```

- [ ] **Step 2: Run** — expect FAIL (no module).

- [ ] **Step 3: Implement** — `pipeline/minimap.py`:

```python
from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw
from pipeline import config
from pipeline.geo import latlon_to_xz
from pipeline.osm_parse import CityData

BG = (34, 36, 40)
GOLD = (230, 190, 80)

def render_minimap(city: CityData, out_path: str | Path, size: int = 2048) -> dict:
    s, w, n, e = config.BBOX
    x0, z0 = latlon_to_xz(n, w)
    x1, z1 = latlon_to_xz(s, e)
    span = max(x1 - x0, z1 - z0)
    scale = size / span
    def px(x: float, z: float) -> tuple[float, float]:
        return ((x - x0) * scale, (z - z0) * scale)
    img = Image.new("RGB", (size, size), BG)
    d = ImageDraw.Draw(img)
    for kind in ("green", "water"):
        for a in sorted((a for a in city.areas if a.kind == kind), key=lambda a: a.osm_id):
            if len(a.outline) < 3:
                continue
            d.polygon([px(x, z) for x, z in a.outline], fill=config.AREA_COLORS[kind])
            for hole in a.holes:
                if len(hole) >= 3:
                    d.polygon([px(x, z) for x, z in hole], fill=BG)
    for r in city.roads:
        color = config.ROAD_COLORS.get(r.road_class, config.DEFAULT_ROAD_COLOR)
        width = max(1, round(r.width * scale))
        d.line([px(x, z) for x, z in r.points], fill=color, width=width)
    for lm in config.LANDMARKS:
        cx, cz = px(*latlon_to_xz(lm["lat"], lm["lon"]))
        rr = max(3, size // 340)
        d.ellipse([cx - rr, cz - rr, cx + rr, cz + rr], fill=GOLD)
    img.save(str(out_path))
    return {"file": Path(out_path).name, "world_origin": [round(x0, 1), round(z0, 1)],
            "world_size": [round(span, 1), round(span, 1)], "px": size}
```

- [ ] **Step 4: Wire into export** — in `export_city`, after landmarks: `meta["minimap"] = render_minimap(city, out / "minimap.png")`.
- [ ] **Step 5: Run** `.venv/Scripts/python -m pytest pipeline -q` — all green (including `test_export_deterministic`, which now covers landmark + minimap blocks).
- [ ] **Step 6: Commit** `git add pipeline && git commit -m "pipeline: minimap PNG render + metadata block"`

---

### Task 10: Full rebuild — fresh OSM (with relations), heightmap, tiles, import, smoke

**Files:**
- Modify (generated): `game/world/**` (tiles, landmarks, minimap.png, city_metadata.json)

**Interfaces:**
- Consumes: everything above. Produces the committed world the remaining game tasks rely on.

- [ ] **Step 1: Delete the stale cache** (query now includes relations — this is the one sanctioned re-download):

```bash
rm data/osm_downtown.osm.xml
```

- [ ] **Step 2: Rebuild** (Overpass download minutes; mirrors flaky — the built-in rotation retries 6×; if all 6 fail, wait ~10 min and rerun):

```bash
rm -f game/world/*.glb game/world/city_metadata.json
.venv/Scripts/python -m pipeline.build
```

Expected console: `parsed: ~7900 roads, ~9000 buildings, <areas noticeably higher than before>`, a `heightmap saved (hrdem|synthetic)` line, and `exported ~260-280 tiles`. Record which heightmap source was used. If a tile raises `over budget`, STOP and report — do not raise the budget without review.

- [ ] **Step 3: Reimport + smoke**:

```bash
tools/godot/godot.exe --headless --path game --import
tools/godot/godot.exe --headless --path game --script res://tests/smoke_test.gd
```

Expected: `SMOKE OK: <N> tiles` with N ≥ 250.

- [ ] **Step 4: Sanity-check the metadata**:

```bash
.venv/Scripts/python -c "import json; m=json.load(open('game/world/city_metadata.json')); print(len(m['tiles']), len(m['landmarks']), m['minimap']['px'])"
```

Expected: `<tile count> 5 2048`.

- [ ] **Step 5: Commit the world** `git add game/world && git commit -m "world: rebuild with palette, river, terrain, landmarks, minimap"`

---

### Task 11: Day/night cycle

**Files:**
- Create: `game/scripts/day_night.gd`
- Modify: `game/scenes/main.tscn`

**Interfaces:**
- Produces: `day_night.gd` attached to the `Sun` DirectionalLight3D; exports `day_length_sec := 600.0`, `time_of_day := 0.35`. Holding `T` fast-forwards. Drives sun rotation/energy/color and the environment sky, ambient, and fog colors.

- [ ] **Step 1: Write** `game/scripts/day_night.gd`:

```gdscript
extends DirectionalLight3D
# Day/night: rotates the sun and blends sky/ambient/fog. 0 = midnight, 0.5 = noon.

@export var day_length_sec := 600.0
@export var time_of_day := 0.35

const NIGHT_SKY := Color(0.05, 0.07, 0.12)
const DAY_SKY := Color(0.75, 0.82, 0.9)
const NIGHT_AMB := Color(0.12, 0.14, 0.22)
const DAY_AMB := Color(0.8, 0.8, 0.85)

var _env: Environment

func _ready() -> void:
	var we := get_node_or_null("../WorldEnvironment") as WorldEnvironment
	if we != null:
		_env = we.environment

func _process(delta: float) -> void:
	time_of_day = fposmod(time_of_day + delta / day_length_sec, 1.0)
	if Input.is_key_pressed(KEY_T):
		time_of_day = fposmod(time_of_day + delta * 0.05, 1.0)
	var s := sin((time_of_day - 0.25) * TAU)      # >0 during day, 1 at noon
	var daylight := clampf(s * 1.5, 0.0, 1.0)
	rotation_degrees = Vector3(-15.0 - 60.0 * maxf(s, 0.0), 40.0 + 360.0 * time_of_day, 0.0)
	light_energy = 0.05 + 1.15 * daylight
	light_color = Color(1.0, 0.75 + 0.25 * daylight, 0.55 + 0.45 * daylight)
	if _env == null:
		return
	_env.background_color = NIGHT_SKY.lerp(DAY_SKY, daylight)
	_env.ambient_light_color = NIGHT_AMB.lerp(DAY_AMB, daylight)
	_env.ambient_light_energy = 0.15 + 0.45 * daylight
	if _env.fog_enabled:
		_env.fog_light_color = _env.background_color
```

- [ ] **Step 2: Wire in `game/scenes/main.tscn`** — bump `load_steps` by 1, add the script resource and fog:

```
[ext_resource type="Script" path="res://scripts/day_night.gd" id="3"]
```

extend the Environment sub_resource:

```
[sub_resource type="Environment" id="env1"]
background_mode = 1
background_color = Color(0.75, 0.82, 0.9, 1)
ambient_light_source = 2
ambient_light_color = Color(0.8, 0.8, 0.85, 1)
ambient_light_energy = 0.6
fog_enabled = true
fog_light_color = Color(0.75, 0.82, 0.9, 1)
fog_density = 0.0004
```

and attach to the Sun node:

```
[node name="Sun" type="DirectionalLight3D" parent="."]
transform = Transform3D(0.866, -0.353, 0.353, 0, 0.707, 0.707, -0.5, -0.612, 0.612, 0, 0, 0)
shadow_enabled = true
script = ExtResource("3")
```

- [ ] **Step 3: Smoke** `tools/godot/godot.exe --headless --path game --script res://tests/smoke_test.gd` — expect `SMOKE OK`.
- [ ] **Step 4: Commit** `git add game && git commit -m "game: day/night cycle with fog"`

---

### Task 12: Minimap UI

**Files:**
- Create: `game/scripts/minimap.gd`
- Modify: `game/scenes/main.tscn`

**Interfaces:**
- Consumes: `game/world/minimap.png` + `meta["minimap"]` (Task 9/10).
- Produces: bottom-left 256 px minimap with a red camera marker.

- [ ] **Step 1: Write** `game/scripts/minimap.gd`:

```gdscript
extends TextureRect
# Bottom-left minimap: full-map texture + marker tracking the active camera.

var _origin := Vector2.ZERO
var _world := Vector2.ONE
@onready var _marker: ColorRect = $Marker

func _ready() -> void:
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if f == null:
		return
	var meta: Variant = JSON.parse_string(f.get_as_text())
	if typeof(meta) != TYPE_DICTIONARY or not meta.has("minimap"):
		return
	var mm: Dictionary = meta["minimap"]
	_origin = Vector2(mm["world_origin"][0], mm["world_origin"][1])
	_world = Vector2(mm["world_size"][0], mm["world_size"][1])

func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var uv := (Vector2(cam.global_position.x, cam.global_position.z) - _origin) / _world
	uv = uv.clamp(Vector2.ZERO, Vector2.ONE)
	_marker.position = uv * size - _marker.size / 2.0
```

- [ ] **Step 2: Wire in `game/scenes/main.tscn`** — bump `load_steps` by 2, add:

```
[ext_resource type="Script" path="res://scripts/minimap.gd" id="4"]
[ext_resource type="Texture2D" path="res://world/minimap.png" id="5"]
```

and append nodes at the end:

```
[node name="HUD" type="CanvasLayer" parent="."]

[node name="Minimap" type="TextureRect" parent="HUD"]
anchors_preset = 2
anchor_top = 1.0
anchor_bottom = 1.0
offset_left = 12.0
offset_top = -268.0
offset_right = 268.0
offset_bottom = -12.0
expand_mode = 1
texture = ExtResource("5")
script = ExtResource("4")

[node name="Marker" type="ColorRect" parent="HUD/Minimap"]
offset_right = 6.0
offset_bottom = 6.0
color = Color(0.9, 0.2, 0.15, 1)
```

- [ ] **Step 3: Smoke** — expect `SMOKE OK`. (If the texture fails to load, rerun `tools/godot/godot.exe --headless --path game --import` once and retry.)
- [ ] **Step 4: Commit** `git add game && git commit -m "game: minimap HUD with camera marker"`

---

### Task 13: Screenshot review, fixes, handoff, tag

**Files:**
- Modify: `game/tests/screenshot.gd`, `docs/superpowers/HANDOFF.md`

**Interfaces:**
- Consumes: everything. Produces the reviewed milestone + `m3-montreal` tag.

- [ ] **Step 1: Add poses** — in `game/tests/screenshot.gd` replace `POSES` with:

```gdscript
const POSES := [
	{"name": "overview",  "pos": Vector3(0, 600, 400),      "look": Vector3(0, 0, 0)},
	{"name": "street",    "pos": Vector3(50, 40, 100),      "look": Vector3(0, 10, -200)},
	{"name": "oldport",   "pos": Vector3(800, 120, 900),    "look": Vector3(400, 0, 400)},
	{"name": "mountain",  "pos": Vector3(-1200, 250, -200), "look": Vector3(-2200, 150, -250)},
	{"name": "biosphere", "pos": Vector3(1250, 120, -800),  "look": Vector3(1600, 30, -1117)},
]
```

- [ ] **Step 2: Capture** (windowed, needs GPU): `tools/godot/godot.exe --path game --script res://tests/screenshot.gd` → PNGs in `%APPDATA%/Godot/app_userdata/MTL Open Ile/`.
- [ ] **Step 3: REVIEW — Read every PNG with the Read tool** and check against this list (mandatory; never claim visual success without looking):
  - Buildings show the palette (brick / gray-blue / greystone variety), NOT uniform white.
  - The St. Lawrence is visible as blue water in `oldport` and `biosphere` shots.
  - Parks/green space visible (overview); Mont Royal slope rises in `mountain` shot.
  - Landmarks: PVM cruciform downtown (overview/street), Biosphere sphere in its shot.
  - Minimap bottom-left with red marker; sky/fog looks coherent, not black.
- [ ] **Step 4: Fix-or-report.** Palette/fog/pose tweaks: fix inline, re-capture, re-review. Structural failures (all-white buildings = vertex colors not imported; missing river; terrain spikes): STOP and report with the screenshot paths — do not improvise architecture changes.
- [ ] **Step 5: Update `docs/superpowers/HANDOFF.md`** — new state (M3 complete, tag `m3-montreal`, heightmap source used, tile count), next up = M4 "On foot" (walkable streets, collisions, street-name HUD — remember the carry-forward: dedupe `streets` metadata, consume or drop `spawn`), keep remaining carry-forwards (fly-cam Esc untested).
- [ ] **Step 6: Verify all clean** — `.venv/Scripts/python -m pytest pipeline -q` green; smoke green; `git status` clean after commit.
- [ ] **Step 7: Commit + tag**:

```bash
git add docs game && git commit -m "docs: M3 handoff; screenshot poses for mountain and biosphere"
git tag m3-montreal
```

---

## Self-Review Notes

- Spec coverage: palette ✓ (T2/3), river relations ✓ (T4/5), Mont Royal terrain ✓ (T6/7), landmarks at true coords ✓ (T8), day/night ✓ (T11), minimap ✓ (T9/12), screenshot verification ✓ (T13). Deferred (unchanged by spec): street-name HUD/spawn (M4).
- Carry-forward findings landed: download sanity + retry sleep (T4), tiler raise + test (T5), ring-node guard (T4). Remaining for M4: streets dedupe, spawn consumption, fly-cam Esc manual test.
- Type consistency: `Heightmap.sample(x, z)` used identically in meshes/tiler/landmarks; `area_piece_mesh(geom, kind, y, hm, flat_y)` signature consistent between T5 def and T7 extension (T7 REPLACES the T5 body — executor of T7 must apply the newer signature); `_apply_city_material` defined T3, used T8.
