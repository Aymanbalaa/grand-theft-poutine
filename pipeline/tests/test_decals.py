from pathlib import Path
from pipeline.decals import manhole_spots
from pipeline.osm_parse import parse_osm

FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"

def test_manholes_sampled_along_named_roads():
    city = parse_osm(FIX)
    holes = manhole_spots(city.roads, hm=None)
    assert len(holes) >= 1
    assert all(set(h) == {"x", "y", "z"} for h in holes)  # dicts, rounded floats

def test_manholes_deterministic():
    city = parse_osm(FIX)
    assert manhole_spots(city.roads, hm=None) == manhole_spots(city.roads, hm=None)
