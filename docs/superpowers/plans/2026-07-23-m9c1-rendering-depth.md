# M9c1 — Rendering Depth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give commercial glass fake interior depth (shader interior-mapping) and grow sparse grass on green terrain in a camera-near ring — both game-side, no pipeline rebuild.

**Architecture:** (1) Extend `building_windows.gdshader` so that on commercial floors ≥1 the inner glass region ray-marches a per-window virtual room box (basis built from the existing world-space cell axes + wall normal — no tangents needed) and shades a procedural interior; the night emissive-window path is untouched. (2) A new `grass_field.gd` Node3D recycles a single MultiMesh of grass tufts around the active camera every quarter-second (light_pool cadence): it scans resident terrain tiles once each for green vertex-color cells (mirroring the terrain shader's grass zone), then instances tufts at deterministic hashed positions whose cell is green.

**Tech Stack:** Godot 4.5 (spatial gdshader, MultiMesh, MeshInstance3D vertex-array scan), GDScript headless tests via `godot_console`.

## Global Constraints

- Commits authored ONLY by Aymanbalaa via repo-local git config (noreply email). NO `Co-Authored-By`/AI trailers, NO `--author` flags, NO git-config changes. Repeat verbatim in every subagent dispatch.
- Commit small and frequent; one commit per task minimum.
- Game-side ONLY this sub-phase: NO `pipeline.build`, world stays 314 tiles, no `.import` commits beyond auto-generated `.uid` sidecars (track them like the repo's other script/shader uids).
- Contracts untouched: `night_amount` global, vertex-alpha packing (`category*40 + round(base_y/2)`), facade seed-from-RGB (`bhash`), the m9b crosswalk/manhole/door additions, the m9b storefront/glass behavior on residential+commercial floor-0.
- **Night regression fails this sub-phase.** The interior box modulates the *daytime* glass color only; the `EMISSION` block (building_windows.gdshader:117-124) must be byte-unchanged.
- No normal maps on tangent-less tile meshes (interior mapping is chosen precisely because it needs no tangents).
- Perf budget RX 6700S: interior-mapping ray steps are O(1) (analytic box intersection, no loop); grass density/ring radius come down before the gate if frame time regresses.
- GDScript headless tests print `... OK` / push_error on failure and are run with `tools/godot/godot_console.exe --headless --path game --script res://tests/<name>.gd`. Godot `.gd` files must be written BOM-less (PS5 `Set-Content` hazard — use the Bash heredoc or an editor that writes UTF-8 without BOM).
- Smoke stays green: after this sub-phase it is 19 gates (adds one GRASS gate in Task 3), ending `SMOKE OK: 314 tiles`. pytest is unaffected (game-side phase) — stays 97.

---

### Task 1: Interior-mapping window interiors (facade shader)

Shaders are not pytest-unit-testable; this project verifies shader work by headless smoke (no `SHADER ERROR`, all gates green) plus screenshot judging (Task 4) — the same path used for M8a/M8b/M9a shader tasks. There is no separate unit test for this task.

**Files:**
- Modify: `game/shaders/building_windows.gdshader` (add an interior-mapping block in `fragment()` and one blend into `col`; do NOT touch `vertex()`, the EMISSION block, or the alpha-unpack lines)

**Interfaces:**
- Consumes: existing fragment locals `wpos`, `wnormal`, `cat`, `floor_idx`, `f`, `lo`, `hi`, `inner`, `seed`, `tint`, `storefront`, `NORMAL`, `VIEW`; Godot built-in `CAMERA_POSITION_WORLD`.
- Produces: no new uniforms or varyings; only `ALBEDO` (via `col`) changes, and only inside the commercial `inner` glass on floors ≥1.

- [ ] **Step 1: Add the interior-mapping helper** above `void fragment()` (after `bhash`, near line 24). It analytically intersects the view ray with a unit room box behind the glass and returns a shaded interior color.

```glsl
// interior mapping: g = fragment pos within aperture in [0,1]^2 on the glass plane;
// rl = view ray in the window-local basis (x along-wall, y up, z into the room).
// analytic nearest-plane hit against a unit box (walls x=0/1, floor/ceil y=0/1,
// back wall z=depth); shaded procedurally per room. No loop, no texture.
vec3 interior_room(vec2 g, vec3 rl, float room_seed) {
	float depth = 0.85;                       // room depth in aperture-heights
	float tz = (rl.z > 1e-4) ? depth / rl.z : 1e9;
	float tx = (rl.x > 1e-4) ? (1.0 - g.x) / rl.x : (rl.x < -1e-4 ? -g.x / rl.x : 1e9);
	float ty = (rl.y > 1e-4) ? (1.0 - g.y) / rl.y : (rl.y < -1e-4 ? -g.y / rl.y : 1e9);
	float t = min(tz, min(tx, ty));
	vec3 hit = vec3(g, 0.0) + rl * t;
	// per-room base palette (warm office / cool office / dim), hashed
	vec3 warm = vec3(0.55, 0.47, 0.36);
	vec3 cool = vec3(0.42, 0.48, 0.55);
	vec3 dim  = vec3(0.14, 0.15, 0.17);
	float pick = fract(room_seed * 3.11);
	vec3 room = (pick < 0.4) ? warm : (pick < 0.75 ? cool : dim);
	// depth shade: back wall darkest, side walls mid, ceiling brightest (fake ceiling light)
	float shade = 1.0 - 0.55 * (hit.z / depth);
	shade *= (t == ty && rl.y < 0.0) ? 1.25 : 1.0;   // looking up -> ceiling, brighter
	shade *= (t == ty && rl.y > 0.0) ? 0.7  : 1.0;    // floor, darker
	// a back-wall furniture band (single horizontal stripe) for readable depth
	float band = (t == tz) ? smoothstep(0.28, 0.30, hit.y) * (1.0 - smoothstep(0.5, 0.52, hit.y)) : 0.0;
	room = mix(room, room * 0.55, band * 0.7);
	return room * clamp(shade, 0.15, 1.35);
}
```

- [ ] **Step 2: Build the window-local ray and blend the interior into `col`.** Insert this block AFTER the sill `col` mix and BEFORE the roof mix — i.e. immediately after line 108 (`col = mix(col, base * 1.3 + vec3(0.03), sill);`) and before the door mixes are fine either side, but place it so doors/roof still win: put it right after line 108.

```glsl
	// --- fake interior depth: commercial (cat 1) floors >= 1, inside the glass ---
	if (cat == 1 && floor_idx >= 1.0) {
		vec3 nrm = normalize(wnormal);
		vec3 tang = normalize(cross(vec3(0.0, 1.0, 0.0), nrm));  // along-wall horizontal
		vec3 rd = normalize(wpos - CAMERA_POSITION_WORLD);       // camera -> fragment
		// window-local ray: x along wall, y up, z into the room (-nrm)
		vec3 rl = normalize(vec3(dot(rd, tang), rd.y, dot(rd, -nrm)));
		// aperture-normalized fragment coords in [0,1]
		vec2 g = clamp(vec2((f.x - lo.x) / max(hi.x - lo.x, 1e-3),
				(f.y - lo.y) / max(hi.y - lo.y, 1e-3)), 0.0, 1.0);
		float room_seed = fract(sin(dot(cell, vec2(19.19, 71.7)) + seed * 23.0) * 43758.5453);
		vec3 room = interior_room(g, rl, room_seed);
		// only where we're actually seeing into the room (rl.z>0) and inside the glass
		col = mix(col, room, inner * step(1e-3, rl.z));
	}
```

- [ ] **Step 3: Verify the shader compiles and night is unchanged.** Run headless smoke:

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`
Expected: no `SHADER ERROR` line; ends `SMOKE OK: 314 tiles` with the existing 18 gates (DECALS OK present). If any `SHADER ERROR` prints, fix the GLSL before proceeding.

- [ ] **Step 4: Capture a quick manual check** (interior visible by day, night skyline unchanged) — defer full judging to Task 4, but eyeball one day + one night shot now:

Run: `tools/godot/godot_console.exe --path game --script res://tests/screenshot.gd`
Read `%APPDATA%/Godot/app_userdata/MTL Open Ile/shot_street.png` (day, commercial) and `shot_night.png`. Confirm commercial upper-floor glass shows interior shading by day and the night lit-window pattern is unchanged. (Tuning happens in Task 4; here you only confirm no gross regression.)

- [ ] **Step 5: Commit**

```bash
git add game/shaders/building_windows.gdshader
git commit -m "game: interior-mapping window depth on commercial upper floors"
```

---

### Task 2: Grass green-cell classifier (pure function + headless test)

The classifier decides whether a terrain vertex color counts as grass, mirroring the terrain shader's grass zone (terrain.gdshader:33-34: `greenness = smoothstep(0.03,0.10, vcol.g - vcol.r) * (1 - wet)`, `wet = smoothstep(0.02,0.06, vcol.b - vcol.g)`). It is pure and unit-testable.

**Files:**
- Create: `game/scripts/grass_field.gd` (classifier only in this task; the Node3D renderer is added in Task 3)
- Create: `game/tests/grass_test.gd`

**Interfaces:**
- Produces: `static func is_grass(c: Color) -> bool` — true when the color reads as vegetated ground (used by Task 3 to mark green cells). Thresholds: grass when `(c.g - c.r) >= GREEN_MIN` and NOT wet (`(c.b - c.g) < WET_MAX`).
- Produces constants `GREEN_MIN := 0.06`, `WET_MAX := 0.04` (mid-points of the shader's smoothstep bands, chosen so a clearly-green vertex passes and a water-bottom/dirt vertex fails).

- [ ] **Step 1: Write the failing test** `game/tests/grass_test.gd`:

```gdscript
extends SceneTree
# headless: godot_console --headless --path game --script res://tests/grass_test.gd

func _init() -> void:
	var GF = load("res://scripts/grass_field.gd")
	# clearly green park vertex -> grass
	assert(GF.is_grass(Color(0.30, 0.55, 0.25)) == true)
	# grey road / concrete (r==g==b) -> not grass
	assert(GF.is_grass(Color(0.45, 0.45, 0.45)) == false)
	# brown dirt (r>g) -> not grass
	assert(GF.is_grass(Color(0.42, 0.34, 0.20)) == false)
	# water bottom (b dominant, wet) -> not grass even if slightly green
	assert(GF.is_grass(Color(0.20, 0.30, 0.40)) == false)
	# borderline just under threshold -> not grass
	assert(GF.is_grass(Color(0.40, 0.45, 0.30)) == false)  # g-r = 0.05 < 0.06
	print("GRASS CLASSIFIER OK")
	quit()
```

- [ ] **Step 2: Run, verify it fails** (file/function missing):

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/grass_test.gd`
Expected: error loading `res://scripts/grass_field.gd` or "Invalid call to is_grass" — a FAIL, not `GRASS CLASSIFIER OK`.

- [ ] **Step 3: Implement the classifier** `game/scripts/grass_field.gd`:

```gdscript
extends Node3D
class_name GrassField

const GREEN_MIN := 0.06   # (g - r) must exceed this (mid of shader's 0.03..0.10 band)
const WET_MAX := 0.04     # (b - g) at/above this reads as water-bottom, not grass

static func is_grass(c: Color) -> bool:
	return (c.g - c.r) >= GREEN_MIN and (c.b - c.g) < WET_MAX
```

- [ ] **Step 4: Run, verify it passes:**

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/grass_test.gd`
Expected: prints `GRASS CLASSIFIER OK`, exit 0.

- [ ] **Step 5: Commit** (include the auto-generated `.uid` for the new script):

```bash
git add game/scripts/grass_field.gd game/scripts/grass_field.gd.uid game/tests/grass_test.gd game/tests/grass_test.gd.uid
git commit -m "game: grass green-cell classifier + headless test"
```

(If the `.uid` files do not yet exist, run `tools/godot/godot_console.exe --headless --path game --import` once to generate them, then add.)

---

### Task 3: Grass MultiMesh renderer (camera-near ring) + smoke gate

**Files:**
- Modify: `game/scripts/grass_field.gd` (add the Node3D lifecycle: green-cell cache from resident terrain, ring regeneration, one MultiMesh)
- Create: `game/shaders/grass.gdshader` (unlit-ish vegetated card with a cheap wind sway)
- Modify: `game/scenes/main.tscn` (add a `Grass` node under `Main`; `load_steps` +1, one ext_resource for the script)
- Modify: `game/tests/smoke_test.gd` (19th gate)

**Interfaces:**
- Consumes: `is_grass()` (Task 2); resident terrain `MeshInstance3D`s under `/root/Main/TileLoader` whose name begins with `terrain`; the active camera (`get_viewport().get_camera_3d()`).
- Produces: node `Grass` with `func green_cell_count() -> int` (number of cached green cells; the smoke gate asserts it grows > 0 after streaming a few tiles) and `func blade_count() -> int` (current MultiMesh `instance_count`).

**Design notes (read before implementing):**
- Tiles STREAM (800 m radius) so the city's terrain is never fully resident. Build the green-cell cache incrementally: each ring-regeneration, scan any near, visible, not-yet-scanned terrain tile once (cache its id in `_scanned`), classifying each vertex via `is_grass()` and adding its world-XZ cell (`CELL := 2.0` m) to `_green` (a Dictionary used as a set: `Vector2i -> true`). Cells are never removed (bounded by explored area).
- Vertex data: for each terrain `MeshInstance3D`, `var arr := inst.mesh.surface_get_arrays(0)`; vertices `arr[Mesh.ARRAY_VERTEX]` (PackedVector3Array), colors `arr[Mesh.ARRAY_COLOR]` (PackedColorArray). Transform each vertex by `inst.global_transform` for world position. Guard empty color arrays (skip tile).
- Placement: over the near ring (`RING := 70.0` m), iterate a fixed world grid at `STRIDE := 3.0` m around the camera cell; for each grid point add a deterministic jitter (`_hash01`) and keep it only if its `CELL` is in `_green`. Cap at `MAX_BLADES := 1400`. Rebuild the MultiMesh only when the camera crosses into a new `STRIDE`-cell (store `_last_cell`).
- Grass mesh: a single `QuadMesh` (size ~0.5×0.6, centered so the base sits at y=0) rendered as two crossed cards via the MultiMesh giving each instance a hashed yaw; material = `grass.gdshader`. Keep it simple — one quad per instance with yaw is acceptable for v1 (crossed-quad upgrade is a Task 4 tuning knob if it reads too flat).

- [ ] **Step 1: Write the grass shader** `game/shaders/grass.gdshader`:

```glsl
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

global uniform float night_amount;
uniform float wind_amp = 0.06;

void vertex() {
	// sway the top of the card; VERTEX.y in [0..~0.6], base stays anchored
	float top = clamp(VERTEX.y / 0.6, 0.0, 1.0);
	float phase = NODE_POSITION_WORLD.x * 0.7 + NODE_POSITION_WORLD.z * 0.9 + TIME * 1.6;
	VERTEX.x += sin(phase) * wind_amp * top;
	VERTEX.z += cos(phase * 0.9) * wind_amp * 0.6 * top;
}

void fragment() {
	float top = clamp((UV.y < 0.5) ? 1.0 : 0.0, 0.0, 1.0); // UV.y small = top of card in QuadMesh
	// blade gradient: darker at root, brighter at tip
	vec3 root = vec3(0.11, 0.22, 0.09);
	vec3 tip  = vec3(0.22, 0.42, 0.16);
	vec3 col = mix(root, tip, top);
	col *= mix(0.35, 1.0, 1.0 - night_amount);  // dim at night like the rest of the scene
	ALBEDO = col;
	ROUGHNESS = 1.0;
	// alpha taper to hide the hard quad edges a little
	float edge = smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.88, 1.0, UV.x));
	ALPHA = edge;
}
```

(Note: `render_mode` uses `depth_draw_opaque` with `ALPHA` for a soft edge; if the cards shimmer through each other at the gate, switch to `depth_prepass_alpha` — a Task 4 knob.)

- [ ] **Step 2: Add the renderer to `grass_field.gd`** (append below the classifier; keep `class_name GrassField` and the static `is_grass`):

```gdscript
const CELL := 2.0          # green-mask cell size (m)
const STRIDE := 3.0        # grass grid spacing (m)
const RING := 70.0         # camera-near radius (m)
const MAX_BLADES := 1400
const REGEN_SEC := 0.25

var _green := {}           # Vector2i -> true (green cells discovered so far)
var _scanned := {}         # terrain tile instance_id -> true (scanned once)
var _mm := MultiMesh.new()
var _accum := 1.0
var _last_cell := Vector2i(2147483647, 0)

func _ready() -> void:
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.6)
	q.center_offset = Vector3(0.0, 0.3, 0.0)   # base at y=0
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass.gdshader")
	q.surface_set_material(0, mat)
	_mm.mesh = q
	_mm.instance_count = 0
	var inst := MultiMeshInstance3D.new()
	inst.name = "GrassMM"
	inst.multimesh = _mm
	add_child(inst)

