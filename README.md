# 🍟 Grand Theft Poutine

**A GTA-like open-world game set in a real, recognizable downtown Montréal — generated from actual map data.**

No missions (yet). The game *is* the city: real street grid, real street names, real landmarks, Mont Royal at real elevation. Walk it, drive it, watch the sun set over the Old Port.

*Working title: MTL — Open Île.*

| | |
|---|---|
| ![Driving through Old Montreal](docs/screenshots/m6c_driving_day.png) | ![Downtown skyline at night](docs/screenshots/m6b_night.png) |
| ![Night drive on Rue Saint-Paul](docs/screenshots/m6c_driving_night.png) | ![Dusk over the Old Port](docs/screenshots/m6b_dusk.png) |
| ![Avenue du Parc streetscape](docs/screenshots/m7_uphill_facade.png) | ![On foot by day](docs/screenshots/m7_onfoot_day.png) |
| ![Downtown at night](docs/screenshots/m35_night.png) | ![Sunset over the Old Port](docs/screenshots/m35_dusk.png) |
| ![Downtown overview](docs/screenshots/m35_overview.png) | ![Mont Royal](docs/screenshots/m35_mountain.png) |
| ![Old Port](docs/screenshots/m35_oldport.png) | ![Biosphère & Île Sainte-Hélène](docs/screenshots/m35_biosphere.png) |

## New: *Nuit de livraison* — the first game mode

The slice is now a game. You're an on-foot courier working a 6-minute rainy evening shift in Old Montréal.

| | |
|---|---|
| ![Title screen](docs/screenshots/game_title.png) | ![Pickup: follow the amber beam](docs/screenshots/game_pickup.png) |
| ![Delivering: order timer, bag condition, minimap](docs/screenshots/game_dropoff.png) | ![Crossroads of rue Saint-Paul and rue Saint-Vincent](docs/screenshots/slice_corner.png) |

- **Deliver**: orders pop up from the quarter's 24 shops (*trois poutines*, *un bouquet de pivoines*, *une caisse de vinyles*...) for its 52 street addresses. Pick up at the amber beam, deliver to the cyan one, and press **E** at the door.
- **Get paid**: base pay grows with distance. Tips scale with time left and bag condition. On-time streaks multiply tips, express orders pay double tips on a tighter clock, and the clock tightens as the shift goes on.
- **Don't wreck the bag**: running into pedestrians or rolling with the bag damages it, and fragile items (wine, vinyl, art) suffer more. Punching passers-by costs a fine.
- **Au voleur !** Pickpockets strike now and then. They sprint through the street graph away from you; punch or roll into them for a reward before they lose you.
- **Explore**: 12 gilt fleurs-de-lys are hidden around the quarter, saved across sessions along with your best shift.
- **The quarter**: rue Saint-Paul, a full rue Saint-Vincent crossing it, and rue de la Commune along the Marché Bonsecours, all sealed by closing buildings. It has blue enamel house numbers, faded painted ads on party walls, and about 34 pedestrians.
- **Interface**: HUD with cash and clock, an objective card with order timer, an edge-of-screen target pointer, a minimap, and title and end-of-shift screens. Sound cues (order ping, cash chime, police whistle...) are synthesized.

Run `play_slice.bat` and press **Enter** for a shift or **Space** for free roam. Gameplay gate (headless): `SLICE_SAVE=user://test_save.json tools/godot/godot_console.exe --headless --fixed-fps 60 --path game --script res://slice/game_test.gd` → `GAME OK`.

## New: the Rue Saint-Paul vertical slice

One hand-dressed Old-Montréal street at blue hour, just after rain. It's the new visual bar: content quality first, one location done properly before scaling back up to the whole city.

| | |
|---|---|
| ![Rue Saint-Paul, blue hour](docs/screenshots/slice_hero.png) | ![Marché Bonsecours dome at the end of the street](docs/screenshots/slice_dome.png) |
| ![Café terrace and string lights](docs/screenshots/slice_cafe.png) | ![On foot, third person](docs/screenshots/slice_onfoot.png) |
| ![Boulangerie storefront](docs/screenshots/slice_storefront.png) | ![Overcast day mood](docs/screenshots/slice_day.png) |

- **Procedural facades with real depth**: greystone, red-brick, French-régime (rubble walls, steep roofs, firewalls, shutters) and Victorian styles. Real window openings with stone reveals, casement frames and muntins, cornices with modillions, mansards with dormers, chimneys. Every window shows an interior-mapped room (parallax walls, pendant lamps, curtains, TV flicker), and shops show shelving and display tables.
- **Wet street**: world-space PBR cobbles (Poly Haven CC0) with puddles that pool in the stone gaps and gutters, animated rain ripples, and screen-space reflections of every lamp and shop window.
- **Light**: wall lanterns, cast-iron kerb lamps, café string lights, glowing shopfronts, a floodlit Marché Bonsecours dome closing the vista, volumetric fog, SDFGI, and AgX tonemapping. Three moods: blue hour, night, overcast day.
- **Life**: umbrella-carrying pedestrians, window-shoppers, a third-person player who can walk, run, roll, punch and wave (CC0 Quaternius characters), steaming manholes, cars under tarps, and synthesized rain, drip and footstep audio.
- **~60 fps at 1080p** on an RX 6700S laptop (High preset; F5 cycles Medium/High/Ultra). Only the 5 lamps nearest the camera render shadow maps.

