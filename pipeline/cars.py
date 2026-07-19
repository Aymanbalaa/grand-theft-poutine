from __future__ import annotations
import math
from pipeline import config

def car_spawns(roads, hm=None) -> list[dict]:
    """Deterministic parked-car poses sampled along named downtown roads.

    Cars sit on the right edge of the roadway (inside the asphalt, so tile
    collision exists under them), pointing along the sampling direction.
    """
    spawns: list[dict] = []
    eligible = (r for r in roads
                if r.name and r.road_class in config.CAR_SPAWN_CLASSES)
    for r in sorted(eligible, key=lambda r: (r.name, r.osm_id)):
        side = r.width / 2.0 - 1.1
        if side < 0.9:
            continue
        carry = config.CAR_SPAWN_SPACING / 2.0
        for (x1, z1), (x2, z2) in zip(r.points[:-1], r.points[1:]):
            seg = math.hypot(x2 - x1, z2 - z1)
            if seg < 1e-6:
                continue
            dx, dz = (x2 - x1) / seg, (z2 - z1) / seg
            t = carry
            while t < seg:
                x, z = x1 + dx * t, z1 + dz * t
                t += config.CAR_SPAWN_SPACING
                if math.hypot(x, z) > config.CAR_SPAWN_RADIUS:
                    continue
                sx, sz = x - dz * side, z + dx * side  # right-hand offset
                if any(math.hypot(sx - s["x"], sz - s["z"]) < config.CAR_SPAWN_MIN_GAP
                       for s in spawns):
                    continue
                y = (hm.sample(sx, sz) if hm is not None else 0.0) + 0.05
                spawns.append({"x": round(sx, 2), "y": round(y, 2),
                               "z": round(sz, 2),
                               "yaw": round(math.atan2(-dx, -dz), 3)})
                if len(spawns) >= config.MAX_CAR_SPAWNS:
                    return spawns
            carry = t - seg
    return spawns
