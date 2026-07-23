# M8a — Light & Atmosphere Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat gradient sky, flat blue water, and flat green terrain with a physical-ish sky shader (clouds, sun disc, stars), a fresnel/depth water shader, and a PBR-blend terrain shader — the M8 "direction gate" phase, ending in a screenshot review for the user.

**Architecture:** Everything is game-side (Godot shaders + scene/material changes); the world's 314 tiles are NOT rebuilt. Terrain vertex colors already encode green/water zones, so the terrain shader reads them instead of new pipeline data. Only pipeline touch: two new ambientCG texture slots (grass, rock) fetched once via the existing `ensure_textures` lock mechanism and committed.

**Tech Stack:** Godot 4.5 (`tools/godot/godot_console.exe`), gdshader (sky/spatial), Python pipeline only for `pipeline/config.py` texture slots + pytest.

## Global Constraints

- Commits authored ONLY by Aymanbalaa via repo-local git config. NO `Co-Authored-By`/AI trailers, NO `--author` flags, NO git-config changes. Subagent dispatches must repeat this prohibition verbatim.
- Commit small and frequent; one commit per task minimum.
- World stays 314 tiles; `pipeline.build` is NOT run; no tile scene or vertex-data changes.
- No normal-map texture slots on tile meshes (they carry no tangents — M6a streak lesson). Custom shaders may compute normals analytically (water does).
- `night_amount` shader global contract preserved: day_night.gd keeps setting it every frame; building_windows.gdshader and light_pool.gd depend on it.
- Ambient light stays script-lerped COLOR mode (M6b decision); SDFGI stays off.
- Headless smoke must stay green: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd` → ends `SMOKE OK: 314 tiles` (16 gates). Run from repo root.
- pytest: `.venv/Scripts/python -m pytest pipeline -q` — currently 86 passing, must not regress.
- Screenshots are judged by Reading the PNGs, never claimed sight-unseen. Windowed harness: `tools/godot/godot_console.exe --path game --script res://tests/screenshot.gd` → PNGs in `%APPDATA%/Godot/app_userdata/MTL Open Ile/`.
- After adding new texture files run `tools/godot/godot_console.exe --headless --path game --import` once before other headless runs.
- License: ambientCG is CC0; new asset IDs get recorded in the texture lock; CREDITS.md already credits ambientCG (verify it needs no per-asset line).

---

### Task 1: Grass + rock texture slots (pipeline)

**Files:**
- Modify: `pipeline/config.py:112-120` (TEXTURE_SLOTS)
- Test: `pipeline/tests/test_textures.py`
- Created by running the fetch: `game/assets/textures/pbr/grass_alb.jpg`, `game/assets/textures/pbr/rock_alb.jpg`, updated `data/textures/textures.lock.json`

**Interfaces:**
- Produces: `game/assets/textures/pbr/grass_alb.jpg` and `rock_alb.jpg` — Task 4's terrain material loads them by exactly these paths.

- [ ] **Step 1: Write the failing test**

Append to `pipeline/tests/test_textures.py`:

```python
def test_grass_and_rock_slots_extract_color_maps(tmp_path):
    out = tmp_path / "out"
    ensure_textures(cache_dir=tmp_path / "cache", out_dir=out, fetch=_fetch_ok)
    assert (out / "grass_alb.jpg").exists()
    assert (out / "rock_alb.jpg").exists()
    # Color-only slots: no normal/roughness extracted
    assert not (out / "grass_nrm.jpg").exists()
    assert not (out / "rock_rgh.jpg").exists()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_textures.py::test_grass_and_rock_slots_extract_color_maps -q`
Expected: FAIL — `grass_alb.jpg` does not exist (slot not defined; `_fetch_ok` raises `AssertionError: unexpected url` is also acceptable as the failure mode).

- [ ] **Step 3: Add the slots**

In `pipeline/config.py`, extend `TEXTURE_SLOTS` (keep existing entries untouched):

```python
    "grass":    {"preferred": "Grass001",         "query": "grass lawn",       "maps": ["Color"]},
    "rock":     {"preferred": "Rock030",          "query": "rock cliff",       "maps": ["Color"]},
```

Note: if the preferred ID turns out not to exist on ambientCG, `ensure_textures` falls back to the query search automatically — that path is already tested.

