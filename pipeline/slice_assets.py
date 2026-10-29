"""Fetch the CC0 Poly Haven assets used by the Rue Saint-Paul vertical slice.

Run: .venv/Scripts/python -m pipeline.slice_assets
Everything lands in game/assets/slice/ (textures, glTF models, HDRIs, people)
and is hash-verified (Poly Haven md5s from its files API; pinned sha256 for the
Quaternius characters); files already on disk with the right hash are skipped.
All assets are CC0. The downloads are gitignored: run this after cloning.
"""
from __future__ import annotations

import hashlib
import json
import time
import urllib.request
from pathlib import Path

API = "https://api.polyhaven.com/files/{id}"
OUT = Path("game/assets/slice")

# slot -> (polyhaven id, resolution). Maps: diffuse, GL normal, ARM (ao/rough/metal).
TEXTURES = {
    "cobble": ("cobblestone_floor_001", "2k"),
    "greystone": ("stone_wall_05", "2k"),
    "rubble": ("old_stone_wall", "1k"),
    "redbrick": ("red_brick_03", "2k"),
    "sandstone": ("sandstone_blocks_05", "1k"),
    "sidewalk": ("granite_tile_04", "1k"),
    "slate": ("roof_slates_03", "1k"),
    "wood": ("wood_peeling_paint_weathered", "1k"),
}
HEIGHT_MAPS = {"cobble"}  # also pull Displacement (drives puddles in the gaps)

MODELS = [
    "street_lamp_02", "outdoor_table_chair_set_01", "planter_box_01", "potted_plant_02",
    "fire_hydrant", "metal_trash_can", "painted_wooden_bench",
    "wine_barrel_01", "wooden_crate_02", "covered_car", "shrub_02", "Lantern_01",
    "round_wooden_table_01", "bar_chair_round_01", "utility_box_01",
]
HDRIS = {"sky": ("rooftop_night", "2k"), "night": ("cobblestone_street_night", "1k")}

# Quaternius (CC0) animated characters, mirrored on poly.pizza. name -> (page id, glb, sha256)
PEOPLE = {
    "casual_man": ("kZ3DmIoGip", "90a9e2d4-053f-42f1-99a2-8f5e1180ea7f", "fea7e71271203e7073f1a073fa1208de7402df276f87f80e149bf7589b5d46b4"),
    "woman_red": ("9kF7eTDbhO", "cf08b740-dd48-443e-9fde-6d3d54abf119", "97a4e8c5e93b5c4f68b25e5240f308aa81ff4ae487b750e62f13e02c338d73e8"),
    "woman_green": ("nIItLV9nxS", "46d6db5a-3c9f-4238-8cdf-8eb7194498dc", "a6522fe53d15de21130a957d1bf2b8a9a58d4e4e9a12af646645b667a9bb2d17"),
    "woman_white": ("qJ2gsTUBHL", "ba7a1955-ea51-4cb9-a561-188bdef0a6c7", "a2212729826b718e59e698211ed3951c22459b48733b1ee6a24fac0abf74dca8"),
    "man_tshirt": ("HMnuH5geEG", "3746be88-6799-4817-929b-6bc067c47caa", "dad8fa3ca2bc7760892f9ff47f544941179e50acb2aa772cf9f035154a37fc58"),
    "adventurer": ("5EGWBMpuXq", "bbe369ee-a686-42c7-adad-14356f5f2f15", "4a8639cd8eee9d8a150464edc25eb0536ced464790704a64e40c8620d99f66db"),
}


def _get(url: str) -> bytes:
    last: Exception | None = None
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "mtl-open-ile-slice"})
            with urllib.request.urlopen(req, timeout=60) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001 - retry any transport error
            last = e
            time.sleep(2.0 * (attempt + 1))
    raise RuntimeError(f"download failed: {url}") from last


def _fetch(url: str, md5: str, dest: Path) -> None:
    if dest.exists() and hashlib.md5(dest.read_bytes()).hexdigest() == md5:
        return
    blob = _get(url)
    if hashlib.md5(blob).hexdigest() != md5:
        raise RuntimeError(f"md5 mismatch: {url}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(blob)
    print(f"  {dest} ({len(blob) // 1024} KB)")


def main() -> None:
    lock: dict[str, str] = {}
    for slot, (pid, res) in TEXTURES.items():
        files = json.loads(_get(API.format(id=pid)))
        maps = {"Diffuse": "alb", "nor_gl": "nrm", "arm": "arm"}
        if slot in HEIGHT_MAPS:
            maps["Displacement"] = "hgt"
        for key, suffix in maps.items():
            f = files[key][res]["jpg" if key != "Displacement" else "png"]
            ext = "png" if key == "Displacement" else "jpg"
            _fetch(f["url"], f["md5"], OUT / "tex" / f"{slot}_{suffix}.{ext}")
        lock[f"tex/{slot}"] = f"{pid}@{res}"
    for pid in MODELS:
        g = json.loads(_get(API.format(id=pid)))["gltf"]["1k"]["gltf"]
        d = OUT / "models" / pid
        _fetch(g["url"], g["md5"], d / f"{pid}.gltf")
        for rel, inc in g["include"].items():
            _fetch(inc["url"], inc["md5"], d / rel)
        lock[f"models/{pid}"] = f"{pid}@1k"
    for slot, (pid, res) in HDRIS.items():
        f = json.loads(_get(API.format(id=pid)))["hdri"][res]["hdr"]
        _fetch(f["url"], f["md5"], OUT / "hdri" / f"{slot}.hdr")
        lock[f"hdri/{slot}"] = f"{pid}@{res}"
    for name, (page, uuid, sha) in PEOPLE.items():
        dest = OUT / "models" / "people" / f"{name}.glb"
        if not (dest.exists() and hashlib.sha256(dest.read_bytes()).hexdigest() == sha):
            blob = _get(f"https://static.poly.pizza/{uuid}.glb")
            if hashlib.sha256(blob).hexdigest() != sha:
                raise RuntimeError(f"sha256 mismatch: {name}")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(blob)
            print(f"  {dest} ({len(blob) // 1024} KB)")
        lock[f"people/{name}"] = f"quaternius via https://poly.pizza/m/{page}"
    (OUT / "SOURCE.json").write_text(json.dumps(lock, indent=1, sort_keys=True) + "\n")
    write_import_stubs()
    print("slice assets OK:", len(lock))


_IMPORT_STUB = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode={mode}
compress/normal_map={normal}
mipmaps/generate=true
process/hdr_as_srgb=false
detect_3d/compress_to=0
"""


def write_import_stubs() -> None:
    """Godot's 2D-texture defaults (no mipmaps, lossless) shimmer badly on 3D
    surfaces. Textures here are loaded from code, so the importer's 3D
    auto-detection never fires: pin mipmapped VRAM import settings up front.
    Godot fills in uid/dest on first import; existing stubs are left alone."""
    for p in sorted((OUT / "tex").glob("*.*")) + sorted((OUT / "hdri").glob("*.hdr")):
        if p.suffix == ".import":
            continue
        stub = p.with_name(p.name + ".import")
        if stub.exists():
            continue
        mode = 0 if p.suffix == ".hdr" or p.stem.endswith("_hgt") else 2
        stub.write_text(_IMPORT_STUB.format(mode=mode, normal=1 if p.stem.endswith("_nrm") else 0))


if __name__ == "__main__":
    main()
