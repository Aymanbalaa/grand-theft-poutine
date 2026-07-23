from __future__ import annotations
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from shapely.geometry import Polygon, box
from shapely.ops import unary_union
from pipeline import config
from pipeline.geo import latlon_to_xz

@dataclass
class Road:
    osm_id: int
    name: str | None
    points: list[tuple[float, float]]
    width: float
    road_class: str = "residential"
    oneway: bool = False

@dataclass
class Building:
    osm_id: int
    footprint: list[tuple[float, float]]
    height: float
    btype: str = "yes"

@dataclass
class Area:
    osm_id: int
    kind: str  # "water" | "green"
    outline: list[tuple[float, float]]
    holes: list[list[tuple[float, float]]] = field(default_factory=list)

@dataclass
class CityData:
    roads: list[Road] = field(default_factory=list)
    buildings: list[Building] = field(default_factory=list)
    areas: list[Area] = field(default_factory=list)
    trees: list[tuple[float, float]] = field(default_factory=list)
    lamps: list[tuple[float, float]] = field(default_factory=list)
    signals: list[tuple[float, float]] = field(default_factory=list)
    benches: list[tuple[float, float]] = field(default_factory=list)
    hydrants: list[tuple[float, float]] = field(default_factory=list)

_NUM = re.compile(r"[-+]?\d*\.?\d+")

def _parse_meters(value: str) -> float | None:
    m = _NUM.search(value)
    return float(m.group()) if m else None

def _building_height(tags: dict[str, str]) -> float:
    if "height" in tags:
        h = _parse_meters(tags["height"])
        if h is not None and h > 0:
            return h
    if "building:levels" in tags:
        lv = _parse_meters(tags["building:levels"])
        if lv is not None and lv > 0:
            return lv * config.LEVEL_HEIGHT
    return config.DEFAULT_BUILDING_HEIGHT

def _area_kind(tags: dict[str, str]) -> str | None:
    if tags.get("natural") == "water" or tags.get("waterway") == "riverbank":
        return "water"
    if tags.get("leisure") in ("park", "garden") or tags.get("landuse") in ("grass", "forest", "recreation_ground"):
        return "green"
    return None

def _assemble_rings(ways: list[list[int]]) -> list[list[int]]:
    """Stitch open way ref-lists into closed rings (closing dup removed).
    Unclosable leftovers are dropped with a warning (carry-forward guard)."""
    segs = sorted((list(w) for w in ways if len(w) >= 2), key=lambda s: s[0])
    rings: list[list[int]] = []
    while segs:
        ring = segs.pop(0)
        progress = True
        while ring[0] != ring[-1] and progress:
            progress = False
            for i, s in enumerate(segs):
                if s[0] == ring[-1]:
                    ring += s[1:]; segs.pop(i); progress = True; break
                if s[-1] == ring[-1]:
                    ring += s[-2::-1]; segs.pop(i); progress = True; break
        if ring[0] == ring[-1] and len(ring) >= 4:
            rings.append(ring[:-1])
        else:
            print(f"warning: dropped unclosed multipolygon ring ({len(ring)} refs)")
    return rings

def _clip_box() -> "box":
    s, w, n, e = config.BBOX
    x1, z1 = latlon_to_xz(n, w)
    x2, z2 = latlon_to_xz(s, e)
    p = config.BBOX_PAD_M
    return box(x1 - p, z1 - p, x2 + p, z2 + p)

def _add_relation_areas(city: CityData, rel_id: int, kind: str,
                        outer_ways: list[list[int]], inner_ways: list[list[int]],
                        nodes: dict[int, tuple[float, float]]) -> None:
    def to_xz(ring: list[int]) -> list[tuple[float, float]]:
        pts = [latlon_to_xz(*nodes[r]) for r in ring if r in nodes]
        if len(pts) < len(ring):
            print(f"warning: ring in relation {rel_id} missing {len(ring) - len(pts)} nodes")
        return pts
    outers = [p for p in (to_xz(r) for r in _assemble_rings(outer_ways)) if len(p) >= 3]
    inners = [p for p in (to_xz(r) for r in _assemble_rings(inner_ways)) if len(p) >= 3]
    if not outers:
        return
    geom = unary_union([Polygon(o).buffer(0) for o in outers])
    if inners:
        geom = geom.difference(unary_union([Polygon(i).buffer(0) for i in inners]))
    geom = geom.intersection(_clip_box())
    polys = [g for g in getattr(geom, "geoms", [geom])
             if g.geom_type == "Polygon" and g.area >= 1.0]
    for i, g in enumerate(sorted(polys, key=lambda g: (-g.area, g.bounds))):
        city.areas.append(Area(
            rel_id * 1000 + i, kind,
            [(x, z) for x, z in g.exterior.coords[:-1]],
            [[(x, z) for x, z in h.coords[:-1]] for h in g.interiors],
        ))

