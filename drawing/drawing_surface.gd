extends Control
## Reusable paper + material tray. The parent supplies tools, config and export UI.
const Document = preload("res://drawing/drawing_document.gd")
const Config = preload("res://drawing/drawing_config.gd")
signal material_placed(id: String, locked: bool)
signal document_changed

var document := Document.new()
var brush_color := Color("245b77")
var brush_width := 12.0 # Logical paper pixels, independent of window scale.
var eraser := false
var show_targets := true
var _ink_texture: ImageTexture
var _pointer := -2 # -2 idle, -1 mouse, >=0 touch index.
var _pressed_at := Vector2.ZERO
var _cursor := Vector2.ZERO
var _drag_id := ""
var _drag_moved := false
var _painting := false
var _last_paper_point := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	document.changed.connect(_refresh)
	document.material_placed.connect(func(id: String, locked: bool): material_placed.emit(id, locked))
	if document.ink_image() == null:
		document.configure(Config.new())
	_refresh()
	resized.connect(cancel_gesture)

func configure(config: Resource) -> String:
	cancel_gesture()
	var error: String = document.configure(config)
	if is_node_ready():
		_refresh()
	return error

func paper_rect() -> Rect2:
	var available := Vector2(maxf(1, size.x - 48), maxf(1, size.y - 160))
	var ratio := minf(available.x / document.paper_size.x, available.y / document.paper_size.y)
	var extent := Vector2(document.paper_size) * ratio
	return Rect2(Vector2((size.x - extent.x) / 2, (size.y - 136 - extent.y) / 2), extent)

func paper_to_local(point: Vector2) -> Vector2:
	var paper := paper_rect()
	return paper.position + point / Vector2(document.paper_size) * paper.size

func local_to_paper(point: Vector2) -> Vector2:
	var paper := paper_rect()
	return (point - paper.position) / paper.size * Vector2(document.paper_size)

func tray_rect(index: int) -> Rect2:
	var count := maxi(1, document.materials.size())
	var width := minf(230, (size.x - 48 - (count - 1) * 12) / count)
	return Rect2(Vector2(24 + index * (width + 12), size.y - 116), Vector2(width, 96))

func cancel_gesture() -> void:
	if _painting:
		document.cancel_stroke()
	_pointer = -2
	_drag_id = ""
	_drag_moved = false
	_painting = false
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		cancel_gesture()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return # Native touch is handled directly; do not start a duplicate mouse gesture.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _pointer == -2:
			_begin_pointer(event.position, -1)
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		if _pointer == -2:
			_begin_pointer(event.position, event.index)
		accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _pointer != -2:
			cancel_gesture()
			get_viewport().set_input_as_handled()
		return
	if _pointer == -2:
		return
	var inverse := get_global_transform_with_canvas().affine_inverse()
	if _pointer == -1:
		if event is InputEventMouseMotion:
			_move_pointer(inverse * event.position)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_end_pointer(inverse * event.position)
		else:
			return
	else:
		if event is InputEventScreenDrag and event.index == _pointer:
			_move_pointer(inverse * event.position)
		elif event is InputEventScreenTouch and event.index == _pointer and not event.pressed:
			if event.canceled:
				cancel_gesture()
			else:
				_end_pointer(inverse * event.position)
		else:
			return
	get_viewport().set_input_as_handled()

func _begin_pointer(point: Vector2, pointer_id: int) -> void:
	grab_focus()
	_pointer = pointer_id
	_pressed_at = point
	_cursor = point
	for index in range(document.materials.size()):
		var item: Dictionary = document.materials[index]
		if tray_rect(index).has_point(point) and not document.placements.has(item.id):
			_drag_id = item.id
			queue_redraw()
			return
	# Unlocked placed assets may be picked up again; locked art remains drawable.
	for index in range(document.materials.size() - 1, -1, -1):
		var item: Dictionary = document.materials[index]
		if document.placements.has(item.id) and document.can_move(item.id) and _material_rect(item).has_point(point):
			_drag_id = item.id
			return
	if paper_rect().has_point(point):
		_painting = document.begin_stroke(local_to_paper(point), brush_color, brush_width, eraser)
		_last_paper_point = point
	else:
		_pointer = -2

func _move_pointer(point: Vector2) -> void:
	_cursor = point
	if not _drag_id.is_empty():
		_drag_moved = _drag_moved or _pressed_at.distance_to(point) >= 8
		queue_redraw()
	elif _painting:
		# Finish at the border; re-entry never joins a line across an outside excursion.
		var clipped := _clip_to_paper(_last_paper_point, point)
		document.append_stroke(local_to_paper(clipped))
		_last_paper_point = clipped
		if not paper_rect().has_point(point):
			document.end_stroke()
			_painting = false

func _clip_to_paper(from: Vector2, to: Vector2) -> Vector2:
	if paper_rect().has_point(to):
		return to
	var paper := paper_rect()
	var delta := to - from
	var fraction := 1.0
	if delta.x > 0: fraction = minf(fraction, (paper.end.x - from.x) / delta.x)
	elif delta.x < 0: fraction = minf(fraction, (paper.position.x - from.x) / delta.x)
	if delta.y > 0: fraction = minf(fraction, (paper.end.y - from.y) / delta.y)
	elif delta.y < 0: fraction = minf(fraction, (paper.position.y - from.y) / delta.y)
	return from + delta * clampf(fraction, 0, 1)

