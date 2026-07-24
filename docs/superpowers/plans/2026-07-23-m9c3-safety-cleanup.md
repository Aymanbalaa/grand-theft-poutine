# M9c3 — Safety & Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the last external-URI material risk (lamp colormap, same class as the white-car bug) and consolidate the `vnight` duplicate of the `night_amount` global — the final M9c "Depth & Life" sub-phase. Game-side only, no rebuild.

**Architecture:** (1) `props_multimesh.gd::_find_mesh` already bakes surface materials into the MultiMesh mesh; extend the "keep the imported material" branch with a colormap safety net — any kept material lacking an `albedo_texture` gets `props/Textures/colormap.png` re-assigned (mirrors `car_visual.gd::_polish_materials` and the m9c2 character net). (2) `day_night.gd` computes `night_amount` (member, line 32) and then a redundant local `vnight = 1.0 - daylight` (line 40) — replace the three `vnight` uses with `night_amount`.

**Tech Stack:** Godot 4.5 (GDScript, StandardMaterial3D, MultiMesh), headless GDScript tests via `godot_console`.

## Global Constraints

- Commits authored ONLY by Aymanbalaa via the repo-local git config (noreply email). NO `Co-Authored-By`/AI trailers, NO `--author` flags, NO git-config changes. Repeat verbatim in every subagent dispatch.
- Commit small and frequent; one commit per task minimum.
- Game-side ONLY: NO `pipeline.build`, world stays 314 tiles, no `.import` commits.
- Contracts untouched: the `night_amount` GLOBAL shader parameter and its value/timing must be byte-identical after the `vnight` refactor (it is the same `1.0 - daylight` value, just deduplicated); the m8/m9 prop rendering (`PROPS OK: 16498 trees, 499 lamps, 21 benches, 0 hydrants`), night volumetric fog behavior, `bhash`, alpha-packing, m9b/m9c1/m9c2 work all unchanged.
- `.gd` files written WITHOUT a UTF-8 BOM (PowerShell `Set-Content` hazard — use Bash/editor tools).
- Smoke stays green at 20 gates ending `SMOKE OK: 314 tiles` (no new gate this phase). pytest unaffected at 100. Headless smoke: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd` (console wrapper from Bash).

---

### Task 1: `vnight` → `night_amount` consolidation (day_night.gd)

**Files:**
- Modify: `game/scripts/day_night.gd` (lines ~40-44)

**Interfaces:**
- Consumes: the existing member `night_amount` (set at day_night.gd:32 to `1.0 - daylight`, before line 40).
- Produces: no interface change — `night_amount` global write (line 33) and the volumetric-fog behavior are value-identical.

- [ ] **Step 1: Replace the `vnight` local with `night_amount`.** In `_process`, delete `var vnight := 1.0 - daylight` and use the member `night_amount` in the three fog lines:

```gdscript
		# (removed: var vnight := 1.0 - daylight  — duplicated the night_amount member)
		_env.volumetric_fog_enabled = night_amount > 0.25
		# low density: extinction applies to the whole vista beyond fog length,
		# so halos come from per-light volumetric energy, not thick fog
		_env.volumetric_fog_density = 0.004 * smoothstep(0.25, 0.7, night_amount)
```

(`night_amount` is assigned at line 32 = `1.0 - daylight`, identical to the deleted `vnight`, and lines 40-44 run after line 32 in the same `_process` — so this is a pure de-duplication with zero behavior change.)

- [ ] **Step 2: Verify smoke** (night fog path still runs; no SCRIPT ERROR):

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`
Expected: 20 gates ending `SMOKE OK: 314 tiles`, no error.

- [ ] **Step 3: Verify night is unchanged** — capture and compare one night pose:

Run: `tools/godot/godot_console.exe --path game --script res://tests/screenshot.gd`
Read `%APPDATA%/Godot/app_userdata/MTL Open Ile/shot_night.png` and confirm the night skyline + fog look identical to `docs/screenshots/m9c2_night.png` (they must — same value).

- [ ] **Step 4: Commit**

```bash
git add game/scripts/day_night.gd
git commit -m "game: consolidate vnight duplicate into the night_amount member"
```

---

### Task 2: Lamp colormap safety net (props_multimesh.gd) + headless test

**Files:**
- Modify: `game/scripts/props_multimesh.gd` (`_find_mesh`, the material-baking loop ~lines 117-130)
- Create: `game/tests/props_colormap_test.gd`

**Interfaces:**
- Consumes: `res://assets/models/props/Textures/colormap.png` (already committed; the Kenney props reference it by external URI); the prop model GLBs.
- Produces: a headless test asserting the lamp model's baked material is textured (never white on a fresh import).

**Context:** `_find_mesh` (props_multimesh.gd) walks each prop GLB and, per surface, either replaces a known material name via `MAT_COLORS` (solid shaded color) or KEEPS the imported material (`m.surface_set_material(s, mat)`). A kept material that references the external-URI `colormap.png` will render WHITE on a fresh import (the gitignored `.glb.import` discards the external-URI texture — the exact white-car-bug mechanism, flagged as an m8c watch-item for lamps). The fix: in the keep branch, re-assign the colormap when the kept material has no `albedo_texture`.

