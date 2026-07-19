from __future__ import annotations
import argparse
from pathlib import Path
from pipeline.download import fetch_osm
from pipeline.osm_parse import parse_osm
from pipeline.export import export_city

def main() -> None:
    ap = argparse.ArgumentParser(description="Build MTL Open Ile city tiles")
    ap.add_argument("--input", default=None, help="OSM XML path (default: cached download)")
    ap.add_argument("--out", default="game/world", help="output directory")
    args = ap.parse_args()
    xml = Path(args.input) if args.input else fetch_osm()
    city = parse_osm(xml)
    print(f"parsed: {len(city.roads)} roads, {len(city.buildings)} buildings, {len(city.areas)} areas")
    meta = export_city(city, args.out)
    print(f"exported {len(meta['tiles'])} tiles, {len(meta['streets'])} named streets -> {args.out}")

if __name__ == "__main__":
    main()
