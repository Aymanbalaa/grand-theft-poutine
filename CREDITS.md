# Credits

MTL: Open Île combines the following third-party data, assets, and software.

## Map data

**OpenStreetMap** — © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors.
Licensed under the [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/).
Downloaded via the Overpass API for the downtown Montréal area used by `pipeline/`.

## Terrain

**HRDEM (High Resolution Digital Elevation Model)** — Natural Resources Canada.
Source: https://open.canada.ca/data/en/dataset/957782bf-847c-4644-a757-e383c0057995
Licensed under the [Open Government Licence – Canada](https://open.canada.ca/en/open-government-licence-canada).

## Textures

**ambientCG** — https://ambientcg.com/
All materials licensed [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/)
(Public Domain). Fetched programmatically via the ambientCG API/download endpoints
(`ambientcg.com/api/v2/...`, `ambientcg.com/get?...`) by `pipeline/textures.py`.

## Car models

**Car Kit** by Kenney (Kenney.nl), original models by Quaternius.
Source: https://kenney.nl/assets/car-kit
Licensed [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) (Public Domain
Dedication) — no attribution required, credited here anyway.
Six vehicle meshes (`sedan`, `suv`, `taxi`, `police`, `hatchback-sports`, `van`) committed as
`game/assets/models/cars/car0.glb` … `car5.glb`. Downloaded 2026-07-19.
Full provenance and per-file mapping: [`game/assets/models/cars/SOURCE.md`](game/assets/models/cars/SOURCE.md).

## Prop models

**Nature Kit**, **City Kit (Roads)**, and **Furniture Kit** by Kenney (Kenney.nl).
Sources: https://kenney.nl/assets/nature-kit, https://kenney.nl/assets/city-kit-roads,
https://kenney.nl/assets/furniture-kit
Licensed [CC0 1.0 Universal](https://creativecommons.org/publicdomain/zero/1.0/) (Public Domain
Dedication) — no attribution required, credited here anyway.
Three tree meshes, one lamp post, and one bench committed as
`game/assets/models/props/{tree0,tree1,tree2,lamp_post,bench}.glb`. Downloaded 2026-07-23.

**Fire hydrant** by Quaternius, via [Poly Pizza](https://poly.pizza/m/DKkMQbEklp).
Licensed [CC0 1.0 Universal / Public Domain](https://creativecommons.org/publicdomain/zero/1.0/).
Committed as `game/assets/models/props/hydrant.glb`. Downloaded 2026-07-23.

Full provenance and per-file mapping: [`game/assets/models/props/SOURCE.md`](game/assets/models/props/SOURCE.md).

## Rue Saint-Paul slice assets

Fetched by `pipeline/slice_assets.py` (gitignored, hash-verified). Pinned IDs: `game/assets/slice/SOURCE.json`.

**Poly Haven** (https://polyhaven.com): textures `cobblestone_floor_001`, `stone_wall_05`, `old_stone_wall`, `red_brick_03`, `sandstone_blocks_05`, `granite_tile_04`, `roof_slates_03`, `wood_peeling_paint_weathered`; models `street_lamp_02`, `outdoor_table_chair_set_01`, `planter_box_01`, `potted_plant_02`, `fire_hydrant`, `metal_trash_can`, `painted_wooden_bench`, `wine_barrel_01`, `wooden_crate_02`, `covered_car`, `shrub_02`, `Lantern_01`, `round_wooden_table_01`, `bar_chair_round_01`, `utility_box_01`; HDRIs `rooftop_night`, `cobblestone_street_night`. All [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

**Quaternius** (https://quaternius.com), via poly.pizza: six animated characters (Casual Character, three Animated Women, Man, Adventurer). [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

**Fonts**: Playfair Display and Josefin Sans (Google Fonts), [SIL Open Font License 1.1](https://openfontlicense.org). The license texts ship in `game/assets/slice/fonts/`.

Slice audio (rain, drips, wet footsteps) is synthesized by `pipeline/slice_audio.py`. No recorded assets.

## Engine

**Godot Engine** — https://godotengine.org/
Licensed under the [MIT License](https://godotengine.org/license/).

## This project

MTL: Open Île's own code (`pipeline/`, `game/scripts/`, etc.) is not covered by the licenses
above; see the repository root for the project's own license, if any.

*Poutine not included.*
