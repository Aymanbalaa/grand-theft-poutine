from __future__ import annotations
import math
from pipeline import config

def manhole_spots(roads, hm=None) -> list[dict]:
    """Deterministic manhole positions: sampled along named roads, alternating
    lane offset, capped by radius and count. Mirrors cars.car_spawns."""
    spots: list[dict] = []
    eligible = (r for r in roads
                if r.name and r.road_class in config.CAR_SPAWN_CLASSES)
    for r in sorted(eligible, key=lambda r: (r.name, r.osm_id)):
        lane = r.width / 4.0
        carry = config.MANHOLE_SPACING / 2.0
        for (x1, z1), (x2, z2) in zip(r.points[:-1], r.points[1:]):
            seg = math.hypot(x2 - x1, z2 - z1)
            if seg < 1e-6:
                continue
            dx, dz = (x2 - x1) / seg, (z2 - z1) / seg
            t = carry
            while t < seg:
                x, z = x1 + dx * t, z1 + dz * t
                t += config.MANHOLE_SPACING
                if math.hypot(x, z) > config.MANHOLE_RADIUS:
                    continue
                side = lane if (len(spots) % 2 == 0) else -lane
                sx, sz = x - dz * side, z + dx * side
                y = (hm.sample(sx, sz) if hm is not None else 0.0)
                spots.append({"x": round(sx, 2), "y": round(y, 2), "z": round(sz, 2)})
                if len(spots) >= config.MAX_MANHOLES:
                    return spots
            carry = t - seg
    return spots
