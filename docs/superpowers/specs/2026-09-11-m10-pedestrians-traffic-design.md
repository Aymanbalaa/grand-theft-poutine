# M10 — Pedestrians & Traffic (Design)

**Date:** 2026-09-11
**Status:** Direction chosen by user at the M9c3 completion gate (M10 = pedestrians & traffic AI). Three design questions answered by user: pedestrians are knocked down (no ragdoll) and recycled; traffic obeys a global signal cycle at the real OSM signal nodes; moderate density (~40 cars / ~60 pedestrians pooled). Design approved in chat 2026-09-11; each sub-phase ends at a user screenshot gate.
**Baseline:** tag `m9c3-safety`, 314 tiles, smoke 20 gates, pytest 100. Reference screenshots `docs/screenshots/m9c2_*.png` (13 poses).
**Parent spec:** `docs/superpowers/specs/2026-07-18-montreal-open-world-design.md` (pedestrian/vehicle traffic listed as deferred; "lane metadata retained for future traffic" — this spec is that future).

## Goal

Make the streets alive. Cars drive the real road network with right-hand lane discipline, queue at the real traffic signals, and brake for the player; pedestrians walk the sidewalks, cross at corners, step aside for the player and are knocked down (then recycled) by the player's car. No police, no combat, no missions — the city is still the game, but it is no longer empty.

## What exists today (audit)

- **Nothing navigable is exported.** `pipeline/osm_parse.py` keeps every road's full centerline, `road_class`, `width` (class-derived), `oneway` (as a bool; `-1` is treated like `yes` with no reversal) and `name`; it drops `lanes`, `maxspeed`, `sidewalk`, `crossing`. Junctions are computed transiently in `pipeline/tiler.py` (`junctions = frozenset(...)`) for sidewalk/roadmark trimming and discarded. The 2157 `highway=traffic_signals` nodes become baked pole geometry in the `props` bucket with no orientation and no metadata entry. `city_metadata.json` carries no road graph.
- **Heights are analytic at build time.** Every exported y is `hm.sample(x, z)`; the road ribbon is `ground + 0.05` at each densified station (`_densify`, 24 m max segment), the sidewalk top is `ground(station) + 0.05 + jitter + SIDEWALK_RAISE (0.12)` sampled at the **centerline station**, not at the offset point. The game has no height oracle — it raycasts (only inside the 280 m collision ring) or falls onto collision.
- **Sidewalk centerline is a fixed offset** from the road centerline: `±(w/2 + CURB_RUN 0.18 + SIDEWALK_WIDTH/2)` = `±(w/2 + 1.18)`, on `SIDEWALK_CLASSES` roads only, over `_clear_intervals` that stay `SIDEWALK_END_TRIM = 8 m` from way ends and junction vertices.
- **All 120 parked cars are full live `car.tscn` nodes** (2 shadow spotlights + camera + audio each), frozen via `park()` because tile collision exists only in the ring. `main.gd::_nearest_car` scans all of them every frame. Parked cars sit `w/2 − 1.1` from the centerline (right edge of the roadway).
- **Player visual is a script** (`character_visual.gd`) that builds a `Skeleton3D` + `AnimationPlayer` + tuque per instance from the CC0 Kenney character (32 clips incl. `idle`, `walk`, `sprint`, `fall`, `sit`, `emote-*`; 7 bones). It is instanceable but has no tint/tuque parameters.
- **No collision layers, no navigation, no `[physics]` section** in `project.godot`. Every body is layer 1 / mask 1.
- **Pooling precedents:** `props_multimesh.gd` (256 m chunked MultiMesh), `light_pool.gd` (24 nearest lights re-targeted every 0.25 s), `decal_pool.gd` (32 decals). HANDOFF rule: never one resident node per world object.

## Approaches considered

- **Pipeline-exported nav graph + analytic lanes/sidewalks (chosen)** vs **Godot NavigationServer navmesh** (needs baking over 314 tiles, no lane/oneway discipline for cars, pedestrians wander onto asphalt, RVO cost) vs **runtime derivation from the glTF road ribbons** (fragile; oneway and signals already lost). The pipeline already has every fact and the heightmap; exporting a graph with baked y lets agents live outside the collision ring with zero raycasts.
- **Structure — three gated sub-phases (chosen)** (10a traffic, 10b pedestrians, 10c optional polish) vs one M10 gate. The two agent systems share the graph but have different risk profiles; one rebuild (10a) exports both graphs so 10b needs no rebuild.
- **Signals — global phase clock at OSM signal nodes (chosen, user)** vs cone-yield only. The baked light heads stay static (a later polish item); cars stopping at real intersections is what sells it.
- **Pedestrian hits — knockdown + recycle (chosen, user)** vs ghosts (no collider) vs physical ragdoll (perf risk × 60).

