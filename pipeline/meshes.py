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

def _jitter(osm_id: int) -> float:
    """Deterministic per-id shade factor in [0.88, 1.08]."""
    return 0.88 + 0.2 * ((osm_id * 2654435761) % 1000) / 1000.0

def _paint(mesh: trimesh.Trimesh, rgb: tuple, factor: float = 1.0) -> trimesh.Trimesh:
    c = np.clip(np.array(rgb, dtype=float) * factor, 0, 255).astype(np.uint8)
    mesh.visual.vertex_colors = np.tile(
        np.array([c[0], c[1], c[2], 255], dtype=np.uint8), (len(mesh.vertices), 1)
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
    else:
        c = poly.centroid
        mesh = _to_yup(extrude_polygon(poly, b.height + 2.0))
        mesh.apply_translation([0.0, hm.sample(c.x, c.y) - 2.0, 0.0])
    top_y = float(mesh.bounds[1][1])
    cat = config.BUILDING_CATEGORIES.get(b.btype, "default")
    roof = None
    if cat == "residential" and b.height <= 13.0:
        roof = _gable_roof(poly, top_y)
    if roof is None:
        roof = _roof_cap(poly, top_y, building_color(b), _jitter(b.osm_id))
    walls = _paint(mesh, building_color(b), _jitter(b.osm_id))
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
