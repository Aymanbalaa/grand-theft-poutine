import trimesh
from pathlib import Path
from pipeline import config
from pipeline.landmarks import BUILDERS, export_landmarks
from pipeline.export import _without_landmark_buildings

def test_all_landmarks_have_builders():
    assert set(BUILDERS) == {lm["key"] for lm in config.LANDMARKS}

def test_builder_heights():
    def top(key):
        m = trimesh.util.concatenate(BUILDERS[key](0.0))
        return m.bounds[1][1]
    assert 180.0 <= top("pvm") <= 200.0
    assert 60.0 <= top("notre_dame") <= 80.0
    assert all(len(m.visual.vertex_colors) == len(m.vertices)
               for m in BUILDERS["habitat67"](0.0))

def test_export_landmarks_writes_glbs(tmp_path):
    entries = export_landmarks(tmp_path, hm=None)
    assert len(entries) == len(config.LANDMARKS)
    for e in entries:
        assert (tmp_path / e["file"]).exists()
        assert isinstance(e["x"], float) and isinstance(e["z"], float)

def test_landmark_buildings_excluded(monkeypatch, tmp_path):
    from pipeline.osm_parse import parse_osm
    from pipeline.export import export_city
    FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"
    city = parse_osm(FIX)
    n_before = len(city.buildings)
    # anchor on top of fixture building 102 (nodes ~45.5046, -73.55425)
    monkeypatch.setattr(config, "LANDMARKS",
        [{"key": "pvm", "name": "t", "lat": 45.5046, "lon": -73.55425, "clear": 60}])
    meta = export_city(city, tmp_path)
    assert len(meta["landmarks"]) == 1
    # export_city must not mutate the caller's CityData
    assert len(city.buildings) == n_before
    # the exclusion itself is verified via the non-mutating helper
    filtered = _without_landmark_buildings(city)
    assert len(filtered.buildings) == n_before - 1
