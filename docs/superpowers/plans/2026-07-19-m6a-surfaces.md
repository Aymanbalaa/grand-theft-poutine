# MTL: Open Île — Plan 6a: Surfaces (Milestone 6, phase a)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kill the flat-colored-boxes look: real PBR textures on roads/sidewalks/terrain/roofs (world-triplanar — no mesh UVs anywhere), a facade shader v2 with per-category wall textures + believable windows/storefronts, and road geometry upgraded with sidewalks, curbs, and lane markings.

**Architecture:** Pipeline fetches CC0 textures from ambientCG (cached + lock-file pinned) into committed `game/assets/textures/pbr/`; building meshes encode their category in vertex-color alpha; new sidewalk/roadmark geometries join each tile. Game side routes the new geometry names to textured materials (StandardMaterial3D world-triplanar for flat surfaces; upgraded `building_windows.gdshader` for facades).

**Tech Stack:** Python (trimesh, shapely, PIL, urllib), Godot 4.5 shading language.

## Global Constraints

- Commit with plain `git commit` — NEVER pass `--author`, never modify git config, never add any AI trailer. Push ONLY in the final task.
- Repo root: `C:\Users\ayman\OneDrive\Documents\SideProjects\MontrealOpenWorld`; bash syntax from repo root.
- Python: `.venv/Scripts/python -m pytest pipeline -q` green at end of every task (58 now, grows). Determinism: no random/time; ties broken by sorted order. No network in tests.
- Godot ONLY via `tools/godot/godot_console.exe`. Smoke: `--headless --path game --script res://tests/smoke_test.gd` → `PLAYER OK`, `LANDED OK y=0.0`, `CAR OK`, `CARS OK: 120`, `ENTER OK`, `DRIVE OK v=...`, `EXIT OK`, `SMOKE OK: 314 tiles`, clean stderr. The world is NOT rebuilt until the final task — game-side changes must stay green against the OLD committed tiles (facade shader must tolerate vertex alpha 255 = legacy/roof).
- Do NOT delete `data/` caches (OSM + heightmap sha256-pinned in HANDOFF). New texture cache also lives in `data/textures/` — never delete it either.
- Coordinates: x east, z south, y up; road surface = terrain + 0.05; tile 256 m. GDScript uses TABS.
- Vertex colors are authored sRGB — custom shaders must linearize with pow(2.2) (M3.5 lesson).
- Tile budget: `MAX_TILE_TRIS = 120000` (tiler raises if busted). If the final rebuild busts it, raise sidewalk `max_len` densify to 48.0 rather than raising the budget.
- CharacterBody3D cannot climb steps: any raised geometry the player/car must mount needs a ≤40° slope face (curbs use ~33°).

## File Structure

```
pipeline/
├── config.py              # + WALL slot map, SIDEWALK_*, ROADMARK_* constants
├── textures.py            # NEW: ambientCG fetch/cache/lock + zip → game assets
├── meshes.py              # _paint(alpha=), building walls category alpha, sidewalk_mesh, roadmark_mesh
├── tiler.py               # + sidewalks/roadmarks buckets
└── tests/test_textures.py # NEW  (+ additions to test_meshes.py)
game/
├── assets/textures/pbr/   # NEW: committed jpg maps (fetched once by Task 1)
├── shaders/building_windows.gdshader  # v2 rewrite
└── scripts/tile_loader.gd # material table + collision exclusion for roadmarks
```

---

### Task 1: Texture fetch — ambientCG CC0 maps into committed game assets

**Files:**
- Create: `pipeline/textures.py`, `pipeline/tests/test_textures.py`
- Modify: `pipeline/config.py`, `.gitignore` check (data/ already ignored)

**Interfaces:**
- Produces:
  - `config.TEXTURE_SLOTS: dict[str, dict]` — slot → `{"preferred": str, "query": str, "maps": [str]}` where maps ⊆ {"Color","NormalGL","Roughness"}.
  - `textures.ensure_textures(cache_dir="data/textures", out_dir="game/assets/textures/pbr", fetch=None) -> dict` — for each slot: resolve an ambientCG asset id (preferred id, else first API search hit), download `{id}_1K-JPG.zip` (via injected `fetch(url) -> bytes`, default urllib with 30 s timeout + 3 retries), cache zip at `cache_dir/{id}.zip`, sha256-record in `cache_dir/textures.lock.json`, extract requested maps to `out_dir/{slot}_{alb|nrm|rgh}.jpg`. If the cache zip + lock entry exist, NO network is touched. Returns `{slot: id}`.
  - Committed files later tasks rely on (exact names): `brick_alb.jpg`, `stone_alb.jpg`, `concrete_alb.jpg`, `roof_alb.jpg`, `asphalt_alb.jpg`, `asphalt_nrm.jpg`, `asphalt_rgh.jpg`, `paving_alb.jpg`, `paving_nrm.jpg`, `paving_rgh.jpg`, `ground_alb.jpg`, `ground_nrm.jpg`, `ground_rgh.jpg`.

- [ ] **Step 1: Add config** — append to `pipeline/config.py`:

