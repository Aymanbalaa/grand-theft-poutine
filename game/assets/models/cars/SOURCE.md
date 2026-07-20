# Car model source

**Pack:** Car Kit
**Author:** Kenney (Kenney.nl) — original models by Quaternius, redistributed/curated in Kenney's Car Kit
**License:** CC0 1.0 Universal (Public Domain Dedication) — https://creativecommons.org/publicdomain/zero/1.0/
**Source URL:** https://kenney.nl/assets/car-kit
**Direct download used:** https://kenney.nl/media/pages/assets/car-kit/1a312ec241-1775131960/kenney_car-kit.zip
**Download date:** 2026-07-19

## License evidence

The Kenney.nl asset page states the license as **"Creative Commons CC0"**, linking directly to
https://creativecommons.org/publicdomain/zero/1.0/ (public domain dedication — no attribution
required, free for personal and commercial use, modification, and redistribution).

Cross-referenced against the original creator's own listing of the same pack (Quaternius "Cars
Bundle"), which likewise states **"Public Domain (CC0)"** and credits Quaternius as the modeler:
https://poly.pizza/bundle/Cars-Bundle-FE5IWe6OMk

## Files

Selected 6 of the pack's vehicle meshes (GLB format, as shipped by Kenney — `Models/GLB format/`
in the zip) and renamed for use by the game:

| Committed file | Original filename | Description        |
|----------------|--------------------|--------------------|
| car0.glb       | sedan.glb          | Sedan               |
| car1.glb       | suv.glb            | SUV                 |
| car2.glb       | taxi.glb           | Taxi                |
| car3.glb       | police.glb         | Police car          |
| car4.glb       | hatchback-sports.glb | Sports hatchback  |
| car5.glb       | van.glb            | Van                 |

`Textures/colormap.png` is the single shared color-palette texture referenced (via external URI)
by all six GLB files' materials — copied alongside the models from the same pack directory
(`Models/GLB format/Textures/colormap.png`) so the models render textured rather than untextured.

## Validation

Loaded and instantiated in Godot 4.5 headless via `game/tests/models_test.gd`
(`tools/godot/godot_console.exe --headless --path game --script res://tests/models_test.gd`).
All 6 models loaded without error; reported world-space bounding-box sizes (meters, x=width,
y=height, z=length):

| File     | Size (x, y, z)         |
|----------|-------------------------|
| car0.glb | (1.5, 1.45, 2.55)        |
| car1.glb | (1.5, 1.4, 2.55)         |
| car2.glb | (1.5, 1.65, 2.75)        |
| car3.glb | (1.5, 1.4, 2.9)          |
| car4.glb | (1.3, 1.25, 2.85)        |
| car5.glb | (1.5, 1.45, 2.75)        |

## Not used

The pack also ships the same models in FBX and OBJ format; only the GLB format (which Godot's
glTF importer consumes natively, no conversion toolchain needed) was used, per task constraints.
