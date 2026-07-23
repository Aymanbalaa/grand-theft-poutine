# M9 — Graphics Realism II (Design)

**Date:** 2026-07-23
**Status:** Direction delegated by user at the M8 completion gate ("improve overall graphics to have more realistic visuals — check what you need and what you can do"). Scope authored from a controller audit of the m8c screenshot set; each phase still ends at a user screenshot gate.
**Baseline:** tag `m8c-assets`, 314 tiles, smoke 17 gates, pytest 92. Reference screenshots `docs/screenshots/m8c_*.png`.

## Audit — what reads least realistic today (street-level priority, per the M8 principle)

1. **Shadows die at 100 m.** The Sun uses Godot's default `directional_shadow_max_distance` (100) with default cascades — mid-distance buildings/trees cast nothing, flattening every vista. Cheapest big win in the project.
2. **Night light is surfaceless.** Streetlights illuminate the ground but there is no atmosphere — no halos, no light cones. Godot Forward+ volumetric fog with per-light energy injection is built for exactly this; night is the money shot and this deepens it.
3. **No color grade.** The image is raw ACES; a mild contrast/saturation adjustment unifies the look toward "graded game" rather than "engine output".
4. **Intersections are bare.** No crosswalks or stop lines — the road network reads schematic at street level. Junction data already exists in the pipeline (M6a `_clear_intervals` junction detection).
5. **Roads are unblemished.** The wear noise helps, but no manholes/cracks. Godot `Decal` nodes project onto geometry WITHOUT UVs — this is the decal infrastructure the M8b/M8c deferrals were waiting for; ambientCG has a CC0 Decal category (manhole covers et al.) fetchable through the existing texture-slot pipeline.
6. **Ground floors have no doors.** Facades meet the sidewalk with nothing but storefront glass — no entrances anywhere in the city.
7. **Windows are uniform glass slabs.** Reflective since m8b, but every pane is the same; no interior depth. (Fake-interior/parallax is the heavy end of this — candidate, not commitment.)
8. **The player is a blocky tuque figure and trees repeat 3 models.** Assets, not rendering — lowest priority here.

## Phases (each ends at a user screenshot gate)

### 9a — Light, Shadow & Atmosphere (game-side only, NO rebuild)
- **Shadow reach:** directional shadow max distance ~500 m, 4 splits tuned for street+vista, blend splits on, bias re-checked at street level (peter-panning vs acne).
- **Volumetric night fog:** `volumetric_fog` enabled with density driven by `night_amount` in day_night.gd (0 by day — day keeps the crisp M8a look; low density at night so the 24 pooled streetlights and car headlights grow halos/cones). ACES note from M6b applies: expect to push volumetric light energies hard.
- **Grade:** Environment `adjustment_*` — mild contrast (~1.05) and saturation (~1.08), tuned against screenshots; glow retune if halos double-glow.
- Gate: m8c vs m9a pairs, all 13 poses; night must gain depth without washing out; day must not haze.

### 9b — Street Detail (pipeline rebuild)
- **Crosswalks + stop lines:** zebra bands and stop bars emitted into `roadmarks` at junction entries on sidewalk-class roads (junction set already computed; reuse `_clear_intervals` machinery).
- **Road decals:** `manholes` (and optionally `cracks`) metadata positions sampled along roads (car_spawns pattern); game-side `Decal` nodes from a chunked pool near the camera; textures via new ambientCG Decal slots (CC0, existing lock mechanism).
- **Doors:** facade shader floor-0 door insets at deterministic per-building positions (seeded by the existing RGB hash) — dark recessed rectangle + frame where no storefront band applies.

### 9c — Depth & Life (candidates, re-scope at the 9b gate)
- Fake window interiors (shader parallax box) on commercial floors ≥1.
- CC0 humanoid player model swap (Quaternius) keeping the tuque via a hat mesh if feasible.
- Sparse grass clumps (MultiMesh, camera-near ring) on green terrain.
- Lamp colormap safety net (watch item from m8c review — same external-URI class as the car bug).

## Constraints (hold throughout)

- All M8 constraints inherited verbatim: authorship/no-trailers, CC0-only assets with SOURCE.md, deterministic pipeline (no network in build), no normal maps on tangent-less tile meshes, ambient stays script-lerped COLOR mode, SDFGI stays off, night regression fails any phase, screenshots judged by Reading PNGs, smoke (17 gates) + pytest (92) stay green, orphan check after rebuilds.
- Volumetric fog must be gated by `night_amount` so day scenes stay untouched; if it costs more than ~2 ms on the reference GPU (RX 6700S), density/froxel settings come down before the gate.
- Decals must be pooled/chunked (the 280 m collision-ring lesson: never one node per world object resident at once).

## Success criteria

- 9a: night shots gain visible light volumes/halos; shadows reach the vista; a consistent grade — all without losing M8a's clear day or the window-glow night.
- 9b: intersections read as real streets (crosswalks/stop bars); roads have believable blemishes; every building has an entrance.
- User signs off at each phase gate.

## Out of scope

- Gameplay/missions, pedestrians/traffic AI (still the M10 candidate).
- SDFGI/GI (static-sun blocker unchanged). SSR (water is transparent-pass; SSR only affects opaque).
- AI-generated Montreal decals/murals: still deferred — needs an asset-generation + licensing decision from the user, not infra anymore (Decal nodes close that gap); raise at a gate.
