# MTL: Open Île — Plan 5: Behind the Wheel (Milestone 5)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drive the city: parked cars spawned along downtown streets from pipeline metadata, walk up to one and press E to drive (arcade physics, chase camera, speedometer), press E again to get out.

**Architecture:** Pipeline emits deterministic `car_spawns` (position + ground y + yaw sampled along named roads near downtown) into `city_metadata.json`. Game side: a `Car` scene (CharacterBody3D arcade physics + procedural blocky visual + chase CamPivot/SpringArm rig, mirroring the Player structure), `main.gd` instantiates parked cars (physics frozen until driven) and owns the enter/exit state machine, prompt label and speedometer. Minimap marker and street HUD already track the active camera, so they follow the car for free.

**Design decision (recorded):** The car is a procedural blocky vehicle on CharacterBody3D arcade physics rather than Godot Easy Vehicle Physics + Kenney Car Kit (the spec's original pick). Same rationale as the M4 character: no network asset downloads, deterministic, license-clean, matches the blocky art style, headless-testable. Swapping in EVP/Kenney later only touches `car.tscn` internals and `car.gd` — the `Car` interface (`park/start_driving/stop_driving/speed/steer_input`) stays.

## Global Constraints

- Commit with plain `git commit` — NEVER pass `--author`, never modify git config, never add any AI trailer. Push ONLY in the final task.
- Repo root: `C:\Users\ayman\OneDrive\Documents\SideProjects\MontrealOpenWorld`; bash syntax from repo root.
- Python: `.venv/Scripts/python -m pytest pipeline -q` green at the end of every task (55 now, grows). Determinism: no random/time; ties broken by sorted order.
- Godot via `tools/godot/godot_console.exe` ONLY (the GUI exe detaches and returns no output). Smoke: `--headless --path game --script res://tests/smoke_test.gd` → currently `PLAYER OK`, `LANDED OK y=0.0`, `SMOKE OK: 314 tiles` (grows per task). GDScript uses tabs.
- Headless frame:physics ≈ 2:1 — NEVER fixed-frame physics waits in tests; poll conditions with a frame cap.
- Do NOT delete `data/` caches (OSM + heightmap both current; heightmap sha256-pinned in HANDOFF).
- Building meshes are NOT watertight — tile collision is concave trimesh built lazily by TileLoader in a 280 m ring around the ACTIVE camera. Anything physical far from the active camera has NO floor under it: parked cars must have physics disabled until driven.
- Coordinates: x east, z south, y up; tile 256 m; road surface = terrain + 0.05. Node yaw convention (matches character_visual): facing direction (dx, dz) ⇒ `rotation.y = atan2(-dx, -dz)`; a node's forward is `-basis.z`.

## File Structure

```
pipeline/
├── config.py            # + CAR_SPAWN_* constants
├── cars.py              # NEW: car_spawns(roads, hm) -> list[dict]
├── export.py            # + "car_spawns" in metadata
└── tests/test_cars.py   # NEW
game/
├── scenes/car.tscn            # NEW: body + box shape + Visual + CamPivot/SpringArm/CarCamera
├── scenes/main.tscn           # + Cars container node, PromptLabel, SpeedLabel
├── scripts/car.gd             # NEW: arcade physics, park/drive lifecycle
├── scripts/car_visual.gd      # NEW: blocky car, spinning/steering wheels, palette
├── scripts/car_camera.gd      # NEW: chase cam behind car heading + mouse look-around
├── scripts/player.gd          # + enter_exit action (KEY_E)
├── scripts/main.gd            # + car spawning, enter/exit state, prompt + speedometer
└── tests/smoke_test.gd        # + CAR/CARS/ENTER/DRIVE/EXIT assertions
```

---

### Task 1: Parked-car spawn points in metadata (pipeline)

**Files:**
- Create: `pipeline/cars.py`, `pipeline/tests/test_cars.py`
- Modify: `pipeline/config.py`, `pipeline/export.py`, `pipeline/tests/test_export.py`

**Interfaces:**
- Consumes: `Road` dataclass (`osm_id, name, points, width, road_class` — points are xz meters), `Heightmap.sample(x, z) -> float`, `config.ROAD_WIDTHS`.
- Produces:
  - `config.CAR_SPAWN_CLASSES = ("primary", "secondary", "tertiary", "residential")`, `CAR_SPAWN_RADIUS = 700.0`, `CAR_SPAWN_SPACING = 90.0`, `CAR_SPAWN_MIN_GAP = 25.0`, `MAX_CAR_SPAWNS = 120`.
  - `cars.car_spawns(roads, hm=None) -> list[dict]` — each `{"x", "y", "z", "yaw"}` (floats; y = road surface = terrain + 0.05; yaw per the atan2(-dx, -dz) convention, car parked on the right edge of the road pointing along it). Deterministic: roads iterated sorted by `(name, osm_id)`.
  - `export_city` metadata gains `"car_spawns"`.

- [ ] **Step 1: Add config** — append to `pipeline/config.py`:

```python
# --- M5 parked cars ---
CAR_SPAWN_CLASSES = ("primary", "secondary", "tertiary", "residential")
CAR_SPAWN_RADIUS = 700.0      # meters from origin — downtown only
CAR_SPAWN_SPACING = 90.0      # arclength between candidates along a road
CAR_SPAWN_MIN_GAP = 25.0      # min distance between any two accepted spawns
MAX_CAR_SPAWNS = 120
```

- [ ] **Step 2: Write failing tests** — `pipeline/tests/test_cars.py`:

```python
import math
from pathlib import Path
from pipeline import config
from pipeline.cars import car_spawns
from pipeline.osm_parse import parse_osm

FIX = Path(__file__).parent / "fixtures" / "mini.osm.xml"

def test_spawns_have_pose_fields():
    city = parse_osm(FIX)
    sp = car_spawns(city.roads)
    assert len(sp) >= 1
    for s in sp:
        assert set(s) == {"x", "y", "z", "yaw"}
        assert -math.pi <= s["yaw"] <= math.pi
        assert s["y"] == 0.05  # no heightmap -> road surface offset only

def test_spawns_deterministic():
    city = parse_osm(FIX)
    assert car_spawns(city.roads) == car_spawns(city.roads)

def test_spawns_respect_gap_and_cap():
    city = parse_osm(FIX)
    sp = car_spawns(city.roads)
    assert len(sp) <= config.MAX_CAR_SPAWNS
    for i, a in enumerate(sp):
        for b in sp[i + 1:]:
            assert math.hypot(a["x"] - b["x"], a["z"] - b["z"]) >= config.CAR_SPAWN_MIN_GAP
```

And in `pipeline/tests/test_export.py`, inside `test_export_writes_glb_and_metadata`, add after the districts assertion:

```python
    assert len(meta["car_spawns"]) >= 1
    assert set(meta["car_spawns"][0]) == {"x", "y", "z", "yaw"}
```

- [ ] **Step 3: Run** `.venv/Scripts/python -m pytest pipeline -q` — expect FAIL (no module `pipeline.cars`).

- [ ] **Step 4: Implement** — `pipeline/cars.py`:

```python
from __future__ import annotations
import math
from pipeline import config

def car_spawns(roads, hm=None) -> list[dict]:
    """Deterministic parked-car poses sampled along named downtown roads.

    Cars sit on the right edge of the roadway (inside the asphalt, so tile
    collision exists under them), pointing along the sampling direction.
    """
    spawns: list[dict] = []
    eligible = (r for r in roads
                if r.name and r.road_class in config.CAR_SPAWN_CLASSES)
    for r in sorted(eligible, key=lambda r: (r.name, r.osm_id)):
        side = r.width / 2.0 - 1.1
        if side < 0.9:
            continue
        carry = config.CAR_SPAWN_SPACING / 2.0
        for (x1, z1), (x2, z2) in zip(r.points[:-1], r.points[1:]):
            seg = math.hypot(x2 - x1, z2 - z1)
            if seg < 1e-6:
                continue
            dx, dz = (x2 - x1) / seg, (z2 - z1) / seg
            t = carry
            while t < seg:
                x, z = x1 + dx * t, z1 + dz * t
                t += config.CAR_SPAWN_SPACING
                if math.hypot(x, z) > config.CAR_SPAWN_RADIUS:
                    continue
                sx, sz = x - dz * side, z + dx * side  # right-hand offset
                if any(math.hypot(sx - s["x"], sz - s["z"]) < config.CAR_SPAWN_MIN_GAP
                       for s in spawns):
                    continue
                y = (hm.sample(sx, sz) if hm is not None else 0.0) + 0.05
                spawns.append({"x": round(sx, 2), "y": round(y, 2),
                               "z": round(sz, 2),
                               "yaw": round(math.atan2(-dx, -dz), 3)})
                if len(spawns) >= config.MAX_CAR_SPAWNS:
                    return spawns
            carry = t - seg
    return spawns
```

In `pipeline/export.py`: add `from pipeline.cars import car_spawns`, and in the `meta` dict (after `"spawn"`):

```python
        "car_spawns": car_spawns(city.roads, hm),
```

- [ ] **Step 5: Run** `.venv/Scripts/python -m pytest pipeline -q` — all green (58).
- [ ] **Step 6: Rebuild metadata** — `.venv/Scripts/python -m pipeline.build` (caches hit; tiles byte-identical, only `city_metadata.json` changes). Then `tools/godot/godot_console.exe --headless --path game --import`, then the smoke test → `PLAYER OK` / `LANDED OK` / `SMOKE OK: 314 tiles`. Sanity: `.venv/Scripts/python -c "import json;print(len(json.load(open('game/world/city_metadata.json'))['car_spawns']))"` → between 20 and 120.
- [ ] **Step 7: Commit** `git add pipeline game/world && git commit -m "pipeline: parked-car spawn poses along downtown streets"`

---

### Task 2: Car body — arcade physics, park/drive lifecycle

**Files:**
- Create: `game/scripts/car.gd`, `game/scenes/car.tscn`
- Modify: `game/scripts/player.gd`, `game/tests/smoke_test.gd`

**Interfaces:**
- Produces: `Car` (class_name, extends CharacterBody3D) — `var driven: bool`, `var speed: float` (signed m/s, + forward), `var steer_input: float` (−1..1, read by the visual for wheel yaw), `func park()` (freeze physics — REQUIRED for any car far from the active camera, no collision ring there), `func start_driving()`, `func stop_driving()` (car coasts to a stop then refreezes itself). Drives with move_forward/move_back/move_left/move_right, jump = handbrake. `car.tscn` root `Car` + BoxShape3D (1.9 × 1.1 × 4.3 at y 0.75) + empty `Visual` Node3D (Task 3 fills it). `player.gd` `ensure_actions()` gains `enter_exit` (KEY_E).

- [ ] **Step 1: Register the action** — in `game/scripts/player.gd`, inside `ensure_actions()`, extend the `defs` array with `["enter_exit", KEY_E]`:

```gdscript
	var defs := [["move_forward", KEY_W], ["move_back", KEY_S], ["move_left", KEY_A],
			["move_right", KEY_D], ["jump", KEY_SPACE], ["sprint", KEY_SHIFT],
			["toggle_fly", KEY_F], ["enter_exit", KEY_E]]
```

- [ ] **Step 2: Write** `game/scripts/car.gd`:

```gdscript
extends CharacterBody3D
class_name Car
# Arcade car: signed forward speed + yaw steering on a kinematic body.
# Parked cars are physics-frozen (park()) — tile collision only exists in a
# ring around the active camera, so a far-away simulated car would fall
# through the world. start_driving() thaws it; after stop_driving() it
# coasts to a stop and refreezes itself.

const MAX_SPEED := 24.0        # m/s ~ 86 km/h
const MAX_REVERSE := 7.0
const ACCEL := 9.0
const BRAKE := 16.0
const COAST_DRAG := 3.0
const HANDBRAKE_DRAG := 12.0
const STEER_RATE := 1.9        # rad/s at crawl, tightens down at speed
const GRAVITY := 14.0

var driven := false
var speed := 0.0
var steer_input := 0.0

func park() -> void:
	driven = false
	speed = 0.0
	set_physics_process(false)

func start_driving() -> void:
	driven = true
	set_physics_process(true)

func stop_driving() -> void:
	driven = false

func _physics_process(delta: float) -> void:
	var throttle := 0.0
	var handbrake := false
	if driven:
		throttle = Input.get_action_strength("move_forward") \
				- Input.get_action_strength("move_back")
		steer_input = Input.get_action_strength("move_left") \
				- Input.get_action_strength("move_right")
		handbrake = Input.is_action_pressed("jump")
	else:
		steer_input = 0.0
	if throttle > 0.0:
		speed = minf(speed + ACCEL * throttle * delta, MAX_SPEED)
	elif throttle < 0.0:
		if speed > 0.5:
			speed = maxf(speed + BRAKE * throttle * delta, 0.0)
		else:
			speed = maxf(speed + ACCEL * throttle * delta, -MAX_REVERSE)
	else:
		var drag := HANDBRAKE_DRAG if handbrake else COAST_DRAG
		speed = move_toward(speed, 0.0, drag * delta)
	if absf(speed) > 0.5:
		var agility := STEER_RATE * (1.0 - 0.55 * absf(speed) / MAX_SPEED)
		rotation.y += steer_input * agility * delta * signf(speed)
	var forward := -transform.basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if not driven and absf(speed) < 0.3 and is_on_floor():
		park()
```

- [ ] **Step 3: Write** `game/scenes/car.tscn`:

```
[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/car.gd" id="1"]

[sub_resource type="BoxShape3D" id="box"]
size = Vector3(1.9, 1.1, 4.3)

[node name="Car" type="CharacterBody3D"]
script = ExtResource("1")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.75, 0)
shape = SubResource("box")

[node name="Visual" type="Node3D" parent="."]
```

- [ ] **Step 4: Extend the smoke test** — in `game/tests/smoke_test.gd`, add next to the existing preload:

```gdscript
const _car_preload = preload("res://scripts/car.gd")
```

and after the `LANDED OK` print:

```gdscript
	var car_scene: PackedScene = load("res://scenes/car.tscn")
	if car_scene == null:
		push_error("FAIL: car.tscn did not load")
		quit(1)
		return
	var test_car := car_scene.instantiate() as Car
	get_root().add_child(test_car)
	test_car.park()
	await process_frame
	if not InputMap.has_action("enter_exit"):
		push_error("FAIL: enter_exit action not registered")
		quit(1)
		return
	test_car.queue_free()
	print("CAR OK")
```

- [ ] **Step 5: Run smoke** — `tools/godot/godot_console.exe --headless --path game --script res://tests/smoke_test.gd` → `PLAYER OK`, `LANDED OK`, `CAR OK`, `SMOKE OK: 314 tiles`, clean stderr.
- [ ] **Step 6: Commit** `git add game && git commit -m "game: car body with arcade physics and park/drive lifecycle"`

---

### Task 3: Blocky car visual — palette, spinning wheels, steering

**Files:**
- Create: `game/scripts/car_visual.gd`
- Modify: `game/scenes/car.tscn`

**Interfaces:**
- Consumes: parent `Car.speed` and `Car.steer_input` (Task 2).
- Produces: `car_visual.gd` on the `Visual` node — `@export var color_index := 0` (main.gd sets it per spawn BEFORE add_child so `_ready` picks it up; body color = `PALETTE[color_index % PALETTE.size()]`). Builds body, cabin, four wheels (front pair yaws with steer_input, all spin with speed), emissive headlights/taillights.

- [ ] **Step 1: Write** `game/scripts/car_visual.gd`:

```gdscript
extends Node3D
# Procedural blocky car. Wheels: pivot (steering yaw) -> spin (roll) -> mesh.
# color_index must be set before the node enters the tree.

const PALETTE := [
	Color(0.72, 0.16, 0.14),  # rouge
	Color(0.16, 0.32, 0.55),  # bleu
	Color(0.85, 0.85, 0.88),  # blanc
	Color(0.13, 0.13, 0.15),  # noir
	Color(0.78, 0.62, 0.15),  # jaune
	Color(0.25, 0.45, 0.28),  # vert
]
const TRIM := Color(0.16, 0.17, 0.19)
const GLASS := Color(0.55, 0.68, 0.75)
const WHEEL_RADIUS := 0.34

@export var color_index := 0

var _spins: Array[Node3D] = []
var _fronts: Array[Node3D] = []
var _roll := 0.0
@onready var _car := get_parent() as Car

func _flat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D, parent: Node3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)

func _wheel(pos: Vector3, steers: bool) -> void:
	var pivot := Node3D.new()
	pivot.position = pos
	add_child(pivot)
	var spin := Node3D.new()
	pivot.add_child(spin)
	var mesh := CylinderMesh.new()
	mesh.top_radius = WHEEL_RADIUS
	mesh.bottom_radius = WHEEL_RADIUS
	mesh.height = 0.26
	mesh.material = _flat(TRIM)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.rotation.z = PI / 2.0  # cylinder axis y -> x (axle)
	spin.add_child(mi)
	_spins.append(spin)
	if steers:
		_fronts.append(pivot)

func _ready() -> void:
	var body := _flat(PALETTE[color_index % PALETTE.size()])
	_box(Vector3(1.8, 0.5, 4.0), Vector3(0, 0.65, 0), body, self)          # body
	_box(Vector3(1.6, 0.45, 1.9), Vector3(0, 1.12, 0.25), _flat(GLASS), self)  # cabin
	_wheel(Vector3(-0.85, WHEEL_RADIUS, -1.35), true)
	_wheel(Vector3(0.85, WHEEL_RADIUS, -1.35), true)
	_wheel(Vector3(-0.85, WHEEL_RADIUS, 1.35), false)
	_wheel(Vector3(0.85, WHEEL_RADIUS, 1.35), false)
	var head := _flat(Color(1.0, 0.97, 0.85), 1.2)
	_box(Vector3(0.3, 0.14, 0.06), Vector3(-0.6, 0.72, -2.02), head, self)
	_box(Vector3(0.3, 0.14, 0.06), Vector3(0.6, 0.72, -2.02), head, self)
	var tail := _flat(Color(0.85, 0.1, 0.08), 0.8)
	_box(Vector3(0.28, 0.12, 0.06), Vector3(-0.6, 0.72, 2.02), tail, self)
	_box(Vector3(0.28, 0.12, 0.06), Vector3(0.6, 0.72, 2.02), tail, self)

func _process(delta: float) -> void:
	if _car == null:
		return
	_roll -= _car.speed / WHEEL_RADIUS * delta
	for s in _spins:
		s.rotation.x = _roll
	for f in _fronts:
		f.rotation.y = _car.steer_input * 0.45
```

- [ ] **Step 2: Wire** — in `game/scenes/car.tscn`: bump `load_steps` to 4, add `[ext_resource type="Script" path="res://scripts/car_visual.gd" id="2"]`, and attach:

```
[node name="Visual" type="Node3D" parent="."]
script = ExtResource("2")
```

- [ ] **Step 3: Smoke** — still `CAR OK` + `SMOKE OK: 314 tiles`, clean stderr (Visual builds headless).
- [ ] **Step 4: Commit** `git add game && git commit -m "game: procedural blocky car visual with steering wheels"`

---

### Task 4: Chase camera + parked cars spawned from metadata

**Files:**
- Create: `game/scripts/car_camera.gd`
- Modify: `game/scenes/car.tscn`, `game/scenes/main.tscn`, `game/scripts/main.gd`, `game/tests/smoke_test.gd`

**Interfaces:**
- Consumes: metadata `car_spawns` (Task 1), `Car.park()` (Task 2), `Visual.color_index` (Task 3).
- Produces:
  - `car.tscn` gains `CamPivot` (Node3D at y 1.4, script car_camera.gd) → `SpringArm3D` (spring_length 7.0) → `CarCamera` (Camera3D far 4000, NOT current by default). Node path other code relies on: `CamPivot/SpringArm3D/CarCamera`.
  - `car_camera.gd`: pivot inherits the car's yaw (child of Car); mouse motion adds a look-around yaw offset that eases back to 0 while moving; pitch clamp −1.0..0.4; Esc releases mouse, click recaptures.
  - `main.tscn` gains `Cars` (plain Node3D container).
  - `main.gd`: `_ready` instantiates one Car per `car_spawns` entry under `$Cars` — sets `Visual.color_index = i` before add_child, then position `(x, y + 0.4, z)`, `rotation.y = yaw`, `park()`.
  - Smoke asserts ≥ 20 cars under `Cars` → prints `CARS OK: <n>`.

- [ ] **Step 1: Write** `game/scripts/car_camera.gd`:

```gdscript
extends Node3D
# Chase cam: this pivot is a child of the Car, so it inherits the car's yaw.
# Mouse adds a temporary look-around offset that eases back behind the car
# while moving. Esc releases the mouse, click recaptures.

@export var sensitivity := 0.003

var _offset_yaw := 0.0
var _pitch := -0.18
@onready var _car := get_parent() as Car
@onready var _cam := $SpringArm3D/CarCamera as Camera3D

func _unhandled_input(event: InputEvent) -> void:
	if not _cam.current: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_offset_yaw -= event.relative.x * sensitivity
		_pitch = clampf(_pitch - event.relative.y * sensitivity, -1.0, 0.4)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if _car != null and absf(_car.speed) > 1.0:
		_offset_yaw = lerp_angle(_offset_yaw, 0.0, 2.5 * delta)
	rotation = Vector3(_pitch, _offset_yaw, 0.0)
```

- [ ] **Step 2: Extend** `game/scenes/car.tscn` — load_steps to 5, add `[ext_resource type="Script" path="res://scripts/car_camera.gd" id="3"]` and append:

```
[node name="CamPivot" type="Node3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.4, 0)
script = ExtResource("3")

[node name="SpringArm3D" type="SpringArm3D" parent="CamPivot"]
spring_length = 7.0

[node name="CarCamera" type="Camera3D" parent="CamPivot/SpringArm3D"]
far = 4000.0
```

- [ ] **Step 3: Add the container** — in `game/scenes/main.tscn`, after the TileLoader node:

```
[node name="Cars" type="Node3D" parent="."]
```

- [ ] **Step 4: Spawn cars** — in `game/scripts/main.gd`: add at the top

```gdscript
const CAR_SCENE := preload("res://scenes/car.tscn")

@onready var _cars := $Cars as Node3D
```

and REPLACE `_ready` with (same metadata read, plus the car loop):

```gdscript
func _ready() -> void:
	var sx := 0.0
	var sz := 0.0
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if f != null:
		var meta: Variant = JSON.parse_string(f.get_as_text())
		if typeof(meta) == TYPE_DICTIONARY:
			if meta.has("spawn"):
				sx = meta["spawn"]["x"]
				sz = meta["spawn"]["z"]
			var i := 0
			for cs in meta.get("car_spawns", []):
				var car := CAR_SCENE.instantiate() as Car
				(car.get_node("Visual") as Node3D).set("color_index", i)
				_cars.add_child(car)
				car.global_position = Vector3(cs["x"], cs["y"] + 0.4, cs["z"])
				car.rotation.y = cs["yaw"]
				car.park()
				i += 1
	_player.global_position = Vector3(sx, 80.0, sz)
	(_player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D).current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
```

- [ ] **Step 5: Extend smoke** — in `game/tests/smoke_test.gd`, after the `CAR OK` block:

```gdscript
	var cars := root.get_node_or_null("Cars")
	if cars == null or cars.get_child_count() < 20:
		var nc := -1 if cars == null else cars.get_child_count()
		push_error("FAIL: expected >=20 parked cars, got %d" % nc)
		quit(1)
		return
	print("CARS OK: %d" % cars.get_child_count())
```

- [ ] **Step 6: Run smoke** — `PLAYER OK`, `LANDED OK`, `CAR OK`, `CARS OK: <20..120>`, `SMOKE OK: 314 tiles`, clean stderr.
- [ ] **Step 7: Commit** `git add game && git commit -m "game: chase camera and parked cars spawned from metadata"`

---

### Task 5: Enter/exit flow, prompt, speedometer

**Files:**
- Modify: `game/scripts/main.gd`, `game/scenes/main.tscn`, `game/tests/smoke_test.gd`

**Interfaces:**
- Consumes: `Car.start_driving()/stop_driving()/speed` (Task 2), `CamPivot/SpringArm3D/CarCamera` path (Task 4).
- Produces: `main.gd` — `_driving: Car` state, `_enter_car(car)/_exit_car()` (smoke + screenshot harness call these directly), `_nearest_car() -> Car` (within 3.5 m of the player), E (`enter_exit`) toggles, F (`toggle_fly`) now toggles fly-cam against whichever game camera is active. HUD gains `PromptLabel` ("Press E to drive", visible when a car is in range on foot) and `SpeedLabel` (bottom-right km/h, visible while driving).

- [ ] **Step 1: HUD labels** — in `game/scenes/main.tscn`, append under the HUD nodes:

```
[node name="PromptLabel" type="Label" parent="HUD"]
visible = false
anchors_preset = 7
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -200.0
offset_right = 200.0
offset_top = -120.0
offset_bottom = -88.0
theme_override_font_sizes/font_size = 20
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 5
horizontal_alignment = 1
text = "Press E to drive"

[node name="SpeedLabel" type="Label" parent="HUD"]
visible = false
anchors_preset = 3
anchor_left = 1.0
anchor_top = 1.0
anchor_right = 1.0
anchor_bottom = 1.0
offset_left = -220.0
offset_right = -24.0
offset_top = -72.0
offset_bottom = -24.0
theme_override_font_sizes/font_size = 30
theme_override_colors/font_outline_color = Color(0, 0, 0, 1)
theme_override_constants/outline_size = 6
horizontal_alignment = 2
text = "0 km/h"
```

- [ ] **Step 2: Rewrite** `game/scripts/main.gd` — full file replacement (spawn logic from Task 4 kept verbatim):

```gdscript
extends Node3D
# Root wiring: spawn player + parked cars from metadata, own the enter/exit
# state machine, the fly-cam toggle and the drive HUD (prompt + speedometer).

const CAR_SCENE := preload("res://scenes/car.tscn")
const ENTER_RADIUS := 3.5

@onready var _player := $Player as Player
@onready var _fly_cam := $Camera as Camera3D
@onready var _cars := $Cars as Node3D
@onready var _prompt := $HUD/PromptLabel as Label
@onready var _speed_label := $HUD/SpeedLabel as Label

var _driving: Car = null

func _ready() -> void:
	var sx := 0.0
	var sz := 0.0
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	if f != null:
		var meta: Variant = JSON.parse_string(f.get_as_text())
		if typeof(meta) == TYPE_DICTIONARY:
			if meta.has("spawn"):
				sx = meta["spawn"]["x"]
				sz = meta["spawn"]["z"]
			var i := 0
			for cs in meta.get("car_spawns", []):
				var car := CAR_SCENE.instantiate() as Car
				(car.get_node("Visual") as Node3D).set("color_index", i)
				_cars.add_child(car)
				car.global_position = Vector3(cs["x"], cs["y"] + 0.4, cs["z"])
				car.rotation.y = cs["yaw"]
				car.park()
				i += 1
	_player.global_position = Vector3(sx, 80.0, sz)
	(_player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D).current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	if _driving != null:
		_speed_label.text = "%d km/h" % absi(roundi(_driving.speed * 3.6))
		return
	_prompt.visible = _player.visible and _nearest_car() != null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("enter_exit"):
		if _driving != null:
			_exit_car()
		else:
			var car := _nearest_car()
			if car != null:
				_enter_car(car)
	elif event.is_action_pressed("toggle_fly"):
		var game_cam := _active_game_camera()
		if game_cam.current:
			_fly_cam.current = true
		else:
			game_cam.current = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _active_game_camera() -> Camera3D:
	if _driving != null:
		return _driving.get_node("CamPivot/SpringArm3D/CarCamera") as Camera3D
	return _player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D

func _nearest_car() -> Car:
	var best: Car = null
	var best_d := ENTER_RADIUS
	for c in _cars.get_children():
		var d := (c as Node3D).global_position.distance_to(_player.global_position)
		if d < best_d:
			best_d = d
			best = c as Car
	return best

func _enter_car(car: Car) -> void:
	if _driving != null:
		return
	_driving = car
	_player.visible = false
	_player.set_physics_process(false)
	(_player.get_node("CollisionShape3D") as CollisionShape3D).set_deferred("disabled", true)
	car.start_driving()
	(car.get_node("CamPivot/SpringArm3D/CarCamera") as Camera3D).current = true
	_prompt.visible = false
	_speed_label.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_car() -> void:
	if _driving == null:
		return
	var car := _driving
	_driving = null
	car.stop_driving()
	_player.global_position = car.global_position \
			- car.global_transform.basis.x * 2.2 + Vector3(0, 0.5, 0)
	_player.velocity = Vector3.ZERO
	_player.visible = true
	_player.set_physics_process(true)
	(_player.get_node("CollisionShape3D") as CollisionShape3D).set_deferred("disabled", false)
	(_player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D).current = true
	_speed_label.visible = false
```

- [ ] **Step 3: Extend smoke** — in `game/tests/smoke_test.gd`, after the `CARS OK` block:

```gdscript
	var drive_car := cars.get_child(0) as Car
	player.global_position = drive_car.global_position + Vector3(2.5, 1.0, 0)
	await physics_frame
	root.call("_enter_car", drive_car)
	await process_frame
	var car_cam := drive_car.get_node("CamPivot/SpringArm3D/CarCamera") as Camera3D
	if not car_cam.current or player.visible:
		push_error("FAIL: entering car did not swap camera / hide player")
		quit(1)
		return
	print("ENTER OK")
	var start_pos := drive_car.global_position
	Input.action_press("move_forward")
	var moving := false
	for i in 900:
		await process_frame
		if drive_car.speed > 3.0 and start_pos.distance_to(drive_car.global_position) >= 1.0:
			moving = true
			break
	Input.action_release("move_forward")
	if not moving:
		push_error("FAIL: car did not drive (speed=%f, dist=%f)"
				% [drive_car.speed, start_pos.distance_to(drive_car.global_position)])
		quit(1)
		return
	print("DRIVE OK v=%.1f" % drive_car.speed)
	root.call("_exit_car")
	await process_frame
	var pcam2 := player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D
	if not player.visible or not pcam2.current:
		push_error("FAIL: exiting car did not restore player")
		quit(1)
		return
	print("EXIT OK")
```

- [ ] **Step 4: Run smoke** — expect `PLAYER OK`, `LANDED OK`, `CAR OK`, `CARS OK: <n>`, `ENTER OK`, `DRIVE OK v=...`, `EXIT OK`, `SMOKE OK: 314 tiles`, clean stderr. If the car never reaches 3 m/s, STOP and report (likely collision-ring timing under the teleported car — do not paper over with longer waits beyond the 900-frame poll).
- [ ] **Step 5: Run pytest** — `.venv/Scripts/python -m pytest pipeline -q` still green.
- [ ] **Step 6: Commit** `git add game && git commit -m "game: enter and exit cars with prompt and speedometer"`

---

### Task 6: Screenshots (driving), review, docs, tag, push — controller-led

**Files:**
- Modify: `game/tests/screenshot.gd`, `docs/superpowers/HANDOFF.md`, `README.md`

- [ ] **Step 1:** Extend `screenshot.gd`: poses may carry `"car": Vector3` — teleport the Player near the car closest to that point, call `root._enter_car(that_car)`, poll until the car `is_on_floor()` (900-frame cap, never fixed waits), settle 10 frames, snapshot (car camera is current). Hold `Input.action_press("move_forward")` for the settle frames on the day pose so wheels/steering read as alive, release before snapshot. After each car pose call `root._exit_car()`. Add poses: `{"name": "driving_day", "car": Vector3(-60, 0, -80), "time": 0.4}`, `{"name": "driving_night", "car": Vector3(200, 0, 250), "time": 0.95}`. Keep all 9 existing poses.
- [ ] **Step 2:** Capture via `tools/godot/godot_console.exe --path game --script res://tests/screenshot.gd` (windowed, GPU); PNGs land in `%APPDATA%/Godot/app_userdata/MTL Open Ile/`. READ every PNG. Checklist: blocky car visible from behind with speedometer bottom-right, car sitting ON the road (not floating/sunk), street+district HUD still correct, parked cars visible along streets in the overview/street poses, night pose shows headlight/taillight glow, on-foot poses unchanged.
- [ ] **Step 3:** Fix-or-report loop: pose coords, HUD offsets, palette/emission tweaks inline; structural failures (car through the world, camera inside geometry) — STOP and report.
- [ ] **Step 4:** Copy keepers to `docs/screenshots/m5_*.png`; README: check the M5 milestone box, add a driving screenshot row; HANDOFF: rewrite state paragraph → tag `m5-driving` (smoke prints PLAYER/LANDED/CAR/CARS/ENTER/DRIVE/EXIT OK), note the recorded design decision (procedural car over EVP/Kenney), carry-forwards updated (still open: landmark collision, HUD unit test, fly-cam Esc manual test, terrain loop perf, minimap.gd guards; new if any).
- [ ] **Step 5:** Full verification: pytest green (58), smoke green, `git status` clean after commit.
- [ ] **Step 6:** `git add -A && git commit -m "docs: M5 driving screenshots and handoff"`, `git tag m5-driving`, `git push origin main --tags`.

---

## Self-Review Notes

- Spec coverage: "walk up to any parked car, press a key, drive" ✓ (T1 spawns + T5 enter), arcade-leaning driving ✓ (T2), camera swap ✓ (T4/T5), speedometer while driving ✓ (T5), character hidden while driving ✓ (T5), cars pre-placed as parked spawns ✓ (T1/T4). EVP + Kenney replaced by procedural car — recorded deviation with swap path, M4 precedent.
- Type consistency: `Car.park/start_driving/stop_driving/speed/steer_input` defined T2, consumed T3 (visual), T4 (main spawn), T5 (enter/exit, speedo); camera node path `CamPivot/SpringArm3D/CarCamera` identical in T4 scene and T5 lookups; `car_spawns` dict keys `{x,y,z,yaw}` match T1 export ↔ T4 loader; `enter_exit` registered in T2 ↔ consumed T5.
- Physics-freeze invariant: every parked car is `set_physics_process(false)` (T4 `park()` on spawn, T2 self-refreeze after `stop_driving`) — required because tile collision only exists in the 280 m ring around the active camera.
- Ordering: T5's smoke drive needs T4 (cars in main) + T2 (physics); T6 screenshots need T5's `_enter_car/_exit_car`.
- Known risks: teleported smoke player + first-car collision timing (poll handles the fall; explicit STOP instruction if the drive stalls); car vs landmark collision still missing (carry-forward); exit while moving teleports the player beside a rolling car — acceptable arcade behavior for v1.
