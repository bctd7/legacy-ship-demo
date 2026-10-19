extends Control
const Catalog = preload("res://levels/level_catalog.gd")
const Flow = preload("res://levels/level_flow.gd")
const Model = preload("res://levels/model_stage.gd")
const DrawingStage = preload("res://levels/drawing_stage.gd")
const Generation = preload("res://levels/generation_stage.gd")
const Presentation = preload("res://levels/presentation/level_theme.gd")
@export var level_options: Dictionary = {}
var flow: Node
var host: Control
var status: Label
var next_button: Button
var export_button: Button
var reset_button: Button
var optional_button: Button
var local_button: Button
var replay_button: Button
var replay_image_path := ""
var optional_window: Window
var optional_stage: Control
var output_directory := ""
var _run_serial := 0
var _optional_serial := 0
var local_mode := "stub"
var local_port := 8769
var official_enabled := false
var _local_config_error := ""
var _drawing_document: RefCounted
var _header_title: Label
var _layout_margin: MarginContainer
var _layout_column: VBoxContainer
var _auto_stage_instance := 0
var _auto_elapsed := 0.0
var _advancing := false
var _resume_file := ""
var _resume_consumed := false

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resume-results="): _resume_file = argument.trim_prefix("--resume-results=")
		if argument == "--bridge-only": level_options["profile"] = "bridge_only"
		if argument.begins_with("--replay-image="): replay_image_path = argument.trim_prefix("--replay-image=")
		if argument.begins_with("--local-port="): local_port = int(argument.trim_prefix("--local-port="))
		if argument.begins_with("--local-mode="):
			local_mode = argument.trim_prefix("--local-mode=")
			if local_mode not in ["stub", "official"]: _local_config_error = "本机模式只能为 stub 或 official。"
	official_enabled = local_mode == "official" and _local_config_error.is_empty()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Presentation.make()
	var background := ColorRect.new()
	background.color = Presentation.BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	_layout_margin = margin
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var column := VBoxContainer.new()
	_layout_column = column
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_header_title = Label.new()
	_header_title.text = "关卡演示 · 模型拼装 → 白纸绘画"
	_header_title.add_theme_font_size_override("font_size", 22)
	column.add_child(_header_title)
	var tools := HFlowContainer.new()
	column.add_child(tools)
	reset_button = _button(tools, "重新开始（清除本次进度）", restart)
	next_button = _button(tools, "进入下一阶段", advance_stage)
	export_button = _button(tools, "导出绘画并完成本阶段", finish_drawing)
	Presentation.primary(next_button)
	Presentation.primary(export_button)
	optional_button = _button(tools, "可选演示：离线 MOCK", open_optional_mock)
	local_button = _button(tools, "本机服务：真实生成" if official_enabled else "本机服务：STUB（非 AI）", open_local_generation)
	status = Label.new()
	replay_button = _button(tools, "已生成图片离线回放", open_recorded_replay)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 28
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", Presentation.MUTED)
	column.add_child(status)
	host = Control.new()
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.clip_contents = true
	column.add_child(host)
	flow = Flow.new()
	add_child(flow)
	flow.progress_changed.connect(_refresh)
	restart()
	call_deferred("_report_launch_identity")

func restart() -> void:
	_cancel_auto_advance()
	_advancing = false
	close_optional_mock()
	_run_serial += 1
	output_directory = "user://level_demo/run_%s_%d" % [Time.get_ticks_usec(), _run_serial]
	var error := DirAccess.make_dir_recursive_absolute(output_directory)
	if error != OK:
		status.text = "不能创建演示输出目录：" + error_string(error)
		return
	var factories := {"model": func(): return Model.new(), "drawing": func(): return DrawingStage.new()}
	var completed_prefix := {}
	if not _resume_file.is_empty() and not _resume_consumed:
		var receipt = JSON.parse_string(FileAccess.get_file_as_string(_resume_file))
		if not receipt is Dictionary or receipt.get("schema") != 1 or not receipt.get("completed_results") is Dictionary:
			status.text = "续接记录无效；未启动或跳过任何阶段。"
			return
		completed_prefix = receipt.completed_results
		_resume_consumed = true
	flow.start(Catalog.integrated_demo(output_directory, level_options), host, factories, false, completed_prefix)
	_set_title()

