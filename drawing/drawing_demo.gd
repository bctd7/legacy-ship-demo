extends Control
## Standalone component demonstration. These are generated shapes, NOT bridge/ship content.
const Surface = preload("res://drawing/drawing_surface.gd")
const Config = preload("res://drawing/drawing_config.gd")
const Toolbar = preload("res://drawing/drawing_toolbar.gd")
var surface: Control
var clear_dialog: ConfirmationDialog
var export_dialog: FileDialog
var status: Label
var undo_button: Button
var redo_button: Button

func _ready() -> void:
	DisplayServer.window_set_title("绘画组件演示 · drawing_demo.tscn")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var drawing_theme := Theme.new()
	for control_type in ["Label", "CheckButton"]:
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			drawing_theme.set_color(color_name, control_type, Color("263c44"))
	theme = drawing_theme
	var background := ColorRect.new()
	background.color = Color("e9e5dc")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 18
	column.offset_top = 12
	column.offset_right = -18
	column.offset_bottom = -12
	add_child(column)
	var title := Label.new()
	title.text = "独立绘画组件演示 · 几何占位素材（桥 / 船尚未接入）"
	title.add_theme_color_override("font_color", Color("263c44"))
	column.add_child(title)
	surface = Surface.new()
	var tools := Toolbar.new()
	column.add_child(tools)
	tools.configure(surface)
	tools.clear_requested.connect(_request_clear)
	undo_button = tools.undo_button
	redo_button = tools.redo_button
	_button(tools, "导出 PNG…", _request_export)
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	surface.custom_minimum_size = Vector2(420, 300)
	column.add_child(surface)
	var error: String = surface.configure(demo_config())
	status = Label.new()
	status.text = "从素材栏按住拖入框内，松手吸附锁定；Esc 取消。可直接在白纸上作画。"
	status.add_theme_color_override("font_color", Color("263c44"))
	column.add_child(status)
	if not error.is_empty(): status.text = error
	clear_dialog = ConfirmationDialog.new()
	clear_dialog.title = "确认清空笔画"
	clear_dialog.dialog_text = "清除整张纸上的笔画？白纸和已锁定素材会保留；可撤销此次清空。"
	clear_dialog.ok_button_text = "确认清空笔画"
	clear_dialog.cancel_button_text = "取消"
	clear_dialog.confirmed.connect(func(): surface.document.clear_strokes(true))
	add_child(clear_dialog)
	export_dialog = FileDialog.new()
	export_dialog.title = "导出纸面 PNG（960 × 640）"
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.add_filter("*.png", "PNG image")
	export_dialog.current_file = "drawing.png"
	export_dialog.file_selected.connect(_export)
	add_child(export_dialog)

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _request_clear() -> void:
	surface.cancel_gesture()
	clear_dialog.popup_centered()

func _request_export() -> void:
	surface.cancel_gesture()
	export_dialog.popup_centered_ratio(0.72)

func _export(path: String) -> void:
	if path.get_extension().to_lower() != "png": path += ".png"
	var error: Error = surface.document.export_png(path)
	status.text = "已导出：" + path if error == OK else "导出失败（%s），请选择可写目录。" % error_string(error)

static func demo_config() -> Resource:
	var config := Config.new()
	config.materials = [
		{"id": "placeholder_a", "label": "Placeholder A", "texture": _placeholder(Color("ac7044"), false), "target_position": Vector2(0.32, 0.60), "display_size": Vector2(0.32, 0.24), "allowed_drop_rect": Rect2(0.12, 0.40, 0.40, 0.40), "lock_on_place": true},
		{"id": "placeholder_b", "label": "Placeholder B", "texture": _placeholder(Color("377e91"), true), "target_position": Vector2(0.74, 0.52), "display_size": Vector2(0.28, 0.30), "allowed_drop_rect": Rect2(0.58, 0.28, 0.34, 0.48), "lock_on_place": true}
	]
	return config

static func _placeholder(color: Color, circle: bool) -> Texture2D:
	var image := Image.create(192, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(12, 116):
		for x in range(12, 180):
			if (Vector2(x, y) - Vector2(96, 64)).length() < 50 if circle else y > 38 and y < 90 or x > 75 and x < 115:
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)
