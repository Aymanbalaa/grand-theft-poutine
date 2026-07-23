import numpy as np
from pipeline.osm_parse import Building, Road, Area
from pipeline.meshes import building_mesh, road_mesh, area_mesh

SQ = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)]

def test_building_mesh_bounds():
    m = building_mesh(Building(1, SQ, 30.0))
    # roof cap is a flat single-sided slab concatenated on top of the watertight
    # wall solid (same convention as area meshes), so the combined mesh is no
    # longer a pure closed volume; is_volume is not asserted here.
    assert m is not None
    lo, hi = m.bounds
    assert abs(lo[1] - 0.0) < 1e-6 and abs(hi[1] - 30.05) < 1e-6  # Y is up; cap sits at top+0.05
    assert abs(hi[0] - 10.0) < 1e-6 and abs(hi[2] - 10.0) < 1e-6

def test_degenerate_building_returns_none():
    assert building_mesh(Building(2, [(0, 0), (1, 0), (2, 0), (3, 0)], 10.0)) is None

def test_road_mesh_is_flat_ribbon():
    m = road_mesh(Road(3, "x", [(0.0, 0.0), (100.0, 0.0)], 8.0))
    lo, hi = m.bounds
    assert abs(hi[1] - lo[1]) < 1e-6            # flat
    assert abs((hi[2] - lo[2]) - 8.0) < 1e-6    # width across z
    assert len(m.faces) == 10                    # 5 densified segments * 2 tris

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

from pipeline.terrain import Heightmap
from pipeline.meshes import terrain_tile_mesh

def _flat_hm(h: float) -> Heightmap:
    return Heightmap(grid=np.full((4, 4), h, dtype=np.float32),
                     x0=-512.0, z0=-512.0, step_x=341.33, step_z=341.33)

def test_building_displaced_onto_terrain():
    m = building_mesh(Building(1, SQ, 30.0, "yes"), hm=_flat_hm(50.0))
    lo, hi = m.bounds
    assert abs(lo[1] - 48.0) < 1e-4   # base sunk 2 m below terrain
    assert abs(hi[1] - 80.05) < 1e-4   # top = terrain + height + roof cap (0.05)

def test_road_densified_and_draped():
    m = road_mesh(Road(2, "x", [(0.0, 0.0), (100.0, 0.0)], 8.0), hm=_flat_hm(10.0))
    assert len(m.faces) == 10          # 100 m -> 5 segments of <=24 m -> 10 tris
    assert abs(m.bounds[0][1] - 10.05) < 1e-4

def test_terrain_tile_mesh_grid():
    from pipeline import config
    m = terrain_tile_mesh(0, 0, _flat_hm(5.0))
    q = config.TERRAIN_TILE_QUADS
    assert len(m.vertices) == (q + 1) ** 2
    assert len(m.faces) == q * q * 2
    assert abs(m.bounds[0][1] - 5.0) < 1e-4

def test_terrain_faces_point_up():
    m = terrain_tile_mesh(0, 0, _flat_hm(5.0))
    assert np.all(m.face_normals[:, 1] > 0.99)

def test_road_faces_point_up():
    m = road_mesh(Road(9, "x", [(0.0, 0.0), (30.0, 0.0)], 8.0))
    assert np.all(m.face_normals[:, 1] > 0.99)

def test_roof_cap_darker_than_walls():
    m = building_mesh(Building(1, SQ, 30.0, "office"))
    tops = m.visual.vertex_colors[m.vertices[:, 1] > 30.0]   # cap sits at 30.05
    walls = m.visual.vertex_colors[m.vertices[:, 1] <= 30.0]
    assert len(tops) > 0
    assert tops[:, :3].max() < walls[:, :3].max()             # cap strictly darker

def test_small_residential_gets_gable():
    m = building_mesh(Building(2, SQ, 8.0, "house"))
    assert m.bounds[1][1] > 8.5   # ridge rises above the flat top
    m_office = building_mesh(Building(3, SQ, 8.0, "office"))
    assert m_office.bounds[1][1] < 8.5  # non-residential stays flat-capped

