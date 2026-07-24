extends Node3D
class_name GrassField

const GREEN_MIN := 0.06   # (g - r) must exceed this (mid of shader's 0.03..0.10 band)
const WET_MAX := 0.04     # (b - g) at/above this reads as water-bottom, not grass

static func is_grass(c: Color) -> bool:
	return (c.g - c.r) >= GREEN_MIN and (c.b - c.g) < WET_MAX
