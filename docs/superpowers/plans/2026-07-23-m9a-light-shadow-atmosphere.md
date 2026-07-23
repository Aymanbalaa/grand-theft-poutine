# M9a — Light, Shadow & Atmosphere Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shadows that reach the vista, volumetric night atmosphere (streetlight halos/cones, headlight beams), and a mild color grade — all game-side, no rebuild.

**Architecture:** Three levers on existing nodes: `Sun` (DirectionalLight3D) shadow cascade settings in main.tscn; Environment volumetric-fog block whose density day_night.gd drives from its existing `daylight` value (0 by day — day keeps the crisp M8a look); Environment `adjustment_*` grade. The 24 pooled streetlight OmniLights and the car headlight SpotLights get volumetric energy so the fog picks them up.

**Tech Stack:** Godot 4.5 (main.tscn text edits, GDScript), no pipeline changes.

## Global Constraints

- Commits authored ONLY by Aymanbalaa via repo-local git config. NO `Co-Authored-By`/AI trailers, NO `--author` flags, NO git-config changes. Repeat verbatim in every subagent dispatch.
- Game-side only: NO `pipeline.build`, `game/world/` untouched, pytest stays 92 (untouched).
- `night_amount` global contract untouched (day_night.gd keeps setting it; consumers unchanged).
- Ambient stays script-lerped COLOR mode; SDFGI stays off.
- Volumetric fog MUST be inert by day: enabled only when night is falling, density 0 in full day. Night is the money shot — halos must deepen it, not wash it (if lit windows lose punch, density comes down).
- Headless smoke stays green: 17 gates ending `SMOKE OK: 314 tiles` (run from repo root, ~5 min timeout).
- main.tscn is hand-edited text: `load_steps` only changes if resources are added (none are in this plan — verify).
- Screenshots judged only by Reading PNGs (windowed harness, 13 poses).

---

### Task 1: Shadow reach + color grade (main.tscn)

**Files:**
- Modify: `game/scenes/main.tscn` (Sun node properties + Environment sub-resource)

**Interfaces:**
- Consumes/produces: nothing cross-task; Task 3 tunes these values against screenshots.

- [ ] **Step 1: Sun shadows.** In the `[node name="Sun" type="DirectionalLight3D" parent="."]` block, after `shadow_enabled = true` add:

```
directional_shadow_max_distance = 500.0
directional_shadow_blend_splits = true
```

(Default 4-split PSSM mode and default split ratios stay; 500 m covers the street-to-vista range the poses show. Do not touch bias yet — Task 3 screenshots judge acne/peter-panning first.)

- [ ] **Step 2: Grade.** In the `[sub_resource type="Environment" id="env1"]` block, after the `glow_bloom` line add:

```
adjustment_enabled = true
adjustment_contrast = 1.05
adjustment_saturation = 1.08
```

- [ ] **Step 3: Headless smoke** → `SMOKE OK: 314 tiles`, no errors.

- [ ] **Step 4: Commit**

```bash
git add game/scenes/main.tscn
git commit -m "game: shadow cascades to 500m with blended splits; mild contrast/saturation grade"
```

---

### Task 2: Volumetric night fog

**Files:**
- Modify: `game/scenes/main.tscn` (Environment volumetric params)
- Modify: `game/scripts/day_night.gd` (density driven by daylight)
- Modify: `game/scripts/light_pool.gd` (omni volumetric energy)
- Modify: the car headlight SpotLights (grep `SpotLight3D` under `game/` — they live in the car scene/script from M6b; set their volumetric energy where they are created/defined)

**Interfaces:**
- Consumes: day_night.gd's existing `daylight` local in `_process` and `_env` reference.
- Produces: night atmosphere; Task 3 tunes density/energies.

- [ ] **Step 1: Environment params.** In the `Environment` sub-resource (after the fog block) add:

```
volumetric_fog_enabled = false
volumetric_fog_density = 0.0
volumetric_fog_albedo = Color(0.82, 0.86, 1, 1)
volumetric_fog_length = 200.0
volumetric_fog_ambient_inject = 0.0
```

(`enabled=false` + density 0 are the day state; the script owns both at runtime.)

- [ ] **Step 2: Drive from day_night.gd.** In `_process`, inside the existing `if _env != null:` block (after the ambient lines), append:

```gdscript
		var vnight := 1.0 - daylight
		_env.volumetric_fog_enabled = vnight > 0.25
		_env.volumetric_fog_density = 0.012 * smoothstep(0.25, 0.7, vnight)
```

(Anchor on the actual file — the block currently ends with the `ambient_light_color` lerp. Everything else in `_process` stays byte-identical.)

- [ ] **Step 3: Light injection.** In `light_pool.gd`, where each pooled `OmniLight3D` is created/configured (energy 9.0, range 20), add:

```gdscript
		light.light_volumetric_fog_energy = 4.0
```

(match the actual local variable name). For the car headlights (two SpotLights, energy 30, from M6b — find them by grepping `SpotLight3D`), set `light_volumetric_fog_energy = 1.5` at their creation/definition site (scene property line if they live in a .tscn, script line if built in code).

- [ ] **Step 4: Headless smoke** → green (17 gates). Volumetric fog is a rendering feature — headless proves no script errors only; visuals are Task 3's job.

- [ ] **Step 5: Commit**

```bash
git add game/scenes/main.tscn game/scripts/day_night.gd game/scripts/light_pool.gd
git commit -m "game: volumetric night fog - streetlight halos and headlight beams"
```

(Include the headlight file, whichever it is.)

---

### Task 3: Screenshot iteration + gate

Controller-led (standing precedent). Judge every pose vs `docs/screenshots/m8c_*.png`.

- [ ] **Step 1: Full screenshot run; judge:**
  - `night`/`onfoot_night`/`driving_night`: streetlight halos + headlight beams visible; window glow keeps punch; no grey wash.
  - Day poses: NO haze regression (volumetrics inert), shadows now reach mid/far buildings and trees; no shadow acne/peter-panning at street level (if present, tune Sun bias/normal bias).
  - `dusk`: volumetrics beginning to breathe is acceptable; warm gradient preserved.
  - Grade: day shots slightly richer, not oversaturated (brick/greenery are the tell).
- [ ] **Step 2: Tune and repeat.** Knobs in order: volumetric density coefficient (0.012), pool light volumetric energy (4.0), headlight volumetric energy (1.5), `volumetric_fog_length`, adjustment contrast/saturation, shadow max distance (500) and bias if artifacts. Commit each round (`game: m9a tuning round N`).
- [ ] **Step 3: Keepers** → `docs/screenshots/m9a_<pose>.png` (exclude the stray `shot_centerline.png`).
- [ ] **Step 4: Final green:** pytest 92; smoke 17 gates.
- [ ] **Step 5: HANDOFF.md** — prepend M9a state (values shipped, spec pointer, 9b next), demote prior.
- [ ] **Step 6: Commit docs; final whole-branch review; STOP — user gate** with m8c-vs-m9a pairs (night, driving_night, onfoot_day, overview).