func finish_drawing() -> void:
	if not is_instance_valid(flow.current_stage) or not flow.current_stage.has_method("export_to"): return
	var error: String = flow.current_stage.export_to(flow.current_stage.stage_config.export_path)
	if not error.is_empty(): status.text = error
	else: _refresh(flow.progress())

func _refresh(progress: Dictionary) -> void:
	var compact: bool = progress.index >= 0 and bool(flow.config.stages[progress.index].get("compact_header", false))
	_header_title.visible = not compact
	_layout_column.add_theme_constant_override("separation", 8 if compact else 12)
	for side in ["left", "top", "right", "bottom"]: _layout_margin.add_theme_constant_override("margin_" + side, 12 if compact else 20)
	_observe_drawing_document()
	next_button.disabled = _advancing or not flow.can_advance() or progress.index == progress.total - 1
	next_button.visible = not _auto_enabled()
	export_button.visible = is_instance_valid(flow.current_stage) and flow.current_stage.has_method("export_to")
	export_button.disabled = flow.can_advance() or not is_instance_valid(flow.current_stage)
	optional_button.visible = progress.finished
	local_button.visible = progress.finished
	replay_button.visible = progress.finished and not replay_image_path.is_empty()
	var current_title := str(flow.config.stages[progress.index].get("title", "")) if progress.index >= 0 else ""
	status.text = "关卡进度 %d/%d · %s · %s" % [progress.completed_count, progress.total, current_title, flow.config.get("notice", "")]
	if progress.finished: status.text = "本轮拼装与绘画已完成 · 可选本机生图或离线模拟；打开面板不会自动发送。"
	status.add_theme_font_size_override("font_size", 13)
	status.add_theme_color_override("font_color", Presentation.MUTED)
	if _auto_enabled() and flow.can_advance() and progress.index < progress.total - 1:
		var item: Dictionary = flow.config.stages[progress.index]
		var next: Dictionary = flow.config.stages[progress.index + 1]
		status.text = "%s · %s（约2秒后自动进入）" % [item.get("completion_text", "%s已完成" % current_title), next.get("entry_label", "进入" + str(next.get("title", "下一阶段")))]
		status.add_theme_font_size_override("font_size", 18)
		status.add_theme_color_override("font_color", Presentation.ACCENT)
	if not progress.error.is_empty(): status.text += " · " + progress.error


func _observe_drawing_document() -> void:
	var document: RefCounted
	if is_instance_valid(flow.current_stage) and flow.current_stage.has_method("export_to"):
		var surface = flow.current_stage.get("surface")
		if is_instance_valid(surface): document = surface.document
	if document == _drawing_document: return
	if _drawing_document != null and _drawing_document.changed.is_connected(_on_drawing_changed):
		_drawing_document.changed.disconnect(_on_drawing_changed)
	_drawing_document = document
	if _drawing_document != null: _drawing_document.changed.connect(_on_drawing_changed)

func _on_drawing_changed() -> void:
	_refresh(flow.progress())

func _set_title() -> void:
	DisplayServer.window_set_title("关卡拼装与绘画 · integrated_demo.tscn")

func open_optional_mock() -> void:
	_open_generation("offline_mock")

func open_local_generation() -> void:
	if not _local_config_error.is_empty() or local_port < 1 or local_port > 65535:
		status.text = _local_config_error if not _local_config_error.is_empty() else "本机端口无效。"
		return
	_open_generation("local_official" if official_enabled else "local_stub")

func open_recorded_replay() -> void:
	if not replay_image_path.is_empty(): _open_generation("recorded_replay")

