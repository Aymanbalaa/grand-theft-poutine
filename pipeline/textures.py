from __future__ import annotations
import hashlib
import json
import time
import urllib.request
import zipfile
from pathlib import Path
from pipeline import config

_MAP_SUFFIX = {"Color": "alb", "NormalGL": "nrm", "Roughness": "rgh", "Opacity": "op"}

def _zip_name(asset_id: str, res: str, fmt: str) -> str:
    """Cache zip filename. JPG (the historical default) keeps the original
    bare `{id}_{res}.zip` shape so existing lock/cache files stay valid;
    other formats append `-{fmt}` to disambiguate."""
    return f"{asset_id}_{res}.zip" if fmt == "JPG" else f"{asset_id}_{res}-{fmt}.zip"

def _default_fetch(url: str) -> bytes:
    last: Exception | None = None
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "mtl-open-ile-pipeline"})
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001 - retry any transport error
            last = e
            time.sleep(2.0 * (attempt + 1))
    raise RuntimeError(f"download failed after retries: {url}") from last

def _resolve_id(slot: str, spec: dict, fetch) -> str:
    res = spec.get("res", "1K")
    fmt = spec.get("fmt", "JPG")
    probe = config.AMBIENTCG_DL.format(id=spec["preferred"], res=res, fmt=fmt)
    try:
        head = fetch(probe)
        if head:
            return spec["preferred"]
    except Exception:
        pass
    listing = json.loads(fetch(config.AMBIENTCG_API.format(q=spec["query"].replace(" ", "+"))).decode())
    assets = listing.get("foundAssets", [])
    if not assets:
        raise RuntimeError(f"no ambientCG asset found for slot {slot!r} (query {spec['query']!r})")
    return assets[0]["assetId"]

def ensure_textures(cache_dir="data/textures", out_dir="game/assets/textures/pbr",
                    fetch=None) -> dict[str, str]:
    """Fetch/caches ambientCG 1K-JPG zips and extract the requested maps.

    Cache zip + lock entry present -> no network. `fetch(url) -> bytes` is
    injectable for tests; the probe download doubles as the preferred-id
    existence check, so a cache hit costs zero requests.
    """
    cache = Path(cache_dir)
    out = Path(out_dir)
    cache.mkdir(parents=True, exist_ok=True)
    out.mkdir(parents=True, exist_ok=True)
    fetch = fetch or _default_fetch
    lock_path = cache / "textures.lock.json"
    lock: dict = json.loads(lock_path.read_text()) if lock_path.exists() else {}
    ids: dict[str, str] = {}
    for slot, spec in sorted(config.TEXTURE_SLOTS.items()):
        res = spec.get("res", "1K")
        fmt = spec.get("fmt", "JPG")
        ext = fmt.lower()
        entry = lock.get(slot)
        zpath = cache / _zip_name(entry["id"], entry.get("res", "1K"), entry.get("fmt", "JPG")) if entry else None
        if (entry and entry.get("preferred") == spec["preferred"]
                and entry.get("res", "1K") == res and entry.get("fmt", "JPG") == fmt
                and zpath.exists()
                and hashlib.sha256(zpath.read_bytes()).hexdigest() == entry["sha256"]):
            asset_id = entry["id"]
        else:
            asset_id = spec["preferred"]
            try:
                blob = fetch(config.AMBIENTCG_DL.format(id=asset_id, res=res, fmt=fmt))
            except Exception:
                asset_id = _resolve_id(slot, spec, fetch)
                blob = fetch(config.AMBIENTCG_DL.format(id=asset_id, res=res, fmt=fmt))
            zpath = cache / _zip_name(asset_id, res, fmt)
            zpath.write_bytes(blob)
            lock[slot] = {"id": asset_id, "sha256": hashlib.sha256(blob).hexdigest(),
                          "url": config.AMBIENTCG_DL.format(id=asset_id, res=res, fmt=fmt),
                          "preferred": spec["preferred"], "res": res, "fmt": fmt}
            lock_path.write_text(json.dumps(lock, indent=1, sort_keys=True))
        ids[slot] = asset_id
        with zipfile.ZipFile(zpath) as z:
            names = z.namelist()
            written: dict[str, Path] = {}
            for m in spec["maps"]:
                match = next((n for n in names if n.endswith(f"_{m}.{ext}")), None)
                if match is None:
                    raise RuntimeError(f"{asset_id}: map {m} missing from zip ({names})")
                dest = out / f"{slot}_{_MAP_SUFFIX[m]}.{ext}"
                dest.write_bytes(z.read(match))
                written[m] = dest
            if spec.get("compose_alpha"):
                from PIL import Image
                rgba = Image.open(written["Color"]).convert("RGB")
                opacity = Image.open(written["Opacity"]).convert("L")
                rgba.putalpha(opacity.resize(rgba.size))
                rgba.save(out / f"{slot}_alb.{ext}")
                written["Opacity"].unlink()
    return ids
