# MTL: Open Île — Design Spec

**Date:** 2026-07-18
**Status:** Approved
**Working title:** MTL: Open Île (subject to change)

## Vision

An open-world free-roam game set in a recognizable downtown Montreal. No missions in v1 — the game is the city itself plus good on-foot and driving mechanics. Real street grid, real street/district names, real landmarks. Hybrid art style: stylized low-poly city generated from map data, with hand-placed detailed hero landmarks.

## Decisions locked

| Decision | Choice |
|---|---|
| Engine | Godot 4.x (free, MIT, text-based scenes/scripts, headless CLI for automated testing) |
| Map scope (v1) | Downtown core ~3-4 km²: Ville-Marie + Old Port + slice of the Plateau, edge of Mont Royal |
| Art style | Hybrid — low-poly generated city + detailed hero landmarks |
| Core loop (v1) | Free-roam: walk/sprint/jump on foot, enter/exit cars, arcade-leaning driving |
| Deferred | Missions, NPCs, pedestrian/vehicle traffic, police, combat, multiplayer |
| Target hardware | 60fps on ROG Zephyrus G14 (Ryzen 9 6900HS, RX 6700S, 16GB RAM) |
| Commit policy | Small frequent commits, authored solely by Aymanbalaa (no AI co-author trailers) |

## Player experience (v1)

Spawn on foot downtown. Streets are real — Ste-Catherine, René-Lévesque, Saint-Laurent, the Old Port — with current street + district shown on the HUD. Low-poly buildings at true footprints and heights. Walk up to any parked car, press a key, drive. Mont Royal provides real elevation. Minimap, speedometer while driving, day/night cycle.

## Architecture

Two decoupled halves with a data contract between them:

### Half 1 — Map pipeline (`pipeline/`, Python, offline)

- **Sources:**
  - BBBike Montreal OSM extract — roads, building footprints, names, height tags (ODbL)
  - Canada HRDEM (CanElevation) heightmap — terrain elevation (Open Government Licence)
  - Montreal open data portal — enrichment/fallback (CC-BY 4.0)
- **Stack:** Python + `osmium`/`pyrosm` + `shapely` + `trimesh`. No Blender dependency in the main loop.
- **Processing:**
  - Clip to downtown bounding box
  - Terrain: HRDEM → heightmap
  - Buildings: footprint extrusion, flat or simple gabled roofs, stylized palette by district/type
  - Roads: polyline → ribbon meshes with sidewalks, merged intersections; lane metadata retained for future traffic
  - Water/parks: flat colored polygons
- **Output (the contract):**
  - glTF tiles on a 256 m grid → committed under `game/world/`
  - `city_metadata.json` — street names, district polygons, spawn points, landmark anchor coordinates
- Deterministic and rerunnable: same input + params → same output.
- Raw downloads live in gitignored `data/` (keeps git and OneDrive sync sane).

### Half 2 — Game (`game/`, Godot 4.x)

- **Player:** `CharacterBody3D` third-person controller (walk/sprint/jump), collision-aware follow camera. Quaternius/Mixamo character + animations.
- **Vehicles:** Godot Easy Vehicle Physics (MIT, raycast-based), tuned arcade-ish. Kenney Car Kit models (CC0). Cars pre-placed as parked spawns. Enter/exit via proximity prompt; camera swaps; character hidden while driving.
- **World loading:** distance-based tile show/hide (no streaming needed at this scale; interface leaves room for real streaming later).
- **HUD:** current street + district (point-in-polygon vs metadata), minimap from road graph, speedometer in vehicles.
- **Day/night:** rotating `DirectionalLight3D` + environment color gradient.

## Hero landmarks (v1)

Hand-placed at true coordinates, replacing the auto-generated geometry at their footprints: Notre-Dame Basilica, Place Ville Marie, Biosphere, Habitat 67, Farine Five Roses sign. Sourced from free Sketchfab models (license verified per model, CC0/CC-BY only) or modeled low-poly from reference. Olympic Stadium deferred until the map grows east.

## Testing & verification

- **Pipeline:** pytest unit tests on geometry functions; golden-sample test (tiny OSM fixture → expected mesh stats); determinism check.
- **Game:** Godot headless smoke tests (scene loads, player spawns, car enter/exit); scripted screenshot captures reviewed visually after each milestone.
- **Performance:** per-tile poly budgets enforced by the pipeline; 60fps target checked on real hardware.

## Milestones

*(Reordered 2026-07-19 per user decision: visuals before character — a recognizable city first.)*

1. **Repo + scaffold** — git repo, Godot project boots, pipeline skeleton runs end-to-end on a stub ✅ (tag m2-gray-city)
2. **Gray city** — real downtown roads + extruded blocks render in Godot, fly-cam ✅ (tag m2-gray-city)
3. **Make it Montreal** — palette, landmarks, water/parks, Mont Royal terrain, minimap, day/night ✅ (tag m3-montreal)
3.5. **WOW pass** *(added 2026-07-19 per user: "better graphics, more detailed, make someone say WOW")* — emissive window grids that light up at night, procedural sky with sun disc + SSAO + glow + ACES tonemap, street trees & lamps from OSM node data, animated water shader, roof caps/gables
4. **On foot** — walkable streets, collisions, street-name HUD
5. **Behind the wheel** — drivable car, enter/exit, camera, speedometer
6. **Polish** — audio, tuning, credits/attribution screen (OSM ODbL + Montreal CC-BY + asset credits)

## Repo layout

```
MontrealOpenWorld/
├── pipeline/        # Python map pipeline
├── game/            # Godot 4 project (world tiles under game/world/)
├── data/            # gitignored raw downloads
└── docs/            # specs and plans
```

## Licensing obligations

- OSM data: ODbL — attribution "© OpenStreetMap contributors" in credits
- Montreal open data: CC-BY 4.0 — attribute Ville de Montréal
- HRDEM: Open Government Licence – Canada
- Kenney/Quaternius: CC0 (attribution optional, given anyway)
- Mixamo: free for use in games; no redistribution of raw animation library
- Per-model license checks for any Sketchfab landmark model before inclusion