func _end_pointer(point: Vector2) -> void:
	_move_pointer(point)
	if not _drag_id.is_empty() and _drag_moved:
		document.place_material(_drag_id, local_to_paper(point) / Vector2(document.paper_size))
	if _painting:
		document.end_stroke()
	_pointer = -2
	_drag_id = ""
	_drag_moved = false
	_painting = false
	queue_redraw()

func _refresh() -> void:
	if document.ink_image() != null:
		if _ink_texture != null and _ink_texture.get_size() == Vector2(document.paper_size):
			_ink_texture.update(document.ink_image())
		else:
			_ink_texture = ImageTexture.create_from_image(document.ink_image())
	queue_redraw()
	document_changed.emit()

func _material_rect(item: Dictionary) -> Rect2:
	var paper := paper_rect()
	var center: Vector2 = document.placements.get(item.id, {}).get("position", item.target_position)
	var extent := document.material_size(item, paper.size)
	return Rect2(paper.position + center * paper.size - extent / 2, extent)

func _draw() -> void:
	var paper := paper_rect()
	var styled_paper := has_theme_stylebox("paper", "DrawingSurface")
	if styled_paper:
		draw_style_box(get_theme_stylebox("paper", "DrawingSurface"), paper)
	else:
		draw_rect(Rect2(paper.position - Vector2(4, 1), paper.size + Vector2(8, 8)), Color(0, 0, 0, 0.15))
		draw_rect(paper, Color.WHITE) # Layer 1: bounded opaque white paper.
	# Layer 2: placed material alpha textures, independent from erasable ink.
	for item in document.materials:
		if document.placements.has(item.id):
			if item.id != _drag_id or not _drag_moved:
				draw_texture_rect(item.texture, _material_rect(item), false)
	if _ink_texture:
		draw_texture_rect(_ink_texture, paper, false) # Layer 3: transparent ink only.
	if not styled_paper: draw_rect(paper, Color("b5aca0"), false, 1)
	if show_targets:
		for item in document.materials:
			if document.placements.has(item.id):
				continue
			var allowed: Rect2 = item.allowed_drop_rect
			var area := Rect2(paper.position + allowed.position * paper.size, allowed.size * paper.size)
			var hot: bool = item.id == _drag_id and _drag_moved and document.accepts_drop(item.id, local_to_paper(_cursor) / Vector2(document.paper_size))
			draw_rect(area, _surface_color("target_fill_hot" if hot else "target_fill", Color(0.2, 0.6, 0.45, 0.12 if hot else 0.04)))
			draw_rect(area, _surface_color("target_border_hot" if hot else "target_border", Color("288669") if hot else Color("bcb8ad")), false, 2 if hot or not has_theme_color("target_border", "DrawingSurface") else 1)
	var font := get_theme_default_font()
	for index in range(document.materials.size()):
		var item: Dictionary = document.materials[index]
		var card := tray_rect(index)
		var placed := document.placements.has(item.id)
		var card_style := "material_card_placed" if placed else "material_card"
		if has_theme_stylebox(card_style, "DrawingSurface"):
			draw_style_box(get_theme_stylebox(card_style, "DrawingSurface"), card)
		else:
			draw_rect(card, Color("dedbd5") if placed else Color("f6f3eb"))
			draw_rect(card, Color("b5aca0"), false, 1)
		var preview := Rect2(card.position + Vector2(12, 8), Vector2(card.size.x - 24, 46))
		var texture: Texture2D = item.texture
		var ratio := minf(preview.size.x / texture.get_width(), preview.size.y / texture.get_height())
		var extent := texture.get_size() * ratio
		var locked_opacity := float(get_theme_constant("locked_preview_opacity_percent", "DrawingSurface")) / 100.0 if has_theme_constant("locked_preview_opacity_percent", "DrawingSurface") else 0.3
		draw_texture_rect(texture, Rect2(preview.get_center() - extent / 2, extent), false, Color(1, 1, 1, locked_opacity if placed else 1))
		if has_theme_constant("separate_material_status", "DrawingSurface") and get_theme_constant("separate_material_status", "DrawingSurface") != 0:
			draw_string(font, card.position + Vector2(12, 73), str(item.get("label", item.id)), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 24, 14, _surface_color("material_label", Color("343b42")))
			var state := "已固定" if placed and not document.can_move(item.id) else "已放置" if placed else "拖入纸面固定区域"
			draw_string(font, card.position + Vector2(12, 91), state, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 24, 11, _surface_color("material_status", Color("343b42")))
		else:
			var label: String = str(item.get("label", item.id)) + (" · locked" if placed and not document.can_move(item.id) else " · placed" if placed else " · drag")
			draw_string(font, card.position + Vector2(10, 77), label, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 20, 14, Color("343b42"))
	if not _drag_id.is_empty() and _drag_moved:
		var item := document.material(_drag_id)
		var extent := document.material_size(item, paper.size)
		draw_texture_rect(item.texture, Rect2(_cursor - extent / 2, extent), false, Color(1, 1, 1, 0.72))

func _surface_color(key: String, fallback: Color) -> Color:
	return get_theme_color(key, "DrawingSurface") if has_theme_color(key, "DrawingSurface") else fallback
