# Session Handoff — read me first in a fresh context

**Project:** MTL: Open Île — GTA-like free-roam downtown Montreal. Spec: `docs/superpowers/specs/2026-07-18-montreal-open-world-design.md`.

**State (2026-07-19, tag `m3.5-wow`):** Milestones 1–3.5 complete. M3.5 WOW pass added: emissive window shader (world-space grid, `night_amount` shader global set by day_night.gd via RenderingServer), ProceduralSky + SSAO + glow + ACES, 16,498 street trees + 499 lamps from OSM nodes as per-tile "props" geometry (300 trees/tile cap), animated water shader, roof caps + residential gables, water/green split into named tile geometries, materials routed by geometry name in tile_loader. Screenshots `docs/screenshots/m35_*.png` (7 poses incl. dusk + night; all reviewed visually over 4 tuning iterations — key fixes: shaders must linearize sRGB vertex COLOR with pow(2.2); emission gated by smoothstep(0.45,0.9,night_amount) so day facades stay matte; glancing-angle emission fade). CROSS-TASK SEAM BUG caught at final review: export.py's landmark-exclusion CityData rebuild silently dropped the new trees/lamps fields — fixed with export-level regression test (test_export_preserves_props). Remote: github.com/Aymanbalaa/grand-theft-poutine (public). Earlier state below still applies.

**Prior state (tag `m3-montreal`):** Milestones 1–3 complete. The city is now recognizably Montreal: stylized palette baked as vertex colors (brick residential, glass commercial, greystone churches), St. Lawrence river + relation-based parks via multipolygon support, Mont Royal terrain from a REAL HRDEM heightmap (NRCan STAC fetch worked; synthetic fallback exists), five procedural hero landmarks (coords OSM-verified except Five Roses — no OSM name match, brief default kept) (PVM, Notre-Dame, Biosphère, Habitat 67, Five Roses), day/night cycle (T fast-forwards), minimap HUD with camera marker. 314 tiles, 45 pytest green, smoke prints `SMOKE OK: 314 tiles`. Milestone screenshots at `docs/screenshots/m3_*.png` (reviewed visually). Plan 2 executed via superpowers:subagent-driven-development; ledger at `.superpowers/sdd/progress.md` (gitignored).

**Next up — Plan 3 "On foot" (M4), to be written with superpowers:writing-plans:**
- Third-person CharacterBody3D controller (walk/sprint/jump), collision-aware follow camera (Quaternius/Mixamo character)
- Collisions for buildings/terrain (tiles currently have no collision shapes — generate trimesh collision in pipeline or Godot import settings). NOTE: building meshes are NOT watertight since M3.5 (roof cap slabs are open) — convex decomposition/`is_volume`-dependent approaches will need the wall solids, not the concatenated mesh
- Street-name + district HUD (point-in-polygon vs metadata) — FIRST dedupe `streets` metadata (7,357 per-way fragments, ~2 MB; dedupe by name / split per district) and consume or drop the unused `spawn` field
- Spawn on foot downtown instead of fly cam (keep fly cam as debug toggle)

**Carry-forward review findings (fix when touching the relevant code):**
- Fly cam Esc mouse-release never manually tested; tile visibility toggling has no automated test
- minimap.gd: metadata sub-key indexing unguarded, silent failure paths (plan-mandated simplicity)
- terrain_tile_mesh: 33×33 Python loop per tile unvectorized (offline-only cost); water/green terrain coloring path untested
- geo constants duplicated in terrain.py (`110574.0`/`111320.0` vs geo.py canonical)
- Final whole-branch review for Plan 2: see ledger FINAL entry for any accepted-risk items
- minimap roads use a single light color for legibility (deviation from plan's per-class colors, chosen at screenshot review)

**Hard constraints (user-mandated):**
- Commits authored ONLY by Aymanbalaa via repo-local git config (noreply email) — NO Co-Authored-By/AI trailers ever. History was rewritten once to scrub a gmail leak; don't reintroduce. KNOWN RISK: one subagent passed `--author` with the gmail address (caught + amended before it left the machine) — every subagent dispatch must explicitly forbid `--author` and git-config changes.
- Commit small and frequent. Cheaper-model subagents for mechanical work — orchestrate, review everything.

**Environment gotchas:**
- `tools/godot/godot.exe` is the MAIN Godot 4.5 binary; `tools/godot/godot_console.exe` is the console wrapper — USE THE CONSOLE WRAPPER from PowerShell, the GUI exe detaches and returns no output. Headless smoke: `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd` → expect "SMOKE OK: 314 tiles". After regenerating world tiles run `--headless --path game --import` first (minutes).
- Screenshots: `tools/godot/godot_console.exe --path game --script res://tests/screenshot.gd` (windowed, needs GPU) → PNGs in `%APPDATA%/Godot/app_userdata/MTL Open Ile/`. ALWAYS look at them (Read tool) before claiming visual success. 5 poses: overview/street/oldport/mountain/biosphere.
- Python: `.venv/Scripts/python -m pytest pipeline -q`; full rebuild `.venv/Scripts/python -m pipeline.build` (OSM + heightmap both cached in `data/`; delete caches ONLY if the query/source changes).
- Overpass mirrors flaky (rotation built in); HRDEM via NRCan STAC can fail → synthetic fallback auto-engages (check console line "heightmap saved (hrdem|synthetic)").
- Heightmap cache pinned: heightmap.npy sha256=76cabf2012331723…, heightmap_meta.json sha256=6ef96faad06ce025… — if data/ is ever lost, a fresh HRDEM fetch may differ; diff new hashes before rebuilding the committed world.
