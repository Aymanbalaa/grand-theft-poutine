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

const MODEL_COUNT := 6
const MODEL_SCALE := {0: 1.55, 1: 1.55, 2: 1.5, 3: 1.45, 4: 1.45, 5: 1.5}

@export var color_index := 0

var _spins: Array[Node3D] = []
var _fronts: Array[Node3D] = []
var _roll := 0.0
var _model_mode := false
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
	var idx := color_index % MODEL_COUNT
	var path := "res://assets/models/cars/car%d.glb" % idx
	if ResourceLoader.exists(path):
		var packed: PackedScene = load(path)
		if packed != null:
			var inst := packed.instantiate()
			if inst != null:
				var inst3d := inst as Node3D
				add_child(inst)
				if inst3d != null:
					inst3d.scale = Vector3.ONE * float(MODEL_SCALE[idx])
					inst3d.rotation.y = PI
				_polish_materials(inst)
				_model_mode = true
				return
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

static func _polish_materials(node: Node) -> void:
	var mi := node as MeshInstance3D
	if mi != null and mi.mesh != null:
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s) as BaseMaterial3D
			if mat == null:
				continue
			if mat.albedo_texture == null:
				var tex := load("res://assets/models/cars/Textures/colormap.png") as Texture2D
				if tex != null:
					mat.albedo_texture = tex
			mat.clearcoat_enabled = true
			mat.clearcoat = 0.6
			mat.clearcoat_roughness = 0.2
			mat.metallic = 0.25
			mat.roughness = 0.35
	for child in node.get_children():
		_polish_materials(child)

func _process(delta: float) -> void:
	if _model_mode:
		return
	if _car == null:
		return
	_roll -= _car.speed / WHEEL_RADIUS * delta
	for s in _spins:
		s.rotation.x = _roll
	for f in _fronts:
		f.rotation.y = _car.steer_input * 0.45