Run it: `.venv/Scripts/python -m pipeline.slice_assets` once (fetches the gitignored CC0 assets, hash-verified), then `play_slice.bat`.
Controls: WASD walk · Shift run · Space roll · LMB punch · E wave · V fly-cam · Tab cinematic tour · 1/2/3 mood · R rain · F5 quality · H help.
Screenshots: `tools/godot/godot_console.exe --path game --resolution 1920x1080 --script res://slice/shots.gd`. Fly-through video: `... res://slice/slice.tscn --write-movie out.avi --fixed-fps 30 -- --tour`.

## How it works

Two halves, joined by a data contract:

```
OpenStreetMap ──┐
                ├──►  pipeline/  (Python)  ──►  game/world/  ──►  game/  (Godot 4.5)
HRDEM elevation ┘     offline, deterministic     glTF tiles         runtime
```

- **`pipeline/`** — Python. Downloads downtown Montréal from OpenStreetMap (Overpass) and terrain from Canada's HRDEM elevation data, then converts it into 256 m glTF tiles: extruded buildings colored by type (brick residential, glass towers, greystone churches), roads by class, the St. Lawrence assembled from multipolygon relations, and terrain-draped everything. Deterministic — same input, byte-identical output. `nav.json` carries road/sidewalk polylines with baked heights so traffic and (M10b) pedestrians never raycast.
- **`game/`** — Godot 4.5. Loads the tiles, distance-culls them, and runs the day/night cycle, minimap, and (soon) the player.
- **Hero landmarks** — Place Ville Marie, Notre-Dame Basilica, the Biosphère, Habitat 67, and the Farine Five Roses sign are procedurally modeled low-poly at their true coordinates.

## Roadmap

- [x] **M1–M2** — Gray city: real street grid + extruded buildings, fly-cam
- [x] **M3** — Make it Montréal: palette, river, Mont Royal terrain, landmarks, day/night, minimap
- [x] **M3.5** — WOW pass: emissive windows at night, 16k street trees & lamps from OSM, procedural sky/SSAO/glow/ACES, animated water, roof caps & gables
- [x] **M4** — On foot: third-person character (blocky minifig with a tuque), lazy trimesh collisions, street + district HUD, spawn downtown (F = debug fly-cam)
- [x] **M5** — Behind the wheel: 120 parked cars on real streets, walk up + **E** to drive (arcade physics, chase cam, speedometer)
- [x] **M6a** — Surfaces: real CC0 textures (brick/stone/concrete facades, asphalt, paving), window frames & storefronts, sidewalks with curbs, lane markings
- [x] **M6b** — Light: warm sun & ambient, thinner fog, pooled street lights, car headlights
- [x] **M6c** — Things: Kenney CC0 car models, traffic lights at real signal positions, credits screen (**C**)
- [x] **M7** — Polish: procedural audio (engine/footsteps/ambient — synthesized, license-free), kill-plane respawn, one-way streets get white centerlines, facades anchored to real ground height, car & headlight tuning, landmark collision
- [x] **M8** — Realism Graphics I: procedural sky/water/terrain shaders (fbm clouds & sun disc, analytic waves, grass/dirt/rock blend + dirt paths), CC0 wall/road/sidewalk textures with per-building facade variation, 16,498 OSM trees & 21 benches via a pooled MultiMesh prop renderer, white-car colormap fix
- [x] **M9** — Realism Graphics II: warm sun/shadow/fog grade (shadow reach, contrast/saturation grade, volumetric night fog), crosswalks & manhole decals & ground-floor doors, fake window interiors & camera-near grass, CC0 player model, storefront awnings, lamp-colormap safety net
- [x] **Game** — *Nuit de livraison*: courier shifts (orders, timers, tips, streaks, express), pickpocket chases, hidden fleurs-de-lys, HUD/minimap/pointer, saves; the quarter expanded to three streets
- [x] **Slice** — Rue Saint-Paul vertical slice: procedural Old-Montréal facades with interior-mapped windows, rain-wet cobbles, lamps, pedestrians, a third-person player, ~60 fps (new visual bar; see above)
- [x] **M10a** — Traffic: pipeline exports a road + sidewalk nav graph (`nav.json`, tiles byte-identical); 40 pooled cars drive real lanes on the right, queue at real signal positions, yield at junctions, brake for you, and collide with your car; pooled headlights at night

## Run it

1. `py -m venv .venv && .venv/Scripts/pip install -r requirements.txt`
2. [Godot 4.5-stable](https://godotengine.org/download/archive/) portable → `tools/godot/`
3. Generate the city (or use the committed tiles in `game/world/`): `.venv/Scripts/python -m pipeline.build`
4. Open `game/` in Godot and run `scenes/main.tscn` — WASD + mouse to walk, **E** near a parked car to drive, **F** for the debug fly-cam, hold **T** to fast-forward time

Tests: `.venv/Scripts/python -m pytest pipeline -q` and `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd`

## Data & licenses

Full attributions: [CREDITS.md](CREDITS.md) (also in-game — press **C**).

- Map data © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors (ODbL)
- Terrain: [HRDEM](https://open.canada.ca/data/en/dataset/957782bf-847c-4644-a757-e383c0057995) — Natural Resources Canada (Open Government Licence – Canada)
- Engine: [Godot](https://godotengine.org/) (MIT)

*Poutine not included.*
