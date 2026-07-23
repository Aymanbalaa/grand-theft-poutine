# Prop model sources

Six CC0 prop models for the street-furniture MultiMesh renderer: three tree
variants, a lamp post, a bench, and a fire hydrant. All six were found —
nothing was skipped.

## Trees (tree0, tree1, tree2) — Kenney Nature Kit

**Pack:** Nature Kit (2.1)
**Author:** Kenney (Kenney.nl)
**License:** CC0 1.0 Universal (Public Domain Dedication) — https://creativecommons.org/publicdomain/zero/1.0/
**Source URL:** https://kenney.nl/assets/nature-kit
**Direct download used:** https://kenney.nl/media/pages/assets/nature-kit/37ac38a37b-1677698939/kenney_nature-kit.zip
**Download date:** 2026-07-23

### License evidence

The pack's own `License.txt` (bundled in the zip) states:
"License: (Creative Commons Zero, CC0) http://creativecommons.org/publicdomain/zero/1.0/ —
This content is free to use in personal, educational and commercial projects." The kenney.nl
asset page independently states the same "Creative Commons CC0" license, and the pack's preview
image carries Kenney's own "CC0 1.0" badge.

### Files

Selected 3 of the pack's ~70 tree meshes (from `Models/GLTF format/`, which — despite the folder
name — contains `.glb` binaries, not separate `.gltf` + buffers) for visual variety of deciduous
street trees (no palms, matching a Montréal setting):

| Committed file | Original filename  | Description                          |
|----------------|---------------------|---------------------------------------|
| tree0.glb      | tree_default.glb    | Round-canopy generic tree             |
| tree1.glb      | tree_oak.glb        | Fuller oak-style canopy               |
| tree2.glb      | tree_detailed.glb   | Higher-poly tree with visible branches |