```python
# --- M6a textures (ambientCG, CC0). preferred id first, API search query as fallback. ---
TEXTURE_SLOTS = {
    "brick":    {"preferred": "Bricks075A",       "query": "red brick",        "maps": ["Color"]},
    "stone":    {"preferred": "Bricks059",        "query": "stone bricks wall","maps": ["Color"]},
    "concrete": {"preferred": "Concrete034",      "query": "concrete",         "maps": ["Color"]},
    "roof":     {"preferred": "Gravel022",        "query": "gravel",           "maps": ["Color"]},
    "asphalt":  {"preferred": "Asphalt026",       "query": "asphalt",          "maps": ["Color", "NormalGL", "Roughness"]},
    "paving":   {"preferred": "PavingStones128",  "query": "concrete paving",  "maps": ["Color", "NormalGL", "Roughness"]},
    "ground":   {"preferred": "Ground037",        "query": "dirt ground",      "maps": ["Color", "NormalGL", "Roughness"]},
}
AMBIENTCG_DL = "https://ambientcg.com/get?file={id}_1K-JPG.zip"
AMBIENTCG_API = "https://ambientcg.com/api/v2/full_json?type=Material&include=downloadData&q={q}"
```

- [ ] **Step 2: Write failing tests** — `pipeline/tests/test_textures.py` (all offline; `fetch` is injected):

```python
import io
import json
import zipfile
from pathlib import Path
from pipeline import config
from pipeline.textures import ensure_textures

def _fake_zip(asset_id: str) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for m in ("Color", "NormalGL", "Roughness"):
            z.writestr(f"{asset_id}_1K-JPG_{m}.jpg", b"\xff\xd8\xff fake " + m.encode())
    return buf.getvalue()

def _fetch_ok(url: str) -> bytes:
    for slot, spec in config.TEXTURE_SLOTS.items():
        if spec["preferred"] in url:
            return _fake_zip(spec["preferred"])
    raise AssertionError("unexpected url " + url)

def test_extracts_requested_maps(tmp_path):
    out = tmp_path / "out"
    ids = ensure_textures(cache_dir=tmp_path / "cache", out_dir=out, fetch=_fetch_ok)
    assert ids["asphalt"] == config.TEXTURE_SLOTS["asphalt"]["preferred"]
    assert (out / "asphalt_alb.jpg").exists()
    assert (out / "asphalt_nrm.jpg").exists()
    assert (out / "asphalt_rgh.jpg").exists()
    assert (out / "brick_alb.jpg").exists()
    assert not (out / "brick_nrm.jpg").exists()  # only requested maps extracted

def test_cache_hit_skips_network(tmp_path):
    calls = []
    def counting_fetch(url):
        calls.append(url)
        return _fetch_ok(url)
    ensure_textures(cache_dir=tmp_path / "c", out_dir=tmp_path / "o", fetch=counting_fetch)
    n = len(calls)
    assert n == len(config.TEXTURE_SLOTS)
    def failing_fetch(url):
        raise AssertionError("network touched on cache hit")
    ensure_textures(cache_dir=tmp_path / "c", out_dir=tmp_path / "o2", fetch=failing_fetch)
    assert (tmp_path / "o2" / "asphalt_alb.jpg").exists()

def test_lock_records_sha256(tmp_path):
    ensure_textures(cache_dir=tmp_path / "c", out_dir=tmp_path / "o", fetch=_fetch_ok)
    lock = json.loads((tmp_path / "c" / "textures.lock.json").read_text())
    for slot in config.TEXTURE_SLOTS:
        assert len(lock[slot]["sha256"]) == 64
```

- [ ] **Step 3: Run** — `.venv/Scripts/python -m pytest pipeline/tests/test_textures.py -q` → FAIL (no module).

- [ ] **Step 4: Implement** — `pipeline/textures.py`:

```python
from __future__ import annotations
import hashlib
import json
import time
import urllib.request
import zipfile
from pathlib import Path
from pipeline import config

_MAP_SUFFIX = {"Color": "alb", "NormalGL": "nrm", "Roughness": "rgh"}

def _default_fetch(url: str) -> bytes:
    last: Exception | None = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "mtl-open-ile-pipeline"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001 - retry any transport error
            last = e
            time.sleep(2.0 * (attempt + 1))
    raise RuntimeError(f"download failed after retries: {url}") from last

def _resolve_id(slot: str, spec: dict, fetch) -> str:
    probe = config.AMBIENTCG_DL.format(id=spec["preferred"])
    try:
        head = fetch(probe)
        if head:
            return spec["preferred"]
    except Exception:
        pass
    listing = json.loads(fetch(config.AMBIENTCG_API.format(q=spec["query"].replace(" ", "+"))).decode())
    assets = listing.get("foundAssets", [])
    if not assets:
        raise RuntimeError(f"no ambientCG asset found for slot {slot!r} (query {spec['query']!r})")
    return assets[0]["assetId"]

def ensure_textures(cache_dir="data/textures", out_dir="game/assets/textures/pbr",
                    fetch=None) -> dict[str, str]:
    """Fetch/caches ambientCG 1K-JPG zips and extract the requested maps.

    Cache zip + lock entry present -> no network. `fetch(url) -> bytes` is
    injectable for tests; the probe download doubles as the preferred-id
    existence check, so a cache hit costs zero requests.
    """
    cache = Path(cache_dir)
    out = Path(out_dir)
    cache.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    fetch = fetch or _default_fetch
    lock_path = cache / "textures.lock.json"
    lock: dict = json.loads(lock_path.read_text()) if lock_path.exists() else {}
    ids: dict[str, str] = {}
    for slot, spec in sorted(config.TEXTURE_SLOTS.items()):
        entry = lock.get(slot)
        zpath = cache / f"{entry['id']}.zip" if entry else None
        if entry and zpath.exists() and hashlib.sha256(zpath.read_bytes()).hexdigest() == entry["sha256"]:
            asset_id = entry["id"]
        else:
            asset_id = spec["preferred"]
            try:
                blob = fetch(config.AMBIENTCG_DL.format(id=asset_id))
            except Exception:
                asset_id = _resolve_id(slot, spec, fetch)
                blob = fetch(config.AMBIENTCG_DL.format(id=asset_id))
            zpath = cache / f"{asset_id}.zip"
            zpath.write_bytes(blob)
            lock[slot] = {"id": asset_id, "sha256": hashlib.sha256(blob).hexdigest(),
                          "url": config.AMBIENTCG_DL.format(id=asset_id)}
            lock_path.write_text(json.dumps(lock, indent=1, sort_keys=True))
        ids[slot] = asset_id
        with zipfile.ZipFile(zpath) as z:
            names = z.namelist()
            for m in spec["maps"]:
                match = next((n for n in names if n.endswith(f"_{m}.jpg")), None)
                if match is None:
                    raise RuntimeError(f"{asset_id}: map {m} missing from zip ({names})")
                (out / f"{slot}_{_MAP_SUFFIX[m]}.jpg").write_bytes(z.read(match))
    return ids
```

