# MTL: Open Île

Open-world free-roam game set in downtown Montréal. Godot 4.5 + Python map pipeline.

- `pipeline/` — Python: OSM data → glTF city tiles (`game/world/`)
- `game/` — Godot 4.5 project

## Setup
1. `py -m venv .venv && .venv/Scripts/pip install -r requirements.txt`
2. Godot 4.5-stable portable → `tools/godot/` (see docs/superpowers/plans)
3. Generate city: `.venv/Scripts/python -m pipeline.build`
4. Open `game/` in Godot, run `scenes/main.tscn`

Map data © OpenStreetMap contributors (ODbL).
