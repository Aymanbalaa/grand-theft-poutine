# M6 — Realism Pass (design)

*2026-07-19. Trigger: user reviewed m5-driving screenshots — "looks like shit, I was expecting a lot more … real video game graphics, maybe not GTA5 level but something comparable." Target bar agreed: realistic-ish city (GTA3-remaster-era / solid indie 3D), not AAA. Free/CC0 assets approved; AI-generated textures available as a later flavor pass.*

## Vision

Kill the "flat-colored rectangles" look. Every visible surface gets a real material: buildings get facade textures with actual windows and storefronts, roads get asphalt with lane markings and sidewalks, the world gets believable lighting day and night, and cars look like cars. Same generated-from-OSM city, same gameplay — transformed presentation.

## Why it currently reads as boxes

1. **No textures anywhere** — every mesh is one flat vertex color.
2. **Roads are untextured ribbons** — no markings, curbs, or sidewalks.
3. **Lighting is flat** — no GI, heavy fog, dim exposure; night light sources don't illuminate anything.
4. **The car is six boxes.**

M6 fixes exactly these, in three phases.

## Decisions locked

| Decision | Choice |
|---|---|
| Building facades | **Pipeline-generated facade textures** (PIL): window grids drawn at exact `LEVEL_HEIGHT` pitch, per-type Montreal palettes (brick/glass/greystone/industrial), storefront ground-floor band; albedo + normal (heightfield→Sobel) + emission-mask maps. Deterministic, license-free, windows align with geometry. |
| Facade UV strategy | Walls split into **two bands at y = LEVEL_HEIGHT**: ground-floor band (storefront texture) and upper band (floor-tile texture, sampler REPEAT). No atlas-in-shader math. Geometry per building type per band (e.g. `bldg_res_upper`), routed by name in `tile_loader` like today. |
| Generic PBR textures | **ambientCG (CC0)**: asphalt, concrete sidewalk, roof gravel/membrane, terrain grass/dirt. Downloaded by pipeline with **pinned URLs + sha256**, cached in `data/`, processed (1K, channel-packed where useful) into committed `game/assets/textures/`. |
| Roads | Ribbon rebuild: tiling asphalt UVs along arclength; **separate `roadmarks` geometry** (yellow dashed centerline on named two-way streets, white edge lines on arterials) offset +0.02 m; **sidewalks** both sides (2 m, +0.12 m raised, curb face) with deterministic ±2 mm height jitter by osm_id to kill coplanar z-fighting at overlaps. Crosswalks at shared-node intersections = stretch goal, not required for 6a. |
| Night windows | Existing world-space-grid shader replaced by **UV shader sampling the facade emission mask** — day facades show real windows, night windows glow in the same places. Keep `night_amount` global + sRGB pow(2.2) lesson. |
| Lighting | **SDFGI on** (Godot 4.5), physical-ish sun energy + exposure, fog cut way down, color grade; **streetlight pool** (~24 recycled OmniLights bound to nearest lamp positions from metadata) + **car headlight SpotLights** on the driven car at night. |
| Cars | **CC0 low-poly-plus models** (4–6 variants: sedans, SUV, taxi), sourced/verified during implementation (poly.pizza or similar; license recorded in credits), committed under `game/assets/models/cars/`; metallic + clearcoat materials. Procedural blocky car stays as fallback if sourcing fails. Physics/enter-exit untouched (swap path designed in M5). |
| Props | Traffic lights placed from OSM `highway=traffic_signals` nodes (new parse field + metadata); lamp/prop meshes upgraded. |
| Performance | 60 fps at 1080p on ROG G14 (RX 6700S). SDFGI acceptable; texture budget ~25 × 1K maps. |
| Roadmap | **M6 = this realism pass (phases 6a/6b/6c)**; old M6 polish (audio, tuning, credits) becomes **M7**, except credits land with 6c's assets. |

## Architecture

