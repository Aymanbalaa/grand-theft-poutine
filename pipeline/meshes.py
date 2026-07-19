from __future__ import annotations
import numpy as np
import trimesh
from shapely.geometry import Polygon, LineString
from trimesh.creation import extrude_polygon, triangulate_polygon
from pipeline.osm_parse import Building, Road, Area

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

def building_mesh(b: Building) -> trimesh.Trimesh | None:
    if len(b.footprint) < 3 or b.height <= 0:
        return None
    poly = Polygon(b.footprint)
    if not poly.is_valid:
        poly = poly.buffer(0)
    if poly.is_empty or poly.area < 1.0 or poly.geom_type != "Polygon":
        return None
    return _to_yup(extrude_polygon(poly, b.height))

def road_mesh(r: Road) -> trimesh.Trimesh | None:
    if len(r.points) < 2 or r.width <= 0:
        return None
    line = LineString(r.points)
    if line.length < 1.0:
        return None
    verts, faces = [], []
    for (x1, z1), (x2, z2) in zip(r.points[:-1], r.points[1:]):
        d = np.array([x2 - x1, z2 - z1])
        n = np.linalg.norm(d)
        if n < 1e-6:
            continue
        px, pz = -d[1] / n, d[0] / n  # left-hand perpendicular in xz
        hw = r.width / 2.0
        i = len(verts)
        verts += [
            [x1 + px * hw, 0.05, z1 + pz * hw], [x1 - px * hw, 0.05, z1 - pz * hw],
            [x2 + px * hw, 0.05, z2 + pz * hw], [x2 - px * hw, 0.05, z2 - pz * hw],
        ]
        faces += [[i, i + 2, i + 1], [i + 1, i + 2, i + 3]]
    if not faces:
        return None
    return trimesh.Trimesh(vertices=np.array(verts), faces=np.array(faces), process=False)

def area_mesh(a: Area) -> trimesh.Trimesh | None:
    if len(a.outline) < 3:
        return None
    poly = Polygon(a.outline)
    if not poly.is_valid:
        poly = poly.buffer(0)
    if poly.is_empty or poly.area < 1.0 or poly.geom_type != "Polygon":
        return None
    v2d, faces = triangulate_polygon(poly)
    verts = np.column_stack([v2d[:, 0], np.full(len(v2d), 0.02), v2d[:, 1]])
    return trimesh.Trimesh(vertices=verts, faces=faces, process=False)
