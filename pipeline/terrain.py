from __future__ import annotations
import json
import math
from dataclasses import dataclass
from pathlib import Path
import numpy as np
import requests
from pipeline import config
from pipeline.geo import latlon_to_xz

STAC_URLS = [
    "https://datacube.services.geo.ca/stac/api/search",
    "https://datacube.services.geo.ca/api/search",
]
STAC_COLLECTIONS = ["hrdem-mosaic-2m", "hrdem-mosaic-1m"]

@dataclass
class Heightmap:
    grid: np.ndarray  # [nz, nx] float32, meters relative to origin elevation
    x0: float
    z0: float
    step_x: float
    step_z: float

    def sample(self, x: float, z: float) -> float:
        nz, nx = self.grid.shape
        fx = min(max((x - self.x0) / self.step_x, 0.0), nx - 1 - 1e-9)
        fz = min(max((z - self.z0) / self.step_z, 0.0), nz - 1 - 1e-9)
        ix, iz = int(fx), int(fz)
        tx, tz = fx - ix, fz - iz
        g = self.grid
        return float(
            g[iz, ix] * (1 - tx) * (1 - tz) + g[iz, ix + 1] * tx * (1 - tz)
            + g[iz + 1, ix] * (1 - tx) * tz + g[iz + 1, ix + 1] * tx * tz
        )

    def save(self, npy_path: str | Path, meta_path: str | Path, source: str) -> None:
        np.save(str(npy_path), self.grid)
        Path(meta_path).write_text(json.dumps({
            "x0": self.x0, "z0": self.z0,
            "step_x": self.step_x, "step_z": self.step_z, "source": source,
        }, sort_keys=True), encoding="utf-8")

    @classmethod
    def load(cls, npy_path: str | Path, meta_path: str | Path) -> "Heightmap":
        meta = json.loads(Path(meta_path).read_text(encoding="utf-8"))
        return cls(np.load(str(npy_path)), meta["x0"], meta["z0"],
                   meta["step_x"], meta["step_z"])

def _grid_frame() -> tuple[float, float, float, float, int, int]:
    """Padded-bbox frame: (x0, z0, step_x, step_z, nx, nz). Row 0 = north edge."""
    s, w, n, e = config.BBOX
    pad_lat = config.BBOX_PAD_M / 110574.0
    pad_lon = config.BBOX_PAD_M / (111320.0 * math.cos(math.radians(config.ORIGIN[0])))
    x0, z0 = latlon_to_xz(n + pad_lat, w - pad_lon)
    x1, z1 = latlon_to_xz(s - pad_lat, e + pad_lon)
    nx = int((x1 - x0) / config.TERRAIN_STEP) + 1
    nz = int((z1 - z0) / config.TERRAIN_STEP) + 1
    return x0, z0, (x1 - x0) / (nx - 1), (z1 - z0) / (nz - 1), nx, nz

def synthetic_heightmap() -> Heightmap:
    x0, z0, sx_, sz_, nx, nz = _grid_frame()
    xs = x0 + np.arange(nx) * sx_
    zs = z0 + np.arange(nz) * sz_
    X, Z = np.meshgrid(xs, zs)
    mx, mz = latlon_to_xz(*config.MONT_ROYAL_SUMMIT)
    grid = 200.0 * np.exp(-((X - mx) ** 2 + (Z - mz) ** 2) / (2 * 700.0 ** 2))
    grid += -3.0 * (X + Z) / 2000.0  # gentle tilt down toward the river (SE)
    hm = Heightmap(grid.astype(np.float32), x0, z0, sx_, sz_)
    hm.grid -= hm.sample(0.0, 0.0)
    return hm

def _fetch_hrdem() -> Heightmap:
    import rasterio  # lazy: heavy optional dependency
    from rasterio.enums import Resampling
    from rasterio.vrt import WarpedVRT

    s, w, n, e = config.BBOX
    pad_lat = config.BBOX_PAD_M / 110574.0
    pad_lon = config.BBOX_PAD_M / (111320.0 * math.cos(math.radians(config.ORIGIN[0])))
    body = {"collections": None, "bbox": [w - pad_lon, s - pad_lat, e + pad_lon, n + pad_lat], "limit": 10}
    href = None
    last = None
    for url in STAC_URLS:
        for coll in STAC_COLLECTIONS:
            try:
                body["collections"] = [coll]
                feats = requests.post(url, json=body, timeout=60).json().get("features", [])
                for f in feats:
                    for key, asset in f.get("assets", {}).items():
                        if "dtm" in key.lower():
                            href = asset["href"]
                            break
                    if href:
                        break
            except Exception as exc:  # noqa: BLE001 - any failure -> next endpoint
                last = exc
            if href:
                break
        if href:
            break
    if not href:
        raise RuntimeError(f"no HRDEM DTM asset found via STAC ({last})")
    print(f"HRDEM: reading {href}")
    x0, z0, sx_, sz_, nx, nz = _grid_frame()
    with rasterio.open(href) as src, WarpedVRT(src, crs="EPSG:4326") as vrt:
        win = vrt.window(w - pad_lon, s - pad_lat, e + pad_lon, n + pad_lat)
        data = vrt.read(1, window=win, out_shape=(nz, nx),
                        resampling=Resampling.bilinear).astype(np.float32)
    valid = data > -1000.0
    if not valid.any():
        raise RuntimeError("HRDEM window contained no valid samples")
    data[~valid] = data[valid].min()
    hm = Heightmap(data, x0, z0, sx_, sz_)
    hm.grid -= hm.sample(0.0, 0.0)
    return hm

def fetch_heightmap(dest_npy: str | Path = "data/heightmap.npy",
                    dest_meta: str | Path = "data/heightmap_meta.json") -> Heightmap:
    dest_npy, dest_meta = Path(dest_npy), Path(dest_meta)
    if dest_npy.exists() and dest_meta.exists():
        print(f"cached heightmap: {dest_npy}")
        return Heightmap.load(dest_npy, dest_meta)
    dest_npy.parent.mkdir(parents=True, exist_ok=True)
    try:
        hm = _fetch_hrdem()
        source = "hrdem"
    except Exception as exc:  # noqa: BLE001 - fallback keeps the build running
        print(f"HRDEM unavailable ({exc}); using synthetic Mont Royal heightmap")
        hm = synthetic_heightmap()
        source = "synthetic"
    hm.save(dest_npy, dest_meta, source)
    print(f"heightmap saved ({source}): {hm.grid.shape}")
    return hm
