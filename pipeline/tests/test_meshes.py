import numpy as np
from pipeline.osm_parse import Building, Road, Area
from pipeline.meshes import building_mesh, road_mesh, area_mesh

SQ = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)]

def test_building_mesh_bounds():
    m = building_mesh(Building(1, SQ, 30.0))
    assert m is not None and m.is_volume
    lo, hi = m.bounds
    assert abs(lo[1] - 0.0) < 1e-6 and abs(hi[1] - 30.0) < 1e-6  # Y is up
    assert abs(hi[0] - 10.0) < 1e-6 and abs(hi[2] - 10.0) < 1e-6

def test_degenerate_building_returns_none():
    assert building_mesh(Building(2, [(0, 0), (1, 0), (2, 0), (3, 0)], 10.0)) is None

def test_road_mesh_is_flat_ribbon():
    m = road_mesh(Road(3, "x", [(0.0, 0.0), (100.0, 0.0)], 8.0))
    lo, hi = m.bounds
    assert abs(hi[1] - lo[1]) < 1e-6            # flat
    assert abs((hi[2] - lo[2]) - 8.0) < 1e-6    # width across z
    assert len(m.faces) == 2                     # one quad = 2 tris

def test_area_mesh_flat():
    m = area_mesh(Area(4, "water", SQ))
    lo, hi = m.bounds
    assert abs(hi[1] - lo[1]) < 1e-6

def test_malformed_inputs_return_none_never_raise():
    assert building_mesh(Building(10, [(0, 0), (1, 1)], 10.0)) is None
    assert building_mesh(Building(11, SQ, 0.0)) is None
    assert building_mesh(Building(12, SQ, -3.0)) is None
    assert road_mesh(Road(13, "x", [(0.0, 0.0)], 8.0)) is None
    assert road_mesh(Road(14, "x", [(0.0, 0.0), (100.0, 0.0)], 0.0)) is None
    assert area_mesh(Area(15, "water", [(0.0, 0.0), (1.0, 1.0)])) is None

def test_building_vertex_colors_by_type_with_jitter():
    a = building_mesh(Building(1, SQ, 30.0, "apartments"))
    b = building_mesh(Building(2, SQ, 30.0, "apartments"))
    office = building_mesh(Building(3, SQ, 30.0, "office"))
    assert a.visual.vertex_colors.shape == (len(a.vertices), 4)
    assert not np.array_equal(a.visual.vertex_colors[0], b.visual.vertex_colors[0])  # id jitter
    assert not np.array_equal(a.visual.vertex_colors[0], office.visual.vertex_colors[0])

def test_road_and_area_colors():
    from pipeline import config
    r = road_mesh(Road(4, "x", [(0.0, 0.0), (10.0, 0.0)], 8.0, "footway"))
    assert tuple(r.visual.vertex_colors[0][:3]) == config.ROAD_COLORS["footway"]
    w = area_mesh(Area(5, "water", SQ))
    assert tuple(w.visual.vertex_colors[0][:3]) == config.AREA_COLORS["water"]

def test_area_mesh_with_hole_has_fewer_area():
    from shapely.geometry import Polygon
    full = area_mesh(Area(6, "water", SQ))
    hole = [(4.0, 4.0), (6.0, 4.0), (6.0, 6.0), (4.0, 6.0)]
    holed = area_mesh(Area(7, "water", SQ, [hole]))
    assert holed is not None and holed.area < full.area
