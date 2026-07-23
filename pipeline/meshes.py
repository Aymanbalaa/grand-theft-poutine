from __future__ import annotations
import math
import numpy as np
import trimesh
import trimesh.transformations as tf
from shapely.geometry import Polygon, LineString
from trimesh.creation import extrude_polygon, triangulate_polygon
from pipeline.osm_parse import Building, Road, Area
from pipeline.terrain import Heightmap
from pipeline import config

def _densify(points: list[tuple[float, float]], max_len: float = 24.0) -> list[tuple[float, float]]:
    out = [points[0]]
    for (x1, z1), (x2, z2) in zip(points[:-1], points[1:]):
        d = math.hypot(x2 - x1, z2 - z1)
        steps = max(1, math.ceil(d / max_len))
        for i in range(1, steps + 1):
            out.append((x1 + (x2 - x1) * i / steps, z1 + (z2 - z1) * i / steps))
    return out

def _jitter3(osm_id: int) -> np.ndarray:
    """Deterministic per-building tone: brightness in [0.86, 1.10] plus a
    warm/cool shift of up to +-6% between the red and blue channels."""
    h = (osm_id * 2654435761) % (2 ** 32)
    bright = 0.86 + 0.24 * ((h & 1023) / 1023.0)
    warm = -0.06 + 0.12 * (((h >> 10) & 1023) / 1023.0)
    return np.array([bright * (1.0 + warm), bright, bright * (1.0 - warm)])

def _paint(mesh: trimesh.Trimesh, rgb: tuple, factor: float = 1.0,
           alpha: int = 255) -> trimesh.Trimesh:
    c = np.clip(np.array(rgb, dtype=float) * factor, 0, 255).astype(np.uint8)
    mesh.visual.vertex_colors = np.tile(
        np.array([c[0], c[1], c[2], alpha], dtype=np.uint8), (len(mesh.vertices), 1)
    )
    return mesh

def building_color(b: Building) -> tuple:
    cat = config.BUILDING_CATEGORIES.get(b.btype, "default")
    return config.BUILDING_PALETTE[cat]

# trimesh extrudes along +Z; rotate so extrusion axis becomes +Y (and XY plane -> XZ plane).
_ZUP_TO_YUP = np.array([
    [1, 0, 0, 0],
    [0, 0, 1, 0],
    [0, 1, 0, 0],
    [0, 0, 0, 1],
], dtype=float)

def _to_yup(mesh: trimesh.Trimesh) -> trimesh.Trimesh:
    mesh.apply_transform(_ZUP_TO_YUP)
    # multibody=False: extrude_polygon always yields a single connected
    # component, and the default (multibody=None) probes body_count via
    # scipy.sparse.csgraph, which isn't installed in this environment.
    mesh.fix_normals(multibody=False)
    return mesh

def _roof_cap(poly: Polygon, top_y: float, rgb: tuple, factor: float) -> trimesh.Trimesh:
    v2d, faces = triangulate_polygon(poly)
    verts = np.column_stack([v2d[:, 0], np.full(len(v2d), top_y + 0.05), v2d[:, 1]])
    cap = trimesh.Trimesh(vertices=verts, faces=faces, process=False)
    dark = tuple(int(c * 0.62) for c in rgb)
    return _paint(cap, dark, factor)

def _gable_roof(poly: Polygon, top_y: float) -> trimesh.Trimesh | None:
    """Triangular prism along the footprint's long axis; None if not rectangular enough."""
    mrr = poly.minimum_rotated_rectangle
    if mrr.area <= 0 or poly.area / mrr.area < 0.75:
        return None
    c = list(mrr.exterior.coords)
    e0 = np.hypot(c[1][0] - c[0][0], c[1][1] - c[0][1])
    e1 = np.hypot(c[2][0] - c[1][0], c[2][1] - c[1][1])
    if e0 >= e1:
        length, width = e0, e1
        ax, az = c[1][0] - c[0][0], c[1][1] - c[0][1]
    else:
        length, width = e1, e0
        ax, az = c[2][0] - c[1][0], c[2][1] - c[1][1]
    rise = min(3.0, width * 0.4)
    m = extrude_polygon(Polygon([(-width / 2, 0), (width / 2, 0), (0.0, rise)]), length)
    m.apply_translation([0.0, 0.0, -length / 2.0])
    # extrusion runs along +Z; rotate so it runs along the long-axis direction (ax, az)
    angle = np.arctan2(ax, az)  # rotation about +Y mapping +Z onto (ax, az) in xz
    m.apply_transform(tf.rotation_matrix(angle, [0, 1, 0]))
    cx, cz = mrr.centroid.x, mrr.centroid.y
    m.apply_translation([cx, top_y, cz])
    return _paint(m, config.ROOF_GABLE_COLOR)