Note: `_resolve_id`'s probe-then-search means a bad preferred id self-heals via the API. The simple `fetch` contract (bytes or raise) keeps tests trivial.

- [ ] **Step 5: Run** the new tests → PASS; full `pytest pipeline -q` green (61).
- [ ] **Step 6: Fetch for real** — `.venv/Scripts/python -c "from pipeline.textures import ensure_textures; print(ensure_textures())"`. Verify: 13 jpgs in `game/assets/textures/pbr/` each > 20 KB (`ls -la game/assets/textures/pbr`), `data/textures/textures.lock.json` written. Open no browser; if a slot fails after API fallback, STOP and report the slot + error.
- [ ] **Step 7: Commit** — `git add pipeline game/assets && git commit -m "pipeline: fetch CC0 PBR textures from ambientCG with cache and lock"` (data/ is gitignored; assets are committed on purpose — CC0).

---

### Task 2: Category-coded vertex alpha on building walls

**Files:**
- Modify: `pipeline/meshes.py`, `pipeline/tests/test_meshes.py`

**Interfaces:**
- Produces: `_paint(mesh, rgb, factor=1.0, alpha=255)`; `building_mesh` paints WALLS with `alpha = WALL_CATEGORY_ALPHA[cat]` and roofs stay alpha 255. `config.WALL_CATEGORY_ALPHA = {"residential": 0, "commercial": 1, "church": 2, "industrial": 3, "civic": 4, "default": 5}` (append to `pipeline/config.py`). The facade shader (Task 5) reads `int(round(COLOR.a * 255.0))`; 255 (roof caps, gables, legacy tiles) must select the concrete/default path.

- [ ] **Step 1: Write failing test** — append to `pipeline/tests/test_meshes.py`:

```python
def test_building_walls_encode_category_alpha():
    from pipeline.meshes import building_mesh
    from pipeline.osm_parse import Building
    from pipeline import config
    b = Building(1, [(0, 0), (20, 0), (20, 12), (0, 12)], 20.0, "office")
    m = building_mesh(b)
    alphas = set(int(a) for a in m.visual.vertex_colors[:, 3])
    assert config.WALL_CATEGORY_ALPHA["commercial"] in alphas  # walls tagged
    assert 255 in alphas                                       # roof cap untagged
    b2 = Building(2, [(0, 0), (20, 0), (20, 12), (0, 12)], 20.0, "house")
    alphas2 = set(int(a) for a in building_mesh(b2).visual.vertex_colors[:, 3])
    assert config.WALL_CATEGORY_ALPHA["residential"] in alphas2
```

- [ ] **Step 2: Run** → FAIL (`_paint` has no alpha concept; alphas are all 255).

- [ ] **Step 3: Implement** — in `pipeline/config.py` append:

```python
WALL_CATEGORY_ALPHA = {"residential": 0, "commercial": 1, "church": 2,
                       "industrial": 3, "civic": 4, "default": 5}
```

In `pipeline/meshes.py`, change `_paint` to:

```python
def _paint(mesh: trimesh.Trimesh, rgb: tuple, factor: float = 1.0,
           alpha: int = 255) -> trimesh.Trimesh:
    c = np.clip(np.array(rgb, dtype=float) * factor, 0, 255).astype(np.uint8)
    mesh.visual.vertex_colors = np.tile(
        np.array([c[0], c[1], c[2], alpha], dtype=np.uint8), (len(mesh.vertices), 1)
    )
    return mesh
```

and in `building_mesh`, replace the walls line:

```python
    walls = _paint(mesh, building_color(b), _jitter(b.osm_id),
                   alpha=config.WALL_CATEGORY_ALPHA.get(cat, 5))
```

(`cat` is already computed above for the roof choice; roofs/gables keep the default alpha 255.)

- [ ] **Step 4: Run** the test file → PASS; full suite green.
- [ ] **Step 5: Commit** — `git add pipeline && git commit -m "pipeline: encode building category in wall vertex alpha"`

---

### Task 3: Sidewalks with climbable curbs

**Files:**
- Modify: `pipeline/config.py`, `pipeline/meshes.py`, `pipeline/tiler.py`, `pipeline/tests/test_meshes.py`