func green_cell_count() -> int:
	return _green.size()

func blade_count() -> int:
	return _mm.instance_count

static func _hash01(x: float, z: float, salt: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233 + salt) * 43758.5453, 1.0)

func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CELL), floori(z / CELL))

func _scan_near_terrain(cam: Vector3) -> void:
	var loader := get_node_or_null("/root/Main/TileLoader")
	if loader == null:
		return
	for child in loader.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not mi.visible or mi.mesh == null:
			continue
		if not mi.name.to_lower().begins_with("terrain"):
			continue
		var id := mi.get_instance_id()
		if _scanned.has(id):
			continue
		# only scan tiles whose origin is within a generous ring (2x) of the camera
		if mi.global_position.distance_to(cam) > RING * 2.0:
			continue
		_scanned[id] = true
		var arr := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var cols: Variant = arr[Mesh.ARRAY_COLOR]
		if typeof(cols) != TYPE_PACKED_COLOR_ARRAY or cols.is_empty():
			continue
		var xf := mi.global_transform
		for i in verts.size():
			if not is_grass(cols[i]):
				continue
			var w: Vector3 = xf * verts[i]
			_green[_cell_of(w.x, w.z)] = true

func _process(delta: float) -> void:
	_accum += delta
	if _accum < REGEN_SEC:
		return
	_accum = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var cp := cam.global_position
	_scan_near_terrain(cp)
	var cc := Vector2i(floori(cp.x / STRIDE), floori(cp.z / STRIDE))
	if cc == _last_cell:
		return
	_last_cell = cc
	var xforms: Array[Transform3D] = []
	var n := int(RING / STRIDE)
	for ix in range(-n, n + 1):
		for iz in range(-n, n + 1):
			var gx := (cc.x + ix) * STRIDE
			var gz := (cc.y + iz) * STRIDE
			var jx := gx + (_hash01(gx, gz, 1.3) - 0.5) * STRIDE
			var jz := gz + (_hash01(gx, gz, 4.7) - 0.5) * STRIDE
			if Vector2(jx - cp.x, jz - cp.z).length() > RING:
				continue
			if not _green.has(_cell_of(jx, jz)):
				continue
			# skip a fraction for sparseness
			if _hash01(gx, gz, 9.1) > 0.6:
				continue
			var y := _green_y(cp, jx, jz)
			var yaw := _hash01(gx, gz, 2.2) * TAU
			var s: float = lerp(0.7, 1.3, _hash01(gx, gz, 6.6))
			xforms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(jx, y, jz)))
			if xforms.size() >= MAX_BLADES:
				break
		if xforms.size() >= MAX_BLADES:
			break
	_mm.instance_count = xforms.size()
	for j in xforms.size():
		_mm.set_instance_transform(j, xforms[j])

