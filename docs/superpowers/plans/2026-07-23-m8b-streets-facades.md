# M8b — Streets & Facades Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Street-level realism: per-building facade variation (tone/warmth + window-pattern differences seeded from vertex data), glass that reflects the sky, a worn-asphalt road shader, a distinct curb, and higher-res wall textures — so ~6 texture sets read as hundreds of distinct buildings.

**Architecture:** The seed rides the channel that already exists: every building gets a unique vertex RGB (palette × per-osm_id jitter). The pipeline upgrades the scalar jitter to a brightness+warmth model (visible variation by itself), and the facade shader hashes the raw vertex RGB into a per-building seed for pattern variation — no new vertex attributes, no fragile glTF custom channels. Curb quads get a distinct baked vertex color (sidewalk material already uses vertex-color albedo, so no game-side change needed for it). Roads move from a StandardMaterial3D to a small shader with world-noise wear. One pipeline rebuild bakes the new vertex data.

**Tech Stack:** Python pipeline (trimesh, pytest), Godot 4.5 gdshader/GDScript, ambientCG CC0 textures via existing `ensure_textures` lock mechanism.

**Deliberate scope cut (surface at the gate):** the spec's "crack/manhole decals" are deferred to 8c — decal placement needs position-sampling infrastructure that belongs with 8c's street props; road realism here comes from the wear-noise shader. Everything else in the 8b spec section is in-plan.

## Global Constraints

- Commits authored ONLY by Aymanbalaa via repo-local git config. NO `Co-Authored-By`/AI trailers, NO `--author` flags, NO git-config changes. Repeat this prohibition verbatim in every subagent dispatch.
- Commit small and frequent; one commit per task minimum.
- Vertex-alpha packing contract is UNTOUCHED: wall alpha = `WALL_CATEGORY_ALPHA[cat]*40 + round(base_y/2)` (max 239), roofs 255. The facade shader's `cat`/`base_y` decode must keep working byte-identically.
- `night_amount` global contract preserved (day_night.gd sets it; facade shader + light_pool.gd consume it). Night look must not regress — it is the money shot; regression fails the phase.
- No normal-map textures on tile meshes (no tangents — M6a lesson). No SDFGI. Ambient stays script-lerped COLOR mode.
- Deterministic pipeline: NO network in `pipeline.build`; texture fetches only via manual `ensure_textures` (lock: `data/textures/textures.lock.json` — gitignored, update on disk only, never force-add).
- Rebuild rules: after `pipeline.build`, check `git status game/world/` for ORPHAN tiles (exporter never deletes; M7 precedent: 3 stray tiles needed `git rm`); expect exactly 314 tiles (same OSM cache + bbox); run `tools/godot/godot_console.exe --headless --path game --import` before any headless run after tile or texture changes.
- Headless smoke stays green: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd` from repo root → ends `SMOKE OK: 314 tiles`, 16 gates, no `SHADER ERROR`.
- pytest: `.venv/Scripts/python -m pytest pipeline -q` — currently 87 passing; this plan adds 4 (task counts below), no regressions.
- Screenshots judged only by Reading the PNGs. Windowed harness: `tools/godot/godot_console.exe --path game --script res://tests/screenshot.gd` → 13 PNGs in `%APPDATA%/Godot/app_userdata/MTL Open Ile/`.
- License: ambientCG is CC0, already credited in CREDITS.md; higher-res fetches are the same assets (no new credit lines needed).

---

### Task 1: Per-building tone/warmth jitter + curb vertex color (pipeline)

**Files:**
- Modify: `pipeline/meshes.py:21-23` (`_jitter` → `_jitter3`), `:108` (building paint call), `:236-237` (sidewalk paint)
- Modify: `pipeline/config.py` (add `CURB_COLOR` next to `SIDEWALK_COLOR`)
- Test: `pipeline/tests/test_meshes.py`