**Interfaces:**
- Consumes: `Road` (points xz, width, road_class, osm_id, name), `_densify`, drape convention `h = 0.05 + hm.sample`.
- Produces:
  - `config`: `SIDEWALK_CLASSES = ("primary", "secondary", "tertiary", "residential", "unclassified")`, `SIDEWALK_WIDTH = 2.0`, `SIDEWALK_RAISE = 0.12`, `CURB_RUN = 0.18`, `SIDEWALK_END_TRIM = 8.0`, `SIDEWALK_COLOR = (168, 164, 156)`.
  - `meshes.sidewalk_mesh(r, hm=None) -> trimesh.Trimesh | None` — both sides of the road; per centerline sample, each side emits (from road edge outward): curb bottom at road level, curb top (+RAISE, CURB_RUN out — a ~33° climbable face), outer top (+RAISE at road edge + SIDEWALK_WIDTH), outer skirt dropping 0.3 below. First/last `SIDEWALK_END_TRIM` meters of the way are skipped (intersection clearance). ±2 mm deterministic height jitter by osm_id kills coplanar z-fighting where sidewalks overlap. Vertex color `SIDEWALK_COLOR`, alpha 255.
  - Tiler buckets it as geometry name `"sidewalks"` (bucketed by road start point, like roads).

- [ ] **Step 1: Write failing tests** — append to `pipeline/tests/test_meshes.py`:

```python
def _mk_road(cls="residential", width=6.0):
    from pipeline.osm_parse import Road
    return Road(7, "Rue Test", [(0.0, 0.0), (60.0, 0.0)], width, cls)

def test_sidewalk_raised_and_trimmed():
    from pipeline.meshes import sidewalk_mesh
    from pipeline import config
    m = sidewalk_mesh(_mk_road())
    assert m is not None
    xs = m.vertices[:, 0]
    ys = m.vertices[:, 1]
    assert xs.min() >= config.SIDEWALK_END_TRIM - 1e-6          # end trim applied
    assert xs.max() <= 60.0 - config.SIDEWALK_END_TRIM + 1e-6
    top = ys.max()
    assert abs(top - (0.05 + config.SIDEWALK_RAISE)) < 0.01     # raised over road drape
    zs = abs(m.vertices[:, 2])
    assert zs.max() <= 6.0 / 2 + config.CURB_RUN + config.SIDEWALK_WIDTH + 1e-6

def test_sidewalk_skips_short_and_excluded():
    from pipeline.meshes import sidewalk_mesh
    from pipeline.osm_parse import Road
    assert sidewalk_mesh(Road(8, None, [(0, 0), (10, 0)], 6.0, "residential")) is None  # < 2*trim
    assert sidewalk_mesh(Road(9, "x", [(0, 0), (60, 0)], 2.0, "footway")) is None       # class excluded

def test_sidewalk_deterministic():
    from pipeline.meshes import sidewalk_mesh
    a = sidewalk_mesh(_mk_road())
    b = sidewalk_mesh(_mk_road())
    assert (a.vertices == b.vertices).all() and (a.faces == b.faces).all()
```

- [ ] **Step 2: Run** → FAIL (no `sidewalk_mesh`).

- [ ] **Step 3: Implement** — append to `pipeline/config.py`:

```python
# --- M6a sidewalks & road markings ---
SIDEWALK_CLASSES = ("primary", "secondary", "tertiary", "residential", "unclassified")
SIDEWALK_WIDTH = 2.0
SIDEWALK_RAISE = 0.12
CURB_RUN = 0.18            # horizontal run of the curb face (~33 deg -> climbable)
SIDEWALK_END_TRIM = 8.0    # skip near way ends = intersection clearance
SIDEWALK_COLOR = (168, 164, 156)
```

Append to `pipeline/meshes.py`:

```python
def _polyline_slice(points: list[tuple[float, float]], start: float, end: float
                    ) -> list[tuple[float, float]]:
    """Sub-polyline between arclengths [start, end], densified endpoints included."""
    out: list[tuple[float, float]] = []
    acc = 0.0
    for (x1, z1), (x2, z2) in zip(points[:-1], points[1:]):
        seg = math.hypot(x2 - x1, z2 - z1)
        if seg < 1e-9:
            continue
        a0, a1 = acc, acc + seg
        lo, hi = max(a0, start), min(a1, end)
        if lo < hi:
            for t in (lo, hi) if not out else (hi,):
                f = (t - a0) / seg
                out.append((x1 + (x2 - x1) * f, z1 + (z2 - z1) * f))
        acc = a1
    return out

def sidewalk_mesh(r: Road, hm: Heightmap | None = None) -> trimesh.Trimesh | None:
    if r.road_class not in config.SIDEWALK_CLASSES or r.width <= 0:
        return None
    line = LineString(r.points)
    usable = line.length - 2 * config.SIDEWALK_END_TRIM
    if usable < 4.0:
        return None
    pts = _densify(_polyline_slice(r.points, config.SIDEWALK_END_TRIM,
                                   line.length - config.SIDEWALK_END_TRIM))
    jitter = ((r.osm_id * 2654435761) % 5 - 2) * 0.001  # -2..+2 mm
    def h(x: float, z: float) -> float:
        return 0.05 + jitter + (hm.sample(x, z) if hm is not None else 0.0)
    hw = r.width / 2.0
    raise_y = config.SIDEWALK_RAISE
    verts, faces = [], []
    for side in (1.0, -1.0):
        for (x1, z1), (x2, z2) in zip(pts[:-1], pts[1:]):
            d = np.array([x2 - x1, z2 - z1])
            n = np.linalg.norm(d)
            if n < 1e-6:
                continue
            px, pz = side * -d[1] / n, side * d[0] / n
            i = len(verts)
            for (x, z) in ((x1, z1), (x2, z2)):
                y = h(x, z)
                verts += [
                    [x + px * hw, y, z + pz * hw],                                            # 0 curb bottom
                    [x + px * (hw + config.CURB_RUN), y + raise_y, z + pz * (hw + config.CURB_RUN)],  # 1 curb top
                    [x + px * (hw + config.CURB_RUN + config.SIDEWALK_WIDTH), y + raise_y,
                     z + pz * (hw + config.CURB_RUN + config.SIDEWALK_WIDTH)],                # 2 outer top
                    [x + px * (hw + config.CURB_RUN + config.SIDEWALK_WIDTH), y - 0.3,
                     z + pz * (hw + config.CURB_RUN + config.SIDEWALK_WIDTH)],                # 3 outer skirt
                ]
            for k in range(3):
                a, b = i + k, i + 4 + k
                if side > 0:
                    faces += [[a, b, a + 1], [a + 1, b, b + 1]]
                else:
                    faces += [[a, a + 1, b], [a + 1, b + 1, b]]
    if not faces:
        return None
    mesh = trimesh.Trimesh(vertices=np.array(verts), faces=np.array(faces), process=False)
    return _paint(mesh, config.SIDEWALK_COLOR)
```