# grass y: raycast down onto terrain collision; fall back to camera-relative ground
func _green_y(cp: Vector3, x: float, z: float) -> float:
	var space := get_world_3d().direct_space_state
	var from := Vector3(x, cp.y + 50.0, z)
	var to := Vector3(x, cp.y - 200.0, z)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(q)
	return (hit.position.y if hit.has("position") else 0.0)
```

- [ ] **Step 3: Wire `Grass` into `main.tscn`.** Bump `load_steps` on line 1 by 1 (19 → 20). Add an ext_resource after the `decal_pool.gd` one (id "13", line 14):

```
[ext_resource type="Script" path="res://scripts/grass_field.gd" id="14"]
```

Add the node after the `DecalPool` node block (after line 84):

```
[node name="Grass" type="Node3D" parent="."]
script = ExtResource("14")
```

- [ ] **Step 4: Add the 19th smoke gate.** In `game/tests/smoke_test.gd`, after the DECALS gate block (the one printing `DECALS OK: %d manholes`), add a grass gate. Grass needs the camera to sit in the world and a couple of process ticks to scan terrain and place blades, so poll after the scene has settled (mirror how the existing gates await settling — reuse the same await/poll idiom already in the file):

```gdscript
	# --- GRASS gate ---
	var grass := main.get_node_or_null("Grass")
	assert(grass != null, "Grass node missing")
	# let it scan resident terrain + regenerate for a few ticks
	for _i in 30:
		await scene_tree.process_frame
	assert(grass.green_cell_count() > 0, "no green terrain cells discovered")
	print("GRASS OK: %d green cells, %d blades" % [grass.green_cell_count(), grass.blade_count()])
