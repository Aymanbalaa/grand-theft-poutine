import hashlib
import io
import json
import zipfile
from pathlib import Path
import pytest
from pipeline import config
from pipeline.textures import ensure_textures

def _fake_zip(asset_id: str) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for m in ("Color", "NormalGL", "Roughness"):
            z.writestr(f"{asset_id}_1K-JPG_{m}.jpg", b"\xff\xd8\xff fake " + m.encode())
    return buf.getvalue()

def _fetch_ok(url: str) -> bytes:
    for slot, spec in config.TEXTURE_SLOTS.items():
        if spec["preferred"] in url:
            return _fake_zip(spec["preferred"])
    raise AssertionError("unexpected url " + url)

def test_extracts_requested_maps(tmp_path):
    out = tmp_path / "out"
    ids = ensure_textures(cache_dir=tmp_path / "cache", out_dir=out, fetch=_fetch_ok)
    assert ids["asphalt"] == config.TEXTURE_SLOTS["asphalt"]["preferred"]
    assert (out / "asphalt_alb.jpg").exists()
    assert (out / "asphalt_nrm.jpg").exists()
    assert (out / "asphalt_rgh.jpg").exists()
    assert (out / "brick_alb.jpg").exists()
    assert not (out / "brick_nrm.jpg").exists()  # only requested maps extracted

def test_cache_hit_skips_network(tmp_path):
    calls = []
    def counting_fetch(url):
        calls.append(url)
        return _fetch_ok(url)
    ensure_textures(cache_dir=tmp_path / "c", out_dir=tmp_path / "o", fetch=counting_fetch)
    n = len(calls)
    assert n == len(config.TEXTURE_SLOTS)
    def failing_fetch(url):
        raise AssertionError("network touched on cache hit")
    ensure_textures(cache_dir=tmp_path / "c", out_dir=tmp_path / "o2", fetch=failing_fetch)
    assert (tmp_path / "o2" / "asphalt_alb.jpg").exists()

def test_lock_records_sha256(tmp_path):
    cache_dir = tmp_path / "c"
    ensure_textures(cache_dir=cache_dir, out_dir=tmp_path / "o", fetch=_fetch_ok)
    lock = json.loads((cache_dir / "textures.lock.json").read_text())
    for slot in config.TEXTURE_SLOTS:
        assert len(lock[slot]["sha256"]) == 64
    entry = lock["asphalt"]
    zpath = cache_dir / f"{entry['id']}.zip"
    assert entry["sha256"] == hashlib.sha256(zpath.read_bytes()).hexdigest()

def test_preferred_change_invalidates_cache(tmp_path, monkeypatch):
    ensure_textures(cache_dir=tmp_path / "c", out_dir=tmp_path / "o", fetch=_fetch_ok)
    monkeypatch.setitem(config.TEXTURE_SLOTS, "brick",
                         {**config.TEXTURE_SLOTS["brick"], "preferred": "BricksZZZ"})

    def fetch(url):
        if "BricksZZZ" in url:
            return _fake_zip("BricksZZZ")
        return _fetch_ok(url)

    ids = ensure_textures(cache_dir=tmp_path / "c", out_dir=tmp_path / "o", fetch=fetch)
    assert ids["brick"] == "BricksZZZ"
    assert b"Color" in (tmp_path / "o" / "brick_alb.jpg").read_bytes()
    lock = json.loads((tmp_path / "c" / "textures.lock.json").read_text())
    assert lock["brick"]["id"] == "BricksZZZ"

def test_api_fallback_when_preferred_missing(tmp_path):
    roof_preferred = config.TEXTURE_SLOTS["roof"]["preferred"]

    def fetch(url):
        if roof_preferred in url and "api/v2/full_json" not in url:
            raise RuntimeError("preferred download failed")
        if "api/v2/full_json" in url:
            return json.dumps({"foundAssets": [{"assetId": "FallbackX"}]}).encode()
        if "FallbackX" in url:
            return _fake_zip("FallbackX")
        return _fetch_ok(url)

    ids = ensure_textures(cache_dir=tmp_path / "c", out_dir=tmp_path / "o", fetch=fetch)
    assert ids["roof"] == "FallbackX"
    lock = json.loads((tmp_path / "c" / "textures.lock.json").read_text())
    assert lock["roof"]["id"] == "FallbackX"

def test_missing_map_raises(tmp_path):
    def fetch(url):
        if config.TEXTURE_SLOTS["asphalt"]["preferred"] in url:
            buf = io.BytesIO()
            with zipfile.ZipFile(buf, "w") as z:
                for m in ("Color", "NormalGL"):
                    z.writestr(f"Asphalt_1K-JPG_{m}.jpg", b"\xff\xd8\xff fake " + m.encode())
            return buf.getvalue()
        return _fetch_ok(url)

    with pytest.raises(RuntimeError, match="Roughness"):
        ensure_textures(cache_dir=tmp_path / "c", out_dir=tmp_path / "o", fetch=fetch)

def test_fallback_then_cache_hit(tmp_path):
    calls = []
    def fb_fetch(url):
        calls.append(url)
        if "FallbackY" in url:
            return _fake_zip("FallbackY")
        if config.TEXTURE_SLOTS["roof"]["preferred"] in url:
            raise RuntimeError("preferred gone")
        if "api/v2/full_json" in url:
            return json.dumps({"foundAssets": [{"assetId": "FallbackY"}]}).encode()
        return _fetch_ok(url)
    ids = ensure_textures(cache_dir=tmp_path / "c", out_dir=tmp_path / "o", fetch=fb_fetch)
    assert ids["roof"] == "FallbackY"
    assert len(calls) >= len(config.TEXTURE_SLOTS)  # fallback path cost extra calls
    def no_net(url):
        raise AssertionError("network touched on fallback cache hit: " + url)
    ids2 = ensure_textures(cache_dir=tmp_path / "c", out_dir=tmp_path / "o2", fetch=no_net)
    assert ids2["roof"] == "FallbackY"