In `pipeline/tiler.py`: import `sidewalk_mesh` (extend the existing meshes import), then after the road loop add:

```python
    for r in city.roads:
        m = sidewalk_mesh(r, hm)
        if m is not None:
            buckets[assign_tile(*r.points[0])]["sidewalks"].append(m)
```

and extend the category tuple in the scene-assembly loop to `("buildings", "roads", "sidewalks", "roadmarks", "water", "green", "props")` (roadmarks arrives Task 4; an always-empty bucket is harmless).

- [ ] **Step 4: Run** the new tests → PASS; full suite green. Face winding sanity: `python -c` snippet checking top-face normals point +y on side 1: already covered visually at Task 6; the winding above mirrors the road ribbon convention.
- [ ] **Step 5: Commit** — `git add pipeline && git commit -m "pipeline: sidewalks with climbable curbs along vehicle roads"`

---

### Task 4: Lane markings

**Files:**
- Modify: `pipeline/config.py`, `pipeline/meshes.py`, `pipeline/tiler.py`, `pipeline/tests/test_meshes.py`

**Interfaces:**
- Consumes: `_polyline_slice` (Task 3), drape convention.
- Produces:
  - `config`: `ROADMARK_CLASSES = ("primary", "secondary", "tertiary", "residential")`, `EDGE_LINE_CLASSES = ("primary", "secondary")`, `MARK_DASH = 3.0`, `MARK_PERIOD = 9.0`, `MARK_WIDTH = 0.15`, `MARK_LIFT = 0.02`, `MARK_YELLOW = (196, 164, 48)`, `MARK_WHITE = (208, 208, 204)`.
  - `meshes.roadmark_mesh(r, hm=None) -> trimesh.Trimesh | None` — named roads in `ROADMARK_CLASSES`: yellow dashed centerline (dash `MARK_DASH` every `MARK_PERIOD`); `EDGE_LINE_CLASSES` additionally get continuous white edge lines at ±(halfwidth − 0.45). All quads at road drape + `MARK_LIFT`, trimmed `SIDEWALK_END_TRIM` from ends. Geometry name `"roadmarks"` in tiles; excluded from game collision (Task 5).

- [ ] **Step 1: Write failing tests** — append to `pipeline/tests/test_meshes.py`:

```python
def test_roadmarks_dashed_centerline():
    from pipeline.meshes import roadmark_mesh
    from pipeline import config
    m = roadmark_mesh(_mk_road())          # residential: centerline only
    assert m is not None
    assert len(m.faces) % 2 == 0
    n_dashes = len(m.faces) // 2
    usable = 60.0 - 2 * config.SIDEWALK_END_TRIM
    assert 1 <= n_dashes <= int(usable / config.MARK_PERIOD) + 1
    assert abs(m.vertices[:, 1].max() - (0.05 + config.MARK_LIFT)) < 0.005
    assert abs(m.vertices[:, 2]).max() <= config.MARK_WIDTH / 2 + 1e-6

def test_roadmarks_edge_lines_on_primary():
    from pipeline.meshes import roadmark_mesh
    m_res = roadmark_mesh(_mk_road("residential"))
    m_pri = roadmark_mesh(_mk_road("primary", width=10.0))
    assert len(m_pri.faces) > len(m_res.faces)          # edge lines added
    assert abs(m_pri.vertices[:, 2]).max() > 4.0        # near ±(5.0 - 0.45)

def test_roadmarks_skip_unnamed_and_footways():
    from pipeline.meshes import roadmark_mesh
    from pipeline.osm_parse import Road
    assert roadmark_mesh(Road(1, None, [(0, 0), (60, 0)], 6.0, "residential")) is None
    assert roadmark_mesh(Road(2, "x", [(0, 0), (60, 0)], 2.0, "footway")) is None
```

- [ ] **Step 2: Run** → FAIL (no `roadmark_mesh`).

- [ ] **Step 3: Implement** — append to `pipeline/config.py`:

```python
ROADMARK_CLASSES = ("primary", "secondary", "tertiary", "residential")
EDGE_LINE_CLASSES = ("primary", "secondary")
MARK_DASH = 3.0
MARK_PERIOD = 9.0
MARK_WIDTH = 0.15
MARK_LIFT = 0.02
MARK_YELLOW = (196, 164, 48)
MARK_WHITE = (208, 208, 204)
```

