# M9c2 — Life & Flavor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the blocky tuque figure the camera follows with a CC0 rigged humanoid (keeping the tuque), and add procedural colored awnings over commercial storefronts — the two "life & flavor" features of M9c.

**Architecture:** (1) Player: source a CC0 rigged low-poly humanoid, load it in `character_visual.gd` mirroring `car_visual.gd`'s GLB-load + material-polish + procedural-fallback pattern; drive idle/walk from the parent CharacterBody3D's speed if the model ships animation clips, else static pose; re-add the tuque as a small mesh at the head. (2) Awnings: a NEW tile geometry bucket `awnings` — `pipeline/meshes.py::awning_mesh(b, hm)` emits sloped colored quads over commercial buildings' ground-floor footprint edges, the tiler buckets them, and `tile_loader.gd` routes them to a flat vertex-colored material (they must NOT ride the `buildings` bucket or the facade window shader would project windows onto them).

**Tech Stack:** Godot 4.5 (glTF skeletal models, AnimationPlayer, BoneAttachment3D, StandardMaterial3D), Python pipeline (trimesh, shapely, PIL, pytest, TDD), CC0 assets.

## Global Constraints

- Commits authored ONLY by Aymanbalaa via the repo-local git config (noreply email). NO `Co-Authored-By`/AI trailers, NO `--author` flags, NO git-config changes. Repeat verbatim in every subagent dispatch.
- Commit small and frequent; one commit per task minimum.
- CC0-only assets, license verified LIVE (License.txt in the pack + the asset page), recorded in a `SOURCE.md` next to the model — mirror `game/assets/models/props/SOURCE.md` (pack, author, license, source URL, download date, license evidence, files table, native dimensions).
- Deterministic pipeline: NO network in `pipeline.build`; asset/texture fetches are manual-only.
- Rebuild rules: expect 314 tiles, orphan check (`git status --short game/world/`), `--headless --path game --import` after tile changes. Awnings ADD geometry to existing tiles — no tile-count change expected.
- Contracts untouched: vertex-alpha packing (`category*40 + round(base_y/2)`), `night_amount` global, facade seed-from-RGB (`bhash`), the m9b crosswalk/manhole/door work, the m9c1 window-interior + grass work. Awnings are a NEW bucket — they must not alter the `buildings` bucket bytes for non-commercial tiles.
- `.gd`/`.gdshader` files written WITHOUT a UTF-8 BOM (PowerShell `Set-Content` hazard — use Bash/editor tools).
- Smoke stays green. This phase adds ONE gate (Task 4: `AWNINGS OK`) → 20 gates ending `SMOKE OK: 314 tiles`. pytest 97 → 99 (2 new awning tests). Headless smoke: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd` (console wrapper from Bash — the GUI exe returns nothing).
- Night regression fails the phase; screenshots judged only by Reading PNGs.

---

### Task 1: Source the CC0 rigged player model (+ SOURCE.md + load test)

**Files:**
- Create: `game/assets/models/character/character.glb` (the committed CC0 model)
- Create: `game/assets/models/character/SOURCE.md`
- Create: `game/tests/character_model_test.gd` (headless: model loads, reports skeleton + animation clips)

**Interfaces:**
- Produces: `res://assets/models/character/character.glb` — Task 2 loads exactly this path.
- Produces (in the report): the exact node structure the model instantiates — whether it contains an `AnimationPlayer` and, if so, the clip names (e.g. `Idle`, `Walk`), and whether it has a `Skeleton3D` with a head/hat bone. Task 2's animation wiring depends on these findings.

**This task involves a manual network download (allowed — not part of `pipeline.build`).**