def building_mesh(b: Building, hm: Heightmap | None = None) -> trimesh.Trimesh | None:
    if len(b.footprint) < 3 or b.height <= 0:
        return None
    poly = Polygon(b.footprint)
    if not poly.is_valid:
        poly = poly.buffer(0)
    if poly.is_empty or poly.area < 1.0 or poly.geom_type != "Polygon":
        return None
    if hm is None:
        mesh = _to_yup(extrude_polygon(poly, b.height))
        base_y = 0.0
    else:
        c = poly.centroid
        base_y = hm.sample(c.x, c.y)
        mesh = _to_yup(extrude_polygon(poly, b.height + 2.0))
        mesh.apply_translation([0.0, base_y - 2.0, 0.0])
    top_y = float(mesh.bounds[1][1])
    cat = config.BUILDING_CATEGORIES.get(b.btype, "default")
    roof = None
    if cat == "residential" and b.height <= 13.0:
        roof = _gable_roof(poly, top_y)
    if roof is None:
        roof = _roof_cap(poly, top_y, building_color(b), _jitter3(b.osm_id))
    q = min(config.WALL_ALPHA_BASE_MAX, max(0, round(base_y / config.WALL_ALPHA_BASE_STEP)))
    walls = _paint(mesh, building_color(b), _jitter3(b.osm_id),
                   alpha=config.WALL_CATEGORY_ALPHA.get(cat, 5) * 40 + q)
    return trimesh.util.concatenate([walls, roof])

def road_mesh(r: Road, hm: Heightmap | None = None) -> trimesh.Trimesh | None:
    if len(r.points) < 2 or r.width <= 0:
        return None
    line = LineString(r.points)
    if line.length < 1.0:
        return None
    pts = _densify(r.points)
    def h(x: float, z: float) -> float:
        return 0.05 + (hm.sample(x, z) if hm is not None else 0.0)
    verts, faces = [], []
    for (x1, z1), (x2, z2) in zip(pts[:-1], pts[1:]):
        d = np.array([x2 - x1, z2 - z1])
        n = np.linalg.norm(d)
        if n < 1e-6:
            continue
        px, pz = -d[1] / n, d[0] / n  # left-hand perpendicular in xz
        hw = r.width / 2.0
        i = len(verts)
        y1, y2 = h(x1, z1), h(x2, z2)
        verts += [
            [x1 + px * hw, y1, z1 + pz * hw], [x1 - px * hw, y1, z1 - pz * hw],
            [x2 + px * hw, y2, z2 + pz * hw], [x2 - px * hw, y2, z2 - pz * hw],
        ]
        faces += [[i, i + 2, i + 1], [i + 1, i + 2, i + 3]]
    if not faces:
        return None
    mesh = trimesh.Trimesh(vertices=np.array(verts), faces=np.array(faces), process=False)
    return _paint(mesh, config.ROAD_COLORS.get(r.road_class, config.DEFAULT_ROAD_COLOR))

def _polyline_slice(points: list[tuple[float, float]], start: float, end: float
                    ) -> list[tuple[float, float]]:
    """Sub-polyline between arclengths [start, end], densified endpoints included."""
    out: list[tuple[float, float]] = []
    acc = 0.0
    for (x1, z1), (x2, z2) in zip(points[:-1], points[1:]):
        seg = math.hypot(x2 - x1, z2 - z1)
        if seg < 1e-9:
            continue
        a0, a1 = acc, acc + seg
        lo, hi = max(a0, start), min(a1, end)
        if lo < hi:
            for t in (lo, hi) if not out else (hi,):
                f = (t - a0) / seg
                out.append((x1 + (x2 - x1) * f, z1 + (z2 - z1) * f))
        acc = a1
    return out

