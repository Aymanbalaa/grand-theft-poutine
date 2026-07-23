# M9b — Street Detail Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Intersections that read as real streets (crosswalk zebras + stop bars from the existing junction data), manhole decals along roads (the long-deferred decal infrastructure via Godot `Decal` nodes), and doors on residential ground floors.

**Architecture:** Crosswalks ride the existing `roadmarks` bucket — `roadmark_mesh` already receives the tiler's junction frozenset and `_clear_intervals` already stops marks short of junctions, so zebra/stop-bar quads are emitted at clear-interval boundaries that abut junctions using the same `_polyline_slice` + `_strip_quads` helpers. Manholes are a metadata position list (cars.py sampling pattern) rendered by a pooled-Decal script (light_pool pattern — never one node per manhole). The decal texture comes from ambientCG's CC0 Decal category through the existing slot mechanism, extended with a PNG-format option and an alpha-composite step (Decal albedo needs RGBA). Doors are a facade-shader addition seeded by the existing per-building RGB hash.

**Tech Stack:** Python pipeline (trimesh, PIL, pytest, TDD), Godot 4.5 (Decal nodes, gdshader), ambientCG CC0.

## Global Constraints

- Commits authored ONLY by Aymanbalaa via repo-local git config. NO `Co-Authored-By`/AI trailers, NO `--author` flags, NO git-config changes. Repeat verbatim in every subagent dispatch.
- Commit small and frequent; one commit per task minimum.
- Deterministic pipeline: NO network in `pipeline.build`; texture fetches only via manual `ensure_textures` (+ lock, gitignored, disk-only).
- Rebuild rules: 314 tiles expected, orphan check (`git status --short game/world/`), `--headless --path game --import` after tile/texture changes.
- Vertex-alpha packing, `night_amount`, seed-from-RGB (facade `bhash`) contracts all untouched.
- Decals must be POOLED (fixed node count recycled near the camera) — never one resident node per world manhole.
- Headless smoke gains one gate this phase (Task 4) → 18 gates ending `SMOKE OK: 314 tiles`.
- pytest: currently 92 → ends 97 (5 new).
- Night regression fails the phase; screenshots judged only by Reading PNGs.
- License: ambientCG CC0 (already credited); new asset IDs recorded in the lock.

---

### Task 1: Crosswalks + stop bars (pipeline roadmarks)

**Files:**
- Modify: `pipeline/meshes.py:266-301` (`roadmark_mesh`)
- Modify: `pipeline/config.py` (constants near the MARK_* group)
- Test: `pipeline/tests/test_meshes.py`

**Interfaces:**
- Consumes: existing `junctions` frozenset parameter (already passed by tiler.py:55), `_clear_intervals`, `_polyline_slice`, `_densify`, `_strip_quads`, `_paint`, `config.MARK_WHITE`.
- Produces: extra white quads in the same returned roadmarks mesh — no new buckets, no game-side change.

- [ ] **Step 1: Write the failing tests**

Append to `pipeline/tests/test_meshes.py` (reuse the road fixture style of `test_roadmarks_dashed_centerline`; construct a straight 3-point road whose MIDDLE vertex is the junction):

```python
def test_crosswalks_at_junctions():
    # straight road with a junction at its middle vertex
    r = <Road fixture like test_roadmarks_dashed_centerline but points
         [(0,0), (60,0), (120,0)], eligible class, named, width 8.0>
    junctions = frozenset({(60.0, 0.0)})
    plain = roadmark_mesh(r, hm=None, junctions=frozenset())
    marked = roadmark_mesh(r, hm=None, junctions=junctions)
    # crosswalk + stop bars add faces beyond the (junction-shortened) centerline
    assert len(marked.faces) > len(plain.faces) * 0.5
    # white bars exist near the junction (within CROSSWALK zone of x=60)
    whites = marked.visual.vertex_colors[:, :3]
    near = marked.vertices[np.abs(marked.vertices[:, 0] - 60.0) < 8.0]
    assert len(near) >= 8  # at least stop bar + zebra bars on each side

def test_no_crosswalks_without_junctions():
    r = <same fixture>
    m = roadmark_mesh(r, hm=None, junctions=frozenset())
    # without junctions, no vertices cluster inside the crosswalk inset zone
    # beyond what the centerline dashes produce — assert face count unchanged
    # across two calls (determinism) and record it as the plain baseline
    assert len(m.faces) == len(roadmark_mesh(r, hm=None, junctions=frozenset()).faces)
```