## Sub-phases

### 10a — Nav export & traffic (pipeline rebuild + game)

**Pipeline.** New `pipeline/nav.py` with `build_nav(city, hm) -> dict`, written by `export_city` to `game/world/nav.json` (compact separators, `sort_keys=True`) and referenced from `city_metadata.json["nav_file"] = "nav.json"`. Tiles must come out **byte-identical** (git status shows only `nav.json` + `city_metadata.json` changed); orphan check as usual.

`osm_parse.Road` gains two optional fields with defaults: `lanes: int | None` (from `lanes=`), `maxspeed: float | None` (m/s, from `maxspeed=` parsing "50", "50 km/h", "30 mph"; unparsable → `None`). `oneway` stays a bool; a new `oneway_reversed: bool` records `oneway=-1` so nav can reverse the polyline. Existing tests/consumers are unaffected (defaults).

Schema of `nav.json`:

| key | shape | notes |
|---|---|---|
| `nodes` | `[[x, y, z], ...]` | shared by all graphs; x/z rounded 0.1 m, y rounded 0.01 m. Road nodes carry **road-surface** y (`ground + 0.05`); walk nodes carry **sidewalk-top** y (`ground(station) + 0.17 + jitter`) — both computed with the same functions/sampling points as `road_mesh` / `sidewalk_mesh` so agents sit on the ribbon. Road polylines use the **densified** stations (`_densify`, 24 m) so linear interpolation between nodes matches the planar ribbon quads exactly. |
| `roads` | `[{"n": [node idx...], "cls": str, "w": float, "oneway": 0\|1, "lanes": int, "speed": float, "id": osm_id}, ...]` | drivable classes only: `motorway, trunk, primary, secondary, tertiary, residential, unclassified, living_street` + `*_link`. **`service` excluded** (parking aisles/driveways). `oneway=-1` ways are reversed so node order is always the legal direction. `lanes` = OSM lanes if present else 2 for two-way / 1 for oneway. `speed` = OSM maxspeed (m/s) if present else class default (`NAV_SPEED_DEFAULTS` in config: motorway 25, trunk 20, primary 14, secondary 12.5, tertiary 11, residential 8.5, unclassified 8.5, living_street 5, links = parent). Junction nodes are shared indices (same rounded (x,z) → same node), so adjacency is implicit. |
| `signals` | `[node idx, ...]` | each OSM signal snapped to the nearest **road** node within 3 m; unmatched dropped; sorted, deduplicated. |
| `walks` | `[{"n": [node idx...], "kind": "side"\|"path"\|"cross"}, ...]` | `side`: for every `SIDEWALK_CLASSES` road and every `_clear_intervals` interval ≥ 4 m, two polylines (left/right) at lateral `±(w/2 + 1.18)` over the densified slice — same trim/junction set as `sidewalk_mesh`. `path`: centerline of `footway, pedestrian, path, steps, living_street` ways (steps walked at half speed). `cross`: at each junction of sidewalk-class roads, all `side` endpoints within 12 m of the junction vertex are connected pairwise (2-node polylines), so pedestrians cross the asphalt at corners; the two `side` endpoints at a dead-end (way end with no junction) are connected by one `cross` so walkers can turn around. Walk endpoints that coincide (rounded 0.1 m) with a `path` endpoint share the node. |

Determinism: iterate roads sorted by `osm_id`, node interning by rounded (x, z, kind) tuple in first-seen order, integer-hash only, no `math.sin`. Size target ≤ 8 MB; if exceeded, prune `path` ways whose first point is beyond `MANHOLE_RADIUS` (900 m) first, then raise the rounding — never prune roads or signals.

Tests `pipeline/tests/test_nav.py` (mini fixture): exact top-level key set and per-record key sets; `service` absent, oneway `-1` reversed, two `side` polylines per eligible road with offsets `w/2 + 1.18` from the centerline (both signs), a `cross` polyline at the fixture junction, signal maps to a road node, `steps` present as `path`, node y equals `hm.sample + 0.05` (road) / `+0.17 + jitter` (walk) with a synthetic heightmap, and `build_nav(city) == build_nav(city)` byte-identical via `json.dumps`. `test_export.py` gains `nav_file` key presence + file exists.

**Game — `nav_graph.gd`** (`RefCounted`, loaded once by `Main`, shared by both managers): parses `nav.json` into `PackedVector3Array` nodes and typed arrays; builds `out_roads[node] -> [(road_idx, dir)]` adjacency where `dir = +1` forward, `-1` reverse (two-way only); exposes `road_point(road, dir, lane, t) -> Vector3` (lane-centerline sample: position + right-hand lateral offset), `road_length(road)`, `next_road(road, dir, seed) -> (road, dir)` (deterministic hash-weighted pick among legal out-edges at the far node, never the reverse of the current road unless it is the only exit), `is_signal(node)`, and the walk equivalents `walk_point`, `next_walk`. Lane lateral offset: two-way → `clamp(w/4, 1.0, 1.75)` on the right of travel; oneway with `L` lanes → lane `k` center at `-w/2 + w*(k+0.5)/L`. Pure functions; unit-tested headless.