Append to `pipeline/meshes.py`:

```python
def _strip_quads(pts: list[tuple[float, float]], offset: float, width: float,
                 h, verts: list, faces: list) -> None:
    """Constant-lateral-offset ribbon of quads along pts (offset 0 = centerline)."""
    for (x1, z1), (x2, z2) in zip(pts[:-1], pts[1:]):
        d = np.array([x2 - x1, z2 - z1])
        n = np.linalg.norm(d)
        if n < 1e-6:
            continue
        px, pz = -d[1] / n, d[0] / n
        hw = width / 2.0
        i = len(verts)
        for (x, z) in ((x1, z1), (x2, z2)):
            y = h(x, z)
            cx, cz = x + px * offset, z + pz * offset
            verts += [[cx + px * hw, y, cz + pz * hw], [cx - px * hw, y, cz - pz * hw]]
        faces += [[i, i + 2, i + 1], [i + 1, i + 2, i + 3]]

def roadmark_mesh(r: Road, hm: Heightmap | None = None) -> trimesh.Trimesh | None:
    if r.road_class not in config.ROADMARK_CLASSES or not r.name:
        return None
    line = LineString(r.points)
    lo, hi = config.SIDEWALK_END_TRIM, line.length - config.SIDEWALK_END_TRIM
    if hi - lo < config.MARK_DASH:
        return None
    def h(x: float, z: float) -> float:
        return 0.05 + config.MARK_LIFT + (hm.sample(x, z) if hm is not None else 0.0)
    parts = []
    # yellow dashed centerline
    verts, faces = [], []
    t = lo
    while t + config.MARK_DASH <= hi:
        seg = _polyline_slice(r.points, t, t + config.MARK_DASH)
        if len(seg) >= 2:
            _strip_quads(_densify(seg), 0.0, config.MARK_WIDTH, h, verts, faces)
        t += config.MARK_PERIOD
    if faces:
        parts.append(_paint(trimesh.Trimesh(vertices=np.array(verts), faces=np.array(faces),
                                            process=False), config.MARK_YELLOW))
    # white edge lines on arterials
    if r.road_class in config.EDGE_LINE_CLASSES:
        everts, efaces = [], []
        span = _densify(_polyline_slice(r.points, lo, hi))
        if len(span) >= 2:
            off = r.width / 2.0 - 0.45
            _strip_quads(span, off, 0.10, h, everts, efaces)
            _strip_quads(span, -off, 0.10, h, everts, efaces)
        if efaces:
            parts.append(_paint(trimesh.Trimesh(vertices=np.array(everts),
                                                faces=np.array(efaces), process=False),
                                config.MARK_WHITE))
    if not parts:
        return None
    return trimesh.util.concatenate(parts)
```

In `pipeline/tiler.py`, extend the meshes import with `roadmark_mesh` and add after the sidewalk loop:

```python
    for r in city.roads:
        m = roadmark_mesh(r, hm)
        if m is not None:
            buckets[assign_tile(*r.points[0])]["roadmarks"].append(m)
```

(The `"roadmarks"` category was already added to the assembly tuple in Task 3.)

- [ ] **Step 4: Run** the new tests → PASS; full suite green.
- [ ] **Step 5: Commit** — `git add pipeline && git commit -m "pipeline: dashed centerlines and arterial edge lines"`

---

### Task 5: Facade shader v2 + textured materials in the tile loader

**Files:**
- Modify: `game/shaders/building_windows.gdshader` (full rewrite), `game/scripts/tile_loader.gd`

**Interfaces:**
- Consumes: committed textures `res://assets/textures/pbr/{brick,stone,concrete,roof}_alb.jpg` and `{asphalt,paving,ground}_{alb,nrm,rgh}.jpg` (Task 1); wall alpha categories 0..5, roofs/legacy 255 (Task 2); geometry names `sidewalks`/`roadmarks` (Tasks 3–4 — not yet in the committed world; routing must be a no-op until the Task 6 rebuild).
- Produces: shader with uniforms `brick_tex, stone_tex, concrete_tex, roof_tex`; `tile_loader.gd` material table: buildings→shader (textures assigned in script), roads→triplanar asphalt, sidewalks→triplanar paving, terrain→triplanar ground, roadmarks→plain vertex-color material; `roadmark` prefix added to the collision exclusion list. MUST stay green on the OLD world (alpha 255 walls fall through to the concrete path; missing geometry names simply never match).

- [ ] **Step 1: Rewrite** `game/shaders/building_windows.gdshader`:

```glsl
shader_type spatial;
render_mode cull_back;

global uniform float night_amount;

uniform sampler2D brick_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D concrete_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D roof_tex : source_color, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;
varying vec3 wnormal;
varying vec4 vcol;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

// two-axis world triplanar for near-vertical surfaces
vec3 tri_wall(sampler2D tex, vec3 p, vec3 n, float s) {
	float wx = abs(n.x);
	float wz = abs(n.z);
	vec3 tx = texture(tex, p.zy * s).rgb;
	vec3 tz = texture(tex, p.xy * s).rgb;
	return (tx * wx + tz * wz) / max(wx + wz, 1e-4);
}

void fragment() {
	// tile vertex colors are authored sRGB; COLOR arrives raw, so linearize
	vec3 tint = pow(vcol.rgb, vec3(2.2));
	int cat = int(round(vcol.a * 255.0));
	float roofness = smoothstep(0.45, 0.6, wnormal.y);   // caps + gables; walls ~0

	// sample everything unconditionally (texture() inside branches breaks mips)
	float ws = 0.22;   // wall texture world scale (~4.5 m period)
	vec3 brick = tri_wall(brick_tex, wpos, wnormal, ws);
	vec3 stone = tri_wall(stone_tex, wpos, wnormal, ws);
	vec3 concr = tri_wall(concrete_tex, wpos, wnormal, ws);
	vec3 rooft = texture(roof_tex, wpos.xz * 0.10).rgb;

	float w_brick = (cat == 0) ? 1.0 : 0.0;
	float w_stone = (cat == 2 || cat == 4) ? 1.0 : 0.0;
	float w_concr = 1.0 - min(w_brick + w_stone, 1.0);   // com/ind/default/legacy
	vec3 wall_tex = brick * w_brick + stone * w_stone + concr * w_concr;
	vec3 base = wall_tex * tint * 2.1;                   // tint is mid-dark; renormalize

	// --- window grid v2 (world-space, like v1) ---
	float vertical = 1.0 - smoothstep(0.25, 0.4, abs(wnormal.y));
	float u = abs(wnormal.x) > abs(wnormal.z) ? wpos.z : wpos.x;
	float v = wpos.y;
	float cw = (cat == 1) ? 2.4 : 3.6;                   // commercial mullions are finer
	vec2 cell = vec2(floor(u / cw), floor(v / 3.2));
	vec2 f = vec2(fract(u / cw), fract(v / 3.2));
	float floor_idx = floor(v / 3.2);

	vec2 lo = (cat == 1) ? vec2(0.08, 0.12) : vec2(0.26, 0.32);
	vec2 hi = (cat == 1) ? vec2(0.92, 0.90) : vec2(0.74, 0.84);
	float storefront = (floor_idx == 0.0 && (cat == 0 || cat == 1 || cat == 5)) ? 1.0 : 0.0;
	lo = mix(lo, vec2(0.06, 0.05), storefront);
	hi = mix(hi, vec2(0.94, 0.72), storefront);

	float inwin = step(lo.x, f.x) * step(f.x, hi.x) * step(lo.y, f.y) * step(f.y, hi.y) * vertical;
	vec2 fb = vec2(0.045, 0.05);
	float inner = step(lo.x + fb.x, f.x) * step(f.x, hi.x - fb.x)
			* step(lo.y + fb.y, f.y) * step(f.y, hi.y - fb.y) * vertical;
	float frame = inwin - inner;
	float sill = step(lo.y - 0.06, f.y) * step(f.y, lo.y)
			* step(lo.x, f.x) * step(f.x, hi.x) * vertical * (1.0 - storefront);

	// inset illusion: glass darkens toward the top of the aperture (fake overhang)
	float glass_grad = mix(0.85, 0.35, smoothstep(lo.y, hi.y, f.y));
	vec3 glass = mix(vec3(0.30, 0.36, 0.42), vec3(0.15, 0.17, 0.19) + tint * 0.08, storefront)
			* glass_grad;

	vec3 col = base;
	col = mix(col, base * 0.5, frame);
	col = mix(col, glass, inner);
	col = mix(col, base * 1.3 + vec3(0.03), sill);
	col = mix(col, rooft * tint * 2.4, roofness);

	ALBEDO = col;
	ROUGHNESS = mix(mix(0.92, 0.18, inner), 0.95, roofness);
	METALLIC = inner * 0.2 * (1.0 - roofness);

	float lit = step(0.62, hash21(cell));
	float night = smoothstep(0.45, 0.9, night_amount);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float glow = max(lit, storefront * 0.9);
	EMISSION = vec3(1.0, 0.72, 0.35)
			* (inner * glow * night * 1.6 * (0.2 + 0.8 * facing) * (1.0 - roofness));
}
```

- [ ] **Step 2: Material table** — in `game/scripts/tile_loader.gd`, replace the material construction and routing:

```gdscript
var _city_mat := _make_city_material()
var _building_mat := _make_building_material()
var _water_mat := _make_shader_material("res://shaders/water.gdshader")
var _road_mat := _make_triplanar_material("asphalt", 0.08, 2.0)
var _sidewalk_mat := _make_triplanar_material("paving", 0.30, 1.6)
var _terrain_mat := _make_triplanar_material("ground", 0.06, 2.0)
var _marks_mat := _make_marks_material()

static func _make_building_material() -> ShaderMaterial:
	var m := _make_shader_material("res://shaders/building_windows.gdshader")
	if m == null:
		return null
	for slot in ["brick", "stone", "concrete", "roof"]:
		var path := "res://assets/textures/pbr/%s_alb.jpg" % slot
		if ResourceLoader.exists(path):
			m.set_shader_parameter(slot + "_tex", load(path))
	return m

static func _make_triplanar_material(slot: String, uv_scale: float, brighten: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(brighten, brighten, brighten)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(uv_scale, uv_scale, uv_scale)
	var alb := "res://assets/textures/pbr/%s_alb.jpg" % slot
	if ResourceLoader.exists(alb):
		m.albedo_texture = load(alb)
	var nrm := "res://assets/textures/pbr/%s_nrm.jpg" % slot
	if ResourceLoader.exists(nrm):
		m.normal_enabled = true
		m.normal_texture = load(nrm)
	var rgh := "res://assets/textures/pbr/%s_rgh.jpg" % slot
	if ResourceLoader.exists(rgh):
		m.roughness_texture = load(rgh)
	return m

static func _make_marks_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.albedo_color = Color(1.4, 1.4, 1.4)
	m.roughness = 0.55
	return m
```

