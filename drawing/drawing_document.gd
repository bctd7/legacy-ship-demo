extends RefCounted
## Data and CPU compositor only: no screen coordinates, controls or model dependencies.
signal changed
signal material_placed(id: String, locked: bool)

var paper_size := Vector2i(960, 640)
var materials: Array[Dictionary] = []
var placements: Dictionary = {}
var strokes: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _active: Dictionary = {}
var _ink: Image
var _sources: Dictionary = {}

func configure(config: Resource) -> String:
	var error: String = config.validation_error()
	if not error.is_empty():
		return error
	var sources: Dictionary = {}
	for item in config.materials:
		var source: Image = item.texture.get_image()
		if source == null or source.is_empty():
			return "Material %s has no readable image." % item.id
		if source.is_compressed() and source.decompress() != OK:
			return "Material %s could not be decompressed." % item.id
		source.convert(Image.FORMAT_RGBA8)
		sources[item.id] = source
	paper_size = config.paper_size
	materials = config.materials.duplicate(true)
	placements.clear()
	_sources = sources
	for item in materials:
		if item.get("initially_locked", false):
			placements[item.id] = {"position": item.target_position, "locked": true}
	strokes.clear()
	_redo.clear()
	_active.clear()
	_rebuild()
	changed.emit()
	return ""

func material(id: String) -> Dictionary:
	for item in materials:
		if item.id == id:
			return item
	return {}

func can_move(id: String) -> bool:
	return not material(id).is_empty() and not placements.get(id, {}).get("locked", false)

func accepts_drop(id: String, normalized_center: Vector2) -> bool:
	var item := material(id)
	return can_move(id) and Rect2(Vector2.ZERO, Vector2.ONE).has_point(normalized_center) and item.allowed_drop_rect.has_point(normalized_center)

func place_material(id: String, normalized_center: Vector2) -> bool:
	if not accepts_drop(id, normalized_center):
		return false
	var item := material(id)
	var locked: bool = item.get("lock_on_place", true)
	placements[id] = {"position": item.target_position, "locked": locked}
	changed.emit()
	material_placed.emit(id, locked)
	return true

func begin_stroke(point: Vector2, color: Color, width: float, eraser: bool = false) -> bool:
	if not _active.is_empty() or not _inside(point) or width <= 0:
		return false
	_active = {"points": PackedVector2Array([point]), "color": color, "width": clampf(width, 1, 96), "eraser": eraser}
	_segment(_ink, point, point, _active, 1.0)
	changed.emit()
	return true

func append_stroke(point: Vector2) -> void:
	if _active.is_empty():
		return
	var clamped := point.clamp(Vector2.ZERO, Vector2(paper_size) - Vector2.ONE * 0.001)
	var points: PackedVector2Array = _active.points
	var previous := points[points.size() - 1]
	if previous.distance_to(clamped) < 0.4:
		return
	points.append(clamped)
	_active.points = points
	_segment(_ink, previous, clamped, _active, 1.0)
	changed.emit()

func end_stroke() -> void:
	if _active.is_empty():
		return
	strokes.append(_active.duplicate(true))
	_active.clear()
	_redo.clear()
	changed.emit()

func cancel_stroke() -> void:
	if _active.is_empty():
		return
	_active.clear()
	_rebuild()
	changed.emit()

func can_undo() -> bool:
	return not strokes.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

func undo() -> void:
	cancel_stroke()
	if strokes.is_empty():
		return
	_redo.append(strokes.pop_back())
	_rebuild()
	changed.emit()

func redo() -> void:
	cancel_stroke()
	if _redo.is_empty():
		return
	strokes.append(_redo.pop_back())
	_rebuild()
	changed.emit()

func clear_strokes(confirmed: bool = false) -> bool:
	if not confirmed:
		return false
	cancel_stroke()
	if not strokes.is_empty():
		# Clear is one undoable command; undo restores every prior stroke together.
		strokes.append({"clear": true})
		_redo.clear()
		_rebuild()
		changed.emit()
	return true