**Game — `traffic.gd`** (`Node3D` "Traffic" under Main, group `traffic`): pool of `POOL_SIZE = 40` `traffic_car.tscn` instances allocated once; per-agent state in parallel arrays (road, dir, lane, t, speed, seed, stuck_time, active). One `_process` updates all agents; **no per-agent script logic**.

- **Spawn/despawn:** every 0.5 s, if a slot is free, pick a hash-random drivable road and `t` such that the point is 80–220 m from the active camera and ≥ 15 m from any agent, parked car, or the player's car; despawn beyond 280 m or after 20 s with speed < 0.2 m/s. Spawn preferably behind the camera (dot with camera forward < 0.3) when a candidate exists.
- **Following:** target speed = `min(road.speed, curve-limited)`; brake for any obstacle inside the ahead cone (15 m long, ±2.5 m lateral, in the lane frame): other agents, the player's car (driven or parked in a lane), the player on foot, and (10b) pedestrians. Headway = 2 s + 6 m. Accel/decel constants mirror `car.gd` (`ACCEL 9`, `BRAKE 16`) so traffic reads like the player's car.
- **Parked cars:** when a parked car lies inside the lane within 12 m ahead, the agent's lateral offset lerps toward `max(1.0, lane − 0.8)` while passing; on 6 m residential streets near-misses are accepted for v1.
- **Signals:** global clock `t = fmod(Time + hash(node) * 5.3, 16.0)`; approaches at a signal node are split into two groups by heading (nearest to the first approach's axis mod 180°); group A is green for `t < 7.5`, group B for `8.0 ≤ t < 15.5`, else red (the gaps are all-red). A red approach stops at a stop line 6 m before the node unless its front bumper is already past it. A signal node whose approaches all fall in one group (a mid-block pedestrian signal) still cycles: group A only, so traffic pauses there roughly half the cycle, which reads as a pedestrian crossing. Unsignalized junctions (≥ 3 out-edges): slow to 50 % within 15 m and yield while any other agent is inside an 8 m radius of the node and arrived first.
- **Body/visual:** `traffic_car.tscn` = `AnimatableBody3D` (`sync_to_physics = true`) with the same `BoxShape3D 1.9 × 1.1 × 4.3` as `car.tscn`, child `Visual` running `car_visual.gd` (`color_index = seed % 6`; same polish + colormap net). Position/yaw set kinematically each frame from `road_point`; y from the graph (no raycast; valid outside the collision ring). The player's `CharacterBody3D` car collides with traffic physically; traffic ignores impacts (kinematic) and simply brakes for the player.
- **Headlights:** no per-car spotlights. `traffic.gd` owns a pool of 8 non-shadow `SpotLight3D` re-targeted every 0.25 s to the nearest active agents, energy driven by the same `smoothstep(0.4, 0.55, night_amount)` as `car.gd`. Night must gain moving headlights without regressing anything else.
- **Player-car hook:** `main.gd` exposes the driven/parked player car and on-foot player position to both managers via a small `agents_context()` accessor — no new globals; `Cars` stays as is.

*Gate 10a: screenshots (13 baseline poses + 2 new street-level poses: `signal` at a signalized intersection, `crosswalk` at a corner, day + night) — cars visibly driving in lanes, queued at a red, headlights at night; driving pose collides with traffic; night unchanged elsewhere; tiles byte-identical; smoke `NAV OK`, `TRAFFIC OK`, `SIGNALS OK`; pytest green.*

### 10b — Pedestrians (game-side, no rebuild)

- **`pedestrians.gd`** (`Node3D` "Pedestrians", group `pedestrians`): pool `POOL_SIZE = 60` `pedestrian.tscn`; state arrays (walk, dir, t, speed, state ∈ {WALK, WAIT, DOWN}, timer, seed). Spawn ring 25–120 m from the active camera, preferably behind it; despawn at 160 m or 4 s after DOWN.
- **Movement:** follow `walks` at 1.2–1.6 m/s (`walk` clip), 10 % joggers at 3.0 m/s (`sprint` clip), `steps` paths at half speed. At a node choose the next walk with the deterministic chooser (no immediate reversal). Before entering a `cross` polyline: WAIT while any traffic agent is within 15 m of the crossing and moving > 1 m/s toward it; traffic in turn brakes for pedestrians inside its cone, so the car stops first and the walker crosses (no deadlock: a waiting walker only yields to *moving* cars).
- **Player interaction:** WAIT (idle) while the on-foot player is within 1.5 m in front. When the **driven** player car moves > 3 m/s and its box comes within 1.6 m: play `fall` once (non-looping), state DOWN, body collider disabled, 4 s, then recycle far away. No ragdoll, no gore, no police.
- **Visual:** `character_visual.gd` gains `@export var tuque_enabled := true`, `@export var tuque_color := TUQUE`, `@export var tint := Color.WHITE` (applied by duplicating the imported materials once per instance and multiplying `albedo_color`; the colormap net runs first, as today). ~60 % of walkers wear tuques from 5 colors; tints are subtle (0.85–1.0 per channel) since the colormap also carries skin. Animation pauses (`AnimationPlayer.active = false`) beyond 70 m.
- **Body:** `AnimatableBody3D` with `CylinderShape3D` (r 0.35, h 1.7) so the on-foot player bumps into walkers; kinematic, y from the graph, no gravity.

*Gate 10b: `sidewalk` day/night poses show walkers on sidewalks and at corners; a walker stops for the player; knockdown works from the driving pose; smoke `PEDS OK`, `KNOCKDOWN OK`; frame-time within budget.*

### 10c — Life polish (optional; decided at the 10b gate)

Candidates, each small and independently droppable: pooled engine hum (6 `AudioStreamPlayer3D`, `engine.wav`, nearest agents, pitch by speed); pedestrian idle emotes at benches (`sit` on the 21 bench positions, `emote-*` occasionally); minimap blips for agents. None requires a rebuild.

## Tests & verification

- **pytest** (`pipeline/tests/test_nav.py`, `test_export.py`, `test_osm_parse.py` for lanes/maxspeed/oneway -1) — target ≥ 110.
- **Godot headless:** new `game/tests/nav_test.gd` (graph loads; node/road/walk counts above floors; `road_point` at `t=0` and `t=length` equals the end nodes; a seeded walker advances 200 m on roads and 200 m on walks without dead-ending; signal grouping yields exactly two non-empty groups at a 4-way node). Smoke gates added in order: `NAV OK: %d nodes, %d roads, %d walks, %d signals`, `TRAFFIC OK: %d active` (≥ 20 active after polling ≤ 600 frames, and at least one agent displaced > 5 m), `SIGNALS OK` (phase function alternates over a 16 s sweep), then in 10b `PEDS OK: %d walking` (≥ 20 active, one displaced > 2 m) and `KNOCKDOWN OK` (teleport the driven car into a walker at speed → state DOWN). Harness rule stands: poll conditions, never fixed frame waits.
- **Screenshots:** `docs/screenshots/m10a_*.png` / `m10b_*.png`, 13 baseline poses + `signal` + `crosswalk` + `sidewalk`, day and night; judged by Reading PNGs.
- **Perf budget:** Traffic + Pedestrians ≤ ~1.5 ms CPU per frame on the reference RX 6700S machine. Knobs, in order: `POOL_SIZE`s, ring radii, animation-pause distance, cone scan frequency (every 2nd frame).

## Constraints (hold throughout)

- All M8/M9 constraints inherited verbatim: commits authored ONLY by Aymanbalaa via the repo-local noreply config — NO `Co-Authored-By`/AI/session trailers, NO `--author` flags, NO git-config changes (repeat verbatim in every subagent dispatch); CC0-only assets with SOURCE.md; deterministic pipeline (no network in `pipeline.build`); no normal maps on tangent-less tile meshes; SDFGI off; **night regression fails any sub-phase**; screenshots judged by Reading PNGs; orphan check + byte-identical tiles after the rebuild.
- Pooled agents only (never one resident node per world object); no per-agent scripts; no raycasts in agent movement (heights come from the graph).
- Contracts untouched: `night_amount` global, vertex-alpha packing, facade `bhash`, `car_spawns` schema, the 120 parked cars and `car.tscn` (traffic is a separate scene), `character_visual.gd` load order (colormap net before tuque).
- No collision-layer scheme is introduced in M10 (everything stays layer 1); revisit only if kinematic bodies fight the player capsule in practice.

## Success criteria

- 10a: cars drive the real streets on the right, stop at red at real signal positions, brake for the player, collide physically with the player's car, show headlights at night; world still 314 tiles, tiles byte-identical.
- 10b: pedestrians walk sidewalks and cross at corners, step aside for the player, get knocked down and recycled by the car; no ragdoll.
- Both: smoke + pytest green, perf within budget, user signs off at each gate.

## Out of scope (M10)

Police/wanted level, combat, ragdolls, lane changes/overtaking, traffic on `service` roads, animated signal heads, buses/bikes/other vehicle types, pedestrians entering buildings, minimap blips unless chosen for 10c, collision-layer rework, any change to the parked-car system.
