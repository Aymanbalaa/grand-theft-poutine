from __future__ import annotations
import json
import math
from pathlib import Path
from pipeline import config
from pipeline.geo import latlon_to_xz
from pipeline.landmarks import export_landmarks
from pipeline.osm_parse import CityData
from pipeline.tiler import build_tiles

def _drop_landmark_buildings(city: CityData) -> None:
    anchors = [(latlon_to_xz(lm["lat"], lm["lon"]), lm["clear"]) for lm in config.LANDMARKS]
    def keep(b) -> bool:
        cx = sum(p[0] for p in b.footprint) / len(b.footprint)
        cz = sum(p[1] for p in b.footprint) / len(b.footprint)
        return all(math.hypot(cx - ax, cz - az) > r for (ax, az), r in anchors)
    city.buildings = [b for b in city.buildings if keep(b)]

def export_city(city: CityData, out_dir: str | Path, hm=None) -> dict:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    _drop_landmark_buildings(city)
    tiles = build_tiles(city, hm=hm)
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
    landmark_entries = export_landmarks(out, hm)
    meta = {
        "origin": {"lat": config.ORIGIN[0], "lon": config.ORIGIN[1]},
        "tile_size": config.TILE_SIZE,
        "tiles": tile_entries,
        "spawn": {"x": 0.0, "z": 0.0},
        "streets": streets,
        "landmarks": landmark_entries,
    }
    (out / "city_metadata.json").write_text(
        json.dumps(meta, sort_keys=True, indent=1), encoding="utf-8"
    )
    return meta
