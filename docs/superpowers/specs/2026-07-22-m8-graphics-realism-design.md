# M8 — Realism Graphics Pass (Design)

**Date:** 2026-07-22
**Status:** Approved direction (realism-leaning PBR), phased like M6.
**Baseline:** tag `m7-polish`, 314 tiles, smoke 16 gates, pytest 86. Reference screenshots `docs/screenshots/m7_*.png`.

## Goal

Move the game's look from "flat-shaded data visualization" toward a realism-leaning
PBR presentation — not AAA, but a credible small-studio 3D city. Priority is
**street level** (on foot / driving), with the cheap high-impact vista wins (sky,
water, fog) riding along. Night already reads well; **day is the problem**: flat
white boxes, sticker windows, lollipop trees, flat green terrain with plank-stripe
path artifacts, flat blue water, empty gradient sky, and an untextured white car
in the m7 driving shot.

## Asset strategy

1. **CC0 libraries are the backbone** — Poly Haven and ambientCG for PBR texture
   sets, Kenney/Quaternius for props, trees, and vehicles. The pipeline's
   `ensure_textures` + lock pattern and CREDITS.md attribution pattern already
   support this.
2. **Procedural variation stretches them** — per-building seeds, shader-side
   tone/pattern variation, road-wear overlays. Deterministic, license-free.
3. **AI generation only for Montreal-specific flavor** — storefront sign strips,
   murals/graffiti decals. Never for tiling PBR textures (seams, no normal maps).

## Phases

### 8a — Light & Atmosphere (direction gate)

No geometry/pipeline changes. The biggest realism lever first, and it doubles as
the user's pass/fail gate on the whole direction.

- **Sky:** replace the plain ProceduralSky gradient with Godot physical sky plus
  a cloud layer. Must keep the moving-sun day/night cycle working (which rules
  out a baked HDRI panorama as the primary sky — its sun cannot move). Night
  keeps the current dark/starry feel; `night_amount` contract with the emissive
  window shader and LightPool is preserved.
- **Water:** real water shader — fresnel reflection, normal-mapped scrolling
  waves, shore fade, sun specular glint. Replaces the flat blue sheet.
- **Terrain:** PBR ground material, grass + dirt/rock blended by slope (triplanar,
  no tangent dependency — M6a lesson: no normal maps on tangent-less meshes).
  Replaces flat green vertex color and kills the plank-stripe artifact on
  Mont Royal paths.
- **Grade:** exposure, fog (aerial perspective so distance reads as depth), SSAO
  retune for the new sky light. SDFGI stays dropped (M6b decision — do not
  revisit without a static-sun mode).
- **Gate:** full screenshot pose set, m7 vs 8a side-by-side. User approves the
  direction before 8b starts.

### 8b — Streets & Facades

Street-level realism. Requires a **pipeline rebuild** (new vertex data), so the
orphan-tile check from the M7 handoff applies.

- **Facade shader v3:** per-building variation seeded in vertex data (hash →
  tone/hue shift, window pattern variation) so ~6 texture sets read as hundreds
  of distinct buildings. Window glass picks up sky reflection. Higher-res brick
  and greystone sets sourced from ambientCG/Poly Haven. Category and base-height
  encodings from M6a/M7 (vertex alpha packing) must survive whatever channel the
  seed uses.
- **Roads:** better asphalt with lane-wear overlay, proper crosswalk/paving
  texture replacing the plank-stripe set, crack/manhole decals, curb material
  distinct from sidewalk.

### 8c — Assets & Flavor

- **Trees:** real low-poly CC0 tree models (Quaternius/Kenney) via MultiMesh,
  replacing the ~16.5k procedural lollipops. Big win at every camera distance.
- **Cars:** diagnose and fix the white untextured car visible in
  `m7_driving_day.png` (suspect: the Kenney `Textures/colormap.png` external
  relative-URI dependency); add clearcoat paint materials.
- **Street props:** lamp posts (at the existing 499 `lamps` metadata positions),
  hydrants, bus stops, benches from CC0 kits where OSM/metadata gives positions.
- **Montreal flavor:** AI-generated storefront sign strips and mural/graffiti
  decals applied to blank commercial walls.

## Constraints (hold throughout)

- **No performance regression:** everything instanced (MultiMesh), tile
  streaming and the 280 m collision ring untouched, 120-car behavior unchanged.
- **License-clean:** CC0/attribution-tracked only; CREDITS.md updated per phase;
  SOURCE.md pattern for committed third-party assets.
- **Deterministic pipeline:** no network in `pipeline.build`; texture fetches go
  through `ensure_textures` + lock.
- **Repo rules:** commits authored only by Aymanbalaa (repo-local config), no
  AI trailers, no `--author` overrides in subagent dispatches; small frequent
  commits.
- **Evidence:** screenshots Read and judged before any phase is called done;
  smoke (16 gates) and pytest stay green; headless `--import` after any tile
  regeneration.

## Success criteria

- Side-by-side m7 vs m8 screenshots show an obvious generational jump, judged
  per pose (street day, driving day, dusk, night, overview, mountain, old port).
- The day street-level shots read as an intentional realistic-leaning game, not
  colored boxes: varied facades, believable road surface, real trees, textured
  cars.
- Night keeps or improves its current quality (it is the current money shot —
  regression here fails the phase).
- User signs off at the 8a gate and at final review.

## Out of scope

- Gameplay/missions, pedestrians/traffic AI (candidate M9).
- SDFGI or other GI (blocked on static-sun mode).
- Photorealism, custom building geometry beyond OSM extrusions, LOD system.
