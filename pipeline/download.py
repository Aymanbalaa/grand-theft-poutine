from __future__ import annotations
import time
from pathlib import Path
import requests
from pipeline import config

# Public Overpass endpoints, tried in order with retries: individual instances
# are routinely flaky (observed 2026-07-18/19: 406 from overpass-api.de,
# 504 from kumi.systems), so resilience matters more than any single choice.
OVERPASS_URLS = [
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]

# Some instances rate-limit requests lacking a descriptive User-Agent
# ("Please include a meaningful User-Agent string..." 429 response).
HEADERS = {"User-Agent": "MTL-Open-Ile-pipeline/1.0 (contact: aymanbalaa30@gmail.com)"}

def _query() -> str:
    s, w, n, e = config.BBOX
    bbox = f"{s},{w},{n},{e}"
    return f"""
[out:xml][timeout:300];
(
  way["highway"]({bbox});
  way["building"]({bbox});
  way["natural"="water"]({bbox});
  way["waterway"="riverbank"]({bbox});
  way["leisure"~"park|garden"]({bbox});
  way["landuse"~"grass|forest|recreation_ground"]({bbox});
);
(._;>;);
out body;
"""

def fetch_osm(dest: str | Path = "data/osm_downtown.osm.xml") -> Path:
    dest = Path(dest)
    if dest.exists() and dest.stat().st_size > 1000:
        print(f"cached: {dest}")
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    last_error: Exception | None = None
    for attempt in range(6):
        url = OVERPASS_URLS[attempt % len(OVERPASS_URLS)]
        print(f"downloading from {url} (attempt {attempt + 1}, may take a couple of minutes)...")
        try:
            resp = requests.post(url, data={"data": _query()}, headers=HEADERS, timeout=600)
            resp.raise_for_status()
        except requests.RequestException as exc:
            print(f"  failed: {exc}")
            last_error = exc
            time.sleep(10 * (attempt + 1))
            continue
        dest.write_bytes(resp.content)
        print(f"saved {len(resp.content) / 1e6:.1f} MB -> {dest}")
        return dest
    raise RuntimeError(f"all Overpass endpoints failed after 6 attempts: {last_error}")
