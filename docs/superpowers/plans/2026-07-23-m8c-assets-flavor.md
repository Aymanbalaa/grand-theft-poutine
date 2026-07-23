# M8c — Assets & Flavor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 16.5k procedural lollipop trees and boxy lamp poles with real CC0 models via GPU-instanced MultiMesh, fix the white untextured car (+ clearcoat paint), and add benches/hydrants from OSM — the asset pass that makes street level read as a finished game.

**Architecture:** Prop POSITIONS move from baked tile geometry to `city_metadata.json` (the `lamps` pattern: `[x,y,z]` lists). The game builds one global `MultiMeshInstance3D` per prop model at load — GPU instancing handles 16.5k trees trivially; no per-tile streaming needed (light_pool.gd already proves metadata-driven props work). Baked `props` geometry shrinks to traffic lights only. Cars: diagnose the texture-load failure with isolated captures, then a two-layer fix (import-side if found + a material safety net in car_visual.gd that assigns the colormap when albedo is missing and adds clearcoat paint).

**Tech Stack:** Python pipeline (pytest, TDD), Godot 4.5 (GDScript, MultiMesh), CC0 models (Quaternius/Kenney).

**Deliberate scope cuts (surface at the gate):** (1) AI-generated Montreal storefront/mural decals and the 8b-deferred crack/manhole decals are deferred again — both need UV-mapped decal geometry infrastructure that doesn't exist; if wanted, they become their own phase after M8. (2) Bus stops: OSM `highway=bus_stop` nodes exist but a bus-stop shelter model + placement orientation is disproportionate effort for this pass — benches and hydrants only.

## Global Constraints

