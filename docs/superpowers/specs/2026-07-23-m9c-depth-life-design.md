# M9c — Depth & Life (Design)

**Date:** 2026-07-23
**Status:** Direction delegated by user at the M9b completion gate ("everything and more" across the M9-spec 9c candidates; "up to you" on structure). Scope authored from a controller audit of the m9b screenshot set; each sub-phase ends at a user screenshot gate.
**Baseline:** tag `m9b-streets`, 314 tiles, smoke 18 gates, pytest 97. Reference screenshots `docs/screenshots/m9b_*.png`.
**Parent spec:** `docs/superpowers/specs/2026-07-23-m9-graphics-realism-2-design.md` (phase 9c "Depth & Life" — candidates re-scoped here into three gated sub-phases).

## Goal

Close out M9 Graphics Realism II by adding perceived depth (behind glass, on the ground) and signs of life (a human avatar, storefront color) to the street-level scene, while hardening the one remaining external-URI material risk. Deliver as three small, independently-gated sub-phases so a risky feature can never stall a ready one.

## Audit — what M9c improves (from the m9b screenshot set)

1. **Windows are flat glass slabs.** Reflective + lit since m8b, but every commercial pane is a mirror with no interior — tall towers read as solid blocks up close. Perceived depth behind glass is the single biggest remaining street-level realism gap.
2. **Green terrain is a flat texture.** Parks and medians read as painted ground; nothing grows at eye level.
3. **The player is a blocky tuque figure.** The one thing the camera follows everywhere reads as a placeholder.
4. **Commercial streets lack color/life.** Doors (m9b) helped; storefronts are still bare glass bands with no awnings or shopfront flavor.
5. **Lamp models carry the same external-URI colormap risk that silently produced white cars** (m8c watch-item) — undefended.

## Sub-phases (each ends at a user screenshot gate)

### 9c1 — Rendering Depth (game-side only, NO rebuild)

- **Fake window interiors (interior mapping / parallax box).** In `game/shaders/building_windows.gdshader`, on commercial floors ≥1 (cat 1, `floor_idx >= 1`): for each window cell, march the view ray in the shader against a virtual room box sized to the cell and shade a fake back wall + side walls + ceiling/floor so the glass reads as a lit room instead of a flat slab. **Basis without tangents:** the box axes are built from the shader's existing world-space cell-grid axes plus the wall normal (the geometric/interpolated NORMAL) — this is why interior mapping is chosen over normal maps, which the tile meshes cannot support (no tangents). Interiors are **procedural**: a small set of tinted room palettes (back-wall + floor/ceiling colors) selected by hashing the existing per-cell coordinate + building `seed` — no texture fetch, no metadata, no rebuild. **Contracts:** gated so it only applies to commercial floors ≥1 (residential/door cells from m9b untouched); night keeps the existing emissive window glow path unchanged (the interior box modulates the daytime glass color only) — **night regression fails the sub-phase**.
- **Grass clumps (camera-near MultiMesh).** A dedicated chunked MultiMesh (reusing the m8c `props_multimesh.gd` chunk/cull pattern) renders sparse grass tufts on green-terrain zones within a ~70 m ring of the active camera. **Positions are procedural** — hashed over a fixed world grid, masked to green/park vertex-color zones sampled from terrain (no OSM data, no pipeline metadata, no rebuild). Geometry is a CC0 grass model **or** procedural crossed billboard quads (decided at plan-time by which reads better and stays cheap); a cheap vertex-shader wind sway. Cells cull with distance like the prop cells; density capped for the RX 6700S budget.

*Gate: m9b vs 9c1, all 13 poses — glass towers gain interior depth, parks/medians gain ground life; day must not haze, night must be unchanged.*

### 9c2 — Life & Flavor (pipeline rebuild)

- **CC0 humanoid player model.** Replace the blocky tuque `CharacterBody3D` visual with a Quaternius (or equivalent CC0) humanoid, **keeping the tuque** via a small hat mesh parented to the head bone if the rig permits. **Animation decision deferred to plan-time based on what the model ships with:** if it carries idle + walk clips, wire basic speed-driven animation (idle/walk) into the existing controller via an `AnimationPlayer`; otherwise ship a static posed model. Scope touches only the player scene/script + `game/assets/models/` + SOURCE.md; the arcade physics, camera rig, and enter/exit car state machine are unchanged. Driving is unaffected (player is hidden while driving).
- **Storefront awnings.** Procedural colored awning geometry baked into tiles over commercial ground-floor storefront bands (the "and more" flavor addition; complements the m9b doors/storefronts). Deterministic color/size variation seeded like the existing per-building jitter. **This is the one M9c item requiring a pipeline rebuild** — folded into this sub-phase with the standard 314-tile orphan check.

