import math
from pipeline import config

M_PER_DEG_LAT = 110574.0
M_PER_DEG_LON_EQUATOR = 111320.0

def latlon_to_xz(lat: float, lon: float) -> tuple[float, float]:
    """Project WGS84 to local meters. x = east, z = SOUTH (Godot: north = -Z)."""
    olat, olon = config.ORIGIN
    x = (lon - olon) * M_PER_DEG_LON_EQUATOR * math.cos(math.radians(olat))
    z = -(lat - olat) * M_PER_DEG_LAT
    return x, z
