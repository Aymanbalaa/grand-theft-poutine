import numpy as np
from pipeline.terrain import Heightmap, synthetic_heightmap

def test_sample_bilinear_and_clamp():
    hm = Heightmap(grid=np.array([[0.0, 10.0], [20.0, 30.0]], dtype=np.float32),
                   x0=0.0, z0=0.0, step_x=10.0, step_z=10.0)
    assert hm.sample(0.0, 0.0) == 0.0
    assert hm.sample(10.0, 10.0) == 30.0
    assert abs(hm.sample(5.0, 0.0) - 5.0) < 1e-5
    assert abs(hm.sample(5.0, 5.0) - 15.0) < 1e-5
    assert hm.sample(-100.0, -100.0) == 0.0     # clamped
    assert hm.sample(1000.0, 1000.0) == 30.0    # clamped

def test_synthetic_mont_royal():
    from pipeline.geo import latlon_to_xz
    hm = synthetic_heightmap()
    assert abs(hm.sample(0.0, 0.0)) < 1.0          # downtown ~0
    sx, sz = latlon_to_xz(45.5063, -73.5872)
    assert hm.sample(sx, sz) > 100.0                # mountain flank high

def test_save_load_roundtrip(tmp_path):
    hm = synthetic_heightmap()
    hm.save(tmp_path / "h.npy", tmp_path / "h.json", source="synthetic")
    hm2 = Heightmap.load(tmp_path / "h.npy", tmp_path / "h.json")
    assert np.array_equal(hm.grid, hm2.grid)
    assert hm2.sample(100.0, 100.0) == hm.sample(100.0, 100.0)