*Gate: 9c1 vs 9c2 — the avatar reads human (on foot, day + night poses); commercial streets gain awning color; world still 314 tiles, no orphans.*

### 9c3 — Safety & Cleanup (game-side)

- **Lamp colormap safety net.** Apply the idempotent, clone-proof `_polish_materials` pattern proven on `car_visual.gd` (the M8c white-car fix) to the lamp prop models, which reference the same external-URI `colormap.png` that a fresh gitignored `.import` can silently discard. Pure insurance; add a headless test that loads a lamp and asserts its albedo/material survives (mirrors `car_capture.gd`/`models_test.gd`).
- **`vnight` / `night_amount` consolidation.** Fold the deferred 9a minor: `vnight` in `day_night.gd` duplicates the `night_amount` global — consolidate to one source of truth, verified against the volumetric-fog and window-glow driving paths.

*Gate: quick — no visual change expected; the fresh-import lamp test proves the safety net, smoke + pytest green.*

## Approaches considered

- **Structure — three gated sub-phases (chosen)** vs one combined M9c plan with a single end gate. Chosen because the features are highly independent (a shader, a MultiMesh, an asset swap, a material net) with very different risk (parallax windows heaviest; lamp net trivial); splitting isolates risk and preserves the project's proven small-chunk→gate cadence. Cost: three gates instead of one — accepted.
- **Window depth — interior mapping (chosen)** vs parallax-occlusion normal maps (impossible: tile meshes have no tangents) vs actual modeled interiors (geometry/perf blowup). Interior mapping is the only tangent-free option that adds real perceived depth at shader cost.
- **Grass placement — procedural game-side (chosen)** vs pipeline metadata like trees. Grass has no OSM source and only matters within a near ring, so procedural hashing avoids a rebuild and a metadata bloat.

## Constraints (hold throughout)

- All M8/M9 constraints inherited verbatim: authorship/no-trailers (commits authored ONLY by Aymanbalaa via repo-local noreply config; NO `Co-Authored-By`/AI trailers, NO `--author` flags, NO git-config changes — repeat verbatim in every subagent dispatch), CC0-only assets with SOURCE.md + licenses verified live, deterministic pipeline (no network in `pipeline.build`; texture/asset fetches manual-only), no normal maps on tangent-less tile meshes, ambient stays script-lerped COLOR mode, SDFGI stays off, **night regression fails any sub-phase**, screenshots judged by Reading PNGs, orphan check after any rebuild.
- Contracts untouched: vertex-alpha packing (`category*40 + round(base_y/2)`), `night_amount` global (9c3 consolidates its `vnight` duplicate but preserves the global's contract and every consumer), facade seed-from-RGB (`bhash`), the m9b crosswalk/manhole/door additions.
- Perf budget on the reference GPU (RX 6700S): interior mapping and grass together must not regress frame time meaningfully; if they cost more than ~2 ms combined, ray-march step count / grass density / ring radius come down before the gate.
- Grass and decals/props stay pooled/chunked (the 280 m collision-ring lesson: never one resident node per world object).

## Success criteria

- 9c1: up-close commercial glass shows believable interior depth; parks/medians show grass at eye level — both without hazing the day or altering the night skyline.
- 9c2: the on-foot avatar reads as a person (tuque preserved); commercial ground floors gain awning color; world stays 314 tiles.
- 9c3: lamps provably survive a fresh import; `night_amount` has a single source of truth; no visual change.
- User signs off at each sub-phase gate.

## Out of scope (M9c)

- Gameplay/missions, pedestrians/traffic AI (still the M10 candidate).
- SDFGI/GI (static-sun blocker unchanged); SSR (water is transparent-pass; opaque-only SSR unused).
- AI-generated Montreal decals/murals (still awaiting a user asset-generation + licensing decision; raise at a gate).
- **Deliberately excluded from M9c to protect quality** (future candidates, not committed): road puddle decals (no SSR/reflection probes → they read as flat dark patches), vent/chimney smoke particles, animated traffic-light cycling (signals are baked tile geometry — can't easily animate emission).