- [ ] **Step 1: Choose and download a CC0 rigged humanoid.** Prefer **Kenney "Mini Characters 1"** (CC0, low-poly rigged humans with an `AnimationPlayer` carrying idle/walk/run/etc. clips — aesthetically consistent with this game's blocky world and it keeps a hat-friendly head), source https://kenney.nl/assets/mini-characters-1 . Acceptable CC0 alternative: **Quaternius "Ultimate Modular Men"** / "Universal Animation Library". Download the pack, and CONFIRM the license live: open the pack's bundled `License.txt` AND the asset page — both must state CC0. If neither confirms CC0, STOP and report BLOCKED with what you found (do NOT substitute a non-CC0 source).

- [ ] **Step 2: Select one character GLB**, copy it to `game/assets/models/character/character.glb`. If the pack ships FBX/OBJ only, convert to glTF is out of scope — pick a pack that ships `.glb`/`.gltf` (Kenney Mini Characters ships glTF). Keep the model's own textures/materials as authored.

- [ ] **Step 3: Write the headless inspection test** `game/tests/character_model_test.gd`:

```gdscript
extends SceneTree
# godot_console --headless --path game --script res://tests/character_model_test.gd
func _init() -> void:
	var path := "res://assets/models/character/character.glb"
	assert(ResourceLoader.exists(path), "character.glb missing at %s" % path)
	var packed: PackedScene = load(path)
	assert(packed != null, "character.glb failed to load as PackedScene")
	var inst := packed.instantiate()
	assert(inst != null, "character.glb failed to instantiate")
	# report skeleton + animations for Task 2
	var anim := inst.find_child("AnimationPlayer", true, false)
	var skel := inst.find_child("*", true, false)  # replaced below with a Skeleton3D search
	var clips := []
	if anim != null:
		clips = (anim as AnimationPlayer).get_animation_list()
	var sk := _find_skeleton(inst)
	var bones := []
	if sk != null:
		for i in sk.get_bone_count():
			bones.append(sk.get_bone_name(i))
	print("CHARACTER OK: anim=%s clips=%s bones=%d" % [anim != null, clips, bones.size()])
	print("BONES: %s" % [bones])
	inst.free()
	quit()

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
```

- [ ] **Step 4: Import + run the test**:

Run: `tools/godot/godot_console.exe --headless --path game --import`
Then: `tools/godot/godot_console.exe --headless --path game --script res://tests/character_model_test.gd`
Expected: prints `CHARACTER OK: anim=<true/false> clips=[...] bones=<n>` and a `BONES: [...]` line. RECORD these in your report verbatim — Task 2 needs the clip names and the head-bone name.

- [ ] **Step 5: Write `SOURCE.md`** mirroring `game/assets/models/props/SOURCE.md`'s structure (pack, author, license, source URL, download date, license evidence quoting the pack's License.txt, files table, native bounding-box dimensions from the test).

- [ ] **Step 6: Commit** (model + SOURCE.md + test + generated `.uid`s; do NOT commit the whole downloaded pack — only the one GLB and any texture it references):

```bash
git add game/assets/models/character game/tests/character_model_test.gd game/tests/character_model_test.gd.uid
git commit -m "assets: CC0 rigged player character model + SOURCE + load test"
```

Report DONE_WITH_CONCERNS if the model lacks idle/walk clips (Task 2 will ship static) — this is expected-path information, not a failure.

---

### Task 2: Swap the character visual to the model (animation + tuque, procedural fallback)

**Files:**
- Modify: `game/scripts/character_visual.gd`

**Interfaces:**
- Consumes: `res://assets/models/character/character.glb` and the clip/bone names reported by Task 1; the parent `CharacterBody3D` (`get_parent()`) and its `.velocity` (already used at character_visual.gd:48).
- Produces: no signature change — the `Visual` node in `player.tscn` keeps script `character_visual.gd`; enter/exit-car (main.gd hides `Visual` while driving) and the third-person camera are unaffected.

- [ ] **Step 1: Rework `_ready()`** to load the model first, mirroring `car_visual.gd:66-81`. Keep the existing procedural builders (`_box`/`_limb`/the blocky assembly) as a `_build_procedural()` fallback called only when the model is absent. Skeleton/scale/orient values (scale, `rotation.y`) come from the Task 1 report's native dimensions — the character must stand ~1.7 m tall and face −Z (the movement code at :51 yaws the whole Visual, so the model just needs its rest facing aligned like the procedural one).

