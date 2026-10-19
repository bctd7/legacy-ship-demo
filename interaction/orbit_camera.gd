extends RefCounted
## View-only module. Never writes assembly state.
var camera: Camera3D
var focus = Vector3(0, 0.095, 0)
var yaw: float = 0.65
var pitch: float = 0.48
var distance: float = 0.78
var distance_limits := Vector2(0.38, 1.65)
var pitch_limits := Vector2(0.12, 1.25)
var pan_limit := 0.18
var _home_focus := Vector3(0, 0.095, 0)
var _home_yaw := 0.65
var _home_pitch := 0.48
var _home_distance := 0.78

func _init(view_camera: Camera3D, settings: Dictionary = {}) -> void:
	camera = view_camera
	distance_limits = settings.get("distance_limits", distance_limits)
	distance_limits.x = maxf(0.01, distance_limits.x)
	distance_limits.y = maxf(distance_limits.x, distance_limits.y)
	pitch_limits = settings.get("pitch_limits", pitch_limits)
	pitch_limits.x = clampf(pitch_limits.x, -1.55, 1.55)
	pitch_limits.y = clampf(pitch_limits.y, pitch_limits.x, 1.55)
	pan_limit = maxf(0.0, float(settings.get("pan_limit", pan_limit)))
	_home_focus = settings.get("focus", focus)
	_home_yaw = float(settings.get("yaw", yaw))
	_home_pitch = clampf(float(settings.get("pitch", pitch)), pitch_limits.x, pitch_limits.y)
	_home_distance = clampf(float(settings.get("distance", distance)), distance_limits.x, distance_limits.y)
	reset_view()

func rotate_view(delta: Vector2) -> void:
	if not delta.is_finite(): return
	yaw -= delta.x * 0.007
	pitch = clampf(pitch + delta.y * 0.006, pitch_limits.x, pitch_limits.y)
	update_view()

func zoom(amount: float) -> void:
	if not is_finite(amount) or amount <= 0: return
	distance = clampf(distance * amount, distance_limits.x, distance_limits.y)
	update_view()

func pan_view(delta: Vector2, viewport_size: Vector2) -> void:
	if not delta.is_finite() or viewport_size.y <= 0: return
	var metres_per_pixel := 2.0 * distance * tan(deg_to_rad(camera.fov * 0.5)) / viewport_size.y
	var displacement := (-camera.global_basis.x * delta.x + camera.global_basis.y * delta.y) * metres_per_pixel
	var offset := (focus + displacement - _home_focus).limit_length(pan_limit)
	offset.y = clampf(offset.y, -pan_limit / 3.0, pan_limit * 2.0 / 3.0)
	focus = _home_focus + offset
	update_view()

func reset_view() -> void:
	focus = _home_focus
	yaw = _home_yaw
	pitch = _home_pitch
	distance = _home_distance
	update_view()

func update_view() -> void:
	camera.position = focus + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(focus)
