from __future__ import annotations
import json
from pathlib import Path
from pipeline import config
from pipeline.osm_parse import CityData
from pipeline.tiler import build_tiles

def export_city(city: CityData, out_dir: str | Path) -> dict:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    tiles = build_tiles(city)
    tile_entries = []
    for (tx, tz), scene in sorted(tiles.items()):
        fname = f"tile_{tx}_{tz}.glb"
        scene.export(out / fname)
        tile_entries.append({"tx": tx, "tz": tz, "file": fname})
    streets = sorted(
        (
            {"name": r.name, "points": [[round(x, 2), round(z, 2)] for x, z in r.points]}
            for r in city.roads if r.name
        ),
        key=lambda s: (s["name"], s["points"][0]),
    )
    meta = {
        "origin": {"lat": config.ORIGIN[0], "lon": config.ORIGIN[1]},
        "tile_size": config.TILE_SIZE,
        "tiles": tile_entries,
        "spawn": {"x": 0.0, "z": 0.0},
        "streets": streets,
    }
    (out / "city_metadata.json").write_text(
        json.dumps(meta, sort_keys=True, indent=1), encoding="utf-8"
    )
    return meta
