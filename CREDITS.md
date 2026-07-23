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

## Engine

**Godot Engine** — https://godotengine.org/
Licensed under the [MIT License](https://godotengine.org/license/).

## This project

MTL: Open Île's own code (`pipeline/`, `game/scripts/`, etc.) is not covered by the licenses
above; see the repository root for the project's own license, if any.

*Poutine not included.*