- [ ] **Step 4: Run the full texture test file, then full pytest**

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_textures.py -q` → all pass.
Run: `.venv/Scripts/python -m pytest pipeline -q` → 87 passed (86 + 1 new).

- [ ] **Step 5: Fetch the real textures (network — allowed here, it's the manual ensure_textures path, not pipeline.build)**

Run: `.venv/Scripts/python -c "from pipeline.textures import ensure_textures; print(ensure_textures())"`
Expected: prints a dict including `'grass': 'Grass001'`-style ids (fallback ids acceptable); `game/assets/textures/pbr/grass_alb.jpg` and `rock_alb.jpg` now exist; `data/textures/textures.lock.json` gained both slots.

- [ ] **Step 6: LOOK at both textures**

Read `game/assets/textures/pbr/grass_alb.jpg` and `rock_alb.jpg` with the Read tool. Grass must read as green lawn/turf (not moss on rocks); rock as grey-brown rock/cliff (not pebbles). If wrong, change `preferred`/`query` in config and re-run Step 5. (M6a lesson: brick/stone once arrived swapped.)

- [ ] **Step 7: Godot import**

Run: `tools/godot/godot_console.exe --headless --path game --import`
Expected: exits without errors; `.import` files appear next to the new jpgs (they are gitignored except the audio ones — do NOT force-add these).

- [ ] **Step 8: Commit**

```bash
git add pipeline/config.py pipeline/tests/test_textures.py data/textures/textures.lock.json game/assets/textures/pbr/grass_alb.jpg game/assets/textures/pbr/rock_alb.jpg
git commit -m "pipeline: grass + rock texture slots for terrain shader"
```

---

### Task 2: Sky shader + day_night rewire

**Files:**
- Create: `game/shaders/sky.gdshader`
- Modify: `game/scenes/main.tscn:1-37` (sky sub-resource → ShaderMaterial, env fog params)
- Modify: `game/scripts/day_night.gd` (drop ProceduralSkyMaterial writes)

**Interfaces:**
- Consumes: nothing from other tasks (independent of Tasks 1/3/4).
- Produces: sky driven entirely by the Sun `DirectionalLight3D` via `LIGHT0_DIRECTION` — day_night.gd no longer owns sky colors. `night_amount` global unchanged for all consumers.

- [ ] **Step 1: Write the sky shader**

Create `game/shaders/sky.gdshader`:

```glsl
shader_type sky;

uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.42;
uniform float cloud_speed = 0.005;
uniform float cloud_scale = 0.18;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 sun = normalize(vec3(0.3, 0.6, 0.2));
	if (LIGHT0_ENABLED) {
		sun = LIGHT0_DIRECTION;
	}
	float sun_h = sun.y;
	float daylight = clamp(sun_h * 2.6, 0.0, 1.0);
	float twilight = clamp(1.0 - abs(sun_h) * 5.0, 0.0, 1.0);
	vec2 flat_dir = normalize(dir.xz + vec2(1e-5));
	vec2 flat_sun = normalize(sun.xz + vec2(1e-5));
	float toward_sun = dot(flat_dir, flat_sun) * 0.5 + 0.5;

	// atmosphere gradient
	float h = clamp(dir.y, 0.0, 1.0);
	float grad = pow(1.0 - h, 3.0);
	vec3 zen = mix(vec3(0.008, 0.012, 0.035), vec3(0.11, 0.28, 0.62), daylight);
	vec3 hor = mix(vec3(0.045, 0.06, 0.11), vec3(0.68, 0.78, 0.88), daylight);
	vec3 col = mix(zen, hor, grad);

	// dawn/dusk warm wash, strongest toward the sun azimuth
	col = mix(col, vec3(0.95, 0.45, 0.18), twilight * grad * (0.25 + 0.75 * toward_sun));

	// sun disc + halo
	float cs = dot(dir, sun);
	float disc = smoothstep(0.9993, 0.9998, cs);
	float halo = pow(clamp(cs, 0.0, 1.0), 350.0) * 0.5 + pow(clamp(cs, 0.0, 1.0), 24.0) * 0.12;
	vec3 sun_tint = mix(vec3(1.0, 0.55, 0.25), vec3(1.0, 0.97, 0.9), daylight);
	col += (disc * 12.0 + halo) * sun_tint * smoothstep(-0.06, 0.02, sun_h);

	// stars
	float night = 1.0 - daylight;
	if (night > 0.55 && dir.y > 0.0) {
		vec2 sp = dir.xz / (dir.y + 0.6);
		float star = step(0.9985, hash12(floor(sp * 380.0)));
		col += vec3(star) * 0.7 * smoothstep(0.55, 0.9, night);
	}

	// clouds
	if (dir.y > 0.015) {
		vec2 cuv = dir.xz / (dir.y * 3.0 + 0.35) * cloud_scale + vec2(TIME * cloud_speed);
		float d = fbm(cuv);
		float cov = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.28, d);
		cov *= smoothstep(0.015, 0.12, dir.y);
		vec3 cloud_lit = mix(vec3(0.03, 0.035, 0.06), vec3(1.0, 0.99, 0.96), daylight);
		cloud_lit = mix(cloud_lit, vec3(1.0, 0.55, 0.3), twilight * 0.7);
		float shade = mix(0.55, 1.0, smoothstep(0.2, 0.9, d));
		col = mix(col, cloud_lit * shade, cov * 0.92);
	}

	COLOR = col;
}
```

- [ ] **Step 2: Swap the sky material in main.tscn**

In `game/scenes/main.tscn`:
1. Header: `load_steps=16` → `load_steps=17`.
2. Add after the last `ext_resource` line (id="10"):

```
[ext_resource type="Shader" path="res://shaders/sky.gdshader" id="11"]
```

3. Replace the whole `[sub_resource type="ProceduralSkyMaterial" id="sky_mat"]` block (lines 14–20) with:

```
[sub_resource type="ShaderMaterial" id="sky_mat"]
shader = ExtResource("11")
```

(`[sub_resource type="Sky" id="sky1"]` keeps referencing `SubResource("sky_mat")` — no change there.)

4. In the `Environment` sub-resource, change/add fog lines so the block reads:

```
fog_enabled = true
fog_light_color = Color(0.75, 0.82, 0.9, 1)
fog_density = 0.00006
fog_aerial_perspective = 0.6
fog_sky_affect = 0.25
```

(Starting values — Task 5 tunes them against screenshots.)

- [ ] **Step 3: Rewire day_night.gd**

In `game/scripts/day_night.gd`:
1. Delete the `_sky_mat` var declaration and the two `_sky_mat` lines in `_ready` (keep `_env` lookup).
2. Delete the `DAY_TOP`/`NIGHT_TOP` constants (now unused) — keep `DAY_HOR`, `NIGHT_HOR`, `DUSK_HOR` for fog color.
3. In `_process`, delete the `if _sky_mat != null:` block (3 lines). Keep everything else (sun rotation, energy/color, `night_amount` global, fog_light_color, ambient lerps) byte-identical.

Resulting `_process` tail:

```gdscript
	var horizon := NIGHT_HOR.lerp(DAY_HOR, daylight).lerp(DUSK_HOR, dusk)
	if _env != null:
		_env.fog_light_color = horizon
		_env.ambient_light_energy = 0.45 + 0.6 * daylight
		var amb := Color(0.17, 0.19, 0.30).lerp(Color(0.92, 0.90, 0.86), daylight)
		_env.ambient_light_color = amb.lerp(Color(1.0, 0.72, 0.5), dusk * 0.6)
```

- [ ] **Step 4: Headless smoke**

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`
Expected: ends `SMOKE OK: 314 tiles`, no `SHADER ERROR` lines, no script errors referencing day_night.gd.

- [ ] **Step 5: Commit**

```bash
git add game/shaders/sky.gdshader game/scenes/main.tscn game/scripts/day_night.gd
git commit -m "game: physical-ish sky shader with clouds, sun disc, stars"
```

---

### Task 3: Water shader v2 (fresnel, depth shore fade, foam)

**Files:**
- Modify: `game/shaders/water.gdshader` (full replacement)

**Interfaces:**
- Consumes: nothing. Material wiring in tile_loader.gd (`_water_mat`) is untouched — same shader path.
- Produces: water no longer reads vertex COLOR; colors are in the shader.

- [ ] **Step 1: Replace the shader**

Overwrite `game/shaders/water.gdshader` with:

```glsl
shader_type spatial;
render_mode cull_back;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 wave_normal(vec2 p, float t) {
	float dx = 0.055 * cos(p.x * 0.11 + t * 0.9)
		+ 0.035 * cos((p.x * 0.7 + p.y * 0.4) * 0.23 + t * 1.7)
		+ 0.018 * cos((p.x + p.y * 1.7) * 0.53 + t * 2.6);
	float dz = 0.065 * cos(p.y * 0.09 - t * 0.7)
		+ 0.030 * cos((p.x * -0.3 + p.y * 0.8) * 0.19 + t * 1.3)
		+ 0.015 * cos((p.x * 1.4 - p.y) * 0.47 + t * 2.2);
	return normalize(vec3(-dx, 1.0, -dz));
}

void fragment() {
	vec3 n = wave_normal(wpos.xz, TIME);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	// scene depth behind the surface -> shore fade + foam
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth_raw, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	float scene_depth = -(vpos.xyz / vpos.w).z;
	float water_depth = clamp(scene_depth + VERTEX.z, 0.0, 60.0);

	vec3 deep = vec3(0.016, 0.045, 0.07);
	vec3 shallow = vec3(0.06, 0.13, 0.14);
	vec3 col = mix(shallow, deep, smoothstep(0.0, 12.0, water_depth));

	float foam = 1.0 - smoothstep(0.0, 2.2, water_depth);
	col = mix(col, vec3(0.85), foam * 0.55);

	ALBEDO = col;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ROUGHNESS = mix(0.04, 0.12, foam);
}
```

