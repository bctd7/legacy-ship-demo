extends "res://interaction/orbit_camera.gd"
## Boat zoom focus and legacy bound names only. All camera math stays shared.
var min_distance: float:
	get: return distance_limits.x
	set(value): distance_limits.x = value
var max_distance: float:
	get: return distance_limits.y
	set(value): distance_limits.y = value
var zoom_focus := Vector3.ZERO
var zoom_focus_enabled := false

func zoom(amount: float) -> void:
	# Manual zoom keeps the chosen orbit centre stable. Connection closeups
	# already have their own smooth focus transition in the assembly director.
	super.zoom(amount)