def test_tall_or_odd_footprint_no_gable():
    tall = building_mesh(Building(4, SQ, 40.0, "apartments"))
    assert tall.bounds[1][1] < 40.5
    lshape = [(0, 0), (20, 0), (20, 6), (6, 6), (6, 20), (0, 20)]
    odd = building_mesh(Building(5, lshape, 8.0, "house"))
    assert odd.bounds[1][1] < 8.5   # L-shape ratio < 0.75 -> no gable

def test_building_walls_encode_category_alpha():
    from pipeline.meshes import building_mesh
    from pipeline.osm_parse import Building
    from pipeline import config
    b = Building(1, [(0, 0), (20, 0), (20, 12), (0, 12)], 20.0, "office")
    m = building_mesh(b)
    alphas = set(int(a) for a in m.visual.vertex_colors[:, 3])
    assert config.WALL_CATEGORY_ALPHA["commercial"] * 40 in alphas  # walls tagged
    assert 255 in alphas                                       # roof cap untagged
    b2 = Building(2, [(0, 0), (20, 0), (20, 12), (0, 12)], 20.0, "house")
    alphas2 = set(int(a) for a in building_mesh(b2).visual.vertex_colors[:, 3])
    assert config.WALL_CATEGORY_ALPHA["residential"] * 40 in alphas2

def test_building_alpha_encodes_base_height():
    from pipeline import config
    class HM:
        def sample(self, x, z):
            return 20.0
    b = Building(1, [(0, 0), (20, 0), (20, 20), (0, 20)], 12.0, "office")
    m = building_mesh(b, HM())
    alphas = set(int(a) for a in m.visual.vertex_colors[:, 3])
    assert config.WALL_CATEGORY_ALPHA["commercial"] * 40 + 10 in alphas  # 20 m / 2 m step
    assert 255 in alphas  # roof cap unencoded

def _mk_road(cls="residential", width=6.0):
    from pipeline.osm_parse import Road
    return Road(7, "Rue Test", [(0.0, 0.0), (60.0, 0.0)], width, cls)

def test_sidewalk_raised_and_trimmed():
    from pipeline.meshes import sidewalk_mesh
    from pipeline import config
    m = sidewalk_mesh(_mk_road())
    assert m is not None
    xs = m.vertices[:, 0]
    ys = m.vertices[:, 1]
    assert xs.min() >= config.SIDEWALK_END_TRIM - 1e-6          # end trim applied
    assert xs.max() <= 60.0 - config.SIDEWALK_END_TRIM + 1e-6
    top = ys.max()
    assert abs(top - (0.05 + config.SIDEWALK_RAISE)) < 0.01     # raised over road drape
    zs = abs(m.vertices[:, 2])
    assert zs.max() <= 6.0 / 2 + config.CURB_RUN + config.SIDEWALK_WIDTH + 1e-6

def test_sidewalk_skips_short_and_excluded():
    from pipeline.meshes import sidewalk_mesh
    from pipeline.osm_parse import Road
    assert sidewalk_mesh(Road(8, None, [(0, 0), (10, 0)], 6.0, "residential")) is None  # < 2*trim
    assert sidewalk_mesh(Road(9, "x", [(0, 0), (60, 0)], 2.0, "footway")) is None       # class excluded

def test_sidewalk_deterministic():
    from pipeline.meshes import sidewalk_mesh
    a = sidewalk_mesh(_mk_road())
    b = sidewalk_mesh(_mk_road())
    assert (a.vertices == b.vertices).all() and (a.faces == b.faces).all()

def test_sidewalk_faces_point_up():
    from pipeline.meshes import sidewalk_mesh
    m = sidewalk_mesh(_mk_road())
    ny = m.face_normals[:, 1]
    assert ny.min() > -0.05          # nothing faces downward (CULL_BACK would hide it)
    assert (ny > 0.9).sum() >= 2     # flat walkable tops present on both sides

def test_roadmarks_dashed_centerline():
    from pipeline.meshes import roadmark_mesh
    from pipeline import config
    m = roadmark_mesh(_mk_road())          # residential: centerline only
    assert m is not None
    assert len(m.faces) % 2 == 0
    n_dashes = len(m.faces) // 2
    usable = 60.0 - 2 * config.SIDEWALK_END_TRIM
    assert 1 <= n_dashes <= int(usable / config.MARK_PERIOD) + 1
    assert abs(m.vertices[:, 1].max() - (0.05 + config.MARK_LIFT)) < 0.005
    assert abs(m.vertices[:, 2]).max() <= config.MARK_WIDTH / 2 + 1e-6