```gdscript
# _ready() outline (fill scale/clip/bone from the Task 1 report):
func _ready() -> void:
	var path := "res://assets/models/character/character.glb"
	if ResourceLoader.exists(path):
		var packed: PackedScene = load(path)
		if packed != null:
			var inst := packed.instantiate()
			if inst != null:
				add_child(inst)
				var n3d := inst as Node3D
				if n3d != null:
					n3d.scale = Vector3.ONE * MODEL_SCALE   # from Task 1 dims (~1.7 m tall)
					n3d.rotation.y = MODEL_YAW               # 0 or PI so it faces -Z at rest
				_anim = inst.find_child("AnimationPlayer", true, false)
				_attach_tuque(inst)
				_model_mode = true
				return
	_build_procedural()
```

- [ ] **Step 2: Add the tuque.** If Task 1 reported a head bone, parent a small tuque `MeshInstance3D` (reuse the procedural `TUQUE` color box, size ~0.28×0.14×0.28) to a `BoneAttachment3D` bound to that bone so it tracks the head during animation; else add the tuque as a fixed child at the model's head height (approx from Task 1 dims). Provide BOTH paths in code, choosing by whether the head bone exists:

```gdscript
func _attach_tuque(root: Node) -> void:
	var sk := _find_skeleton(root)
	var hat := _tuque_mesh()   # MeshInstance3D, TUQUE color, size (0.28,0.14,0.28)
	if sk != null and HEAD_BONE != "" and sk.find_bone(HEAD_BONE) != -1:
		var ba := BoneAttachment3D.new()
		ba.bone_name = HEAD_BONE
		sk.add_child(ba)
		ba.add_child(hat)
		hat.position = HAT_OFFSET   # small local offset onto the crown, from Task 1 dims
	else:
		hat.position = Vector3(0.0, HEAD_Y, 0.0)   # fixed fallback
		add_child(hat)
```

- [ ] **Step 3: Drive animation from speed** in `_process(delta)`. Keep the existing yaw-toward-velocity logic (character_visual.gd:48-52). If `_model_mode` and `_anim` exists and Task 1 reported the clip names, cross-play idle vs walk by speed; else (static model or procedural) keep/branch to the existing procedural limb swing. Do NOT run the procedural limb swing on the model.

```gdscript
func _process(delta: float) -> void:
	if _body == null:
		return
	var speed := Vector2(_body.velocity.x, _body.velocity.z).length()
	if speed > 0.5:
		rotation.y = lerp_angle(rotation.y, atan2(-_body.velocity.x, -_body.velocity.z), 10.0 * delta)
	if _model_mode:
		if _anim != null:
			var want := WALK_CLIP if speed > 0.6 else IDLE_CLIP   # names from Task 1
			if want != "" and _anim.current_animation != want:
				_anim.play(want)
		return
	# ... existing procedural limb swing unchanged ...
```

- [ ] **Step 4: Verify.** Headless smoke must still pass its player gates (PLAYER OK / LANDED OK) with no SCRIPT ERROR: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd` → ends `SMOKE OK: 314 tiles`. Then capture a look: `tools/godot/godot_console.exe --path game --script res://tests/screenshot.gd`; Read `shot_onfoot_day.png` (character reads as a person WITH the tuque, standing on the ground not sunk/floating) and `shot_onfoot_night.png`. (Full judging is Task 5.)

- [ ] **Step 5: Commit**

```bash
git add game/scripts/character_visual.gd
git commit -m "game: swap player to CC0 rigged character (animated) keeping the tuque"
```

Report DONE_WITH_CONCERNS with specifics if the model sinks/floats, faces the wrong way, or the tuque won't bind — those are Task 5 tuning items but flag them.

---

### Task 3: Storefront awnings (pipeline geometry, new bucket)

**Files:**
- Create: `pipeline/meshes.py::awning_mesh` (new function)
- Modify: `pipeline/config.py` (awning constants + palette)
- Modify: `pipeline/tiler.py` (call `awning_mesh`, bucket `awnings`, add to the assembly cat tuple at tiler.py:97)
- Modify: `game/scripts/tile_loader.gd` (route `awnings` geometry to a flat vertex-colored material)
- Test: `pipeline/tests/test_meshes.py`