### Pipeline (`pipeline/`)
- `facades.py` (new) — deterministic facade texture generation: `generate_facade_set(btype) -> albedo/normal/emission PNGs` written to `game/assets/textures/facades/`. Unit-testable (image hashes, window-pitch math).
- `textures.py` (new) — pinned-URL ambientCG fetch → `data/textures/` cache (sha256-verified) → resized/packed copies in `game/assets/textures/pbr/`.
- `meshes.py` — building extrusion emits UVs + band split (`*_lower`/`*_upper` per type); road ribbon UVs; new `roadmark_mesh`, `sidewalk_mesh`; roofs UV'd for roof texture.
- `osm_parse.py` — collect `highway=traffic_signals` node positions.
- `export.py` — metadata gains `lamps` and `signals` position lists (for game-side lights/props).
- Tiles keep vertex colors as tint where useful; textures are NOT embedded in GLB (materials live game-side).

### Game (`game/`)
- `tile_loader.gd` — name→material table grows: per-type facade ShaderMaterials (windows emission), asphalt/sidewalk/roadmarks/roof/terrain StandardMaterial3Ds with textures from `res://assets/textures/`.
- `shaders/building_windows.gdshader` → v2: samples albedo/normal/emission textures via UV; emission gated by `night_amount` smoothstep as today.
- `light_pool.gd` (new, 6b) — recycles a fixed OmniLight pool to the nearest `lamps` positions around the active camera at night.
- `car.tscn`/`car_visual.gd` (6c) — model-swap on Visual; headlight SpotLights (6b) toggle with night.
- `main.tscn` environment (6b) — SDFGI, exposure, fog, grade.

## Phases

- **6a "Surfaces"** — facades + UVs + window-shader v2, roads/markings/sidewalks, roof/terrain textures, full rebuild, screenshot review. *Biggest visual delta; done first.*
- **6b "Light"** — SDFGI + exposure + sky/fog/grade, streetlight pool, headlights, night re-tune of emission strengths.
- **6c "Things"** — car model sourcing + materials + swap, traffic lights/prop pass, credits screen (OSM ODbL, HRDEM, ambientCG, model credits).

Each phase: own plan (superpowers:writing-plans), subagent-driven execution, screenshot gate reviewed by actually looking at the PNGs at day/dusk/night poses before tagging (`m6a-surfaces`, `m6b-light`, `m6c-things`).

## Testing

- Pipeline: pytest for UV validity (0≤v within band, u monotonic with arclength), band-split correctness (no wall face spans the y=LEVEL_HEIGHT seam), facade generator determinism (byte-identical PNGs), texture fetch cache/sha256 behavior, signals parsing.
- Game: existing smoke suite must stay green untouched (PLAYER/LANDED/CAR/CARS/ENTER/DRIVE/EXIT/SMOKE OK); materials load headless without stderr noise.
- Visual: screenshot poses are the real gate — iterate like M3.5 (expect several tuning rounds).

## Risks / mitigations

- **Z-fighting** (markings on road, sidewalk overlaps): +0.02 m offsets and per-road ±2 mm jitter; verify in screenshots at grazing angles.
- **SDFGI + hundreds of emissive windows**: may need emission energy re-tune (6b re-tunes; 6a keeps current energy).
- **Download flakiness** (ambientCG, car models): pinned URLs + sha256 + `data/` cache, same pattern as HRDEM; procedural fallbacks stay.
- **trimesh GLB UV export + Godot import**: verify early in 6a Task 1 with a single textured test tile before converting everything.
- **Tile size growth** (band split ≈ more geometries, sidewalks/markings ≈ more tris): stay under existing `MAX_TILE_TRIS` budget; pytest asserts it.

## Out of scope (unchanged from v1 spec)

Missions, NPCs, traffic, police, combat, multiplayer, interior spaces, weather. AI-generated Montreal-flavor facade variants = optional later pass on top of 6a.