```

(Match the actual variable names in smoke_test.gd — it already holds the loaded main scene and a tree reference for the other gates; reuse those exact identifiers rather than `main`/`scene_tree` if they differ. Read the DECALS gate just above and copy its await/lookup idiom.)

- [ ] **Step 5: Import + run smoke** (import once so the new script/shader `.uid`s and the tscn edit register):

Run: `tools/godot/godot_console.exe --headless --path game --import`
Then: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`
Expected: 19 gates, including `GRASS OK: <n> green cells, <m> blades` with n>0, ending `SMOKE OK: 314 tiles`. No `SHADER ERROR`.

- [ ] **Step 6: Commit** (include generated `.uid` sidecars for the new shader and script):

```bash
git add game/scripts/grass_field.gd game/shaders/grass.gdshader game/shaders/grass.gdshader.uid game/scenes/main.tscn game/tests/smoke_test.gd
git commit -m "game: camera-near grass MultiMesh on green terrain + smoke gate"
```

(If `grass_field.gd.uid` was already committed in Task 2, it will simply be unchanged; `git add` any new `.uid` that appears.)

---

### Task 4: Screenshot iteration + gate

Controller-led (not a subagent task).

- [ ] **Step 1: Capture the 13 poses.** Run `tools/godot/godot_console.exe --path game --script res://tests/screenshot.gd`; copy the PNGs from `%APPDATA%/Godot/app_userdata/MTL Open Ile/` to `docs/screenshots/m9c1_*.png`.
- [ ] **Step 2: Judge every pose by Reading the PNGs vs `docs/screenshots/m9b_*.png`.** Confirm:
  - Commercial upper-floor glass shows readable interior depth (parallax shifts with view angle) in `street`, `driving_day`, `uphill_facade`, `overview` — NOT flat mirrors, NOT black holes.
  - Interiors do NOT appear on residential/door facades (cat 0/5) or on ground-floor storefronts.
  - Grass tufts appear on parks/medians/green terrain in `onfoot_day`, `street`, `oldport`, `mountain` — present in a near ring, absent on roads/sidewalks/water, no floating tufts, no hard pop at the ring edge (if pop is objectionable, add a `visibility_range` fade — knob).
  - Day is not hazed; **night poses (`night`, `driving_night`, `onfoot_night`, `dusk`) are unchanged** vs m9b (interior box is day-only; grass dims). Any night lit-window change = regression, fix in the shader gate.