**Interfaces:**
- Consumes: nothing new.
- Produces: building wall/roof vertex RGB = `palette * _jitter3(osm_id)` (per-channel, brightness 0.86–1.10, warm/cool shift ±6% between R and B) — Task 4's shader hashes this RGB as the per-building seed. Sidewalk mesh vertex colors: curb verts (indices 0,1 of each 4-vertex cross-section) = `config.CURB_COLOR`, walk verts (2,3) = `config.SIDEWALK_COLOR`. Rebuild happens in Task 3, not here.

- [ ] **Step 1: Write the failing tests**

Append to `pipeline/tests/test_meshes.py` (mirror the Building/Road construction pattern already used by `test_building_vertex_colors_by_type_with_jitter` at line 40 and `test_sidewalk_raised_and_trimmed` — same constructors, just the osm_ids/fields shown here):

```python
def test_jitter3_warmth_varies_per_building():
    a = meshes._jitter3(101)
    b = meshes._jitter3(202)
    assert a.shape == (3,)
    # bounded so the category hue stays readable
    assert np.all(a > 0.80) and np.all(a < 1.17)
    # warm/cool axis differs between buildings (not just brightness)
    assert abs(a[0] / a[2] - b[0] / b[2]) > 1e-6

def test_building_walls_carry_tone_variation():
    # two identical buildings differing only by osm_id -> different wall RGB
    b1 = <same Building fixture as test_building_vertex_colors_by_type_with_jitter, osm_id=11>
    b2 = <same fixture, osm_id=12>
    c1 = building_mesh(b1).visual.vertex_colors[0][:3]
    c2 = building_mesh(b2).visual.vertex_colors[0][:3]
    assert not np.array_equal(c1, c2)

def test_sidewalk_curb_distinct_color():
    # same Road fixture as test_sidewalk_raised_and_trimmed
    m = sidewalk_mesh(<that road>, hm=None, junctions=frozenset())
    cols = {tuple(c[:3]) for c in m.visual.vertex_colors}
    assert tuple(config.CURB_COLOR) in cols
    assert tuple(config.SIDEWALK_COLOR) in cols
```

(The `<...>` fixture references mean: copy the existing construction lines from the named tests verbatim — the file already builds these objects; do not invent new field values. Everything else is literal.)

- [ ] **Step 2: Run the new tests, verify they fail** (`_jitter3` missing / `CURB_COLOR` missing).

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_meshes.py -q -k "jitter3 or tone_variation or curb_distinct"`

- [ ] **Step 3: Implement**

In `pipeline/meshes.py`, replace `_jitter` (lines 21-23) with:

```python
def _jitter3(osm_id: int) -> np.ndarray:
    """Deterministic per-building tone: brightness in [0.86, 1.10] plus a
    warm/cool shift of up to +-6% between the red and blue channels."""
    h = (osm_id * 2654435761) % (2 ** 32)
    bright = 0.86 + 0.24 * ((h & 1023) / 1023.0)
    warm = -0.06 + 0.12 * (((h >> 10) & 1023) / 1023.0)
    return np.array([bright * (1.0 + warm), bright, bright * (1.0 - warm)])