def parse_osm(xml_path: str | Path) -> CityData:
    nodes: dict[int, tuple[float, float]] = {}
    tree_ids: dict[int, tuple[float, float]] = {}
    lamp_ids: dict[int, tuple[float, float]] = {}
    signal_ids: dict[int, tuple[float, float]] = {}
    bench_ids: dict[int, tuple[float, float]] = {}
    hydrant_ids: dict[int, tuple[float, float]] = {}
    way_refs: dict[int, list[int]] = {}
    city = CityData()
    for _, el in ET.iterparse(str(xml_path), events=("end",)):
        if el.tag == "node":
            nid = int(el.get("id"))
            nodes[nid] = (float(el.get("lat")), float(el.get("lon")))
            if el.find("tag") is not None:
                tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
                if tags.get("natural") == "tree":
                    tree_ids[nid] = nodes[nid]
                elif tags.get("highway") == "street_lamp":
                    lamp_ids[nid] = nodes[nid]
                elif tags.get("highway") == "traffic_signals":
                    signal_ids[nid] = nodes[nid]
                elif tags.get("amenity") == "bench":
                    bench_ids[nid] = nodes[nid]
                elif tags.get("emergency") == "fire_hydrant":
                    hydrant_ids[nid] = nodes[nid]
        elif el.tag == "way":
            wid = int(el.get("id"))
            tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
            refs = [int(nd.get("ref")) for nd in el.findall("nd")]
            way_refs[wid] = refs
            pts = [latlon_to_xz(*nodes[r]) for r in refs if r in nodes]
            if len(pts) >= 2 and "highway" in tags:
                width = config.ROAD_WIDTHS.get(tags["highway"], config.DEFAULT_ROAD_WIDTH)
                city.roads.append(Road(wid, tags.get("name"), pts, width, tags["highway"],
                                       tags.get("oneway") in ("yes", "true", "1", "-1")))
            elif len(pts) >= 4 and refs[0] == refs[-1]:
                ring = pts[:-1]
                if "building" in tags:
                    city.buildings.append(Building(wid, ring, _building_height(tags), tags.get("building", "yes")))
                else:
                    kind = _area_kind(tags)
                    if kind:
                        city.areas.append(Area(wid, kind, ring))
        elif el.tag == "relation":
            tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
            if tags.get("type") == "multipolygon":
                kind = _area_kind(tags)
                if kind:
                    outer_w: list[list[int]] = []
                    inner_w: list[list[int]] = []
                    for m in el.findall("member"):
                        if m.get("type") != "way":
                            continue
                        refs = way_refs.get(int(m.get("ref")))
                        if refs:
                            (inner_w if m.get("role") == "inner" else outer_w).append(refs)
                    _add_relation_areas(city, int(el.get("id")), kind, outer_w, inner_w, nodes)
        if el.tag in ("node", "way", "relation"):
            el.clear()
    city.roads.sort(key=lambda r: r.osm_id)
    city.buildings.sort(key=lambda b: b.osm_id)
    city.areas.sort(key=lambda a: a.osm_id)
    s, w, n, e = config.BBOX
    def _in_bbox(latlon: tuple) -> bool:
        return s <= latlon[0] <= n and w <= latlon[1] <= e
    # bbox-guard point props (no-op for the bbox-bounded cached extract; protects
    # future refetches from listing metadata props outside the world, like signals)
    city.trees = [latlon_to_xz(*tree_ids[i]) for i in sorted(tree_ids) if _in_bbox(tree_ids[i])]
    city.lamps = [latlon_to_xz(*lamp_ids[i]) for i in sorted(lamp_ids)]
    city.benches = [latlon_to_xz(*bench_ids[i]) for i in sorted(bench_ids) if _in_bbox(bench_ids[i])]
    city.hydrants = [latlon_to_xz(*hydrant_ids[i]) for i in sorted(hydrant_ids) if _in_bbox(hydrant_ids[i])]
    city.signals = [latlon_to_xz(*signal_ids[i]) for i in sorted(signal_ids)
                    if _in_bbox(signal_ids[i])]
    return city