and route in `_apply_city_material` (order matters — check the more specific `roadmarks` before `roads`):

```gdscript
		if _building_mat != null and n.begins_with("buildings"):
			inst.material_override = _building_mat
		elif _water_mat != null and n.begins_with("water"):
			inst.material_override = _water_mat
		elif n.begins_with("roadmarks"):
			inst.material_override = _marks_mat
		elif n.begins_with("roads"):
			inst.material_override = _road_mat
		elif n.begins_with("sidewalks"):
			inst.material_override = _sidewalk_mat
		elif n.begins_with("terrain"):
			inst.material_override = _terrain_mat
		else:
			inst.material_override = _city_mat
```

and in `_build_collision`, extend the exclusion:

```gdscript
			if n.begins_with("water") or n.begins_with("props") or n.begins_with("roadmarks"):
				continue
```

- [ ] **Step 3: Smoke on the OLD world** — full OK sequence unchanged (`SMOKE OK: 314 tiles`), clean stderr (shader compiles headless; alpha-255 walls hit the concrete path; sidewalks/roadmarks names don't exist yet so routing is inert).
- [ ] **Step 4: Commit** — `git add game && git commit -m "game: facade shader v2 and triplanar textured materials"`

---

### Task 6: Rebuild, screenshot review loop, docs, tag, push — controller-led

**Files:**
- Modify: `game/world/*` (rebuild), `docs/superpowers/HANDOFF.md`, `README.md`; possibly shader/material tuning constants from the review loop.

- [ ] **Step 1: Rebuild** — `.venv/Scripts/python -m pipeline.build` (OSM + heightmap caches hit; tiles CHANGE this time — new geometries + wall alphas). Watch for `MAX_TILE_TRIS` errors; if a tile busts, bump sidewalk `_densify` max_len to 48.0 (meshes.sidewalk_mesh) and rebuild. Then `tools/godot/godot_console.exe --headless --path game --import` (minutes), then the smoke test → full OK sequence, `SMOKE OK: 314 tiles`.
- [ ] **Step 2: Capture** — `tools/godot/godot_console.exe --path game --script res://tests/screenshot.gd`; READ every PNG. Checklist: brick/stone/concrete texture visible on facades (not flat color), windows have frames + darker inset glass, ground-floor storefronts read as storefronts, roofs textured, roads show asphalt grain + yellow dashes, sidewalks with curbs line the streets, terrain has ground texture, night shots keep glowing windows + storefronts, driving shots still correct (car on road, speedometer). Verify no z-fighting shimmer between marks/sidewalks/roads at grazing angles.
- [ ] **Step 3: Tuning loop** — iterate shader constants (tint renormalizers ×2.1/×2.4, texture scales, window aperture, storefront glass) and material brighten factors from screenshots; expect 2–4 rounds like M3.5. Structural failures (player falls through sidewalk, car stuck on curb, budget bust that survives the densify fix) — STOP and report.
- [ ] **Step 4: Verify gameplay collision** — smoke green after rebuild (already run in Step 1; re-run after any pipeline tweak). The DRIVE test now runs on a road with a curb to its right — if the car wedges on the curb, the spawn offset (side = width/2 − 1.1) needs to shrink by CURB_RUN; report if so.
- [ ] **Step 5: Docs** — copy keepers to `docs/screenshots/m6a_*.png` (day street, night street, driving, overview); README: swap the top screenshot row to m6a shots, update the M6 roadmap line to `- [x] **M6a** — Surfaces: real textures, sidewalks & curbs, lane markings, facade shader v2`; HANDOFF: state → `m6a-surfaces` (tile count, new smoke unchanged, geometry names, alpha encoding, texture lock file), carry-forwards updated.
- [ ] **Step 6: Full verification** — pytest green, smoke green, `git status` clean after staging.
- [ ] **Step 7: Ship** — `git add -A && git commit -m "world: M6a surfaces rebuild, screenshots and handoff"`, `git tag m6a-surfaces`, `git push origin main --tags`.

---

## Self-Review Notes

- Spec coverage: triplanar textures ✓ (T1 fetch, T5 materials), category alpha ✓ (T2), window grid v2 + storefronts + roof branch ✓ (T5 shader), sidewalks + climbable curbs ✓ (T3, 33° = atan(0.12/0.18) ≈ 33.7° < 45° floor_max_angle), markings ✓ (T4), no mesh UVs anywhere ✓, lock-file texture pinning ✓ (T1), budget guard ✓ (T6 + tiler raise). Crosswalks = stretch goal, correctly absent.
- Type consistency: geometry names `sidewalks`/`roadmarks` (T3/T4 tiler) ↔ routing prefixes (T5); texture filenames `{slot}_{alb,nrm,rgh}.jpg` (T1) ↔ loader paths (T5); `WALL_CATEGORY_ALPHA` values (T2) ↔ shader cat weights (T5: 0 brick, 2/4 stone, else concrete — incl. 255 legacy); `_polyline_slice` defined T3, consumed T4.
- Ordering: T5 must stay green on the old world (verified by its Step 3 gate); the world only changes in T6 after all pipeline tasks landed. T4 reuses T3's `_polyline_slice` and the tiler category tuple added in T3.
- Known risks: winding on side<0 sidewalk faces (mirrored explicitly; screenshot review catches inversions as black faces), texture(…) in varying control flow avoided by unconditional sampling, marks z-fight (LIFT 0.02 + review), curb vs car-spawn offset interplay (explicit T6 Step 4 check), ambientCG preferred-id drift (self-heals via API fallback + lock).