**Interfaces:**
- Consumes: `Building` (`.footprint`, `.btype`, `.osm_id`, `.height`), `config.BUILDING_CATEGORIES`, `_jitter3`, `_paint`, `Heightmap.sample`, shapely `Polygon`/`orient`.
- Produces: a trimesh named into the `awnings` bucket per tile; `tile_loader.gd` renders any geometry whose node name begins `awnings` with `_awning_mat`.

- [ ] **Step 1: Write the failing tests** in `pipeline/tests/test_meshes.py` (mirror the existing building fixture style):

```python
def test_awning_on_commercial_building():
    b = <Building fixture, btype that maps to "commercial" in config.BUILDING_CATEGORIES,
         a rectangular footprint ~12x8 m, height 12.0, osm_id set>
    m = awning_mesh(b, hm=None)
    assert m is not None
    assert len(m.faces) > 0
    # awnings sit at storefront height, well below the roof
    assert m.vertices[:, 1].max() < config.AWNING_TOP_Y + 0.01
    assert m.vertices[:, 1].min() > 0.0

def test_no_awning_on_residential_building():
    b = <same fixture but a residential btype>
    assert awning_mesh(b, hm=None) is None
```

(Replace `<...>` with the concrete `Building` construction used by the existing building tests in this file; tighten the max/min-Y and face-count assertions to exact numbers computed from the constants once implemented.)

- [ ] **Step 2: Run, verify failure** (`awning_mesh` undefined):

Run: `.venv/Scripts/python -m pytest pipeline/tests/test_meshes.py -k awning -q`
Expected: FAIL (NameError / not defined).

- [ ] **Step 3: Constants** in `pipeline/config.py`:

```python
AWNING_TOP_Y = 3.3        # wall attach height (m above base) — just above the storefront band
AWNING_DROP = 0.6         # how far the outer edge hangs below the attach height (m)
AWNING_DEPTH = 0.9        # outward protrusion from the wall (m)
AWNING_MIN_EDGE = 3.0     # skip footprint edges shorter than this (m)
AWNING_INSET = 0.4        # pull each awning in from the edge ends (m)
AWNING_COLORS = [         # deterministic per-building pick (Montréal storefront reds/greens/blues)
    (0.62, 0.16, 0.14), (0.15, 0.35, 0.22), (0.16, 0.28, 0.48),
    (0.55, 0.42, 0.14), (0.30, 0.30, 0.33),
]
```

- [ ] **Step 4: Implement `awning_mesh`** in `pipeline/meshes.py` (place near `building_mesh`; read `_paint`/`_densify` signatures and reuse them):

```python
from shapely.geometry.polygon import orient

def awning_mesh(b: Building, hm: Heightmap | None = None) -> trimesh.Trimesh | None:
    cat = config.BUILDING_CATEGORIES.get(b.btype, "default")
    if cat != "commercial":
        return None
    poly = Polygon(b.footprint)
    if not poly.is_valid:
        poly = poly.buffer(0)
    if poly.is_empty or poly.geom_type != "Polygon" or poly.area < 1.0:
        return None
    poly = orient(poly, sign=1.0)            # force CCW exterior -> outward normal is the right perpendicular
    base_y = hm.sample(poly.centroid.x, poly.centroid.y) if hm is not None else 0.0
    coords = list(poly.exterior.coords)[:-1]
    verts, faces = [], []
    top = base_y + config.AWNING_TOP_Y
    outy = top - config.AWNING_DROP
    color = config.AWNING_COLORS[int(_jitter_pick(b.osm_id)) % len(config.AWNING_COLORS)]
    for (x1, z1), (x2, z2) in zip(coords, coords[1:] + coords[:1]):
        dx, dz = x2 - x1, z2 - z1
        L = math.hypot(dx, dz)
        if L < config.AWNING_MIN_EDGE:
            continue
        ux, uz = dx / L, dz / L
        ox, oz = uz, -ux                      # outward (right) normal for CCW ring
        # pull ends in by AWNING_INSET
        ax1, az1 = x1 + ux * config.AWNING_INSET, z1 + uz * config.AWNING_INSET
        ax2, az2 = x2 - ux * config.AWNING_INSET, z2 - uz * config.AWNING_INSET
        i = len(verts)
        # wall-top edge (a1,a2) at `top`; outer edge (b1,b2) at `outy`, pushed out by depth
        verts += [
            [ax1, top, az1], [ax2, top, az2],
            [ax2 + ox * config.AWNING_DEPTH, outy, az2 + oz * config.AWNING_DEPTH],
            [ax1 + ox * config.AWNING_DEPTH, outy, az1 + oz * config.AWNING_DEPTH],
        ]
        faces += [[i, i + 1, i + 2], [i, i + 2, i + 3]]      # sloped top, wound so the normal faces up/out
    if not faces:
        return None
    m = trimesh.Trimesh(vertices=np.array(verts, dtype=float),
                        faces=np.array(faces), process=False)
    return _paint(m, color, 1.0)             # flat vertex color, no alpha packing needed for the awning bucket
```

