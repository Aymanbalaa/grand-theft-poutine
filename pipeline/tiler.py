from __future__ import annotations
import math
from collections import defaultdict
import trimesh
from pipeline import config
from pipeline.osm_parse import CityData
from pipeline.meshes import building_mesh, road_mesh, area_mesh

def assign_tile(x: float, z: float) -> tuple[int, int]:
    return (math.floor(x / config.TILE_SIZE), math.floor(z / config.TILE_SIZE))

def build_tiles(city: CityData) -> dict[tuple[int, int], trimesh.Scene]:
    buckets: dict[tuple[int, int], dict[str, list]] = defaultdict(lambda: defaultdict(list))
    for b in city.buildings:
        m = building_mesh(b)
        if m is not None:
            buckets[assign_tile(*b.footprint[0])]["buildings"].append(m)
    for r in city.roads:
        m = road_mesh(r)
        if m is not None:
            buckets[assign_tile(*r.points[0])]["roads"].append(m)
    for a in city.areas:
        m = area_mesh(a)
        if m is not None:
            buckets[assign_tile(*a.outline[0])]["areas"].append(m)
    tiles: dict[tuple[int, int], trimesh.Scene] = {}
    for key in sorted(buckets):
        scene = trimesh.Scene()
        total_tris = 0
        for cat in ("buildings", "roads", "areas"):
            if buckets[key][cat]:
                merged = trimesh.util.concatenate(buckets[key][cat])
                total_tris += len(merged.faces)
                scene.add_geometry(merged, geom_name=cat, node_name=cat)
        assert total_tris <= config.MAX_TILE_TRIS, f"tile {key}: {total_tris} tris over budget"
        tiles[key] = scene
    return tiles
