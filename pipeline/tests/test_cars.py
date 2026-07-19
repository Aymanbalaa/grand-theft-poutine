import math
from pathlib import Path
from pipeline import config
from pipeline.cars import car_spawns
from pipeline.osm_parse import parse_osm

FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"

def test_spawns_have_pose_fields():
    city = parse_osm(FIX)
    sp = car_spawns(city.roads)
    assert len(sp) >= 1
    for s in sp:
        assert set(s) == {"x", "y", "z", "yaw"}
        assert -math.pi <= s["yaw"] <= math.pi
        assert s["y"] == 0.05  # no heightmap -> road surface offset only

def test_spawns_deterministic():
    city = parse_osm(FIX)
    assert car_spawns(city.roads) == car_spawns(city.roads)

def test_spawns_respect_gap_and_cap():
    city = parse_osm(FIX)
    sp = car_spawns(city.roads)
    assert len(sp) <= config.MAX_CAR_SPAWNS
    for i, a in enumerate(sp):
        for b in sp[i + 1:]:
            assert math.hypot(a["x"] - b["x"], a["z"] - b["z"]) >= config.CAR_SPAWN_MIN_GAP
