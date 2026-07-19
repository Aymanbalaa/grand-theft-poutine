# Map bounding box (south, west, north, east) — downtown core + Old Port + Habitat 67 + Biosphere
BBOX = (45.488, -73.582, 45.520, -73.525)
# Local origin (lat, lon) — near Place Ville Marie
ORIGIN = (45.504, -73.5535)
TILE_SIZE = 256.0

ROAD_WIDTHS = {
    "motorway": 14.0, "trunk": 12.0, "primary": 10.0, "secondary": 8.0,
    "tertiary": 7.0, "residential": 6.0, "unclassified": 5.0, "service": 4.0,
    "pedestrian": 5.0, "footway": 2.0, "cycleway": 2.5, "living_street": 5.0,
    "motorway_link": 8.0, "trunk_link": 8.0, "primary_link": 7.0, "secondary_link": 6.0,
}
DEFAULT_ROAD_WIDTH = 6.0
LEVEL_HEIGHT = 3.2
DEFAULT_BUILDING_HEIGHT = 10.0
MAX_TILE_TRIS = 120000
