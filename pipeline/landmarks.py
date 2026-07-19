from __future__ import annotations
from pathlib import Path
import numpy as np
import trimesh
from shapely.geometry import Polygon
from trimesh.creation import box as tm_box, icosphere, extrude_polygon
from pipeline import config
from pipeline.geo import latlon_to_xz
from pipeline.meshes import _paint, _ZUP_TO_YUP

GLASS = (120, 135, 150)
STONE = (110, 106, 100)
DARK_ROOF = (70, 66, 62)
CONCRETE = (196, 190, 180)
STEEL = (140, 150, 155)
MILL = (150, 140, 130)
SIGN_RED = (200, 40, 40)

def _box(sx: float, sy: float, sz: float, cx: float, base_y: float, cz: float,
         rgb: tuple) -> trimesh.Trimesh:
    b = tm_box((sx, sy, sz))
    b.apply_translation([cx, base_y + sy / 2.0, cz])
    return _paint(b, rgb)

def _prism(width: float, height: float, length: float, cx: float, base_y: float,
           cz: float, rgb: tuple) -> trimesh.Trimesh:
    """Triangular roof prism: cross-section in XY (y up), extruded along Z."""
    m = extrude_polygon(Polygon([(-width / 2, 0), (width / 2, 0), (0, height)]), length)
    m.apply_translation([cx, 0, -length / 2.0])
    m.apply_translation([0, base_y, cz])
    return _paint(m, rgb)

def pvm(base_y: float) -> list[trimesh.Trimesh]:
    parts = [_box(90, 5, 90, 0, base_y, 0, CONCRETE)]           # podium
    parts.append(_box(62, 183, 18, 0, base_y + 5, 0, GLASS))    # cruciform tower
    parts.append(_box(18, 183, 62, 0, base_y + 5, 0, GLASS))
    return parts

def notre_dame(base_y: float) -> list[trimesh.Trimesh]:
    parts = [
        _box(12, 66, 12, -12, base_y, -26, STONE),  # west tower
        _box(12, 66, 12, 12, base_y, -26, STONE),   # east tower
        _box(34, 22, 58, 0, base_y, 8, STONE),      # nave
        _prism(34, 12, 58, 0, base_y + 22, 8, DARK_ROOF),
    ]
    return parts

def biosphere(base_y: float) -> list[trimesh.Trimesh]:
    s = icosphere(subdivisions=2, radius=38.0)
    s.apply_translation([0, base_y + 20.0, 0])  # sphere sunk into the ground
    return [_paint(s, STEEL)]

def habitat67(base_y: float) -> list[trimesh.Trimesh]:
    parts = []
    for tier, count in enumerate((15, 10, 6)):
        for i in range(count):
            x = -70.0 + i * (140.0 / max(count - 1, 1)) + ((i * 37) % 7) - 3.0
            z = float(((i * 53 + tier * 29) % 11) - 5)
            parts.append(_box(12, 4, 7, x, base_y + tier * 4.5, z, CONCRETE))
    return parts

def five_roses(base_y: float) -> list[trimesh.Trimesh]:
    parts = [
        _box(28, 35, 22, -18, base_y, 0, MILL),
        _box(36, 28, 20, 16, base_y, 2, MILL),
        _box(2, 8, 2, -26, base_y + 35, 0, MILL),   # sign posts
        _box(2, 8, 2, -10, base_y + 35, 0, MILL),
        _box(42, 7, 1.5, -18, base_y + 41, 0, SIGN_RED),  # FARINE FIVE ROSES panel
    ]
    return parts

BUILDERS = {
    "pvm": pvm, "notre_dame": notre_dame, "biosphere": biosphere,
    "habitat67": habitat67, "five_roses": five_roses,
}

def export_landmarks(out_dir: str | Path, hm) -> list[dict]:
    out = Path(out_dir) / "landmarks"
    out.mkdir(parents=True, exist_ok=True)
    entries = []
    for lm in config.LANDMARKS:
        x, z = latlon_to_xz(lm["lat"], lm["lon"])
        base_y = hm.sample(x, z) if hm is not None else 0.0
        mesh = trimesh.util.concatenate(BUILDERS[lm["key"]](base_y))
        mesh.apply_translation([x, 0, z])
        scene = trimesh.Scene()
        scene.add_geometry(mesh, geom_name=lm["key"], node_name=lm["key"])
        fname = f"landmarks/{lm['key']}.glb"
        scene.export(Path(out_dir) / fname)
        entries.append({"key": lm["key"], "name": lm["name"], "file": fname,
                        "x": round(x, 1), "z": round(z, 1)})
    return entries
