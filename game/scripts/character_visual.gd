extends Node3D
# Procedural blocky minifig + walk swing. Parent must be a CharacterBody3D.

const JACKET := Color(58.0 / 255.0, 74.0 / 255.0, 96.0 / 255.0)
const PANTS := Color(40.0 / 255.0, 42.0 / 255.0, 48.0 / 255.0)
const SKIN := Color(224.0 / 255.0, 172.0 / 255.0, 138.0 / 255.0)
const TUQUE := Color(176.0 / 255.0, 52.0 / 255.0, 48.0 / 255.0)

var _l_arm: Node3D
var _r_arm: Node3D
var _l_leg: Node3D
var _r_leg: Node3D
var _phase := 0.0
@onready var _body := get_parent() as CharacterBody3D

func _box(size: Vector3, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi

func _limb(size: Vector3, pivot_pos: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	add_child(pivot)
	_box(size, Vector3(0, -size.y / 2.0, 0), color, pivot)
	return pivot

func _ready() -> void:
	_box(Vector3(0.5, 0.6, 0.3), Vector3(0, 1.15, 0), JACKET, self)   # torso
	_box(Vector3(0.3, 0.3, 0.3), Vector3(0, 1.6, 0), SKIN, self)      # head
	_box(Vector3(0.32, 0.12, 0.32), Vector3(0, 1.78, 0), TUQUE, self) # tuque
	_l_arm = _limb(Vector3(0.14, 0.55, 0.14), Vector3(-0.33, 1.42, 0), JACKET)
	_r_arm = _limb(Vector3(0.14, 0.55, 0.14), Vector3(0.33, 1.42, 0), JACKET)
	_l_leg = _limb(Vector3(0.18, 0.85, 0.18), Vector3(-0.13, 0.85, 0), PANTS)
	_r_leg = _limb(Vector3(0.18, 0.85, 0.18), Vector3(0.13, 0.85, 0), PANTS)

func _process(delta: float) -> void:
	if _body == null:
		return
	var hvel := Vector2(_body.velocity.x, _body.velocity.z)
	var speed := hvel.length()
	if speed > 0.5:
		var target_yaw := atan2(-hvel.x, -hvel.y)
		rotation.y = lerp_angle(rotation.y, target_yaw, 10.0 * delta)
	_phase += speed * 2.2 * delta
	var amp := clampf(speed / 4.5, 0.0, 1.4) * 0.7
	var swing := sin(_phase) * amp
	if speed < 0.5:
		swing = lerpf(_l_leg.rotation.x, 0.0, 12.0 * delta)
	_l_leg.rotation.x = swing
	_r_leg.rotation.x = -swing
	_l_arm.rotation.x = -swing * 0.8
	_r_arm.rotation.x = swing * 0.8
