import io
import json
import zipfile
from pathlib import Path
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
    ensure_textures(cache_dir=tmp_path / "c", out_dir=tmp_path / "o", fetch=_fetch_ok)
    lock = json.loads((tmp_path / "c" / "textures.lock.json").read_text())
    for slot in config.TEXTURE_SLOTS:
        assert len(lock[slot]["sha256"]) == 64
