from pathlib import Path
from pipeline import config
from pipeline.osm_parse import parse_osm
from pipeline.streets import build_street_grid, district_polys

FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"

def test_grid_dedupes_names():
    city = parse_osm(FIX)
    sg = build_street_grid(city.roads)
    assert "Rue Sainte-Catherine" in sg["names"]
    assert len(sg["names"]) == len(set(sg["names"]))
    assert sg["cell"] == config.STREET_GRID_CELL
    assert len(sg["grid"]) >= 1
    assert all(isinstance(v, int) and 0 <= v < len(sg["names"]) for v in sg["grid"].values())

def test_grid_deterministic():
    city = parse_osm(FIX)
    assert build_street_grid(city.roads) == build_street_grid(city.roads)

def test_district_polys_are_quads():
    ds = district_polys()
    assert len(ds) == len(config.DISTRICTS)
    for d in ds:
        assert len(d["poly"]) == 4
        assert all(len(pt) == 2 for pt in d["poly"])
