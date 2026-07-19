from pathlib import Path
from pipeline.osm_parse import parse_osm, _building_height

FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"

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