- [ ] **Step 1: Write the failing test** `game/tests/props_colormap_test.gd`:

```gdscript
extends SceneTree
# godot_console --headless --path game --script res://tests/props_colormap_test.gd
# Guards the lamp against the white-car-bug class: a fresh import can drop the
# external-URI colormap; the safety net in props_multimesh must re-assign it.
func _init() -> void:
	var PM = load("res://scripts/props_multimesh.gd")
	var entry: Dictionary = PM._first_mesh("res://assets/models/props/lamp_post.glb")
	assert(not entry.is_empty(), "lamp_post.glb produced no mesh")
	var mesh: Mesh = entry["mesh"]
	var textured_or_colored := false
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s) as BaseMaterial3D
		if mat == null:
			continue
		# after the safety net, every kept surface material is either a MAT_COLORS
		# solid color OR carries the colormap texture — never an untextured white default
		if mat.albedo_texture != null or mat.albedo_color != Color(1, 1, 1, 1):
			textured_or_colored = true
	assert(textured_or_colored, "lamp material is untextured white (colormap safety net failed)")
	print("PROPS COLORMAP OK")
	quit()
```

- [ ] **Step 2: Run, verify it fails** IF the lamp currently keeps an untextured material on this checkout. (It may PASS already because the local `.import` still resolves the colormap — that is expected; the test's real value is guarding the FRESH-import regression. If it passes pre-fix, note that in your report and still add the safety net, then confirm the test stays green.)

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/props_colormap_test.gd`

- [ ] **Step 3: Add the safety net** in `props_multimesh.gd::_find_mesh`, in the material loop's KEEP branch (currently `else: m.surface_set_material(s, mat)`):

```gdscript
			else:
				# colormap safety net (white-car-bug class): a fresh import can drop
				# the external-URI colormap.png, leaving the material untextured/white.
				var bmat := mat as BaseMaterial3D
				if bmat != null and bmat.albedo_texture == null:
					var tex := load("res://assets/models/props/Textures/colormap.png") as Texture2D
					if tex != null:
						bmat.albedo_texture = tex
				m.surface_set_material(s, mat)
```

- [ ] **Step 4: Run the test, verify it passes:**

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/props_colormap_test.gd`
Expected: prints `PROPS COLORMAP OK`.

- [ ] **Step 5: Verify props still render correctly** (the safety net must not break the trees/bench/hydrant which use `MAT_COLORS` solid colors — those take the `if MAT_COLORS.has(...)` branch, not the keep branch, so they are untouched):

Run: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`
Expected: `PROPS OK: 16498 trees, 499 lamps, 21 benches, 0 hydrants` present, ends `SMOKE OK: 314 tiles`.

- [ ] **Step 6: Commit** (include the generated `.uid` for the new test):

```bash
git add game/scripts/props_multimesh.gd game/tests/props_colormap_test.gd game/tests/props_colormap_test.gd.uid
git commit -m "game: colormap safety net for prop models (lamp) + headless test"
```

---

### Task 3: Verify + gate

Controller-led.

- [ ] **Step 1: Full smoke** → 20 gates, `PROPS OK: ...`, `SMOKE OK: 314 tiles`, no errors.
- [ ] **Step 2: Screenshot check** — capture and Read a day pose (lamps textured, not white) and `shot_night.png` (skyline/fog identical to m9c2). Since M9c3 is defensive/cleanup, expect NO visual change.
- [ ] **Step 3:** Keepers `m9c3_*` (only if any visual change — otherwise note "no visual delta, m9c2 shots stand"), pytest 100 + smoke 20, HANDOFF prepend, docs commit, final whole-branch review, STOP at the user gate. On pass: tag (suggest `m9c3-safety`), push — **M9c "Depth & Life" is then COMPLETE** (all of 9c1/9c2/9c3 shipped); next candidates per the M9/M10 direction: pedestrians/traffic AI, missions/gameplay loop, or a bolder-awnings retune.

---

## Self-Review

**Spec coverage** (against `2026-07-23-m9c-depth-life-design.md` §9c3): lamp colormap safety net (car-bug class) → Task 2; `vnight`/`night_amount` consolidation → Task 1; verify + gate → Task 3. Both §9c3 items covered.

**Placeholder scan:** no TBD/TODO; both code changes are shown in full. Task 2 Step 2 explicitly handles the "test may pass pre-fix" case (the safety net guards a fresh-import regression the local `.import` masks) — that is a real TDD nuance for import-cache-dependent behavior, not a placeholder.

**Type consistency:** `night_amount` is the existing member (day_night.gd:12,32); `_find_mesh`/`_first_mesh`/`MAT_COLORS` match props_multimesh.gd; the colormap path `res://assets/models/props/Textures/colormap.png` matches the committed tree. The safety-net pattern mirrors the verified `car_visual.gd::_polish_materials` and m9c2 character net.

**Risk note:** the `vnight` refactor is value-identical (same `1.0 - daylight`, member already assigned earlier in the same `_process`) — zero behavior change; the night screenshot in Task 1 Step 3 is the guard. The colormap net only touches the KEEP branch, so MAT_COLORS-colored props (trees/bench/hydrant) are provably unaffected.
