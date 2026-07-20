extends CanvasLayer
# C toggles the attribution overlay. Content mirrors CREDITS.md.

const TEXT := """MTL: Open Île — Grand Theft Poutine

Map data © OpenStreetMap contributors — ODbL
  openstreetmap.org/copyright
Terrain: HRDEM — Natural Resources Canada
  Open Government Licence – Canada
Textures: ambientCG — CC0
  ambientcg.com
Car models: Kenney Car Kit (orig. Quaternius) — CC0
  kenney.nl/assets/car-kit
Engine: Godot Engine — MIT
  godotengine.org

Press C to close"""

func _ready() -> void:
	visible = false
	($Panel/Label as Label).text = TEXT

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("credits"):
		visible = not visible
