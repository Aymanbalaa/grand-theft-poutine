from __future__ import annotations
from pathlib import Path
from PIL import Image, ImageDraw
from pipeline import config
from pipeline.geo import latlon_to_xz
from pipeline.osm_parse import CityData

BG = (34, 36, 40)
GOLD = (230, 190, 80)

def render_minimap(city: CityData, out_path: str | Path, size: int = 2048) -> dict:
    s, w, n, e = config.BBOX
    x0, z0 = latlon_to_xz(n, w)
    x1, z1 = latlon_to_xz(s, e)
    span = max(x1 - x0, z1 - z0)
    scale = size / span
    def px(x: float, z: float) -> tuple[float, float]:
        return ((x - x0) * scale, (z - z0) * scale)
    img = Image.new("RGB", (size, size), BG)
    d = ImageDraw.Draw(img)
    for kind in ("green", "water"):
        for a in sorted((a for a in city.areas if a.kind == kind), key=lambda a: a.osm_id):
            if len(a.outline) < 3:
                continue
            d.polygon([px(x, z) for x, z in a.outline], fill=config.AREA_COLORS[kind])
            for hole in a.holes:
                if len(hole) >= 3:
                    d.polygon([px(x, z) for x, z in hole], fill=BG)
    for r in city.roads:
        color = config.ROAD_COLORS.get(r.road_class, config.DEFAULT_ROAD_COLOR)
        width = max(1, round(r.width * scale))
        d.line([px(x, z) for x, z in r.points], fill=color, width=width)
    for lm in config.LANDMARKS:
        cx, cz = px(*latlon_to_xz(lm["lat"], lm["lon"]))
        rr = max(3, size // 340)
        d.ellipse([cx - rr, cz - rr, cx + rr, cz + rr], fill=GOLD)
    img.save(str(out_path))
    return {"file": Path(out_path).name, "world_origin": [round(x0, 1), round(z0, 1)],
            "world_size": [round(span, 1), round(span, 1)], "px": size}