func _open_generation(backend: String) -> void:
	if not flow.progress().finished: return
	close_optional_mock()
	_optional_serial += 1
	optional_window = Window.new()
	optional_window.title = "本机真实生成 · 仅手动提交，可能计费" if backend == "local_official" else "本机 HTTP STUB · 非真实 AI" if backend == "local_stub" else "可选离线 MOCK · 非真实 AI 生成"
	optional_window.size = Vector2i(1180, 740)
	if backend == "recorded_replay": optional_window.title = "已有官方图片 · 离线回放 · 本次不发送请求"
	optional_window.close_requested.connect(close_optional_mock)
	add_child(optional_window)
	var background := ColorRect.new()
	background.color = Presentation.BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	optional_window.add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 18)
	optional_window.add_child(margin)
	optional_stage = Generation.new()
	optional_stage.return_requested.connect(close_optional_mock)
	optional_stage.theme = theme
	margin.add_child(optional_stage)
	var config: Dictionary = flow.config.optional_generation.duplicate(true)
	config["backend"] = backend
	config["replay_image_path"] = replay_image_path
	config["local_port"] = local_port
	config["official_enabled"] = official_enabled
	config.output_path = output_directory.path_join("%s_result_%d.png" % [backend, _optional_serial])
	var error: String = optional_stage.enter_stage(config, {"level_id": flow.config.id,
		"results": flow.results.duplicate(true), "mock_mode": false, "demonstration": true})
	if not error.is_empty(): status.text = error; close_optional_mock(); return
	optional_window.popup_centered()

func close_optional_mock() -> void:
	if is_instance_valid(optional_stage): optional_stage.exit_stage()
	optional_stage = null
	if is_instance_valid(optional_window):
		optional_window.hide()
		optional_window.queue_free()
	optional_window = null

func _exit_tree() -> void:
	_cancel_auto_advance()
	close_optional_mock()
	if is_instance_valid(flow): flow.stop()

func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _auto_enabled() -> bool:
	return is_instance_valid(flow) and bool(flow.config.get("auto_advance", {}).get("enabled", false))

func _cancel_auto_advance() -> void:
	_auto_stage_instance = 0
	_auto_elapsed = 0.0

func _process(delta: float) -> void:
	if not _auto_enabled() or _advancing or not is_instance_valid(flow.current_stage):
		_cancel_auto_advance()
		return
	var progress: Dictionary = flow.progress()
	if progress.index < 0 or progress.index >= progress.total - 1:
		_cancel_auto_advance()
		return
	var stage: Control = flow.current_stage
	if stage.has_method("is_stage_complete") and not stage.is_stage_complete():
		_cancel_auto_advance()
		if flow.results.has(progress.stage_id): flow.revoke_current_completion()
		return
	if not flow.can_advance():
		_cancel_auto_advance()
		return
	if _auto_stage_instance != stage.get_instance_id():
		_auto_stage_instance = stage.get_instance_id()
		_auto_elapsed = 0.0
		_refresh(progress)
	_auto_elapsed += delta
	if _auto_elapsed >= float(flow.config.auto_advance.get("delay_seconds", 2.0)): advance_stage()

func advance_stage() -> void:
	if _advancing or not is_instance_valid(flow) or not flow.can_advance(): return
	_advancing = true
	_cancel_auto_advance()
	var error: String = flow.advance()
	_set_title()
	if not error.is_empty(): status.text = error
	call_deferred("_release_advance", _run_serial)

func _release_advance(serial: int) -> void:
	if serial != _run_serial: return
	_advancing = false
	_refresh(flow.progress())

func _report_launch_identity() -> void:
	var scene := get_tree().current_scene
	print("LEVEL_ENTRY ", JSON.stringify({"current_scene":scene.scene_file_path if is_instance_valid(scene) else "", "local_mode":local_mode, "local_port":local_port, "resume_consumed":_resume_consumed, "stage_id":flow.progress().stage_id, "completed_count":flow.results.size()}))
