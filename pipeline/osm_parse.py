from __future__ import annotations
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from pipeline import config
from pipeline.geo import latlon_to_xz

@dataclass
class Road:
    osm_id: int
    name: str | None
    points: list[tuple[float, float]]
    width: float

@dataclass
class Building:
    osm_id: int
    footprint: list[tuple[float, float]]
    height: float

@dataclass
class Area:
    osm_id: int
    kind: str  # "water" | "green"
    outline: list[tuple[float, float]]

@dataclass
class CityData:
    roads: list[Road] = field(default_factory=list)
    buildings: list[Building] = field(default_factory=list)
    areas: list[Area] = field(default_factory=list)

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

def parse_osm(xml_path: str | Path) -> CityData:
    nodes: dict[int, tuple[float, float]] = {}
    city = CityData()
    for _, el in ET.iterparse(str(xml_path), events=("end",)):
        if el.tag == "node":
            nodes[int(el.get("id"))] = (float(el.get("lat")), float(el.get("lon")))
        elif el.tag == "way":
            wid = int(el.get("id"))
            tags = {t.get("k"): t.get("v") for t in el.findall("tag")}
            refs = [int(nd.get("ref")) for nd in el.findall("nd")]
            pts = [latlon_to_xz(*nodes[r]) for r in refs if r in nodes]
            if len(pts) >= 2 and "highway" in tags:
                width = config.ROAD_WIDTHS.get(tags["highway"], config.DEFAULT_ROAD_WIDTH)
                city.roads.append(Road(wid, tags.get("name"), pts, width))
            elif len(pts) >= 4 and refs[0] == refs[-1]:
                ring = pts[:-1]
                if "building" in tags:
                    city.buildings.append(Building(wid, ring, _building_height(tags)))
                else:
                    kind = _area_kind(tags)
                    if kind:
                        city.areas.append(Area(wid, kind, ring))
        if el.tag in ("node", "way"):
            el.clear()
    city.roads.sort(key=lambda r: r.osm_id)
    city.buildings.sort(key=lambda b: b.osm_id)
    city.areas.sort(key=lambda a: a.osm_id)
    return city
