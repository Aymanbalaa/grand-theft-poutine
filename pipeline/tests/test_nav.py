import json
import math
from pathlib import Path
import numpy as np
import pytest
from pipeline import config
from pipeline.nav import build_nav, road_junctions
from pipeline.osm_parse import parse_osm
from pipeline.terrain import Heightmap

NAV = Path(__file__).parent / "fixtures" / "nav.osm.xml"

def _city():
    return parse_osm(NAV)

def _road(nav, osm_id):
    return next(r for r in nav["roads"] if r["id"] == osm_id)

def test_top_level_schema():
    nav = build_nav(_city())
    assert set(nav) == {"nodes", "roads", "signals", "walks"}
    assert all(len(p) == 3 for p in nav["nodes"])
    for r in nav["roads"]:
        assert set(r) == {"id", "n", "cls", "w", "oneway", "lanes", "speed"}
        assert len(r["n"]) >= 2
        assert all(0 <= i < len(nav["nodes"]) for i in r["n"])

def test_only_drivable_classes_become_roads():
    nav = build_nav(_city())
    assert sorted(r["id"] for r in nav["roads"]) == [200, 201, 202]   # no service/footway/steps

def test_oneway_minus_one_is_reversed():
    nav = build_nav(_city())
    inv = _road(nav, 202)
    first, last = nav["nodes"][inv["n"][0]], nav["nodes"][inv["n"][-1]]
    assert inv["oneway"] == 1
    assert first[0] > last[0]          # legal direction runs east (F) -> west (E)
    assert _road(nav, 200)["oneway"] == 0

def test_lanes_and_speed():
    nav = build_nav(_city())
    assert _road(nav, 200)["lanes"] == 3 and _road(nav, 200)["speed"] == round(50 / 3.6, 2)
    assert _road(nav, 201)["lanes"] == 2 and _road(nav, 201)["speed"] == config.NAV_SPEED_DEFAULTS["residential"]
    assert _road(nav, 202)["lanes"] == 1

def test_roads_are_densified_and_share_junction_node():
    nav = build_nav(_city())
    main, side = _road(nav, 200), _road(nav, 201)
    assert len(main["n"]) > 3                      # ~390 m at <=24 m stations
    shared = set(main["n"]) & set(side["n"])
    assert len(shared) == 1
    x, _, z = nav["nodes"][next(iter(shared))]
    assert math.hypot(x, z) < 0.2                  # the junction is node J at the origin

def test_signal_snaps_to_junction_node_and_far_one_dropped():
    nav = build_nav(_city())
    assert len(nav["signals"]) == 1
    x, _, z = nav["nodes"][nav["signals"][0]]
    assert math.hypot(x, z) < 0.2

def test_road_node_heights_follow_heightmap():
    hm = Heightmap(grid=np.full((4, 4), 5.0, dtype=np.float32),
                   x0=-3000.0, z0=-3000.0, step_x=2000.0, step_z=2000.0)
    nav = build_nav(_city(), hm=hm)
    for r in nav["roads"]:
        for i in r["n"]:
            assert nav["nodes"][i][1] == 5.05

def test_road_junctions_matches_tiler_rule():
    j = road_junctions(_city().roads)
    assert len(j) == 1 and all(abs(v) < 0.2 for v in next(iter(j)))

def test_deterministic():
    city = _city()
    a = json.dumps(build_nav(city), sort_keys=True)
    b = json.dumps(build_nav(city), sort_keys=True)
    assert a == b
