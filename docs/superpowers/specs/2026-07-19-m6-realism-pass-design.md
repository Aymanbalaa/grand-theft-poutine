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
| Building facades | **World-triplanar real textures + enhanced procedural windows in the facade shader** (revised from PIL-atlas plan during 6a design research: the existing `building_windows.gdshader` already draws world-space window grids, and Godot StandardMaterial3D has native world-triplanar — so no mesh UV export is needed at all). Walls get triplanar ambientCG brick/stone/concrete by building category; window grid v2 adds frames, inset shading, sills, commercial mullions, ground-floor storefront band; roof faces (upward normals) get roof texture in the same shader. |
| Category routing | Building **category encoded in vertex-color alpha** (walls: 0 residential / 1 commercial / 2 church / 3 industrial / 4 default; roofs stay 255) — one shader branches materials per category; palette tint still comes from vertex RGB. |
| Generic PBR textures | **ambientCG (CC0)**: asphalt, concrete sidewalk, roof gravel/membrane, terrain grass/dirt. Downloaded by pipeline with **pinned URLs + sha256**, cached in `data/`, processed (1K, channel-packed where useful) into committed `game/assets/textures/`. |
| Roads | Ribbon rebuild: tiling asphalt UVs along arclength; **separate `roadmarks` geometry** (yellow dashed centerline on named two-way streets, white edge lines on arterials) offset +0.02 m; **sidewalks** both sides (2 m, +0.12 m raised, curb face) with deterministic ±2 mm height jitter by osm_id to kill coplanar z-fighting at overlaps. Crosswalks at shared-node intersections = stretch goal, not required for 6a. |
| Night windows | Same world-space grid, upgraded in shader v2 — the day-visible window frames/glass and the night emission share one grid, so windows glow exactly where they're drawn. Keep `night_amount` global + sRGB pow(2.2) lesson. |
| Lighting | ~~SDFGI~~ *(amended at 6b: dropped — replaces ambient with GI that cannot converge under a moving sun; revisit only with a static-sun mode)*, physical-ish sun energy + exposure, fog cut way down, color grade; **streetlight pool** (~24 recycled OmniLights bound to nearest lamp positions from metadata) + **car headlight SpotLights** on the driven car at night. |
| Cars | **CC0 low-poly-plus models** (4–6 variants: sedans, SUV, taxi), sourced/verified during implementation (poly.pizza or similar; license recorded in credits), committed under `game/assets/models/cars/`; metallic + clearcoat materials. Procedural blocky car stays as fallback if sourcing fails. Physics/enter-exit untouched (swap path designed in M5). |
| Props | Traffic lights placed from OSM `highway=traffic_signals` nodes (new parse field + metadata); lamp/prop meshes upgraded. |
| Performance | 60 fps at 1080p on ROG G14 (RX 6700S). SDFGI acceptable; texture budget ~25 × 1K maps. |
| Roadmap | **M6 = this realism pass (phases 6a/6b/6c)**; old M6 polish (audio, tuning, credits) becomes **M7**, except credits land with 6c's assets. |

## Architecture

### Pipeline (`pipeline/`)
- `textures.py` (new) — ambientCG fetch (preferred IDs with API fallback) → `data/textures/` zip cache → selected 1K maps copied to committed `game/assets/textures/pbr/`; final IDs + sha256 recorded in a lock file for rebuild stability.
- `meshes.py` — building `_paint` gains category-alpha encoding for walls; new `sidewalk_mesh` (raised 0.12 m slab, outer curb face sloped ~33° so player/car can climb it — CharacterBody3D has no stair-stepping) and `roadmark_mesh` (dashed yellow centerline, white edge lines on arterials, +0.02 m). No mesh UVs anywhere — all texture mapping is world-triplanar game-side.
- `osm_parse.py` — collect `highway=traffic_signals` node positions.
- `export.py` — metadata gains `lamps` and `signals` position lists (for game-side lights/props).
- Tiles keep vertex colors as tint where useful; textures are NOT embedded in GLB (materials live game-side).

### Game (`game/`)
- `tile_loader.gd` — name→material table grows: per-type facade ShaderMaterials (windows emission), asphalt/sidewalk/roadmarks/roof/terrain StandardMaterial3Ds with textures from `res://assets/textures/`.
- `shaders/building_windows.gdshader` → v2: triplanar wall textures by category (alpha-encoded), window grid with frames/insets/sills, storefront band, roof-face branch; emission gated by `night_amount` smoothstep as today.
- `light_pool.gd` (new, 6b) — recycles a fixed OmniLight pool to the nearest `lamps` positions around the active camera at night.
- `car.tscn`/`car_visual.gd` (6c) — model-swap on Visual; headlight SpotLights (6b) toggle with night.
- `main.tscn` environment (6b) — SDFGI, exposure, fog, grade.

## Phases

- **6a "Surfaces"** — facades + UVs + window-shader v2, roads/markings/sidewalks, roof/terrain textures, full rebuild, screenshot review. *Biggest visual delta; done first.*
- **6b "Light"** — SDFGI + exposure + sky/fog/grade, streetlight pool, headlights, night re-tune of emission strengths.
- **6c "Things"** — car model sourcing + materials + swap, traffic lights/prop pass, credits screen (OSM ODbL, HRDEM, ambientCG, model credits).

Each phase: own plan (superpowers:writing-plans), subagent-driven execution, screenshot gate reviewed by actually looking at the PNGs at day/dusk/night poses before tagging (`m6a-surfaces`, `m6b-light`, `m6c-things`).

## Testing

- Pipeline: pytest for category-alpha encoding, sidewalk/roadmark geometry (offsets, slope, determinism), texture fetch cache/lock behavior, signals parsing (6c).
- Game: existing smoke suite must stay green untouched (PLAYER/LANDED/CAR/CARS/ENTER/DRIVE/EXIT/SMOKE OK); materials load headless without stderr noise.
- Visual: screenshot poses are the real gate — iterate like M3.5 (expect several tuning rounds).

## Risks / mitigations

- **Z-fighting** (markings on road, sidewalk overlaps): +0.02 m offsets and per-road ±2 mm jitter; verify in screenshots at grazing angles.
- **SDFGI + hundreds of emissive windows**: may need emission energy re-tune (6b re-tunes; 6a keeps current energy).
- **Download flakiness** (ambientCG, car models): pinned URLs + sha256 + `data/` cache, same pattern as HRDEM; procedural fallbacks stay.
- **Curbs vs CharacterBody3D** (no stair-stepping in Godot): curb faces sloped ~33°, under the default 45° floor_max_angle, so player and car climb them.
- **Tile size growth** (sidewalks/markings ≈ more tris): stay under existing `MAX_TILE_TRIS` budget; the tiler already raises if busted.

## Out of scope (unchanged from v1 spec)

Missions, NPCs, traffic, police, combat, multiplayer, interior spaces, weather. AI-generated Montreal-flavor facade variants = optional later pass on top of 6a.
