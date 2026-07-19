import math
from pipeline.geo import latlon_to_xz
from pipeline import config

def test_origin_maps_to_zero():
    x, z = latlon_to_xz(*config.ORIGIN)
    assert abs(x) < 1e-6 and abs(z) < 1e-6

def test_north_is_negative_z():
    _, z = latlon_to_xz(config.ORIGIN[0] + 0.01, config.ORIGIN[1])
    assert z < -1000  # ~1.11 km north => z ≈ -1110

def test_east_is_positive_x_scaled_by_latitude():
    x, _ = latlon_to_xz(config.ORIGIN[0], config.ORIGIN[1] + 0.01)
    expected = 0.01 * 111320.0 * math.cos(math.radians(config.ORIGIN[0]))
    assert abs(x - expected) < 1.0