func ink_image() -> Image:
	return _ink

func material_size(item: Dictionary, canvas_size: Vector2) -> Vector2:
	# display_size is a normalized bounding box; preserve source image aspect ratio.
	var box: Vector2 = item.display_size * canvas_size
	var texture: Texture2D = item.texture
	return texture.get_size() * minf(box.x / texture.get_width(), box.y / texture.get_height())

func compose(output_size: Vector2i = Vector2i.ZERO) -> Image:
	var extent := paper_size if output_size == Vector2i.ZERO else output_size
	# Equal x/y scale prevents distorted artwork and brush widths.
	if extent.x < 16 or extent.y < 16 or extent.x > 4096 or extent.y > 4096 or extent.x * paper_size.y != extent.y * paper_size.x:
		return null
	var result := Image.create(extent.x, extent.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.WHITE)
	for item in materials:
		if not placements.has(item.id):
			continue
		var source: Image = _sources[item.id].duplicate()
		var dimensions := material_size(item, Vector2(extent))
		var pixels := Vector2i(maxi(1, roundi(dimensions.x)), maxi(1, roundi(dimensions.y)))
		source.resize(pixels.x, pixels.y, Image.INTERPOLATE_LANCZOS)
		var center: Vector2 = placements[item.id].position * Vector2(extent)
		result.blend_rect(source, Rect2i(Vector2i.ZERO, pixels), Vector2i((center - Vector2(pixels) / 2).round()))
	var ink := _ink if extent == paper_size else _render_ink(extent)
	result.blend_rect(ink, Rect2i(Vector2i.ZERO, extent), Vector2i.ZERO)
	return result

func export_png(path: String, output_size: Vector2i = Vector2i.ZERO) -> Error:
	var result := compose(output_size)
	if result == null:
		return ERR_INVALID_PARAMETER
	return result.save_png(path)

func _inside(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, Vector2(paper_size)).has_point(point)

func _rebuild() -> void:
	_ink = _render_ink(paper_size)

func _render_ink(extent: Vector2i) -> Image:
	var ink := Image.create(extent.x, extent.y, false, Image.FORMAT_RGBA8)
	ink.fill(Color.TRANSPARENT)
	var scale := float(extent.x) / paper_size.x
	var commands := strokes.duplicate()
	if not _active.is_empty():
		commands.append(_active)
	for command in commands:
		if command.get("clear", false):
			ink.fill(Color.TRANSPARENT)
			continue
		var points: PackedVector2Array = command.points
		_segment(ink, points[0] * scale, points[0] * scale, command, scale)
		for i in range(1, points.size()):
			_segment(ink, points[i - 1] * scale, points[i] * scale, command, scale)
	return ink

func _segment(ink: Image, a: Vector2, b: Vector2, command: Dictionary, scale: float) -> void:
	var radius: float = command.width * scale / 2
	var left := maxi(0, floori(minf(a.x, b.x) - radius - 1))
	var top := maxi(0, floori(minf(a.y, b.y) - radius - 1))
	var right := mini(ink.get_width() - 1, ceili(maxf(a.x, b.x) + radius + 1))
	var bottom := mini(ink.get_height() - 1, ceili(maxf(a.y, b.y) + radius + 1))
	for y in range(top, bottom + 1):
		for x in range(left, right + 1):
			var pixel := Vector2(x + 0.5, y + 0.5)
			var closest := Geometry2D.get_closest_point_to_segment(pixel, a, b)
			var coverage := clampf(radius + 0.5 - closest.distance_to(pixel), 0, 1)
			if coverage <= 0:
				continue
			var old := ink.get_pixel(x, y)
			if command.eraser:
				old.a *= 1.0 - coverage
				ink.set_pixel(x, y, old)
			else:
				var color: Color = command.color
				color.a *= coverage
				ink.set_pixel(x, y, old.blend(color))
