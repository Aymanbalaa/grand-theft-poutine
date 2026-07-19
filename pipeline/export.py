from __future__ import annotations
import dataclasses
import json
import math
from pathlib import Path
from pipeline import config
from pipeline.geo import latlon_to_xz
from pipeline.landmarks import export_landmarks
from pipeline.minimap import render_minimap
from pipeline.osm_parse import CityData
from pipeline.streets import build_street_grid, district_polys
from pipeline.tiler import build_tiles

def _without_landmark_buildings(city: CityData) -> CityData:
    anchors = [(latlon_to_xz(lm["lat"], lm["lon"]), lm["clear"]) for lm in config.LANDMARKS]
    def keep(b) -> bool:
        cx = sum(p[0] for p in b.footprint) / len(b.footprint)
        cz = sum(p[1] for p in b.footprint) / len(b.footprint)
        return all(math.hypot(cx - ax, cz - az) > r for (ax, az), r in anchors)
    # replace() keeps every other field, so future CityData fields can't be dropped
    return dataclasses.replace(city, buildings=[b for b in city.buildings if keep(b)])

def export_city(city: CityData, out_dir: str | Path, hm=None) -> dict:
    city = _without_landmark_buildings(city)
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    tiles = build_tiles(city, hm=hm)
    tile_entries = []
    for (tx, tz), scene in sorted(tiles.items()):
        fname = f"tile_{tx}_{tz}.glb"
        scene.export(out / fname)
        tile_entries.append({"tx": tx, "tz": tz, "file": fname})
    landmark_entries = export_landmarks(out, hm)
    meta = {
        "minimap": render_minimap(city, out / "minimap.png"),
        "origin": {"lat": config.ORIGIN[0], "lon": config.ORIGIN[1]},
        "tile_size": config.TILE_SIZE,
        "tiles": tile_entries,
        "spawn": {"x": 0.0, "z": 0.0},
        "streets": build_street_grid(city.roads),
        "districts": district_polys(),
        "landmarks": landmark_entries,
    }
    (out / "city_metadata.json").write_text(
        json.dumps(meta, sort_keys=True, indent=1), encoding="utf-8"
    )
    return meta