Sky reflection comes free: low roughness + the new sky's radiance cubemap. Sun glint comes from the DirectionalLight specular against the analytic wave normal.

- [ ] **Step 2: Headless smoke**

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`
Expected: `SMOKE OK: 314 tiles`, no `SHADER ERROR` lines.

- [ ] **Step 3: Commit**

```bash
git add game/shaders/water.gdshader
git commit -m "game: water shader v2 - fresnel, depth shore fade, foam"
```

---

### Task 4: Terrain shader + paths material split

**Files:**
- Create: `game/shaders/terrain.gdshader`
- Modify: `game/scripts/tile_loader.gd:11-16` (new materials) and `:68-83` (`_apply_city_material` routing)

**Interfaces:**
- Consumes: `game/assets/textures/pbr/{grass,rock}_alb.jpg` from Task 1; existing `ground_alb.jpg`.
- Produces: geometry buckets `terrain` → terrain shader, `paths` → own dirt triplanar material (no longer sharing `_sidewalk_mat` — this kills the plank-stripe artifact on Mont Royal paths).

- [ ] **Step 1: Write the terrain shader**

Create `game/shaders/terrain.gdshader`. Terrain vertex colors encode zones (pipeline `terrain_tile_mesh`): green areas = `(96,124,82)`, water bottoms = `(52,84,104)`, urban = elevation blend to `(150,146,138)`. The shader classifies by channel differences — water bottoms have `b > g`, green has `g > r`:

```glsl
shader_type spatial;

uniform sampler2D grass_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 0.06;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 vcol;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vcol = COLOR;
}

void fragment() {
	vec3 painted = pow(vcol.rgb, vec3(2.2));
	vec2 uv = wpos.xz * uv_scale;
	vec3 grass = texture(grass_tex, uv).rgb;
	vec3 dirt = texture(dirt_tex, uv * 1.9).rgb;
	vec3 rock = texture(rock_tex, uv * 0.7).rgb;

	float wet = smoothstep(0.03, 0.10, vcol.b - vcol.g);
	float greenness = smoothstep(0.03, 0.10, vcol.g - vcol.r) * (1.0 - wet);
	vec3 flat_col = mix(dirt, grass, greenness);
	float rockiness = smoothstep(0.30, 0.55, 1.0 - wnrm.y);
	vec3 col = mix(flat_col, rock, rockiness);

	// keep the baked large-scale tint so elevation/district variation survives
	col *= mix(vec3(1.0), painted * 2.2, 0.45);
	ALBEDO = mix(col, painted, wet);
	ROUGHNESS = 1.0;
}
```

(`painted * 2.2` recenters the dark linear vertex color around 1.0 as a modulator — a tunable; Task 5 adjusts if terrain reads too dark/bright.)

- [ ] **Step 2: Wire materials in tile_loader.gd**

Add two members after `_marks_mat` (line 16):

```gdscript
var _terrain_mat := _make_terrain_material()
var _path_mat := _make_triplanar_material("ground", 0.35, 1.15)
```

Add the factory after `_make_marks_material`:

```gdscript
static func _make_terrain_material() -> ShaderMaterial:
	var m := _make_shader_material("res://shaders/terrain.gdshader")
	if m == null:
		return null
	var slots := {"grass_tex": "grass", "dirt_tex": "ground", "rock_tex": "rock"}
	for p in slots:
		var path := "res://assets/textures/pbr/%s_alb.jpg" % slots[p]
		if ResourceLoader.exists(path):
			m.set_shader_parameter(p, load(path))
	return m
```

Rewrite the routing chain in `_apply_city_material` (paths split out, terrain added; order matters — keep the existing prefixes first):

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
		elif n.begins_with("paths"):
			inst.material_override = _path_mat
		elif _terrain_mat != null and n.begins_with("terrain"):
			inst.material_override = _terrain_mat
		else:
			inst.material_override = _city_mat
```