def _clear_intervals(points: list[tuple[float, float]], junctions, trim: float
                     ) -> list[tuple[float, float]]:
    """Arclength intervals of the polyline that stay `trim` away from way ends
    and from any vertex present in `junctions` (a set of (x, z) tuples)."""
    seglens = [math.hypot(x2 - x1, z2 - z1)
               for (x1, z1), (x2, z2) in zip(points[:-1], points[1:])]
    L = sum(seglens)
    blocked = [(0.0, trim), (L - trim, L)]
    acc = 0.0
    for i, (x, z) in enumerate(points):
        if i > 0:
            acc += seglens[i - 1]
        if (round(x, 2), round(z, 2)) in junctions:
            blocked.append((acc - trim, acc + trim))
    merged: list[list[float]] = []
    for b0, b1 in sorted(blocked):
        b0, b1 = max(b0, 0.0), min(b1, L)
        if b0 >= b1:
            continue
        if merged and b0 <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], b1)
        else:
            merged.append([b0, b1])
    clear: list[tuple[float, float]] = []
    prev = 0.0
    for b0, b1 in merged:
        if b0 > prev:
            clear.append((prev, b0))
        prev = max(prev, b1)
    if prev < L:
        clear.append((prev, L))
    return clear

def sidewalk_mesh(r: Road, hm: Heightmap | None = None,
                  junctions: frozenset = frozenset()) -> trimesh.Trimesh | None:
    if r.road_class not in config.SIDEWALK_CLASSES or r.width <= 0:
        return None
    intervals = [iv for iv in _clear_intervals(r.points, junctions, config.SIDEWALK_END_TRIM)
                if iv[1] - iv[0] >= 4.0]
    if not intervals:
        return None
    jitter = ((r.osm_id * 2654435761) % 5 - 2) * 0.001  # -2..+2 mm
    def h(x: float, z: float) -> float:
        return 0.05 + jitter + (hm.sample(x, z) if hm is not None else 0.0)
    hw = r.width / 2.0
    raise_y = config.SIDEWALK_RAISE
    verts, faces = [], []
    for lo, hi in intervals:
        pts = _densify(_polyline_slice(r.points, lo, hi))
        for side in (1.0, -1.0):
            for (x1, z1), (x2, z2) in zip(pts[:-1], pts[1:]):
                d = np.array([x2 - x1, z2 - z1])
                n = np.linalg.norm(d)
                if n < 1e-6:
                    continue
                px, pz = side * -d[1] / n, side * d[0] / n
                i = len(verts)
                for (x, z) in ((x1, z1), (x2, z2)):
                    y = h(x, z)
                    verts += [
                        [x + px * hw, y, z + pz * hw],                                            # 0 curb bottom
                        [x + px * (hw + config.CURB_RUN), y + raise_y, z + pz * (hw + config.CURB_RUN)],  # 1 curb top
                        [x + px * (hw + config.CURB_RUN + config.SIDEWALK_WIDTH), y + raise_y,
                         z + pz * (hw + config.CURB_RUN + config.SIDEWALK_WIDTH)],                # 2 outer top
                        [x + px * (hw + config.CURB_RUN + config.SIDEWALK_WIDTH), y - 0.3,
                         z + pz * (hw + config.CURB_RUN + config.SIDEWALK_WIDTH)],                # 3 outer skirt
                    ]
                for k in range(3):
                    a, b = i + k, i + 4 + k
                    # columns run OUTWARD (opposite lateral sense to road_mesh's
                    # left->right), so side>0 takes the flipped pattern
                    if side > 0:
                        faces += [[a, a + 1, b], [a + 1, b + 1, b]]
                    else:
                        faces += [[a, b, a + 1], [a + 1, b, b + 1]]
    if not faces:
        return None
    mesh = trimesh.Trimesh(vertices=np.array(verts), faces=np.array(faces), process=False)
    curb = np.array([*config.CURB_COLOR, 255], dtype=np.uint8)
    walk = np.array([*config.SIDEWALK_COLOR, 255], dtype=np.uint8)
    colors = np.tile(walk, (len(mesh.vertices), 1))
    colors[0::4] = curb   # curb bottom
    colors[1::4] = curb   # curb top (shared edge blends into the walk face - fine, both grey)
    mesh.visual.vertex_colors = colors
    return mesh

def _strip_quads(pts: list[tuple[float, float]], offset: float, width: float,
                 h, verts: list, faces: list) -> None:
    """Constant-lateral-offset ribbon of quads along pts (offset 0 = centerline)."""
    for (x1, z1), (x2, z2) in zip(pts[:-1], pts[1:]):
        d = np.array([x2 - x1, z2 - z1])
        n = np.linalg.norm(d)
        if n < 1e-6:
            continue
        px, pz = -d[1] / n, d[0] / n
        hw = width / 2.0
        i = len(verts)
        for (x, z) in ((x1, z1), (x2, z2)):
            y = h(x, z)
            cx, cz = x + px * offset, z + pz * offset
            verts += [[cx + px * hw, y, cz + pz * hw], [cx - px * hw, y, cz - pz * hw]]
        faces += [[i, i + 2, i + 1], [i + 1, i + 2, i + 3]]

