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
ROOF_GABLE_COLOR = (104, 66, 54)  # dark shingle for gabled residential roofs

# --- Terrain ---
TERRAIN_STEP = 8.0            # heightmap grid spacing (m)
TERRAIN_TILE_QUADS = 32       # terrain quads per tile edge (32 -> 2048 tris/tile)
TERRAIN_COLOR_LOW = (150, 146, 138)   # urban ground
TERRAIN_COLOR_HIGH = (96, 124, 82)    # wooded slopes
TERRAIN_COLOR_BLEND = (45.0, 110.0)   # y-range over which low blends to high (downtown stays urban)
TERRAIN_WATER_DROP = 3.0      # terrain depression under water polygons (m)
TERRAIN_WATER_COLOR = (52, 84, 104)
MONT_ROYAL_SUMMIT = (45.5063, -73.5872)  # just west of bbox; east flank is in-map

# --- Hero landmarks (true coords; clear = radius m of auto-buildings removed) ---
# Coordinates verified against data/osm_downtown.osm.xml (Task 8 Step 1):
#   pvm, notre_dame: brief defaults confirmed within ~0.0005 deg of OSM centroids
#     (pvm: unnamed building height=188.1m at 45.5016,-73.56866 matches PVM's tower height;
#      notre_dame: "Basilique Notre-Dame" at 45.50447,-73.55622).
#   biosphere, habitat67: replaced with OSM centroids (differed >0.0005 deg from brief defaults):
#     "Biosphère" way centroid 45.51411,-73.53146; "Habitat '67" way centroid 45.49987,-73.54365.
#   five_roses: no OSM match for "Five Roses"/"Farine" in the cached extract; brief default kept.
LANDMARKS = [
    {"key": "pvm",        "name": "Place Ville Marie",      "lat": 45.5017, "lon": -73.5685, "clear": 70},
    {"key": "notre_dame", "name": "Basilique Notre-Dame",   "lat": 45.5045, "lon": -73.5562, "clear": 55},
    {"key": "biosphere",  "name": "Biosphère",              "lat": 45.51411, "lon": -73.53146, "clear": 55},
    {"key": "habitat67",  "name": "Habitat 67",             "lat": 45.49987, "lon": -73.54365, "clear": 90},
    {"key": "five_roses", "name": "Farine Five Roses",      "lat": 45.4922, "lon": -73.5545, "clear": 60},
]

# --- M3.5 Task 3: street trees & lamps ---
MAX_TREES_PER_TILE = 300
TREE_CANOPY_COLORS = ((58, 110, 52), (74, 124, 58))
TREE_TRUNK_COLOR = (92, 64, 40)
LAMP_POLE_COLOR = (70, 72, 76)
LAMP_HEAD_COLOR = (255, 214, 130)

# --- Street-name HUD ---
STREET_GRID_CELL = 64.0
# Rough district boxes (s, w, n, e); first match wins, specific before general.
DISTRICTS = [
    {"name": "Vieux-Montréal",           "box": (45.5025, -73.5620, 45.5125, -73.5495)},
    {"name": "Vieux-Port",               "box": (45.4980, -73.5560, 45.5090, -73.5430)},
    {"name": "Quartier des Spectacles",  "box": (45.5055, -73.5700, 45.5125, -73.5620)},
    {"name": "Milton-Parc",              "box": (45.5055, -73.5820, 45.5200, -73.5700)},
    {"name": "Griffintown",              "box": (45.4880, -73.5745, 45.4930, -73.5530)},
    {"name": "Parc Jean-Drapeau",        "box": (45.5010, -73.5430, 45.5200, -73.5250)},
    {"name": "Centre-Ville",             "box": (45.4880, -73.5820, 45.5055, -73.5430)},
]

# --- M5 parked cars ---
CAR_SPAWN_CLASSES = ("primary", "secondary", "tertiary", "residential")
CAR_SPAWN_RADIUS = 700.0      # meters from origin — downtown only
CAR_SPAWN_SPACING = 90.0      # arclength between candidates along a road
CAR_SPAWN_MIN_GAP = 25.0      # min distance between any two accepted spawns
MAX_CAR_SPAWNS = 120

# --- M6a Task 2: category-coded wall vertex alpha (facade shader selection) ---
WALL_CATEGORY_ALPHA = {"residential": 0, "commercial": 1, "church": 2,
                       "industrial": 3, "civic": 4, "default": 5}

# --- M6a textures (ambientCG, CC0). preferred id first, API search query as fallback. ---
TEXTURE_SLOTS = {
    "brick":    {"preferred": "Bricks059",        "query": "red brick",        "maps": ["Color"]},
    "stone":    {"preferred": "Bricks075A",       "query": "stone bricks wall","maps": ["Color"]},
    "concrete": {"preferred": "Concrete034",      "query": "concrete",         "maps": ["Color"]},
    "roof":     {"preferred": "Gravel022",        "query": "gravel",           "maps": ["Color"]},
    "asphalt":  {"preferred": "Road012A",         "query": "asphalt",          "maps": ["Color", "NormalGL", "Roughness"]},
    "paving":   {"preferred": "PavingStones128",  "query": "concrete paving",  "maps": ["Color", "NormalGL", "Roughness"]},
    "ground":   {"preferred": "Ground037",        "query": "dirt ground",      "maps": ["Color", "NormalGL", "Roughness"]},
}
AMBIENTCG_DL = "https://ambientcg.com/get?file={id}_1K-JPG.zip"
AMBIENTCG_API = "https://ambientcg.com/api/v2/full_json?type=Material&include=downloadData&q={q}"

# --- M6a sidewalks & road markings ---
SIDEWALK_CLASSES = ("primary", "secondary", "tertiary", "residential", "unclassified")
SIDEWALK_WIDTH = 2.0
SIDEWALK_RAISE = 0.12
CURB_RUN = 0.18            # horizontal run of the curb face (~33 deg -> climbable)
SIDEWALK_END_TRIM = 8.0    # skip near way ends = intersection clearance
SIDEWALK_COLOR = (168, 164, 156)

ROADMARK_CLASSES = ("primary", "secondary", "tertiary", "residential")
EDGE_LINE_CLASSES = ("primary", "secondary")
MARK_DASH = 3.0
MARK_PERIOD = 9.0
MARK_WIDTH = 0.15
MARK_LIFT = 0.02
MARK_YELLOW = (196, 164, 48)
MARK_WHITE = (208, 208, 204)
