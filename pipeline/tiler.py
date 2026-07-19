from __future__ import annotations
import math
from collections import defaultdict
import trimesh
from shapely.geometry import Polygon, box as shp_box
from pipeline import config
from pipeline.osm_parse import CityData
from pipeline.meshes import building_mesh, road_mesh, area_piece_mesh

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
        if len(a.outline) < 3:
            continue
        poly = Polygon(a.outline, a.holes)
        if not poly.is_valid:
            poly = poly.buffer(0)
        if poly.is_empty:
            continue
        minx, minz, maxx, maxz = poly.bounds
        tx0, tz0 = assign_tile(minx, minz)
        tx1, tz1 = assign_tile(maxx, maxz)
        for tx in range(tx0, tx1 + 1):
            for tz in range(tz0, tz1 + 1):
                cell = shp_box(tx * config.TILE_SIZE, tz * config.TILE_SIZE,
                               (tx + 1) * config.TILE_SIZE, (tz + 1) * config.TILE_SIZE)
                m = area_piece_mesh(poly.intersection(cell), a.kind)
                if m is not None:
                    buckets[(tx, tz)]["areas"].append(m)
    tiles: dict[tuple[int, int], trimesh.Scene] = {}
    for key in sorted(buckets):
        scene = trimesh.Scene()
        total_tris = 0
        for cat in ("buildings", "roads", "areas"):
            if buckets[key][cat]:
                merged = trimesh.util.concatenate(buckets[key][cat])
                total_tris += len(merged.faces)
                scene.add_geometry(merged, geom_name=cat, node_name=cat)
        if total_tris > config.MAX_TILE_TRIS:
            raise ValueError(f"tile {key}: {total_tris} tris over budget")
        tiles[key] = scene
    return tiles
