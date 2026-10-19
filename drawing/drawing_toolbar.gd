extends HFlowContainer
## Public-operation toolbar. Hosts own confirmation, export and stage buttons.
signal clear_requested
var surface: Control
var undo_button: Button
var redo_button: Button
var _locked := false

func configure(for_surface: Control, options: Dictionary = {}) -> void:
	surface = for_surface
	var eraser := CheckButton.new()
	eraser.text = str(options.get("eraser_label", "橡皮（仅擦笔画）"))
	eraser.toggled.connect(func(enabled: bool): surface.eraser = enabled)
	add_child(eraser)
	var color := ColorPickerButton.new()
	color.color = surface.brush_color
	color.custom_minimum_size = Vector2(float(options.get("color_width", 64)), 32)
	color.color_changed.connect(func(value: Color): surface.brush_color = value)
	add_child(color)
	var width := HSlider.new()
	width.min_value = 1
	width.max_value = 64
	width.value = surface.brush_width
	width.custom_minimum_size = Vector2(140, 32)
	add_child(width)
	var width_label := Label.new()
	width_label.text = "%d px" % width.value
	width_label.visible = bool(options.get("show_width_label", true))
	add_child(width_label)
	width.value_changed.connect(func(value: float): surface.brush_width = value; width_label.text = "%d px" % value)
	undo_button = _button("撤销", func(): surface.cancel_gesture(); surface.document.undo())
	redo_button = _button("重做", func(): surface.cancel_gesture(); surface.document.redo())
	_button("清空笔画…", func(): surface.cancel_gesture(); clear_requested.emit())
	surface.document_changed.connect(_refresh)
	_refresh()

func set_locked(value: bool) -> void:
	_locked = value
	for child in get_children():
		if child is BaseButton: child.disabled = value
		if child is Slider: child.editable = not value
	_refresh()

func _refresh() -> void:
	undo_button.disabled = _locked or not surface.document.can_undo()
	redo_button.disabled = _locked or not surface.document.can_redo()

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	add_child(button)
	return button
