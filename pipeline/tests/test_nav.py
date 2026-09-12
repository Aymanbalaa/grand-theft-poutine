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

def test_signals_attributed_to_junction_and_midblock_kept():
    nav = build_nav(_city())
    # J itself (node 1) and the stop-line signal 12 m west of J (node 15) both become J;
    # the mid-block signal on way 202 (node 16) stays on its own node; far node 14 is dropped
    assert len(nav["signals"]) == 2
    pts = sorted((round(nav["nodes"][i][0]), round(nav["nodes"][i][2])) for i in nav["signals"])
    assert pts == [(0, -111), (0, 0)]
    j = next(i for i in nav["signals"] if abs(nav["nodes"][i][0]) < 0.2 and abs(nav["nodes"][i][2]) < 0.2)
    assert j in _road(nav, 200)["n"] and j in _road(nav, 201)["n"]   # the shared junction node

def test_signal_reach_is_bounded(monkeypatch):
    monkeypatch.setattr(config, "NAV_SIGNAL_JUNCTION_REACH", 5.0)
    nav = build_nav(_city())
    # with a 5 m reach the 12 m stop-line signal can no longer fold into J: 3 distinct signal nodes
    assert len(nav["signals"]) == 3

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

def _walk_nodes(nav, kind):
    return [[nav["nodes"][i] for i in w["n"]] for w in nav["walks"] if w["kind"] == kind]

def test_side_walks_offset_both_sides():
    nav = build_nav(_city())
    sides = _walk_nodes(nav, "side")
    # primary w=10 runs along z=0: sidewalk centerlines at |z| = 5 + 0.18 + 1.0 = 6.18
    zs = sorted({round(p[2], 1) for w in sides for p in w if abs(p[0]) > 20 and abs(p[2]) < 8})
    assert zs == [-6.2, 6.2]
    # residential w=6 runs along x=0: |x| = 3 + 1.18 = 4.18
    xs = sorted({round(p[0], 1) for w in sides for p in w if 20 < abs(p[2]) < 100 and abs(p[0]) < 8})
    assert xs == [-4.2, 4.2]
    # straight 2-point sidewalk-class ways (way 202) still get both sides
    assert len([w for w in sides if all(abs(p[2] + 110.6) < 6 for p in w)]) == 2

def test_side_walks_trimmed_at_junction_and_ends():
    nav = build_nav(_city())
    for w in _walk_nodes(nav, "side"):
        for x, _, z in w:
            assert math.hypot(x, z) >= config.SIDEWALK_END_TRIM - 0.5

def test_crossings_at_junction_and_dead_ends():
    nav = build_nav(_city())
    crosses = _walk_nodes(nav, "cross")
    assert all(len(w) == 2 for w in crosses)
    for (xa, _, za), (xb, _, zb) in crosses:
        assert math.hypot(xa - xb, za - zb) <= config.NAV_CROSS_MAX + 1e-6
    at_j = [w for w in crosses if all(math.hypot(x, z) <= config.NAV_CROSS_RADIUS for x, _, z in w)]
    assert len(at_j) >= 4                      # straight crossings + same-side continuations, no diagonals
    # dead end of the primary at x ~ -195: its two sidewalk ends are joined
    west = [w for w in crosses if all(x < -150 and abs(z) < 8 for x, _, z in w)]
    assert len(west) == 1                      # (way 202's dead end sits at z ~ -110, excluded)

def test_paths_include_footway_and_steps():
    nav = build_nav(_city())
    assert len(_walk_nodes(nav, "path")) == 2

def test_walk_heights_follow_heightmap():
    hm = Heightmap(grid=np.full((4, 4), 5.0, dtype=np.float32),
                   x0=-3000.0, z0=-3000.0, step_x=2000.0, step_z=2000.0)
    nav = build_nav(_city(), hm=hm)
    for w in nav["walks"]:
        for i in w["n"]:
            y = nav["nodes"][i][1]
            if w["kind"] == "path":
                assert y == 5.05
            else:
                assert abs(y - 5.17) <= 0.003      # +-2 mm per-road jitter, like sidewalk_mesh

def test_path_radius_prunes_far_footpaths():
    nav = build_nav(_city(), path_radius=10.0)
    assert _walk_nodes(nav, "path") == []
    assert len(_walk_nodes(nav, "side")) > 0