- [ ] **Step 3: Tune** (shader constants: room `depth`, palette, band; grass: `STRIDE`, sparseness cutoff, `MAX_BLADES`, `wind_amp`, quad size, alpha mode). Prefer shader/script knobs — no rebuild is possible or needed this sub-phase. Re-capture and re-judge until all poses pass.
- [ ] **Step 4: Update HANDOFF + ledger, commit docs, request final whole-branch review, STOP at the user gate** with m9b-vs-m9c1 pairs. On pass: tag (suggest `m9c1-depth`), push, then write the M9c2 plan.

---

## Self-Review

**Spec coverage** (against `2026-07-23-m9c-depth-life-design.md` §9c1): fake window interiors → Task 1; grass clumps camera-near MultiMesh on green terrain, procedural, no rebuild → Tasks 2–3; screenshot gate → Task 4. Both 9c1 features covered. (9c2 player/awnings and 9c3 lamp-net/vnight are out of scope for this plan — separate sub-phases per the spec.)

**Placeholder scan:** no TBD/TODO; every code step shows full code. The two explicit "tuning knob" deferrals (crossed-quad grass, alpha mode, room depth) are screenshot-round tuning of shipped code, not missing implementation. Task 3 Step 4 tells the implementer to reuse smoke_test.gd's real identifiers — this is a deliberate "match existing names" instruction, not a placeholder (the exact variable names are in the file being edited).

**Type consistency:** `is_grass(Color) -> bool`, `green_cell_count() -> int`, `blade_count() -> int`, `_hash01`, `CELL/STRIDE/RING/MAX_BLADES` used consistently across Tasks 2–3 and the smoke gate. `night_amount` global uniform matches the existing declaration in building_windows/terrain. `CAMERA_POSITION_WORLD` is the correct Godot 4 fragment built-in. `QuadMesh.center_offset` and `surface_set_material` are valid Godot 4 API.

**Risk notes for the implementer:** (a) if `CAMERA_POSITION_WORLD` produces a wrong-direction ray (interior looks inverted), negate `rd`; verify against the day street shot. (b) The grass y-raycast needs terrain collision resident (it is, within the near ring per the M5 collision-ring); if tufts sit at y=0 in the air, the ray missed — widen the ray or gate placement on a hit. (c) `surface_get_arrays` returns the tile's LOCAL verts; the `global_transform` multiply is mandatory or green cells land at the origin.