def test_roadmarks_edge_lines_on_primary():
    from pipeline.meshes import roadmark_mesh
    m_res = roadmark_mesh(_mk_road("residential"))
    m_pri = roadmark_mesh(_mk_road("primary", width=10.0))
    assert len(m_pri.faces) > len(m_res.faces)          # edge lines added
    assert abs(m_pri.vertices[:, 2]).max() > 4.0        # near ±(5.0 - 0.45)

def test_roadmarks_skip_unnamed_and_footways():
    from pipeline.meshes import roadmark_mesh
    from pipeline.osm_parse import Road
    assert roadmark_mesh(Road(1, None, [(0, 0), (60, 0)], 6.0, "residential")) is None
    assert roadmark_mesh(Road(2, "x", [(0, 0), (60, 0)], 2.0, "footway")) is None

def test_roadmarks_faces_point_up():
    from pipeline.meshes import roadmark_mesh
    m = roadmark_mesh(_mk_road("primary", width=10.0))
    assert m.face_normals[:, 1].min() > 0.9   # every mark quad faces up

def test_clear_intervals_blocks_junctions():
    from pipeline.meshes import _clear_intervals
    pts = [(0.0, 0.0), (30.0, 0.0), (60.0, 0.0)]
    iv = _clear_intervals(pts, {(30.0, 0.0)}, 8.0)
    assert iv == [(8.0, 22.0), (38.0, 52.0)]

def test_sidewalk_gap_at_interior_junction():
    from pipeline.meshes import sidewalk_mesh
    from pipeline.osm_parse import Road
    r = Road(7, "Rue Test", [(0.0, 0.0), (30.0, 0.0), (60.0, 0.0)], 6.0, "residential")
    m = sidewalk_mesh(r, junctions=frozenset({(30.0, 0.0)}))
    xs = m.vertices[:, 0]
    assert not ((xs > 23.0) & (xs < 37.0)).any()   # cleared around the junction

def test_roadmarks_gap_at_interior_junction():
    from pipeline.meshes import roadmark_mesh
    from pipeline.osm_parse import Road
    r = Road(7, "Rue Test", [(0.0, 0.0), (30.0, 0.0), (60.0, 0.0)], 6.0, "residential")
    m = roadmark_mesh(r, junctions=frozenset({(30.0, 0.0)}))
    xs = m.vertices[:, 0]
    assert not ((xs > 23.0) & (xs < 37.0)).any()

def test_traffic_light_mesh_shape():
    from pipeline.meshes import traffic_light_mesh
    m = traffic_light_mesh(10.0, 20.0, 0.0)
    assert m.vertices[:, 1].max() > 4.0          # head height
    assert m.vertices[:, 1].min() >= -0.01
    assert abs(m.vertices[:, 0] - 10.0).max() < 3.0   # near anchor
    a = traffic_light_mesh(10.0, 20.0, 0.0)
    assert (a.vertices == m.vertices).all()      # deterministic

def test_oneway_centerline_is_white():
    from pipeline.meshes import roadmark_mesh
    from pipeline import config
    r = Road(1, "Rue Test", [(0.0, 0.0), (60.0, 0.0)], 6.0, "residential", True)
    m = roadmark_mesh(r)
    cols = {tuple(c[:3]) for c in m.visual.vertex_colors}
    assert tuple(config.MARK_WHITE) in cols
    assert tuple(config.MARK_YELLOW) not in cols