```

`_paint` needs no change — `np.array(rgb) * factor` broadcasts a length-3 array. Update the building paint call (line 108) from `_jitter(b.osm_id)` to `_jitter3(b.osm_id)`; grep for any other `_jitter(` call sites (roof cap receives the factor through `building_mesh` — verify it still compiles; tree/sidewalk hashes are separate inline code, untouched). Delete `_jitter` if nothing else uses it; if something does, keep both.

In `pipeline/config.py`, next to `SIDEWALK_COLOR` add:

```python
CURB_COLOR = (146, 143, 138)   # darker concrete lip, distinct from sidewalk paving
```

In `sidewalk_mesh` (meshes.py:236-237), replace `return _paint(mesh, config.SIDEWALK_COLOR)` with:

```python
    curb = np.array([*config.CURB_COLOR, 255], dtype=np.uint8)
    walk = np.array([*config.SIDEWALK_COLOR, 255], dtype=np.uint8)
    colors = np.tile(walk, (len(mesh.vertices), 1))
    colors[0::4] = curb   # curb bottom
    colors[1::4] = curb   # curb top (shared edge blends into the walk face - fine, both grey)
    mesh.visual.vertex_colors = colors
    return mesh
```

(Vertices are appended 4 per cross-section in order 0..3 with `process=False`, so stride-4 indexing is exact.)

- [ ] **Step 4: Run the new tests (pass), then full pytest**

Run: `.venv/Scripts/python -m pytest pipeline -q` → 90 passed (87 + 3 new). If `test_building_vertex_colors_by_type_with_jitter` asserts scalar-jitter specifics that the warmth model breaks, update THAT test's assertions to the new contract (different RGB per osm_id, bounded factors) and say so in your report.

- [ ] **Step 5: Commit**

```bash
git add pipeline/meshes.py pipeline/config.py pipeline/tests/test_meshes.py
git commit -m "pipeline: per-building tone/warmth jitter + distinct curb color"
```

---

### Task 2: Texture slot resolution support + 2K wall textures (pipeline)

**Files:**
- Modify: `pipeline/config.py:112-124` (TEXTURE_SLOTS + AMBIENTCG_DL)
- Modify: `pipeline/textures.py` (res-aware URL, lock entry, cache key)
- Test: `pipeline/tests/test_textures.py`
- Created by fetch: refreshed `game/assets/textures/pbr/{brick,stone,concrete}_alb.jpg` at 2K

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: same output filenames (`{slot}_alb.jpg`) at higher resolution — no game-side path changes anywhere.

- [ ] **Step 1: Write the failing test**

Append to `pipeline/tests/test_textures.py`, reusing the file's existing fake-fetch helper pattern (`_fetch_ok`) — extend/wrap it so it records requested URLs:

```python
def test_slot_res_selects_download_url(tmp_path):
    urls = []
    def fetch(url):
        urls.append(url)
        return _fetch_ok(url)          # existing helper serves a valid zip regardless
    ensure_textures(cache_dir=tmp_path / "cache", out_dir=tmp_path / "out", fetch=fetch)
    assert any("Bricks059_2K-JPG.zip" in u for u in urls)      # res-tagged slot
    assert any("Road012A_1K-JPG.zip" in u for u in urls)       # default stays 1K
```

If `_fetch_ok` asserts on exact expected URLs internally, extend its accepted set for the `_2K-JPG` variants rather than weakening the assertion.

- [ ] **Step 2: Run it, verify it fails** (URL still hardcodes `_1K-JPG`).

- [ ] **Step 3: Implement**

`pipeline/config.py`:
- `AMBIENTCG_DL = "https://ambientcg.com/get?file={id}_{res}-JPG.zip"` (was `{id}_1K-JPG.zip`)
- Add `"res": "2K"` to the `brick`, `stone`, and `concrete` slot dicts (leave `roof` and all others at default).

`pipeline/textures.py`:
- Wherever the download URL is formatted, pass `res=spec.get("res", "1K")`.
- The cached zip filename must include the res token (a 1K zip must not satisfy a 2K request) — add the res to the cache file name.
- Lock entry: record `"res"`; the cache-hit check requires `entry.get("res", "1K") == spec.get("res", "1K")` in addition to the existing preferred+sha256 conditions (this makes the res change self-invalidate exactly like a preferred change — the existing `test_preferred_change_invalidates_cache` shows the pattern).

- [ ] **Step 4: Full texture tests, then full pytest**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_textures.py -q` → all pass.
Run: `.venv/Scripts/python -m pytest pipeline -q` → 91 passed (90 + 1 new).

- [ ] **Step 5: Fetch the real 2K textures (network allowed — manual ensure_textures path)**

Run: `.venv/Scripts/python -c "from pipeline.textures import ensure_textures; print(ensure_textures())"`
Expected: brick/stone/concrete re-download at 2K; other slots cache-hit. `game/assets/textures/pbr/{brick,stone,concrete}_alb.jpg` change on disk (larger).

- [ ] **Step 6: LOOK at the three refreshed textures** (Read tool). Brick = red brick, stone = grey stone blocks, concrete = concrete. Same assets as before, just sharper — if an ID resolves differently at 2K (unlikely), stop and report.

- [ ] **Step 7: Godot import**

Run: `tools/godot/godot_console.exe --headless --path game --import` (do NOT force-add any `.import` files).

- [ ] **Step 8: Commit**

```bash
git add pipeline/config.py pipeline/textures.py pipeline/tests/test_textures.py game/assets/textures/pbr/brick_alb.jpg game/assets/textures/pbr/stone_alb.jpg game/assets/textures/pbr/concrete_alb.jpg
git commit -m "pipeline: per-slot texture resolution; brick/stone/concrete at 2K"
```

---

### Task 3: World rebuild (new vertex data)

**Files:**
- Regenerated: `game/world/tile_*.glb` (all 314), `game/world/city_metadata.json`, `game/world/minimap.png`, landmark GLBs

**Interfaces:**
- Consumes: Task 1's mesh changes (tone jitter, curb colors).
- Produces: the rebuilt world every later task renders against.

This task is mechanical but environment-heavy; the controller may run it inline (M7 Task 9 precedent).

- [ ] **Step 1: Rebuild**

Run: `.venv/Scripts/python -m pipeline.build` (OSM + heightmap come from `data/` caches — console must NOT show network fetches for them; heightmap line should say cached/hrdem).

- [ ] **Step 2: Orphan check**

Run: `git status --short game/world/ | grep -v '^ M'` — expect NO untracked (`??`) tile files and no deleted-but-tracked strays. 314 `tile_*.glb` modified is the healthy signature. If any orphans appear, `git rm` them and record it.

- [ ] **Step 3: Import + smoke**

Run: `tools/godot/godot_console.exe --headless --path game --import` (minutes), then the headless smoke → `SMOKE OK: 314 tiles`, 16 gates.

- [ ] **Step 4: Commit**

```bash
git add game/world
git commit -m "world: M8b rebuild - per-building tone jitter + curb colors baked"
```

---

### Task 4: Facade shader v3 (seeded variation + glass reflection)

**Files:**
- Modify: `game/shaders/building_windows.gdshader`

**Interfaces:**
- Consumes: Task 3's rebuilt tiles (per-building RGB from `_jitter3`).
- Produces: nothing downstream; `night_amount`, category decode, and base_y decode contracts unchanged.

- [ ] **Step 1: Apply the shader edits**

All edits to `game/shaders/building_windows.gdshader`; everything not listed stays byte-identical.

(a) After the `hash21` function (line 19), add:

```glsl
float bhash(vec3 c) {
	return fract(sin(dot(floor(c * 255.0 + 0.5), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}
```

(b) In `fragment()`, immediately after the `base_y` decode line (`float base_y = ...`; line 41), add:

```glsl
	float seed = bhash(vcol.rgb);   // stable per building: vertex color is constant per building
```

(c) Replace the window-grid constants (lines 61-64):

```glsl
	float cw = (cat == 1) ? 2.4 : 3.6;
	vec2 cell = vec2(floor(u / cw), floor(v / 3.2));
	vec2 f = vec2(fract(u / cw), fract(v / 3.2));
	float floor_idx = floor(v / 3.2);
```

with:

```glsl
	float cw = ((cat == 1) ? 2.4 : 3.6) * mix(0.85, 1.2, fract(seed * 7.31));
	float rh = 3.2 * mix(0.92, 1.12, fract(seed * 3.77));
	vec2 cell = vec2(floor(u / cw), floor(v / rh));
	vec2 f = vec2(fract(u / cw), fract(v / rh));
	float floor_idx = floor(v / rh);
```

(d) Glass picks up the sky — replace the ROUGHNESS/METALLIC lines (92-93):

```glsl
	ROUGHNESS = mix(mix(0.92, 0.14, inner), 0.95, roofness);
	METALLIC = inner * 0.55 * (1.0 - roofness);
```

(e) Per-building lit-window density + occasional cool-white storefronts — replace lines 95-100:

```glsl
	float lit = step(mix(0.5, 0.74, fract(seed * 5.13)), hash21(cell + vec2(seed * 31.0, 0.0)));
	float night = smoothstep(0.45, 0.9, night_amount);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float glow = max(lit, storefront * 0.55);
	vec3 glow_col = mix(vec3(1.0, 0.72, 0.35), vec3(0.78, 0.86, 1.0),
			step(0.85, fract(seed * 9.73)) * storefront);
	EMISSION = glow_col
			* (inner * glow * night * 1.6 * (0.2 + 0.8 * facing) * (1.0 - roofness));
```

- [ ] **Step 2: Headless smoke** → `SMOKE OK: 314 tiles`, no `SHADER ERROR`.

- [ ] **Step 3: Commit**

```bash
git add game/shaders/building_windows.gdshader
git commit -m "game: facade shader v3 - per-building seed variation, reflective glass"
```

---

### Task 5: Road wear shader + curb/sidewalk material cleanup

**Files:**
- Create: `game/shaders/road.gdshader`
- Modify: `game/scripts/tile_loader.gd:14-18` (road material swap, sidewalk scale), `:44-60` (`_make_triplanar_material` drops roughness textures), routing guard for roads

**Interfaces:**
- Consumes: Task 3's rebuilt tiles (curb colors ride vertex-color albedo — no new wiring needed for curbs).
- Produces: side effect — dropping `_rgh.jpg` from triplanar materials removes the pre-existing "shader requires tangents" warning flood (M6a/M7 known cosmetic; the identified fix was exactly this).

- [ ] **Step 1: Write the road shader**

Create `game/shaders/road.gdshader`:

```glsl
shader_type spatial;

uniform sampler2D asphalt_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float uv_scale = 0.08;
uniform float brighten = 3.2;

varying vec3 wpos;
varying vec3 vtint;

float rhash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float rnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(rhash(i), rhash(i + vec2(1.0, 0.0)), u.x),
			mix(rhash(i + vec2(0.0, 1.0)), rhash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec3 asph = texture(asphalt_tex, wpos.xz * uv_scale).rgb;
	// patchy wear: broad tonal drift + finer repair blotches
	float wear = rnoise(wpos.xz * 0.013) * 0.7 + rnoise(wpos.xz * 0.06) * 0.3;
	vec3 col = asph * vtint * brighten * mix(0.78, 1.12, wear);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	METALLIC = 0.0;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vtint = pow(COLOR.rgb, vec3(2.2));
}
```

(Roads are flat ribbons; a plain world-XZ projection is correct — no triplanar needed. Vertex tint keeps the road-class coloring.)

- [ ] **Step 2: Wire it in tile_loader.gd**

- Line 14: `var _road_mat := _make_road_material()`
- Line 15: sidewalk scale retune: `var _sidewalk_mat := _make_triplanar_material("paving", 0.5, 1.8)` (0.8 read as oversized planks in the m8a driving shots)
- Add after `_make_marks_material`:

```gdscript
static func _make_road_material() -> ShaderMaterial:
	var m := _make_shader_material("res://shaders/road.gdshader")
	if m == null:
		return null
	var path := "res://assets/textures/pbr/asphalt_alb.jpg"
	if ResourceLoader.exists(path):
		m.set_shader_parameter("asphalt_tex", load(path))
	return m
```

- In `_apply_city_material`, guard the roads branch like the other shader branches: `elif _road_mat != null and n.begins_with("roads"):`
- In `_make_triplanar_material` (lines 44-60): delete the roughness-texture block (the `var rgh := ...` / `if ResourceLoader.exists(rgh): m.roughness_texture = load(rgh)` lines) and add `m.roughness = 0.92` — this is the M7-identified fix for the tangent-warning flood.

- [ ] **Step 3: Headless smoke** → `SMOKE OK: 314 tiles`, no `SHADER ERROR`. Then run ONE windowed screenshot pose run and confirm in the console output that the "shader requires tangents" warning flood is gone (grep the output; a handful of unrelated warnings are fine, the per-tile road/sidewalk flood must be absent).

- [ ] **Step 4: Commit**

```bash
git add game/shaders/road.gdshader game/scripts/tile_loader.gd
git commit -m "game: road wear shader; sidewalk retune; drop tangent-warning roughness textures"
```

---

### Task 6: Screenshot iteration + 8a carry-forward fixes + gate

Iterative by design; controller-led (M7 Task 9 / M8a Task 5 precedent). Do NOT skip the looking.

**Files:**
- Modify (tuning only): shader uniform defaults, `game/scenes/main.tscn` env params
- Modify: `game/shaders/sky.gdshader` (carry-forward fix)
- Create: `docs/screenshots/m8b_*.png`, update `docs/superpowers/HANDOFF.md`

- [ ] **Step 1: 8a carry-forward — night sun disc.** In `game/shaders/sky.gdshader`, the sun disc/halo line gates on `smoothstep(-0.06, 0.02, sun_h)`, which is fully open at night (sun never goes below ~6°). Replace that factor with `smoothstep(0.05, 0.25, daylight)` so the disc fades with darkness. (The symmetric twilight wash is accepted behavior — matches day_night.gd's own dusk term; do not change it.)

- [ ] **Step 2: Full screenshot run + judge every pose** against `docs/screenshots/m8a_*.png` per pose:
  - `street`/`onfoot_day`/`driving_day`/`uphill_facade`: facades visibly vary building-to-building (tone AND window rhythm); glass shows sky; road reads worn asphalt, not uniform grey; curb line visible; sidewalk no longer plank-scaled.
  - `overview`/`oldport`/`mountain`/`biosphere`/`dusk`: no regression; facade variation should read as texture richness at distance, not noise.
  - `night`/`onfoot_night`/`driving_night`: window glow preserved with per-building density variation; occasional cool-white storefronts read as intentional; NO regression (fails the phase); no sun disc in the night sky.
  - `credits`: legible, unchanged.

- [ ] **Step 3: Tune and repeat.** Likely knobs in order: `_jitter3` warm/bright ranges are PIPELINE-side (avoid retouching — needs rebuild; only if variation reads as garish), shader `mix(0.85,1.2,...)` cw range and `mix(0.92,1.12,...)` rh range, glass METALLIC 0.55, wear `mix(0.78,1.12,...)` span, road `brighten`, sidewalk uv_scale. Commit each round: `git commit -m "game: m8b screenshot tuning round N"`.

- [ ] **Step 4: Save keepers** (same PowerShell copy pattern as m8a, prefix `m8b_`).

- [ ] **Step 5: Final green run:** pytest → 91 passed; headless smoke → `SMOKE OK: 314 tiles`.

- [ ] **Step 6: Update HANDOFF.md** — prepend new State paragraph (demote current): M8b complete, what shipped, seed mechanism (RGB hash — document that changing the palette or jitter breaks per-building stability of the seed, by design harmless but re-rolls building variations), curb colors baked, road shader, tangent-warning flood FIXED (rgh textures dropped), 2K wall textures, decals deferred to 8c, tile rebuild (still 314), test count 91, keeper screenshots, NEXT: user gate then 8c.

- [ ] **Step 7: Commit docs, then STOP — user gate.** Present m8a-vs-m8b pairs (street, onfoot_day, driving_day, night, uphill_facade) before any 8c planning.
