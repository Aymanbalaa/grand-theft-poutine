from __future__ import annotations
import math
from collections import defaultdict
import trimesh
from shapely.geometry import Polygon, box as shp_box
from shapely.ops import unary_union
from shapely.prepared import prep
from pipeline import config
from pipeline.geo import latlon_to_xz
from pipeline.osm_parse import CityData
from pipeline.meshes import building_mesh, road_mesh, sidewalk_mesh, roadmark_mesh, area_piece_mesh, terrain_tile_mesh, traffic_light_mesh, awning_mesh

def assign_tile(x: float, z: float) -> tuple[int, int]:
    return (math.floor(x / config.TILE_SIZE), math.floor(z / config.TILE_SIZE))

def _bbox_tile_range() -> list[tuple[int, int]]:
    s, w, n, e = config.BBOX
    x0, z0 = latlon_to_xz(n, w)
    x1, z1 = latlon_to_xz(s, e)
    tx0, tz0 = assign_tile(x0, z0)
    tx1, tz1 = assign_tile(x1 - 1e-6, z1 - 1e-6)
    return [(tx, tz) for tx in range(tx0, tx1 + 1) for tz in range(tz0, tz1 + 1)]

def _area_union(city: CityData, kind: str):
    polys = []
    for a in city.areas:
        if a.kind != kind or len(a.outline) < 3:
            continue
        p = Polygon(a.outline, a.holes)
        polys.append(p if p.is_valid else p.buffer(0))
    return prep(unary_union(polys)) if polys else None

def build_tiles(city: CityData, hm=None) -> dict[tuple[int, int], trimesh.Scene]:
    buckets: dict[tuple[int, int], dict[str, list]] = defaultdict(lambda: defaultdict(list))
    for b in city.buildings:
        m = building_mesh(b, hm)
        if m is not None:
            buckets[assign_tile(*b.footprint[0])]["buildings"].append(m)
        a = awning_mesh(b, hm)
        if a is not None:
            buckets[assign_tile(*b.footprint[0])]["awnings"].append(a)
    for r in city.roads:
        m = road_mesh(r, hm)
        if m is not None:
            cat = "paths" if r.road_class in config.PATH_CLASSES else "roads"
            buckets[assign_tile(*r.points[0])][cat].append(m)
    counts: dict[tuple[float, float], int] = defaultdict(int)
    for r in city.roads:
        if r.road_class in config.SIDEWALK_CLASSES or r.road_class in config.ROADMARK_CLASSES:
            for x, z in r.points:
                counts[(round(x, 2), round(z, 2))] += 1
    junctions = frozenset(k for k, v in counts.items() if v >= 2)
    for r in city.roads:
        m = sidewalk_mesh(r, hm, junctions=junctions)
        if m is not None:
            buckets[assign_tile(*r.points[0])]["sidewalks"].append(m)
    for r in city.roads:
        m = roadmark_mesh(r, hm, junctions=junctions)
        if m is not None:
            buckets[assign_tile(*r.points[0])]["roadmarks"].append(m)
    for a in city.areas:
        if len(a.outline) < 3:
            continue
        if hm is not None and a.kind == "green":
            continue  # terrain vertices are painted green instead
        poly = Polygon(a.outline, a.holes)
        if not poly.is_valid:
            poly = poly.buffer(0)
        if poly.is_empty:
            continue
        flat_y = None
        if hm is not None and a.kind == "water":
            flat_y = min(hm.sample(x, z) for x, z in a.outline) + 0.02
        minx, minz, maxx, maxz = poly.bounds
        tx0, tz0 = assign_tile(minx, minz)
        tx1, tz1 = assign_tile(maxx, maxz)
        for tx in range(tx0, tx1 + 1):
            for tz in range(tz0, tz1 + 1):
                cell = shp_box(tx * config.TILE_SIZE, tz * config.TILE_SIZE,
                               (tx + 1) * config.TILE_SIZE, (tz + 1) * config.TILE_SIZE)
                m = area_piece_mesh(poly.intersection(cell), a.kind, flat_y=flat_y)
                if m is not None:
                    buckets[(tx, tz)][a.kind].append(m)

    for x, z in city.signals:
        y = hm.sample(x, z) if hm is not None else 0.0
        buckets[assign_tile(x, z)]["props"].append(traffic_light_mesh(x, z, y))

    water_geom = green_geom = None
    keys = set(buckets)
    if hm is not None:
        water_geom = _area_union(city, "water")
        green_geom = _area_union(city, "green")
        keys |= set(_bbox_tile_range())

    tiles: dict[tuple[int, int], trimesh.Scene] = {}
    for key in sorted(keys):
        scene = trimesh.Scene()
        total_tris = 0
        for cat in ("buildings", "roads", "paths", "sidewalks", "roadmarks", "water", "green", "props", "awnings"):
            if buckets[key][cat]:
                merged = trimesh.util.concatenate(buckets[key][cat])
                total_tris += len(merged.faces)
                scene.add_geometry(merged, geom_name=cat, node_name=cat)
        if hm is not None:
            t = terrain_tile_mesh(key[0], key[1], hm, water_geom, green_geom)
            total_tris += len(t.faces)
            scene.add_geometry(t, geom_name="terrain", node_name="terrain")
        if total_tris > config.MAX_TILE_TRIS:
            raise ValueError(f"tile {key}: {total_tris} tris over budget")
        tiles[key] = scene
    return tiles