- [ ] **Step 3: Headless smoke**

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`
Expected: `SMOKE OK: 314 tiles`, no `SHADER ERROR`, no missing-texture warnings for grass/rock (would indicate Task 1 files absent).

- [ ] **Step 4: Commit**

```bash
git add game/shaders/terrain.gdshader game/scripts/tile_loader.gd
git commit -m "game: terrain PBR blend shader; paths get own dirt material"
```

---

### Task 5: Screenshot iteration + grade tuning + gate

This task is iterative by design (m3.5 took 4 rounds). Do NOT skip the looking.

**Files:**
- Modify (tuning only): `game/scenes/main.tscn` env params, shader uniform defaults in `sky.gdshader` / `water.gdshader` / `terrain.gdshader`
- Create: `docs/screenshots/m8a_*.png` (keepers), update `docs/superpowers/HANDOFF.md`

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces: the m8a screenshot set for the user's direction gate.

- [ ] **Step 1: Full screenshot run**

Run: `tools/godot/godot_console.exe --path game --script res://tests/screenshot.gd` (windowed, needs GPU; takes a while — 13 poses).
Expected: 13 `saved shot_*.png` lines; files in `%APPDATA%/Godot/app_userdata/MTL Open Ile/`.

- [ ] **Step 2: Read and judge every pose**

Read each PNG with the Read tool. Judge against the m7 baseline (`docs/screenshots/m7_*.png`) per pose:
- `overview`/`oldport`/`biosphere`: sky has clouds + believable gradient; water reads as reflective river with shore transition, not flat blue; distance hazes out (aerial perspective).
- `mountain`: Mont Royal reads grass/dirt/rock blended, NO plank stripes on paths, no neon-green sheet.
- `street`/`onfoot_day`/`driving_day`: overall light feels like the new sky (no regression to murk); facades unchanged is EXPECTED (that's 8b).
- `dusk`: warm horizon wash toward sun azimuth, clouds tinted.
- `night`/`onfoot_night`/`driving_night`: window glow + streetlights preserved (regression here fails the phase); stars visible; water not glowing.
- `uphill_facade`, `credits`: unchanged/no regression.

- [ ] **Step 3: Tune and repeat**

Fix what looks wrong by adjusting, in order of likely need: `fog_density` / `fog_aerial_perspective` / `fog_sky_affect` (main.tscn), `cloud_coverage`/`cloud_scale` (sky.gdshader defaults), terrain `uv_scale` and the `painted * 2.2` / `0.45` modulation constants (terrain.gdshader), water `deep`/`shallow` colors and foam width (water.gdshader), SSAO/glow (main.tscn). Re-run Step 1, re-Read. Iterate until the day poses read as an obvious generational jump over m7 and night holds. Commit each tuning round:

```bash
git add -A game/
git commit -m "game: m8a screenshot tuning round N"
```

- [ ] **Step 4: Save keepers**

Copy the final PNGs to `docs/screenshots/` renamed `m8a_<pose>.png` (PowerShell):

```powershell
$src = "$env:APPDATA/Godot/app_userdata/MTL Open Ile"
Get-ChildItem "$src/shot_*.png" | ForEach-Object { Copy-Item $_.FullName ("docs/screenshots/m8a_" + ($_.Name -replace '^shot_','')) }
```

- [ ] **Step 5: Final green run**

Run: `.venv/Scripts/python -m pytest pipeline -q` → 87 passed.
Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd` → `SMOKE OK: 314 tiles`.

- [ ] **Step 6: Update HANDOFF.md**

Prepend a new **State** paragraph to `docs/superpowers/HANDOFF.md` (demote current one to "Prior state"): M8a complete — sky shader (clouds/sun disc/stars, LIGHT0-driven, day_night.gd no longer writes sky colors), water v2 (fresnel/depth shore/foam, ignores vertex COLOR), terrain shader (grass/dirt/rock by vertex-color zones + slope, new grass+rock texture slots), paths split from sidewalks (plank-stripe fix), fog aerial perspective; world still 314 tiles, no rebuild; smoke 16 gates green, pytest 87; screenshots `docs/screenshots/m8a_*.png`; NEXT: user direction gate, then 8b Streets & Facades per spec `docs/superpowers/specs/2026-07-22-m8-graphics-realism-design.md`.

- [ ] **Step 7: Commit**

```bash
git add docs/screenshots docs/superpowers/HANDOFF.md
git commit -m "docs: m8a screenshots + handoff"
```

- [ ] **Step 8: STOP — user gate**

Present the m7 vs m8a screenshots to the user for the direction pass/fail. Do NOT start 8b planning until they approve.
