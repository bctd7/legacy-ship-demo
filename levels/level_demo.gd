extends Control
const Catalog = preload("res://levels/level_catalog.gd")
const Flow = preload("res://levels/level_flow.gd")
const Bridge = preload("res://levels/bridge_stage_adapter.gd")
const Pending = preload("res://levels/pending_stage.gd")
const DrawingStage = preload("res://levels/drawing_stage.gd")
const Mock = preload("res://levels/mock_stage.gd")
var flow: Node
var host: Control
var status: Label
var next_button: Button
var export_button: Button
var export_dialog: FileDialog

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("e9e5dc")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(column)
	var tools := HBoxContainer.new()
	column.add_child(tools)
	_button(tools, "正式组件流程（船未接入）", func(): _start(false))
	_button(tools, "全流程测试（全部 mock）", func(): _start(true))
	next_button = _button(tools, "进入下一阶段", func(): flow.advance())
	export_button = _button(tools, "导出绘画并完成…", func(): export_dialog.popup_centered_ratio(0.7))
	status = Label.new()
	status.add_theme_color_override("font_color", Color("263c44"))
	column.add_child(status)
	host = Control.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.clip_contents = true
	column.add_child(host)
	flow = Flow.new()
	add_child(flow)
	flow.progress_changed.connect(_refresh)
	export_dialog = FileDialog.new()
	export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_dialog.add_filter("*.png", "PNG image")
	export_dialog.current_file = "level_drawing.png"
	export_dialog.file_selected.connect(func(path: String):
		if is_instance_valid(flow.current_stage) and flow.current_stage.has_method("export_to"):
			var error: String = flow.current_stage.export_to(path)
			if not error.is_empty(): status.text = error)
	add_child(export_dialog)
	_start(OS.get_cmdline_user_args().has("--mock"))

func _start(mock_mode: bool) -> void:
	var factories := {"bridge": func(): return Bridge.new(), "pending": func(): return Pending.new(), "drawing": func(): return DrawingStage.new()}
	if mock_mode:
		factories = {"bridge": func(): return Mock.new(), "pending": func(): return Mock.new(), "drawing": func(): return Mock.new()}
	flow.start(Catalog.first_level(), host, factories, mock_mode)

func _refresh(progress: Dictionary) -> void:
	next_button.disabled = not flow.can_advance() or progress.index == progress.total - 1
	export_button.visible = not progress.simulated and is_instance_valid(flow.current_stage) and flow.current_stage.has_method("export_to")
	status.text = "%s · %s · 已完成 %d/%d%s" % ["MOCK 测试（非正式进度）" if progress.simulated else "正式组件流程", progress.stage_id, progress.completed_count, progress.total, " · 流程完成" if progress.finished else ""]
	if progress.index >= 0 and not progress.simulated:
		var item: Dictionary = flow.config.stages[progress.index]
		if item.get("integration_status") == "pending_integration": status.text += " · " + str(item.get("message", "等待组件接入"))
	if not progress.error.is_empty(): status.text += " · " + progress.error

func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button