- Commits authored ONLY by Aymanbalaa via repo-local git config. NO `Co-Authored-By`/AI trailers, NO `--author` flags, NO git-config changes. Repeat verbatim in every subagent dispatch.
- Commit small and frequent; one commit per task minimum.
- License-clean: CC0 only for models; every committed model gets a SOURCE.md entry (asset pack, URL, license, download date — mirror `game/assets/models/cars/SOURCE.md`) and a CREDITS.md line if the source is new.
- Deterministic pipeline: NO network in `pipeline.build`. Model downloads are a manual, documented step (M6c car-kit precedent).
- Rebuild rules: expect 314 tiles, check `git status game/world/` for orphans, `--headless --path game --import` after tile/asset changes.
- Headless smoke stays green and GAINS a gate this phase (Task 4): final sequence ends `SMOKE OK: 314 tiles` with a new `PROPS OK` line before `SMOKE OK`.
- pytest: currently 91 passing → ends at 92 (2 new, 1 obsolete removed).
- `night_amount` / light_pool contract: the 24-light pool keyed to `meta["lamps"]` MUST keep working — lamp positions stay in metadata untouched (only the baked pole GEOMETRY moves to MultiMesh).
- Screenshots judged only by Reading PNGs; night regression fails the phase.
- Perf constraint from spec: everything instanced (MultiMesh); tile streaming and 280 m collision ring untouched; 120-car behavior unchanged. Props have no collision (today's behavior, kept).

---

### Task 1: Prop positions to metadata; slim the baked props bucket (pipeline)

**Files:**
- Modify: `pipeline/osm_parse.py` (parse benches + hydrants; CityData fields)
- Modify: `pipeline/export.py:44-47` (metadata keys `trees`, `benches`, `hydrants`)
- Modify: `pipeline/tiler.py:82-95` (stop baking tree + lamp meshes into props; keep traffic lights)
- Test: `pipeline/tests/test_osm_parse.py`, `pipeline/tests/test_export.py`
- Delete test: `test_tree_cap_deterministic` in `pipeline/tests/test_export.py:85-95` (cap is obsolete — trees no longer baked)

**Interfaces:**
- Consumes: existing `city.trees` / `city.lamps` (`list[tuple[float,float]]`, osm_parse.py:176-177).
- Produces: `city_metadata.json` gains `"trees"`, `"benches"`, `"hydrants"` — each a list of `[x, y, z]` rounded to 1 decimal, y = heightmap sample, exactly the `lamps` shape at export.py:45-46. `CityData` gains `benches: list = None`-style fields following the `trees` field pattern (osm_parse.py:39-41). Baked `props` geometry = traffic lights only.

- [ ] **Step 1: Write the failing tests**

In `pipeline/tests/test_osm_parse.py`, extend the fixture XML used by `test_trees_and_lamps_parsed` (line 72) with two nodes inside the same `<osm>` body (`amenity=bench`, `emergency=fire_hydrant` — copy an existing tree node element and change the tag), then append:

```python
def test_benches_and_hydrants_parsed():
    city = parse_osm(FIX)   # same fixture-loading call as test_trees_and_lamps_parsed
    assert len(city.benches) == 1
    assert len(city.hydrants) == 1
    assert all(len(p) == 2 for p in city.benches + city.hydrants)
```

In `pipeline/tests/test_export.py`, append (mirror `test_export_writes_glb_and_metadata`'s setup at line 22 — same fixture/tmp_path/export_city call):

```python
def test_prop_positions_in_metadata(tmp_path):
    meta = <same export_city(...) call pattern as test_export_writes_glb_and_metadata>
    for key in ("trees", "benches", "hydrants"):
        assert key in meta
        assert all(len(p) == 3 for p in meta[key])
    assert len(meta["trees"]) >= 1
```

(`<...>` means: copy the existing setup lines from the named test verbatim.)

- [ ] **Step 2: Run both new tests, verify they fail** (missing CityData fields / metadata keys).

- [ ] **Step 3: Implement**

`pipeline/osm_parse.py`:
- Node recognition (lines 127-138): add to the chain, following the exact `tree_ids` pattern:

```python
        elif tags.get("amenity") == "bench":
            bench_ids[nid] = (lat, lon)
        elif tags.get("emergency") == "fire_hydrant":
            hydrant_ids[nid] = (lat, lon)
```

(initialize `bench_ids/hydrant_ids = {}` next to `tree_ids`).
- `CityData` (lines 34-41): add `benches` and `hydrants` fields exactly like `trees`.
- Final assembly (lines 176-177): `city.benches = [latlon_to_xz(*bench_ids[i]) for i in sorted(bench_ids)]`, same for hydrants.

`pipeline/export.py` (next to `"lamps"`, lines 44-47): add three keys with the identical comprehension shape:

```python
        "trees": [[round(x, 1), round((hm.sample(x, z) if hm is not None else 0.0), 1), round(z, 1)]
                  for x, z in city.trees],
        "benches": [...same for city.benches...],
        "hydrants": [...same for city.hydrants...],
```

(Write all three out fully — no `[...]` in the real code.)

`pipeline/tiler.py` (lines 82-95): delete the tree-baking block (including the `tree_count` cap logic) and the lamp-baking block; keep the traffic-signal block. Delete `MAX_TREES_PER_TILE` from `pipeline/config.py` if nothing else uses it (grep first). `tree_mesh`/`lamp_mesh` in meshes.py become uncalled — delete them AND their config colors if grep shows no other users; if a test still exercises them directly, delete that test too and say so in your report.

- [ ] **Step 4: Full pytest**

Run: `.venv/Scripts/python -m pytest pipeline -q` → 92 passed (91 + 2 new − 1 removed `test_tree_cap_deterministic`). `test_props_geometry_in_tiles` must still pass (fixture has a traffic signal, so a `props` node survives). If other tests referenced the deleted helpers, adjust per Step 3 and report exact deltas.

- [ ] **Step 5: Commit**

```bash
git add pipeline/osm_parse.py pipeline/export.py pipeline/tiler.py pipeline/config.py pipeline/meshes.py pipeline/tests/test_osm_parse.py pipeline/tests/test_export.py
git commit -m "pipeline: tree/bench/hydrant positions to metadata; props bucket bakes signals only"
```

---

### Task 2: CC0 prop models (download, validate, commit)

**Files:**
- Create: `game/assets/models/props/tree0.glb`, `tree1.glb`, `tree2.glb`, `lamp_post.glb`, `bench.glb`, `hydrant.glb` (+ any texture files they reference, kept in relative position)
- Create: `game/assets/models/props/SOURCE.md`
- Modify: `CREDITS.md` (only if a new source (e.g. Quaternius direct) isn't already credited)
- Modify: `game/tests/models_test.gd` (validate the new GLBs)

**Interfaces:**
- Produces: six GLBs at exactly these paths — Task 4 loads them by these names. Each must contain at least one `MeshInstance3D` with a non-null mesh, reasonable footprint (trees 3–8 m tall, lamp ~5 m, bench/hydrant <1.5 m — rescaling in Task 4 is fine but record native sizes in SOURCE.md).

- [ ] **Step 1: Source the models (network allowed — manual asset step, M6c precedent).** Preferred sources, in order: Quaternius "Ultimate Nature"/"Stylized Nature" packs (CC0, quaternius.com) for the three tree variants; Kenney kits (kenney.nl — Nature Kit / City Kit / Roads) for lamp post, bench, hydrant. Any CC0 pack with GLB/GLTF format works; convert OBJ→GLB via a scripted Godot import ONLY if no GLB exists (prefer packs shipping GLB). Verify the license page says CC0 at download time and record the URL. If a hydrant (or bench) genuinely isn't available CC0 in these packs, SKIP that model, note it in SOURCE.md and your report — Task 4 degrades gracefully per-key.

- [ ] **Step 2: Rename/place** the chosen files at the exact paths above (keep referenced texture files in their relative positions next to the GLBs, like the car kit's `Textures/colormap.png`).

- [ ] **Step 3: Write SOURCE.md** — pack name, author, URL, license (CC0), download date, native model names → our filenames mapping, native dimensions, texture dependencies (external URIs, if any — flag them explicitly; the car kit's external colormap has been a hazard).

- [ ] **Step 4: Extend `game/tests/models_test.gd`** — mirror its existing car-GLB validation loop for the six new paths (load, instantiate, assert a MeshInstance3D with non-null mesh exists; skip-with-print for models recorded as unavailable in SOURCE.md).

- [ ] **Step 5: Import + validate**

Run: `tools/godot/godot_console.exe --headless --path game --import` then the models test the same way smoke runs scripts: `tools/godot/godot_console.exe --headless --path game --script res://tests/models_test.gd` → all validations print OK.

- [ ] **Step 6: LOOK at the models.** Render is not available headless; instead confirm each GLB's mesh stats are sane via the models_test output (vertex counts > 0) and Read the pack's preview image if one was downloaded. Full visual judgment happens in Task 6 screenshots.

- [ ] **Step 7: Commit** (include every texture the GLBs reference; do NOT force-add `.import` files):

```bash
git add game/assets/models/props CREDITS.md game/tests/models_test.gd
git commit -m "assets: CC0 prop models - trees, lamp post, bench, hydrant"
```

---

### Task 3: World rebuild (props slim to signals; metadata gains prop keys)

Controller-led (M7/M8b precedent).

- [ ] **Step 1:** `.venv/Scripts/python -m pipeline.build` (caches only, no network).
- [ ] **Step 2:** Orphan check: `git status --short game/world/` — no `??` files; expect ~all tiles modified (props shrink) + `city_metadata.json`.
- [ ] **Step 3:** `--headless --path game --import`, then headless smoke → `SMOKE OK: 314 tiles` (16 gates — the new PROPS gate arrives in Task 4).
- [ ] **Step 4:** Commit: `git add game/world && git commit -m "world: M8c rebuild - props bake signals only; tree/bench/hydrant metadata"`

---

### Task 4: MultiMesh prop renderer + smoke gate

**Files:**
- Create: `game/scripts/props_multimesh.gd`
- Modify: `game/scenes/main.tscn` (add `Props` Node3D with the script)
- Modify: `game/tests/smoke_test.gd` (new `PROPS OK` gate)

**Interfaces:**
- Consumes: `city_metadata.json` keys `trees`/`lamps`/`benches`/`hydrants` (each `[[x,y,z],...]`); Task 2's GLBs by exact path.
- Produces: node `Props` (group `"props"`) with method `instance_count(key: String) -> int` — the smoke gate calls it.

- [ ] **Step 1: Write `game/scripts/props_multimesh.gd`**

```gdscript
extends Node3D
## Builds one MultiMeshInstance3D per prop model from metadata positions.
## GPU instancing carries all instances resident; Godot culls by MultiMesh AABB.

const SPECS := [
	{"key": "trees", "models": ["res://assets/models/props/tree0.glb",
			"res://assets/models/props/tree1.glb", "res://assets/models/props/tree2.glb"],
		"scale_min": 0.85, "scale_max": 1.3},
	{"key": "lamps", "models": ["res://assets/models/props/lamp_post.glb"],
		"scale_min": 1.0, "scale_max": 1.0},
	{"key": "benches", "models": ["res://assets/models/props/bench.glb"],
		"scale_min": 1.0, "scale_max": 1.0},
	{"key": "hydrants", "models": ["res://assets/models/props/hydrant.glb"],
		"scale_min": 1.0, "scale_max": 1.0},
]

var _counts := {}

func _ready() -> void:
	add_to_group("props")
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if f == null:
		return
	var meta = JSON.parse_string(f.get_as_text())
	if typeof(meta) != TYPE_DICTIONARY:
		return
	for spec in SPECS:
		_build(spec, meta.get(spec["key"], []))

func instance_count(key: String) -> int:
	return _counts.get(key, 0)

static func _hash01(x: float, z: float, salt: float) -> float:
	return fposmod(sin(x * 12.9898 + z * 78.233 + salt) * 43758.5453, 1.0)

func _build(spec: Dictionary, positions: Array) -> void:
	if positions.is_empty():
		return
	var meshes: Array[Mesh] = []
	for path in spec["models"]:
		var m := _first_mesh(path)
		if m != null:
			meshes.append(m)
	if meshes.is_empty():
		return
	# bucket positions by model variant (hash of position)
	var buckets: Array = []
	for i in meshes.size():
		buckets.append(PackedVector3Array())
	for p in positions:
		var v := Vector3(p[0], p[1], p[2])
		var mi := int(_hash01(v.x, v.z, 7.7) * meshes.size()) % meshes.size()
		buckets[mi].append(v)
	var total := 0
	for i in meshes.size():
		if buckets[i].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[i]
		mm.instance_count = buckets[i].size()
		for j in buckets[i].size():
			var v: Vector3 = buckets[i][j]
			var yaw := _hash01(v.x, v.z, 3.1) * TAU
			var s: float = lerp(spec["scale_min"], spec["scale_max"], _hash01(v.x, v.z, 5.3))
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), v)
			mm.set_instance_transform(j, xf)
		var inst := MultiMeshInstance3D.new()
		inst.multimesh = mm
		inst.name = "%s_%d" % [spec["key"], i]
		add_child(inst)
		total += buckets[i].size()
	_counts[spec["key"]] = total

static func _first_mesh(path: String) -> Mesh:
	if not ResourceLoader.exists(path):
		return null
	var scene = load(path)
	if scene == null:
		return null
	var root = scene.instantiate()
	var mesh := _find_mesh(root)
	root.free()
	return mesh

static func _find_mesh(node: Node) -> Mesh:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		var m := mi.mesh
		# bake the importer's surface materials into the mesh so MultiMesh keeps them
		for s in m.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat != null:
				m.surface_set_material(s, mat)
		return m
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null
```

- [ ] **Step 2: Wire into `game/scenes/main.tscn`** — add a child node: `[node name="Props" type="Node3D" parent="."]` with `script = ExtResource(...)` pointing at `res://scripts/props_multimesh.gd` (add the matching `ext_resource` line and bump `load_steps` by 2 — one ext_resource, and verify against the actual header count).

- [ ] **Step 3: Smoke gate** — in `game/tests/smoke_test.gd`, after the LIGHTS gate block (line ~86-91), add (mirror the existing gate style — `push_error` + `quit(1)` on failure, print on success):

```gdscript
	var props := root.get_tree().get_first_node_in_group("props")
	if props == null or props.call("instance_count", "trees") < 10000:
		push_error("PROPS FAIL: trees=%s" % (props.call("instance_count", "trees") if props else "no node"))
		get_tree().quit(1); return
	if props.call("instance_count", "lamps") != 499:
		push_error("PROPS FAIL: lamps=%d" % props.call("instance_count", "lamps"))
		get_tree().quit(1); return
	print("PROPS OK: %d trees, %d lamps, %d benches, %d hydrants" % [
		props.call("instance_count", "trees"), props.call("instance_count", "lamps"),
		props.call("instance_count", "benches"), props.call("instance_count", "hydrants")])
```

(Adapt mechanically to the file's actual gate idiom — read the LIGHTS gate and copy its structure; the assertions and the printed line are the requirement.)

- [ ] **Step 4: Headless smoke** → new line `PROPS OK: ...` (trees ≥ 10000, lamps exactly 499) and final `SMOKE OK: 314 tiles` (now 17 gates).

- [ ] **Step 5: Commit**

```bash
git add game/scripts/props_multimesh.gd game/scenes/main.tscn game/tests/smoke_test.gd
git commit -m "game: MultiMesh props - real trees, lamp posts, benches, hydrants; PROPS smoke gate"
```

---

### Task 5: White-car diagnosis + fix + clearcoat paint

**Files:**
- Create: `game/tests/car_capture.gd` (diagnostic, committed — reusable)
- Modify: `game/scripts/car_visual.gd` (material safety net + clearcoat)
- Possibly modify: `game/assets/models/cars/*.glb.import` semantics via re-import settings — ONLY if diagnosis shows an import-side cause, and note that `.import` files are gitignored so any import-side fix must be expressed in a way that survives a fresh clone (e.g. fixing the GLB itself or applying the game-side safety net; do NOT force-add `.import` files).

**Interfaces:**
- Consumes: `car0-5.glb` + `Textures/colormap.png` (external-URI dependency).
- Produces: cars render textured with clearcoat paint; procedural fallback path untouched.

- [ ] **Step 1: Diagnostic captures.** Write `game/tests/car_capture.gd` (windowed, GPU): a minimal scene script that instantiates each of `car0.glb`..`car5.glb` in a row on a grey plane with a camera and a DirectionalLight, waits for frames to settle (copy the settle idiom from `res://tests/screenshot.gd`), saves ONE png `car_lineup.png` to `user://`, prints its path, quits. Run it: `tools/godot/godot_console.exe --path game --script res://tests/car_capture.gd`. Read the PNG. Judge: do ANY of the six show multi-tone texturing (darker glass, distinct wheels)? Record the verdict in your report with the image.

- [ ] **Step 2: Root-cause check.** If all six are flat white: the colormap texture isn't resolving. Inspect `game/assets/models/cars/car0.glb.import` — the suspicious param is `gltf/embedded_image_handling` (a prior investigation flagged value 1). Test the hypothesis: change the import option via a re-import with corrected settings (edit the `.import` file's param, re-run `--headless --path game --import`), re-run Step 1's capture. Whatever you learn, remember `.import` files are GITIGNORED — an import-param fix alone will silently regress on fresh clones, so Step 3's safety net is REQUIRED regardless of what you find here. Document the root cause in your report.

- [ ] **Step 3: Material safety net + clearcoat in `car_visual.gd`.** After the model-load success path sets scale/rotation (lines 74-79), walk the instantiated model and fix materials:

```gdscript
	_polish_materials(inst)
```

and add:

```gdscript
static func _polish_materials(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat == null:
				continue
			if mat.albedo_texture == null:
				var tex := load("res://assets/models/cars/Textures/colormap.png") as Texture2D
				if tex != null:
					mat.albedo_texture = tex
			mat.clearcoat_enabled = true
			mat.clearcoat = 0.6
			mat.clearcoat_roughness = 0.2
			mat.metallic = 0.25
			mat.roughness = 0.35
	for child in node.get_children():
		_polish_materials(child)
```

- [ ] **Step 4: Verify.** Re-run the Step 1 capture; Read the PNG: six textured cars with visible paint variety and specular highlights. Then headless smoke → green (CARVIS gate must still pass).

- [ ] **Step 5: Commit**

```bash
git add game/tests/car_capture.gd game/scripts/car_visual.gd
git commit -m "game: fix untextured cars + clearcoat paint; car lineup diagnostic"
```

(If Step 2 additionally changed a GLB file itself, include it and explain in the commit body.)

---

### Task 6: Screenshot iteration + gate

Controller-led. Do NOT skip the looking.

- [ ] **Step 1: Full screenshot run; judge every pose** vs `docs/screenshots/m8b_*.png`:
  - Trees are the headline: real canopies at every distance, no lollipops, believable variety (3 models × rotation × scale). Watch for: floating/buried trees (y from heightmap vs terrain drift), garish scale outliers, AABB pop-in.
  - Lamp posts: real poles at plausible positions; night light pool still centered on them.
  - Cars: driving poses show a textured car with clearcoat.
  - Benches/hydrants: visible at street level where OSM has them (may be sparse — fine).
  - `night`/`onfoot_night`/`driving_night`: NO regression (money shot); tree silhouettes shouldn't read as black blobs against lit windows.
  - Everything else: no regression.
- [ ] **Step 2: Tune and repeat.** Knobs: SPECS scale ranges, per-model rescale (if a pack's native size is off, set it in the spec's scale range), y-offset if models float/sink (add a per-spec `"y_off"` only if needed). Commit each round.
- [ ] **Step 3: Keepers** → `docs/screenshots/m8c_<pose>.png` (avoid copying stray `shot_centerline.png`).
- [ ] **Step 4: Final green:** pytest → 92; smoke → `SMOKE OK: 314 tiles` with `PROPS OK` line (17 gates).
- [ ] **Step 5: HANDOFF.md** — prepend M8c state (props architecture, car root cause + fix, scope cuts, counts), demote prior.
- [ ] **Step 6: Commit docs; final whole-branch review; STOP — user gate** with m8b-vs-m8c pairs. M8 completion decision (tag/push + whether decals become a follow-up phase) belongs to the user.
