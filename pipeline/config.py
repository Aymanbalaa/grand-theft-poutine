# Map bounding box (south, west, north, east) — downtown core + Old Port + Habitat 67 + Biosphere
BBOX = (45.488, -73.582, 45.520, -73.525)
# Padding (meters) applied when clipping multipolygon relations to the bbox
BBOX_PAD_M = 100.0
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

# --- M3 visual pass: stylized Montreal palette (sRGB 0-255) ---
BUILDING_PALETTE = {
    "residential": (166, 100, 80),   # Montreal brick
    "commercial":  (141, 148, 158),  # downtown glass/steel
    "church":      (105, 100, 96),   # greystone
    "industrial":  (122, 105, 88),
    "civic":       (176, 164, 140),  # sandstone
    "default":     (168, 168, 164),
}
BUILDING_CATEGORIES = {
    "apartments": "residential", "residential": "residential", "house": "residential",
    "detached": "residential", "terrace": "residential", "dormitory": "residential",
    "retail": "commercial", "commercial": "commercial", "office": "commercial", "hotel": "commercial",
    "church": "church", "cathedral": "church", "chapel": "church", "monastery": "church",
    "industrial": "industrial", "warehouse": "industrial",
    "university": "civic", "school": "civic", "college": "civic", "hospital": "civic",
    "public": "civic", "civic": "civic", "government": "civic", "museum": "civic",
}
ROAD_COLORS = {
    "motorway": (52, 52, 56), "trunk": (52, 52, 56),
    "motorway_link": (52, 52, 56), "trunk_link": (52, 52, 56),
    "primary": (64, 64, 68), "secondary": (64, 64, 68),
    "primary_link": (64, 64, 68), "secondary_link": (64, 64, 68),
    "pedestrian": (150, 140, 124), "footway": (150, 140, 124), "cycleway": (96, 116, 96),
}
DEFAULT_ROAD_COLOR = (78, 78, 82)
AREA_COLORS = {"water": (62, 110, 138), "green": (88, 132, 76)}

# --- Terrain ---
TERRAIN_STEP = 8.0            # heightmap grid spacing (m)
TERRAIN_TILE_QUADS = 32       # terrain quads per tile edge (32 -> 2048 tris/tile)
TERRAIN_COLOR_LOW = (150, 146, 138)   # urban ground
TERRAIN_COLOR_HIGH = (96, 124, 82)    # wooded slopes
TERRAIN_COLOR_BLEND = (25.0, 90.0)    # y-range over which low blends to high
TERRAIN_WATER_DROP = 3.0      # terrain depression under water polygons (m)
TERRAIN_WATER_COLOR = (52, 84, 104)
MONT_ROYAL_SUMMIT = (45.5063, -73.5872)  # just west of bbox; east flank is in-map
