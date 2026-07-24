# Character model source

CC0 rigged low-poly humanoid for the player character, used as the base for
M9c2 "Life & Flavor" animation + tuque-attachment work.

## Player character — Kenney "Mini Characters"

**Pack:** Mini Characters (1.0)
**Author:** Kenney (Kenney.nl)
**License:** CC0 1.0 Universal (Public Domain Dedication) — https://creativecommons.org/publicdomain/zero/1.0/
**Source URL:** https://kenney.nl/assets/mini-characters
(Note: the task brief's linked URL, https://kenney.nl/assets/mini-characters-1, 404s — Kenney
has since renamed the pack's page slug to drop the trailing "-1". Same pack: "Mini Characters
(1.0)", same 32-animations/wheelchair-accessibility description as the brief.)
**Direct download used:** https://kenney.nl/media/pages/assets/mini-characters/bfc7e272b4-1774770718/kenney_mini-characters.zip
**Download date:** 2026-07-23

### License evidence

The pack's own `License.txt` (bundled in the zip) states:
"Mini Characters (1.0) / Created/distributed by Kenney (www.kenney.nl) / License: (Creative
Commons Zero, CC0) http://creativecommons.org/publicdomain/zero/1.0/ — You can use this content
for personal, educational, and commercial purposes." The kenney.nl asset page independently
states "Creative Commons CC0" as the license.

### Files

The pack ships 24 character/accessory GLB files (6 female + 6 male body variants, plus mobility
aids and wheelchairs) under `Models/GLB format/`. One male character was selected:

| Committed file | Original filename        | Description                          |
|-----------------|---------------------------|----------------------------------------|
| character.glb   | character-male-a.glb      | Blocky low-poly rigged male character |

### External texture dependency

`character.glb`'s material references its texture via **external relative URI**
`Textures/colormap.png` (same recurring hazard as the props pack — confirmed by inspecting the
glTF JSON `images` array: `{"uri": "Textures/colormap.png", "name": "colormap"}`). The file has
been copied alongside the model, preserving the relative path:

```
game/assets/models/character/Textures/colormap.png
```

sourced from the same pack directory (`Models/GLB format/Textures/colormap.png`). This texture
is shared across the whole Mini Characters pack — if more characters/accessories from this pack
are added later, they likely reuse the same `colormap.png`.

### Rig, animations, and node structure (from `character_model_test.gd`)

`character.glb` instantiates as a `Node3D` scene containing an `AnimationPlayer` and a
`Skeleton3D` with 7 bones. Verified live via
`tools/godot/godot_console.exe --headless --path game --script res://tests/character_model_test.gd`
(after `--import`):

```
CHARACTER OK: anim=true clips=["attack-kick-left", "attack-kick-right", "attack-melee-left", "attack-melee-right", "crouch", "die", "drive", "emote-no", "emote-yes", "fall", "holding-both", "holding-both-shoot", "holding-left", "holding-left-shoot", "holding-right", "holding-right-shoot", "idle", "interact-left", "interact-right", "jump", "pick-up", "sit", "sprint", "static", "walk", "wheelchair-look-left", "wheelchair-look-right", "wheelchair-move-back", "wheelchair-move-forward", "wheelchair-move-left", "wheelchair-move-right", "wheelchair-sit"] bones=7
BONES: ["root", "leg-left", "leg-right", "torso", "arm-left", "arm-right", "head"]
```

31 animation clips total, including **`idle`** and **`walk`** (and `sprint`, `jump`, `crouch`,
`sit`, emotes, combat, wheelchair-accessibility clips, etc.) — Task 2 can wire idle/walk
directly, no static-only fallback needed. The skeleton has a simple 7-bone rig
(`root` → `leg-left`/`leg-right`/`torso` → `torso` → `arm-left`/`arm-right`/`head`); the
**`head`** bone is the attachment point for the tuque prop in a later task.

### Native dimensions (world-space bounding box, meters, from `character_model_test.gd`)

| File          | Size (x, y, z)                    |
|----------------|-------------------------------------|
| character.glb | (0.767168, 0.671325, 0.34)         |

This bounding box is computed over the rest-pose (bind-pose) skinned mesh geometry, not a
standing "idle" animation frame — Kenney's mini-character rest pose is a semi-crouched/seated-ish
default pose (some kit characters use a chibi/idle-crouch rest pose rather than a T-pose), so the
0.67 m height figure should not be read as "standing height"; it reflects the raw bind pose only.
Kit scale generally — real human height is ~1.7 m; Task 2's animation/scaling work is expected to
handle final in-world scale.

## Validation

Loaded and instantiated in Godot 4.5 headless via `game/tests/character_model_test.gd`
(`tools/godot/godot_console.exe --headless --path game --script res://tests/character_model_test.gd`,
after `tools/godot/godot_console.exe --headless --path game --import`). Loaded without error, with
a non-null `AnimationPlayer` (31 clips, including `idle`/`walk`) and a `Skeleton3D` (7 bones,
including `head`); see native dimensions table above for the reported world-space bounding-box
size.