(`<...>` = copy the named fixture's construction verbatim, adjusting only the listed fields. Tighten the assertions to concrete numbers once the geometry is implemented — the final committed test must assert exact expected bar counts, not just inequalities; compute them from the constants below.)

- [ ] **Step 2: Run, verify failure** (no extra faces near junction).

- [ ] **Step 3: Constants** in `pipeline/config.py` next to the MARK_* group:

```python
CROSSWALK_BARS = 4       # zebra bars per crossing
CROSSWALK_BAR = 0.45     # along-road length of each bar (m)
CROSSWALK_GAP = 0.45     # gap between bars (m)
CROSSWALK_INSET = 1.5    # first bar starts this far inside the clear interval (m)
STOPBAR_LEN = 0.4        # stop line along-road length (m)
STOPBAR_INSET = 0.4      # stop line offset inside the clear interval (m)
CROSSWALK_MIN_INTERVAL = 8.0   # skip crossings on shorter clear intervals
```

- [ ] **Step 4: Implement** in `roadmark_mesh`, after the edge-lines block, before assembling `parts` into the final mesh — add a crosswalk part:

```python
    # crosswalks + stop bars at clear-interval boundaries that abut junctions.
    # way-end boundaries sit exactly at SIDEWALK_END_TRIM / L - SIDEWALK_END_TRIM;
    # interior boundaries are junction-caused.
    L = sum(math.hypot(x2 - x1, z2 - z1)
            for (x1, z1), (x2, z2) in zip(r.points[:-1], r.points[1:]))
    trim = config.SIDEWALK_END_TRIM
    cverts, cfaces = [], []
    bw = r.width * 0.85

    def _bars(start: float, direction: float) -> None:
        # stop bar, then zebra, marching `direction` (+1 into the interval from lo,
        # -1 into the interval from hi)
        s0 = start + direction * config.STOPBAR_INSET
        seg = _polyline_slice(r.points, min(s0, s0 + direction * config.STOPBAR_LEN),
                              max(s0, s0 + direction * config.STOPBAR_LEN))
        if len(seg) >= 2:
            _strip_quads(_densify(seg), 0.0, bw, h, cverts, cfaces)
        z0 = start + direction * config.CROSSWALK_INSET
        step = config.CROSSWALK_BAR + config.CROSSWALK_GAP
        for k in range(config.CROSSWALK_BARS):
            a = z0 + direction * k * step
            b = a + direction * config.CROSSWALK_BAR
            seg = _polyline_slice(r.points, min(a, b), max(a, b))
            if len(seg) >= 2:
                _strip_quads(_densify(seg), 0.0, bw, h, cverts, cfaces)

    for lo, hi in intervals:
        if hi - lo < config.CROSSWALK_MIN_INTERVAL:
            continue
        if lo > trim + 0.01:          # boundary at lo abuts a junction
            _bars(lo, 1.0)
        if hi < L - trim - 0.01:      # boundary at hi abuts a junction
            _bars(hi, -1.0)
    if cfaces:
        parts.append(_paint(trimesh.Trimesh(vertices=np.array(cverts),
                                            faces=np.array(cfaces), process=False),
                            config.MARK_WHITE))
```

(Match how the existing `parts` list is finally concatenated/returned — read the function tail and slot this in before it. `h` is the function's existing height closure.)

- [ ] **Step 5: Finalize test numbers** (exact face/bar counts from the constants), run the meshes test file, then full pytest → 94 passed (92 + 2).

- [ ] **Step 6: Commit**

```bash
git add pipeline/meshes.py pipeline/config.py pipeline/tests/test_meshes.py
git commit -m "pipeline: crosswalk zebras + stop bars at junction-abutting roadmark boundaries"
```

---

### Task 2: Manhole positions + decal texture slot (pipeline)

**Files:**
- Create: `pipeline/decals.py`
- Modify: `pipeline/export.py` (metadata key `manholes`), `pipeline/config.py` (constants + decal slot), `pipeline/textures.py` (PNG format + alpha-composite support)
- Test: `pipeline/tests/test_decals.py` (new), `pipeline/tests/test_textures.py`
- Created by fetch: `game/assets/textures/decals/manhole_alb.png` (RGBA)

**Interfaces:**
- Produces: `city_metadata.json["manholes"]` = `[[x,y,z],...]` (lamps shape); `game/assets/textures/decals/manhole_alb.png` — Task 4 loads it by exactly this path.

- [ ] **Step 1: Failing tests.**

`pipeline/tests/test_decals.py` (mirror test_cars.py's fixture style):

```python
def test_manholes_sampled_along_named_roads():
    roads = <same road-list fixture style as pipeline/tests/test_cars.py>
    holes = manhole_spots(roads, hm=None)
    assert len(holes) >= 1
    assert all(set(h) == {"x", "y", "z"} for h in holes)  # dicts, rounded floats
def test_manholes_deterministic():
    roads = <same>
    assert manhole_spots(roads, hm=None) == manhole_spots(roads, hm=None)
```

`pipeline/tests/test_textures.py`:

```python
def test_png_slot_with_opacity_composites_rgba(tmp_path):
    # the decal slot requests PNG format with Color+Opacity and compose_alpha;
    # ensure_textures must emit {slot}_alb.png with an alpha channel
    out = tmp_path / "out"
    ensure_textures(cache_dir=tmp_path / "cache", out_dir=out, fetch=_fetch_ok)
    from PIL import Image
    img = Image.open(out / "manhole_alb.png")
    assert img.mode == "RGBA"
```

(Extend `_fetch_ok` to serve a PNG-variant zip containing tiny Color + Opacity images for the manhole slot — mirror how it fabricates JPG zips today.)

- [ ] **Step 2: Run, verify failures.**

- [ ] **Step 3: Implement.**

`pipeline/config.py`:

```python
MANHOLE_SPACING = 57.0    # m along-road; off-sync with dash period
MANHOLE_RADIUS = 900.0    # only near downtown, like car spawns
MAX_MANHOLES = 600
```

and a new slot in `TEXTURE_SLOTS`:

```python
    "manhole": {"preferred": "Manhole001", "query": "manhole", "maps": ["Color", "Opacity"],
                "fmt": "PNG", "compose_alpha": True, "out_subdir": "decals"},
```

`pipeline/textures.py`:
- DL template gains format: replace the literal `-JPG.zip` handling so the url uses `spec.get("fmt", "JPG")` (i.e. `{id}_{res}-{fmt}.zip`); cache filename + lock entry include fmt like they do res.
- `_MAP_SUFFIX` gains `"Opacity": "op"`; extracted files keep the source extension (png stays png).
- `compose_alpha` slots: after extraction, open Color + Opacity with PIL, build RGBA (Opacity's single channel → A), save `{slot}_alb.png`, delete the intermediate `_op` file. `out_subdir` routes output to `out_dir/../decals`? NO — keep it simple and explicit: `out_subdir` means the slot writes into `game/assets/textures/{out_subdir}/` instead of the default pbr dir; implement by joining `out_dir.parent / spec["out_subdir"]` ONLY if `out_dir` is the default; in tests (custom out_dir) write into `out_dir` directly so the test above stays simple. If this dual behavior reads too clever, drop `out_subdir` and write to the standard pbr dir with path `game/assets/textures/pbr/manhole_alb.png` — then Task 4 loads THAT path instead; state clearly in your report which you did.

`pipeline/decals.py` (mirror cars.py structure):

```python
from __future__ import annotations
import math
from pipeline import config

def manhole_spots(roads, hm=None) -> list[dict]:
    """Deterministic manhole positions: sampled along named roads, alternating
    lane offset, capped by radius and count. Mirrors cars.car_spawns."""
    spots: list[dict] = []
    eligible = (r for r in roads
                if r.name and r.road_class in config.CAR_SPAWN_CLASSES)
    for r in sorted(eligible, key=lambda r: (r.name, r.osm_id)):
        lane = r.width / 4.0
        carry = config.MANHOLE_SPACING / 2.0
        for (x1, z1), (x2, z2) in zip(r.points[:-1], r.points[1:]):
            seg = math.hypot(x2 - x1, z2 - z1)
            if seg < 1e-6:
                continue
            dx, dz = (x2 - x1) / seg, (z2 - z1) / seg
            t = carry
            while t < seg:
                x, z = x1 + dx * t, z1 + dz * t
                t += config.MANHOLE_SPACING
                if math.hypot(x, z) > config.MANHOLE_RADIUS:
                    continue
                side = lane if (len(spots) % 2 == 0) else -lane
                sx, sz = x - dz * side, z + dx * side
                y = (hm.sample(sx, sz) if hm is not None else 0.0)
                spots.append({"x": round(sx, 2), "y": round(y, 2), "z": round(sz, 2)})
                if len(spots) >= config.MAX_MANHOLES:
                    return spots
            carry = t - seg
    return spots
```

`pipeline/export.py`: next to the other metadata keys add `"manholes": [[s["x"], s["y"], s["z"]] for s in manhole_spots(city.roads, hm=hm)]` (import at top, matching how car_spawns is wired — read that wiring and mirror it exactly).

- [ ] **Step 4: Full pytest** → 97 passed (94 + 3).

- [ ] **Step 5: Fetch the real decal (network allowed — manual path).** Run ensure_textures; if `Manhole001` doesn't exist on ambientCG the query fallback engages; LOOK at the resulting PNG (Read tool): it must read as a round metal manhole cover with transparent surroundings. If ambientCG has no CC0 manhole decal at all, STOP and report BLOCKED with what the API returned — do not substitute a non-CC0 source.

- [ ] **Step 6: Godot import** (`--headless --path game --import`; no `.import` commits).

- [ ] **Step 7: Commit** (code + tests + the fetched PNG; lock stays disk-only).

```bash
git add pipeline/decals.py pipeline/export.py pipeline/config.py pipeline/textures.py pipeline/tests/test_decals.py pipeline/tests/test_textures.py game/assets/textures
git commit -m "pipeline: manhole decal positions + PNG/alpha texture slot support"
```

---

### Task 3: World rebuild

Controller-led. `.venv/Scripts/python -m pipeline.build` (no network) → orphan check → `--import` → headless smoke (17 gates still — the DECALS gate arrives in Task 4) → commit `game/world` as `world: M9b rebuild - crosswalks baked; manhole metadata`.

---

### Task 4: Pooled manhole decals (game) + smoke gate

**Files:**
- Create: `game/scripts/decal_pool.gd`
- Modify: `game/scenes/main.tscn` (DecalPool node), `game/tests/smoke_test.gd` (18th gate)

**Interfaces:**
- Consumes: `meta["manholes"]`, the manhole PNG from Task 2 (whichever path Task 2 shipped — check its report/commit).
- Produces: node `DecalPool` with `manhole_count() -> int` (metadata size) for the smoke gate.

- [ ] **Step 1: Write `game/scripts/decal_pool.gd`** — copy light_pool.gd's structure (it is the codebase's pooled-nearest-N pattern; read it first):
  - loads `meta["manholes"]` into a `PackedVector3Array` the same way light_pool loads lamps;
  - creates `POOL_SIZE := 32` `Decal` nodes at `_ready`: `size = Vector3(0.9, 0.6, 0.9)`, `texture_albedo = load(<manhole png path>)`, `cull_mask` left default, `visible = false`;
  - every 0.25 s (mirror light_pool's reassign cadence mechanism) assigns the pool to the nearest manholes within 120 m of the active camera, positioning each decal at the manhole position + `Vector3(0, 0.3, 0)` with a deterministic yaw (`rotation.y` from a position hash like props_multimesh's `_hash01`);
  - exposes `func manhole_count() -> int` returning the metadata array size.
- [ ] **Step 2: Wire into main.tscn** (new node `DecalPool` + script ext_resource; load_steps +1 — verify against the actual header).
- [ ] **Step 3: Smoke gate** after the PROPS gate, same idiom (`get_node_or_null("DecalPool")`): fail if `manhole_count() < 100` or pool child count != 32; print `DECALS OK: %d manholes`.
- [ ] **Step 4: Headless smoke** → 18 gates, `DECALS OK: ...`, `SMOKE OK: 314 tiles`.
- [ ] **Step 5: Commit** `game: pooled manhole decals + DECALS smoke gate`.

---

### Task 5: Ground-floor doors (facade shader)

**Files:**
- Modify: `game/shaders/building_windows.gdshader`

**Interfaces:**
- Consumes: existing `seed`, `cell`, `f`, `rh`, `floor_idx`, `storefront`, `vertical`, `cat` locals; contracts untouched.

- [ ] **Step 1: Shader edits.** After the `storefront` computation (the `lo/hi` mix lines), insert:

```glsl
	// residential/default ground-floor doors: one cell in ~5, non-storefront
	float door_pick = fract(sin(cell.x * 91.7 + seed * 47.0) * 43758.5453);
	float is_door = (floor_idx == 0.0 && storefront < 0.5 && (cat == 0 || cat == 5))
			? step(0.8, door_pick) : 0.0;
	float door_mask = is_door * step(0.30, f.x) * step(f.x, 0.70)
			* step(f.y, 2.2 / rh) * vertical;
	float door_rim = is_door * step(0.26, f.x) * step(f.x, 0.74)
			* step(f.y, 2.35 / rh) * vertical - door_mask;
```

Immediately after the four aperture masks (`inwin`/`inner`/`frame`/`sill`) are computed, suppress windows in door cells:

```glsl
	inwin *= 1.0 - is_door;
	inner *= 1.0 - is_door;
	frame *= 1.0 - is_door;
	sill *= 1.0 - is_door;
```

After the existing `col` mixes (sill line), before the roof mix:

```glsl
	col = mix(col, base * 1.15, clamp(door_rim, 0.0, 1.0));
	col = mix(col, vec3(0.13, 0.09, 0.06), door_mask);
```

- [ ] **Step 2: Headless smoke** → 18 gates green, no SHADER ERROR.
- [ ] **Step 3: Commit** `game: ground-floor doors on residential facades`.

---

### Task 6: Screenshot iteration + gate

Controller-led. Judge every pose vs `docs/screenshots/m9a_*.png`: crosswalks/stop bars at intersections (street/driving/uphill poses), manholes visible on nearby asphalt without z-fighting or floating (Decal projection depth may need the 0.6 vertical size tuned), doors present on residential ground floors and NOT on storefront commercial strips, night unchanged. Tune (crosswalk constants need a rebuild — prefer shader/decal knobs; note any pipeline retune as a follow-up instead of re-rebuilding unless it's badly wrong). Keepers `m9b_*`, pytest 97 + smoke 18, HANDOFF prepend, docs commit, final whole-branch review, STOP at user gate with m9a-vs-m9b pairs.