def test_crosswalks_at_junctions():
    from pipeline.meshes import roadmark_mesh
    from pipeline import config
    # straight road with a junction at its middle vertex
    r = Road(7, "Rue Test", [(0.0, 0.0), (60.0, 0.0), (120.0, 0.0)], 8.0, "residential")
    junctions = frozenset({(60.0, 0.0)})
    plain = roadmark_mesh(r, hm=None, junctions=frozenset())
    marked = roadmark_mesh(r, hm=None, junctions=junctions)
    # --- plain baseline (no junctions): one clear interval (8, 112), L=120 ---
    # dashes at t = 8 + 9k while t+3 <= 112  =>  k = 0..11  =>  12 dashes
    # each dash is one straight 2-point segment -> 1 quad -> 2 faces, 4 verts
    assert len(plain.faces) == 24
    assert len(plain.vertices) == 48
    # --- marked (junction at x=60): splits into two clear intervals ---
    # (8, 52) and (68, 112), each length 44 (>= CROSSWALK_MIN_INTERVAL=8)
    # centerline dash phase restarts at each interval's lo:
    #   (8, 52):  t = 8 + 9k,  t+3<=52  => k=0..4 => 5 dashes
    #   (68, 112): t = 68 + 9k, t+3<=112 => k=0..4 => 5 dashes
    # 10 dashes total -> 20 faces, 40 verts for the centerline part
    # crosswalks: the boundary at x=52 (hi of interval 1, dir=-1) and the
    # boundary at x=68 (lo of interval 2, dir=+1) both abut the junction.
    # each gets 1 stop bar + CROSSWALK_BARS(4) zebra bars = 5 bars, each a
    # single straight segment -> 1 quad -> 2 faces, 4 verts per bar.
    # 2 boundaries * 5 bars = 10 bars -> 20 faces, 40 verts for the crosswalk part
    # total: centerline(20 faces, 40 verts) + crosswalk(20 faces, 40 verts)
    assert len(marked.faces) == 40
    assert len(marked.vertices) == 80
    # isolate the crosswalk-only vertices: they're the wide (bw = width*0.85)
    # bars, distinct in |z| from the narrow (MARK_WIDTH) centerline dashes
    wide = marked.vertices[np.abs(marked.vertices[:, 2]) > config.MARK_WIDTH / 2 + 1e-6]
    assert len(wide) == 40  # 2 boundaries * 5 bars * 4 verts/bar
    assert abs(np.abs(wide[:, 2]).max() - r.width * 0.85 / 2.0) < 1e-6
    # bars sit inset from the junction: boundary at 52 -> stop bar [51.2, 51.6],
    # zebra bars stepping 0.9m inward down to 47.35; boundary at 68 -> mirrored
    # out to 72.65
    assert abs(wide[:, 0].min() - 47.35) < 1e-6
    assert abs(wide[:, 0].max() - 72.65) < 1e-6

def test_no_crosswalks_without_junctions():
    from pipeline.meshes import roadmark_mesh
    r = Road(7, "Rue Test", [(0.0, 0.0), (60.0, 0.0), (120.0, 0.0)], 8.0, "residential")
    m = roadmark_mesh(r, hm=None, junctions=frozenset())
    # without junctions there's a single clear interval (8, 112) with no interior
    # boundary, so no crosswalk/stop-bar part is added: 12 centerline dashes only
    # (see derivation in test_crosswalks_at_junctions) -> 24 faces
    assert len(m.faces) == 24
    # deterministic across calls
    assert len(m.faces) == len(roadmark_mesh(r, hm=None, junctions=frozenset()).faces)

def test_jitter3_warmth_varies_per_building():
    from pipeline import meshes
    a = meshes._jitter3(101)
    b = meshes._jitter3(202)
    assert a.shape == (3,)
    # bounded so the category hue stays readable
    assert np.all(a > 0.80) and np.all(a < 1.17)
    # warm/cool axis differs between buildings (not just brightness)
    assert abs(a[0] / a[2] - b[0] / b[2]) > 1e-6

def test_building_walls_carry_tone_variation():
    # two identical buildings differing only by osm_id -> different wall RGB
    b1 = building_mesh(Building(11, SQ, 30.0, "apartments"))
    b2 = building_mesh(Building(12, SQ, 30.0, "apartments"))
    c1 = b1.visual.vertex_colors[0][:3]
    c2 = b2.visual.vertex_colors[0][:3]
    assert not np.array_equal(c1, c2)

def test_sidewalk_curb_distinct_color():
    from pipeline.meshes import sidewalk_mesh
    from pipeline import config
    m = sidewalk_mesh(_mk_road())
    cols = {tuple(c[:3]) for c in m.visual.vertex_colors}
    assert tuple(config.CURB_COLOR) in cols
    assert tuple(config.SIDEWALK_COLOR) in cols