No external texture files — these meshes are vertex-colored (no `images`/materials with texture
references in the glTF JSON; confirmed by inspecting each `.glb`'s JSON chunk).

### Native dimensions (world-space bounding box, meters, from `models_test.gd`)

| File      | Size (x, y, z)              |
|-----------|-------------------------------|
| tree0.glb | (0.755, 1.71, 0.654)          |
| tree1.glb | (0.641, 1.23, 0.740)          |
| tree2.glb | (0.847, 1.33, 0.762)          |

These are Kenney's small "kit" scale (~1–2 m tall), well under the 3–8 m real-world tree height
called for in the task brief — the MultiMesh renderer (Task 4) is expected to rescale them up.

## Lamp post — Kenney City Kit (Roads)

**Pack:** City Kit (Roads) (2.0)
**Author:** Kenney (Kenney.nl)
**License:** CC0 1.0 Universal (Public Domain Dedication) — https://creativecommons.org/publicdomain/zero/1.0/
**Source URL:** https://kenney.nl/assets/city-kit-roads
**Direct download used:** https://kenney.nl/media/pages/assets/city-kit-roads/74288c9459-1741864740/kenney_city-kit-roads.zip
**Download date:** 2026-07-23

### License evidence

Pack's `License.txt`: "License: (Creative Commons Zero, CC0) — You can use this content for
personal, educational, and commercial purposes." Matches the kenney.nl asset page's stated
"Creative Commons CC0" license.

### Files

| Committed file | Original filename (in `Models/GLB format/`) | Description                    |
|-----------------|----------------------------------------------|---------------------------------|
| lamp_post.glb   | light-square.glb                              | Single street light on a post  |

(Other light variants in the pack — `light-curved`, `light-square-cross`, `light-square-double`,
`light-curved-double`, `light-curved-cross` — are double-headed or curved-arm street lights; the
plain single post was the closest fit for a generic "lamp post" prop.)

### ⚠ External texture dependency

`lamp_post.glb`'s material references its texture via **external relative URI**
`Textures/colormap.png` (same recurring hazard as the car kit — confirmed by inspecting the
glTF JSON `images` array: `{"uri": "Textures/colormap.png", ...}`). The file has been copied
alongside the model, preserving the relative path:

```
game/assets/models/props/Textures/colormap.png
```

sourced from the same pack directory (`Models/GLB format/Textures/colormap.png`). This texture
is shared across the whole City Kit (Roads) pack — if more roads-kit props are added later to
this project, they likely reuse the same `colormap.png`.

### Native dimensions

| File          | Size (x, y, z)        |
|---------------|--------------------------|
| lamp_post.glb | (0.05, 0.6, 0.2375)     |

Kit scale again — real street lamps are ~5 m; Task 4's renderer rescales.

## Bench — Kenney Furniture Kit

**Pack:** Furniture Kit (2.0)
**Author:** Kenney (Kenney.nl)
**License:** CC0 1.0 Universal (Public Domain Dedication) — https://creativecommons.org/publicdomain/zero/1.0/
**Source URL:** https://kenney.nl/assets/furniture-kit
**Direct download used:** https://kenney.nl/media/pages/assets/furniture-kit/440e0608a4-1677580847/kenney_furniture-kit.zip
**Download date:** 2026-07-23

### License evidence

Pack's `License.txt`: "License: (Creative Commons Zero, CC0) — This content is free to use in
personal, educational and commercial projects." Matches the kenney.nl asset page.

### Files

| Committed file | Original filename (in `Models/GLTF format/`) | Description        |
|-----------------|------------------------------------------------|---------------------|
| bench.glb       | bench.glb                                       | Plain wooden bench  |

(The pack also ships `benchCushion.glb` and `benchCushionLow.glb` — cushioned/indoor variants;
the plain wooden `bench.glb` reads best as street furniture.) No external texture — vertex-colored,
same as the trees (no `images` array in the glTF JSON).

### Native dimensions

| File     | Size (x, y, z)     |
|----------|----------------------|
| bench.glb | (0.4, 0.47, 0.2)    |

## Fire hydrant — Quaternius (via Poly Pizza)

**Author:** Quaternius
**License:** CC0 / Public Domain — https://creativecommons.org/publicdomain/zero/1.0/
**Redistributor / download host:** Poly Pizza — https://poly.pizza/m/DKkMQbEklp
**Direct download used:** https://static.poly.pizza/0e892859-5ccd-4f9a-aa56-c7a9adb6f3de.glb
**Download date:** 2026-07-23

### License evidence

No Kenney or Quaternius pack in the packs checked for this task (Nature Kit, City Kit Suburban,
City Kit Roads, Furniture Kit) ships a fire hydrant model. Quaternius does model fire hydrants,
but as a standalone/loose asset rather than bundled with a currently-listed pack page on
quaternius.com; Poly Pizza (a well-known aggregator of CC0/attribution-tracked models, used
previously in this project's research as a cross-reference for the car kit) hosts it directly
with an explicit, unambiguous per-model license field. The model's Poly Pizza page states the
license as **"Public Domain (CC0)"**, hyperlinked to
https://creativecommons.org/publicdomain/zero/1.0/, and separately confirmed by fetching the raw
page HTML: the license string appears as `Public Domain (CC0)` immediately after the file-format
field (`FBX/GLTF format`), with the creator listed as `Quaternius`. This is consistent with
Quaternius's site-wide policy — every Quaternius pack independently checked (e.g. Modular Streets
Pack, https://quaternius.com/packs/modularstreets.html) is also explicitly licensed CC0; Quaternius
has never published a non-CC0 pack.

### Files

| Committed file | Description                                  |
|-----------------|-----------------------------------------------|
| hydrant.glb     | Single-mesh red fire hydrant, 969 vertices    |

### ⚠ Embedded-texture import quirk (not an external URI, but flag it anyway)

The GLB embeds its texture image in a binary `bufferView` (not an external URI — confirmed by
inspecting the glTF JSON: `"images":[{"name":"Zombie_Atlas.png","bufferView":0,...}]`, no `uri`
key), so there is **no external texture file to commit**; the single `hydrant.glb` is fully
self-contained. However, Godot's glTF importer automatically extracts embedded images into a
loose PNG next to the source model on every `--import` run
(`game/assets/models/props/hydrant_Zombie_Atlas.png`), to apply its own texture-compression
pipeline. This is a deterministic, regenerable import byproduct — verified by deleting it and the
`.godot` import cache and re-running `--import`, which recreated it identically — analogous to the
`.import` cache files. It is **not committed**; it's explicitly ignored via `.gitignore`
(`game/assets/models/props/hydrant_Zombie_Atlas.png`). The embedded image name
("Zombie_Atlas.png") is a harmless leftover from whatever other Quaternius asset the texture atlas
was originally authored for — it has no bearing on the hydrant's own appearance.

### Native dimensions

| File        | Size (x, y, z)              |
|-------------|--------------------------------|
| hydrant.glb | (0.515, 0.773, 0.399)         |

Note: the raw mesh vertices in the GLB are tiny (millimeter scale); the model's `FireHydrant` node
carries a `scale: [100, 100, 100]` to bring it to the dimensions above. A naive
`MeshInstance3D.get_aabb()` read without accounting for that scale would misreport the size by
100× — `models_test.gd`'s prop-validation loop computes the composite local-transform chain
explicitly (rather than relying on `Node3D.global_transform`, which requires the node to be
inside a live, ticked `SceneTree` and otherwise silently returns identity) specifically so this
kind of scaled intermediate node is measured correctly. 0.77 m tall is a realistic real-world fire
hydrant height, so this model is very close to true scale already — BUT only when the scale-100
intermediate node is honored: the renderer's `_find_mesh` accumulates node transforms into the
instance transforms precisely so this model renders at 0.77 m (raw mesh vertices are millimeter
scale; a spec scale of 1.0 with the transform chain ignored would render an 8 mm hydrant).

## Not skipped

Unlike the brief's fallback allowance, all six requested props (three trees, lamp post, bench,
fire hydrant) were found as verifiably CC0 GLB models. No `PROP_SKIP` entries are needed in
`models_test.gd`.

## Validation

Loaded and instantiated in Godot 4.5 headless via `game/tests/models_test.gd`
(`tools/godot/godot_console.exe --headless --path game --script res://tests/models_test.gd`,
after `tools/godot/godot_console.exe --headless --path game --import`). All 6 props loaded
without error, each with a non-null mesh on its first `MeshInstance3D`; see native dimensions
tables above for the reported world-space bounding-box sizes.
