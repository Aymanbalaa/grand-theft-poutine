extends Node3D
# Root wiring: spawn the player from metadata, own the fly/player camera toggle.

@onready var _player := $Player as Player
@onready var _fly_cam := $Camera as Camera3D

func _ready() -> void:
	var f := FileAccess.open("res://world/city_metadata.json", FileAccess.READ)
	var sx := 0.0
	var sz := 0.0
	if f != null:
		var meta: Variant = JSON.parse_string(f.get_as_text())
		if typeof(meta) == TYPE_DICTIONARY and meta.has("spawn"):
			sx = meta["spawn"]["x"]
			sz = meta["spawn"]["z"]
	_player.global_position = Vector3(sx, 80.0, sz)
	(_player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D).current = true

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fly"):
		var pc := _player.get_node("CamPivot/SpringArm3D/PlayerCamera") as Camera3D
		if pc.current:
			_fly_cam.current = true
		else:
			pc.current = true
