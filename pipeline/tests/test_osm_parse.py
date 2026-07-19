from pathlib import Path
from pipeline.osm_parse import parse_osm, _building_height
from pipeline.osm_parse import _assemble_rings

FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"
RIVER = Path(__file__).parent / "fixtures" / "river.osm.xml"

def test_counts():
    city = parse_osm(FIX)
    assert len(city.roads) == 2
    assert len(city.buildings) == 2
    assert len(city.areas) == 1

def test_road_names_and_width():
    city = parse_osm(FIX)
    ste_cath = next(r for r in city.roads if r.name == "Rue Sainte-Catherine")
    assert ste_cath.width == 10.0  # primary
    assert len(ste_cath.points) == 2

def test_building_heights():
    city = parse_osm(FIX)
    hs = sorted(b.height for b in city.buildings)
    assert hs == [16.0, 44.0]  # 5 levels * 3.2, explicit 44

def test_footprint_is_closed_ring_dropped_dup():
    city = parse_osm(FIX)
    for b in city.buildings:
        assert len(b.footprint) == 4  # closing duplicate removed

def test_sorted_by_id():
    city = parse_osm(FIX)
    assert [r.osm_id for r in city.roads] == sorted(r.osm_id for r in city.roads)

def test_zero_or_junk_height_falls_through():
    assert _building_height({"height": "0"}) == 10.0
    assert _building_height({"height": "0", "building:levels": "3"}) == 3 * 3.2
    assert _building_height({"height": "abc"}) == 10.0
    assert _building_height({"height": "-5"}) == 10.0
    assert _building_height({"height": "-5", "building:levels": "3"}) == 3 * 3.2

def test_road_class_and_btype_carried():
    city = parse_osm(FIX)
    ste_cath = next(r for r in city.roads if r.name == "Rue Sainte-Catherine")
    assert ste_cath.road_class == "primary"
    assert sorted(b.btype for b in city.buildings) == ["apartments", "yes"]

def test_assemble_rings_stitches_and_reverses():
    rings = _assemble_rings([[1, 2, 3], [1, 4, 3]])   # second must be reversed to close
    assert len(rings) == 1 and sorted(rings[0]) == [1, 2, 3, 4]

def test_assemble_rings_drops_unclosed():
    assert _assemble_rings([[1, 2, 3], [5, 6]]) == []

def test_multipolygon_water_with_hole():
    city = parse_osm(RIVER)
    lake = next(a for a in city.areas if a.holes)
    assert lake.kind == "water" and len(lake.holes) == 1
    assert len(lake.holes[0]) >= 3

def test_relation_clipped_to_bbox():
    from pipeline import config
    city = parse_osm(RIVER)
    pad = config.BBOX_PAD_M + 1.0
    from pipeline.geo import latlon_to_xz
    s, w, n, e = config.BBOX
    x_min, z_min = latlon_to_xz(n, w)
    x_max, z_max = latlon_to_xz(s, e)
    for a in city.areas:
        for x, z in a.outline:
            assert x_min - pad <= x <= x_max + pad and z_min - pad <= z <= z_max + pad

def test_trees_and_lamps_parsed():
    city = parse_osm(FIX)
    assert len(city.trees) == 2
    assert len(city.lamps) == 1