def roadmark_mesh(r: Road, hm: Heightmap | None = None,
                  junctions: frozenset = frozenset()) -> trimesh.Trimesh | None:
    if r.road_class not in config.ROADMARK_CLASSES or not r.name:
        return None
    intervals = [iv for iv in _clear_intervals(r.points, junctions, config.SIDEWALK_END_TRIM)
                if iv[1] - iv[0] >= config.MARK_DASH]
    if not intervals:
        return None
    def h(x: float, z: float) -> float:
        return 0.05 + config.MARK_LIFT + (hm.sample(x, z) if hm is not None else 0.0)
    parts = []
    # dashed centerline: yellow two-way, white one-way
    verts, faces = [], []
    for lo, hi in intervals:
        t = lo
        while t + config.MARK_DASH <= hi:
            seg = _polyline_slice(r.points, t, t + config.MARK_DASH)
            if len(seg) >= 2:
                _strip_quads(_densify(seg), 0.0, config.MARK_WIDTH, h, verts, faces)
            t += config.MARK_PERIOD
    if faces:
        parts.append(_paint(trimesh.Trimesh(vertices=np.array(verts), faces=np.array(faces),
                                            process=False), config.MARK_WHITE if r.oneway else config.MARK_YELLOW))
    # white edge lines on arterials
    if r.road_class in config.EDGE_LINE_CLASSES:
        everts, efaces = [], []
        for lo, hi in intervals:
            span = _densify(_polyline_slice(r.points, lo, hi))
            if len(span) >= 2:
                off = r.width / 2.0 - 0.45
                _strip_quads(span, off, 0.10, h, everts, efaces)
                _strip_quads(span, -off, 0.10, h, everts, efaces)
        if efaces:
            parts.append(_paint(trimesh.Trimesh(vertices=np.array(everts),
                                                faces=np.array(efaces), process=False),
                                config.MARK_WHITE))
    # crosswalks + stop bars at clear-interval boundaries that abut junctions.
    # way-end boundaries sit exactly at SIDEWALK_END_TRIM / L - SIDEWALK_END_TRIM;
    # interior boundaries are junction-caused.
    L = sum(math.hypot(x2 - x1, z2 - z1)
            for (x1, z1), (x2, z2) in zip(r.points[:-1], r.points[1:]))
    trim = config.SIDEWALK_END_TRIM
    cverts, cfaces = [], []
    bw = r.width * 0.85

    def _bars(start: float, direction: float) -> None:
        # stop bar, then zebra, marching `direction` (+1 into the interval from lo,
        # -1 into the interval from hi)
        s0 = start + direction * config.STOPBAR_INSET
        seg = _polyline_slice(r.points, min(s0, s0 + direction * config.STOPBAR_LEN),
                              max(s0, s0 + direction * config.STOPBAR_LEN))
        if len(seg) >= 2:
            _strip_quads(_densify(seg), 0.0, bw, h, cverts, cfaces)
        z0 = start + direction * config.CROSSWALK_INSET
        step = config.CROSSWALK_BAR + config.CROSSWALK_GAP
        for k in range(config.CROSSWALK_BARS):
            a = z0 + direction * k * step
            b = a + direction * config.CROSSWALK_BAR
            seg = _polyline_slice(r.points, min(a, b), max(a, b))
            if len(seg) >= 2:
                _strip_quads(_densify(seg), 0.0, bw, h, cverts, cfaces)

    for lo, hi in intervals:
        if hi - lo < config.CROSSWALK_MIN_INTERVAL:
            continue
        if lo > trim + 0.01:          # boundary at lo abuts a junction
            _bars(lo, 1.0)
        if hi < L - trim - 0.01:      # boundary at hi abuts a junction
            _bars(hi, -1.0)
    if cfaces:
        parts.append(_paint(trimesh.Trimesh(vertices=np.array(cverts),
                                            faces=np.array(cfaces), process=False),
                            config.MARK_WHITE))
    if not parts:
        return None
    return trimesh.util.concatenate(parts)

