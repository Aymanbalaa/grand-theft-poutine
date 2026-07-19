import json
from pathlib import Path
import pytest
from pipeline import config
from pipeline.osm_parse import parse_osm, Area
from pipeline.tiler import assign_tile, build_tiles
from pipeline.export import export_city

FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"

def test_assign_tile():
    assert assign_tile(0.0, 0.0) == (0, 0)
    assert assign_tile(-0.1, 300.0) == (-1, 1)

def test_build_tiles_has_categories():
    city = parse_osm(FIX)
    tiles = build_tiles(city)
    assert len(tiles) >= 1
    names = {n for scene in tiles.values() for n in scene.geometry}
    assert "buildings" in names and "roads" in names and "water" in names

def test_export_writes_glb_and_metadata(tmp_path):
    city = parse_osm(FIX)
    meta = export_city(city, tmp_path)
    files = sorted(p.name for p in tmp_path.glob("*.glb"))
    assert files == sorted(t["file"] for t in meta["tiles"])
    assert (tmp_path / "city_metadata.json").exists()
    assert "Rue Sainte-Catherine" in meta["streets"]["names"]
    assert meta["streets"]["cell"] == 64.0
    assert len(meta["districts"]) == 7
    assert len(meta["car_spawns"]) >= 1
    assert set(meta["car_spawns"][0]) == {"x", "y", "z", "yaw"}

def test_export_deterministic(tmp_path):
    city = parse_osm(FIX)
    export_city(city, tmp_path / "a")
    export_city(city, tmp_path / "b")
    ja = (tmp_path / "a" / "city_metadata.json").read_bytes()
    jb = (tmp_path / "b" / "city_metadata.json").read_bytes()
    assert ja == jb

def test_big_area_clipped_across_tiles():
    big = Area(1, "water", [(-10.0, -10.0), (500.0, -10.0), (500.0, 500.0), (-10.0, 500.0)])
    from pipeline.osm_parse import CityData
    tiles = build_tiles(CityData(areas=[big]))
    assert len(tiles) >= 4  # spans tiles (-1..1, -1..1)
    for scene in tiles.values():
        assert "water" in scene.geometry

def test_tile_budget_raises(monkeypatch):
    monkeypatch.setattr(config, "MAX_TILE_TRIS", 1)
    city = parse_osm(FIX)
    with pytest.raises(ValueError, match="over budget"):
        build_tiles(city)

def test_build_tiles_with_heightmap_has_terrain_everywhere():
    import numpy as np
    from pipeline.terrain import Heightmap
    hm = Heightmap(grid=np.zeros((4, 4), dtype=np.float32),
                   x0=-3000.0, z0=-3000.0, step_x=2000.0, step_z=2000.0)
    city = parse_osm(FIX)
    tiles = build_tiles(city, hm=hm)
    assert len(tiles) >= 200  # full bbox range gets terrain tiles
    assert all("terrain" in scene.geometry for scene in tiles.values())

def test_props_geometry_in_tiles():
    city = parse_osm(FIX)
    tiles = build_tiles(city)
    names = {n for scene in tiles.values() for n in scene.geometry}
    assert "props" in names

def test_export_preserves_props(tmp_path):
    # regression: _without_landmark_buildings rebuilt CityData and silently
    # dropped trees/lamps, so exported tiles lost all props
    import trimesh
    city = parse_osm(FIX)
    meta = export_city(city, tmp_path)
    names = set()
    for t in meta["tiles"]:
        names |= set(trimesh.load(tmp_path / t["file"]).geometry.keys())
    assert "props" in names

def test_tree_cap_deterministic(monkeypatch):
    from pipeline import config
    monkeypatch.setattr(config, "MAX_TREES_PER_TILE", 1)
    city = parse_osm(FIX)
    t1 = build_tiles(city)
    t2 = build_tiles(city)
    for k in t1:
        if "props" in t1[k].geometry:
            a = t1[k].geometry["props"].vertices
            b = t2[k].geometry["props"].vertices
            assert (a == b).all()
