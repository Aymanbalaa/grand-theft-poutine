# Session Handoff — read me first in a fresh context

**Project:** MTL: Open Île — GTA-like free-roam downtown Montreal. Spec: `docs/superpowers/specs/2026-07-18-montreal-open-world-design.md` (milestone order updated 2026-07-19: visuals now come BEFORE character).

**State (2026-07-19, tag `m2-gray-city`):** Milestones 1–2 complete. Flyable gray city over real downtown OSM data: 255 glTF tiles in `game/world/` (255 load in smoke test), 18 pytest green. Plan 1 executed via superpowers:subagent-driven-development; per-task ledger at `.superpowers/sdd/progress.md` (gitignored), all reviews clean.

**Next up — Plan 2 "Make it Montreal" (visual pass), to be written with superpowers:writing-plans:**
- Stylized palette: color buildings by type/district, roads by class, water blue, parks green (pipeline currently exports colorless meshes → renders white; carry OSM tags into materials in `pipeline/meshes.py`/`tiler.py`, vertex colors or per-category materials in the GLB)
- St. Lawrence river needs Overpass multipolygon RELATION support (only way-based water is fetched today — the river body is missing)
- Hero landmarks at true coords: Notre-Dame, Place Ville Marie, Biosphere, Habitat 67, Farine Five Roses (Sketchfab CC0/CC-BY, verify license per model)
- Mont Royal terrain from HRDEM heightmap (currently flat y=0)
- Day/night cycle, minimap (road-graph render)

**Carry-forward review findings (fix when touching the relevant code):**
- `pipeline/download.py`: sanity-check 200 responses start with `<?xml` before caching; don't sleep after final failed attempt
- `pipeline/tiler.py`: MAX_TILE_TRIS `assert` → `raise` (assert dies under `python -O`); no test that it fires
- `pipeline/osm_parse.py`: ring-closure checks raw refs but drops unresolved nodes silently — guard when reworking for multipolygons
- Metadata `streets` = 7,352 per-way fragments (not deduped by name), 2.1 MB JSON — dedupe/split before the street-name HUD (now M4); `spawn` field is produced but unconsumed (consume in M4 or drop)
- Fly cam Esc mouse-release never manually tested; tile visibility toggling has no automated test

**Hard constraints (user-mandated):**
- Commits authored ONLY by Aymanbalaa via repo-local git config (noreply email) — NO Co-Authored-By/AI trailers ever. History was rewritten once to scrub a gmail leak; don't reintroduce.
- Commit small and frequent. User has cheaper-model subagents in mind for mechanical work — orchestrate, review everything.

**Environment gotchas:**
- `tools/godot/godot.exe` (gitignored) is the MAIN Godot 4.5 binary (console wrapper refuses renaming). Headless: `tools/godot/godot.exe --headless --path game --script res://tests/smoke_test.gd` → expect "SMOKE OK: 255 tiles". After regenerating world tiles run `--headless --path game --import` first (minutes).
- Screenshots: `tools/godot/godot.exe --path game --script res://tests/screenshot.gd` (windowed, needs GPU) → PNGs in `%APPDATA%/Godot/app_userdata/MTL Open Ile/`. ALWAYS look at them (Read tool) before claiming visual success.
- Python: `.venv/Scripts/python -m pytest pipeline -q`; full rebuild `.venv/Scripts/python -m pipeline.build` (Overpass download cached at `data/osm_downtown.osm.xml`, mirror rotation built in).
- Overpass instances are flaky; the download is cached — don't re-trigger needlessly.