Add a small deterministic helper if one does not already exist (check `meshes.py` — it may already have `_jitter3`; reuse or add):

```python
def _jitter_pick(osm_id: int) -> float:
    return abs(math.sin(float(osm_id) * 12.9898) * 43758.5453) % 1000.0
```

(If `_paint`'s signature differs from `(mesh, rgb, factor)`, match its real signature — read it. The awning bucket does NOT use the building shader, so the category-alpha packing is irrelevant here; paint a plain color.)

- [ ] **Step 5: Wire the bucket in `pipeline/tiler.py`.** Import `awning_mesh` (tiler.py:11) and, in the building loop (near tiler.py:36-38), also emit awnings:

```python
        a = awning_mesh(b, hm)
        if a is not None:
            buckets[assign_tile(*b.footprint[0])]["awnings"].append(a)
```

Add `"awnings"` to the assembly cat tuple at tiler.py:97:

```python
        for cat in ("buildings", "roads", "paths", "sidewalks", "roadmarks", "water", "green", "props", "awnings"):
```

- [ ] **Step 6: Route the material in `game/scripts/tile_loader.gd`.** Add a flat vertex-colored awning material (next to the other `_make_*` materials) and a routing branch (next to the `props`/`roadmarks` branches). Awnings use vertex COLOR (authored sRGB — a plain StandardMaterial3D with `vertex_color_use_as_albedo = true` renders them directly; no shader needed):

```gdscript
var _awning_mat := _make_awning_material()

static func _make_awning_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	return m
```

and in the material-routing loop (mirror the `roadmarks` branch):

```gdscript
		elif n.begins_with("awnings"):
			inst.material_override = _awning_mat
```

Also add `awnings` to the skip list at tile_loader.gd:156 (the collision-build skip: `n.begins_with("water") or n.begins_with("props") or ...`) so awnings get no collision (like props/roadmarks).

- [ ] **Step 7: Finalize the test numbers** (exact max/min-Y and face counts from the constants), run:

Run: `.venv/Scripts/python -m pytest pipeline -q`
Expected: 99 passed (97 + 2).

- [ ] **Step 8: Commit** (pipeline + game material; the world rebuild is Task 4):

```bash
git add pipeline/meshes.py pipeline/config.py pipeline/tiler.py game/scripts/tile_loader.gd pipeline/tests/test_meshes.py
git commit -m "pipeline: storefront awnings bucket + game material routing"
```

---

### Task 4: World rebuild + AWNINGS smoke gate

Controller-led.

- [ ] **Step 1: Rebuild** `.venv/Scripts/python -m pipeline.build` (no network; OSM + heightmap cached). Watch the console `heightmap saved (hrdem|synthetic)` line — it must say `hrdem` (the pinned cache); if it says `synthetic`, STOP (cache lost — see HANDOFF heightmap sha256 pins).
- [ ] **Step 2: Orphan check** `git status --short game/world/` — expect only modified `.glb` tiles (awnings added to commercial-bearing tiles), NO new/deleted tiles (still 314). If tiles were added/deleted, investigate before committing.
- [ ] **Step 3: Import** `tools/godot/godot_console.exe --headless --path game --import`.
- [ ] **Step 4: Add the AWNINGS smoke gate** in `game/tests/smoke_test.gd` (after the GRASS gate; mirror how a gate counts a tile geometry — count MeshInstances under TileLoader whose name begins `awnings`, assert > 0): print `AWNINGS OK: %d awning meshes`. → 20 gates.
- [ ] **Step 5: Run smoke** → 20 gates including `AWNINGS OK: <n>` (n>0) and `SMOKE OK: 314 tiles`, no SHADER/SCRIPT ERROR.
- [ ] **Step 6: Commit** the rebuilt world + smoke gate:

```bash
git add game/world game/tests/smoke_test.gd
git commit -m "world: M9c2 rebuild - storefront awnings baked; AWNINGS smoke gate"
```

---

### Task 5: Screenshot iteration + gate

Controller-led. Judge every pose vs `docs/screenshots/m9c1_*.png` by Reading the PNGs:
- The player reads as a human with the tuque, on the ground (not sunk/floating), facing its travel direction, idle/walk animating (check `onfoot_day`, `onfoot_night`, and a driving exit if visible).
- Awnings appear as colored overhangs over commercial storefronts (`street`, `driving_day`, `uphill_facade`, `oldport`), correctly protruding outward (not inward/clipping badly), varied colors, NOT on residential/industrial buildings.
- Night unchanged in character/awning lighting vs m9c1 (awnings are matte vertex-colored, character uses its own materials — no emissive regression).
Tune (character scale/orient/tuque offset are script knobs — no rebuild; awning height/depth/colors are pipeline constants — a rebuild, so batch any awning retune before re-judging). Keepers `m9c2_*`, pytest 99 + smoke 20, HANDOFF prepend, docs commit, final whole-branch review, STOP at the user gate with m9c1-vs-m9c2 pairs. On pass: tag (suggest `m9c2-life`), push, then plan 9c3 Safety & Cleanup.

---

## Self-Review

**Spec coverage** (against `2026-07-23-m9c-depth-life-design.md` §9c2): CC0 humanoid player keeping the tuque, animated-if-rigged-else-static → Tasks 1–2; storefront awnings baked with per-building color, pipeline rebuild → Tasks 3–4; screenshot gate → Task 5. Covered. (9c3 lamp-net + vnight consolidation is the next sub-phase, out of scope here.)

**Placeholder scan:** the model-specific values (MODEL_SCALE, MODEL_YAW, IDLE/WALK clip names, HEAD_BONE, HAT_OFFSET) are explicitly sourced from Task 1's inspection report — that is a real cross-task interface, not a placeholder; Task 1 produces those exact values and Task 2 consumes them. Awning geometry, constants, and material are fully specified. Test bodies show real assertions (final numbers tightened in Step 7/Step 1's finalize step, per TDD).

**Type consistency:** `awning_mesh(b, hm) -> Trimesh | None` used consistently in tiler.py; `_awning_mat` / `_make_awning_material` names match; the `awnings` bucket string is identical in tiler emit, tiler assembly tuple, tile_loader routing, tile_loader collision-skip, and the smoke gate. `_model_mode`/`_anim` mirror `car_visual.gd`'s established fields.

**Risk notes for the implementer:** (a) if the CC0 model has no animation clips, Task 2 ships static (still a win — the tuque humanoid beats blocky boxes) and the procedural fallback stays for when the GLB is absent; flag it, don't block. (b) Awnings on ALL commercial footprint edges will place some on party/alley walls (mild unrealism, possible neighbor clipping) — accepted for v1; street-facing-only detection (which edge faces a road) is a documented future refinement, NOT in scope. (c) The awning winding (Step 4) must give an upward/outward-facing normal — if awnings render black/backface in Task 5, flip the two triangles' winding.