def area_piece_mesh(geom, kind: str, y: float = 0.02,
                    hm: Heightmap | None = None,
                    flat_y: float | None = None) -> trimesh.Trimesh | None:
    polys = [g for g in getattr(geom, "geoms", [geom])
             if g.geom_type == "Polygon" and not g.is_empty and g.area >= 1.0]
    parts = []
    for p in polys:
        v2d, faces = triangulate_polygon(p)
        if flat_y is not None:
            ys = np.full(len(v2d), flat_y)
        elif hm is not None:
            ys = np.array([hm.sample(px, pz) + y for px, pz in v2d])
        else:
            ys = np.full(len(v2d), y)
        verts = np.column_stack([v2d[:, 0], ys, v2d[:, 1]])
        parts.append(trimesh.Trimesh(vertices=verts, faces=faces, process=False))
    if not parts:
        return None
    return _paint(trimesh.util.concatenate(parts), config.AREA_COLORS[kind])

def area_mesh(a: Area) -> trimesh.Trimesh | None:
    if len(a.outline) < 3:
        return None
    poly = Polygon(a.outline, a.holes)
    if not poly.is_valid:
        poly = poly.buffer(0)
    return area_piece_mesh(poly, a.kind)

def traffic_light_mesh(x: float, z: float, y: float) -> trimesh.Trimesh:
    pole_h = 4.6
    arm_len = 1.6
    head_size = (0.35, 1.0, 0.35)
    pole = trimesh.creation.box((0.22, pole_h, 0.22))
    pole.apply_translation([0, pole_h / 2.0, 0])
    _paint(pole, config.TRAFFIC_POLE_COLOR)
    arm = trimesh.creation.box((arm_len, 0.12, 0.12))
    arm.apply_translation([-arm_len / 2.0, pole_h, 0])
    _paint(arm, config.TRAFFIC_POLE_COLOR)
    head = trimesh.creation.box(head_size)
    head.apply_translation([-arm_len, pole_h - head_size[1] / 2.0, 0])
    _paint(head, config.TRAFFIC_POLE_COLOR)
    lights = []
    light_size = 0.16
    front_z = head_size[2] / 2.0 + light_size / 2.0
    colors = ((200, 40, 30), (220, 160, 30), (40, 170, 60))
    for i, rgb in enumerate(colors):
        cy = pole_h - head_size[1] * (2 * i + 1) / 6.0
        lamp = trimesh.creation.box((light_size, light_size, light_size))
        lamp.apply_translation([-arm_len, cy, front_z])
        lights.append(_paint(lamp, rgb))
    m = trimesh.util.concatenate([pole, arm, head, *lights])
    m.apply_translation([x, y, z])
    return m

def terrain_tile_mesh(tx: int, tz: int, hm: Heightmap,
                      water_geom=None, green_geom=None) -> trimesh.Trimesh:
    from shapely.geometry import Point
    q = config.TERRAIN_TILE_QUADS
    ts = config.TILE_SIZE
    n = q + 1
    verts = np.zeros((n * n, 3))
    colors = np.zeros((n * n, 4), dtype=np.uint8)
    lo_y, hi_y = config.TERRAIN_COLOR_BLEND
    c_lo = np.array(config.TERRAIN_COLOR_LOW, dtype=float)
    c_hi = np.array(config.TERRAIN_COLOR_HIGH, dtype=float)
    c_wet = np.array(config.TERRAIN_WATER_COLOR, dtype=float)
    for iz in range(n):
        for ix in range(n):
            x = tx * ts + ix * ts / q
            z = tz * ts + iz * ts / q
            yv = hm.sample(x, z)
            pt = Point(x, z)
            if water_geom is not None and water_geom.contains(pt):
                yv -= config.TERRAIN_WATER_DROP
                rgb = c_wet
            elif green_geom is not None and green_geom.contains(pt):
                rgb = c_hi
            else:
                t = min(max((yv - lo_y) / (hi_y - lo_y), 0.0), 1.0)
                rgb = c_lo * (1 - t) + c_hi * t
            k = iz * n + ix
            verts[k] = [x, yv, z]
            colors[k] = [*rgb.astype(np.uint8), 255]
    faces = []
    for iz in range(q):
        for ix in range(q):
            a = iz * n + ix
            faces += [[a, a + n, a + 1], [a + 1, a + n, a + n + 1]]
    mesh = trimesh.Trimesh(vertices=verts, faces=np.array(faces), process=False)
    mesh.visual.vertex_colors = colors
    return mesh
