extends "res://levels/stage.gd"
signal return_requested
const Result = preload("res://image_generation/result.gd")
const Job = preload("res://image_generation/job.gd")
## Thin host adapter. Existing services own protocol, timeout and job semantics.
const Service = preload("res://image_generation/service.gd")
const Request = preload("res://image_generation/request.gd")
const Proxy = preload("res://image_generation/proxy_provider.gd")
const MockTransport = preload("res://image_generation/mock_transport.gd")
const Handoff = preload("res://levels/generation_handoff.gd")
const LocalProvider = preload("res://image_generation/loopback_provider.gd")
const LocalTransport = preload("res://image_generation/loopback_transport.gd")
var service: Node
var job: RefCounted
var input_image: Image
var output_image: Image
var prompt: LineEdit
var mode: OptionButton
var generate_button: Button
var cancel_button: Button
var status: Label
var output_view: TextureRect
var state := "idle"
var request_epoch := 0
var timeout_seconds := 2.0
var mock_delay := 0.5
var submitted_prompt := ""
var backend := "offline_mock"
var official_enabled := false

func enter_stage(config: Dictionary, context: Dictionary) -> String:
	var error := super.enter_stage(config, context)
	if not error.is_empty(): return error
	if not context.get("demonstration", false): return "Generation preview requires demonstration mode."
	backend = str(config.get("backend", "offline_mock"))
	if backend not in ["offline_mock", "local_stub", "local_official", "recorded_replay"]: return "Unknown generation backend."
	official_enabled = bool(config.get("official_enabled", false))
	if backend != "offline_mock": timeout_seconds = float(config.get("timeout_seconds", 120.0))
	var drawing: Dictionary = context.get("results", {}).get(str(config.get("input_stage", "drawing")), {})
	var handoff := Handoff.prepare(drawing, "input check")
	if not handoff.ok: return str(handoff.message)
	input_image = Image.load_from_file(str(handoff.request.input_texture_path))
	if input_image == null or input_image.is_empty(): return "The exported drawing image cannot be loaded."
	_build_ui()
	if backend == "recorded_replay":
		_set_state("idle", "离线回放：右图来自此前独立真实 API 调用，并非根据本次左侧画纸重新生成。不会创建网络服务或发送请求。")
		return ""
	service = Service.new()
	if backend == "offline_mock":
		var provider := Proxy.new()
		provider.endpoint = "https://offline.invalid/image-generation"
		service.provider = provider
		service.transport_factory = func():
			var transport := MockTransport.new()
			transport.mode = ["success", "error", "hang", "malformed", "network"][mode.selected]
			transport.delay_seconds = mock_delay
			return transport
	else:
		var provider := LocalProvider.new()
		provider.port = int(config.get("local_port", 8769))
		provider.expected_mode = "official" if backend == "local_official" else "stub"
		service.provider = provider
		service.transport_factory = func(): return LocalTransport.new()
	add_child(service)
	_set_state("idle", "尚未发送。%s" % ("本机真实模式须用户安全配置并明确点击提交；取消不保证停止计费。" if backend == "local_official" else "本机 STUB 仅回传绘画 PNG，非真实 AI。" if backend == "local_stub" else "使用导出的真实纸面 PNG 与提示词执行离线模拟。"))
	return ""

func request_generation() -> void:
	if not active or _reported or state == "waiting": return
	if backend == "local_official" and not official_enabled:
		_set_state("blocked", "真实发送未启用；请在安全配置确认后使用明确的 official 启动入口。未发送请求。")
		return
	request_epoch += 1
	var token := request_epoch
	output_image = null
	output_view.texture = null
	submitted_prompt = prompt.text
	if backend == "recorded_replay":
		submitted_prompt = ""
		_set_state("waiting", "正在读取已有图片；离线回放，不发送请求。")
		job = Job.new()
		job.finished.connect(func(result): _received(result, token))
		var replay_job = job
		job.cancel_requested.connect(func(): replay_job.complete(Result.failure("cancelled", "Offline replay cancelled.")))
		call_deferred("_complete_replay", job, token)
		return
	var request := Request.new(input_image, submitted_prompt)
	request.timeout_seconds = timeout_seconds
	_set_state("waiting", "等待本机官方生成…可停止本地等待，费用可能已发生。" if backend == "local_official" else "等待本机 HTTP STUB 回传…非真实 AI。" if backend == "local_stub" else "离线 MOCK 处理中…可取消。没有请求真实 AI 服务。")
	job = service.generate(request)
	job.finished.connect(func(result): _received(result, token))

func _complete_replay(replay_job: RefCounted, token: int) -> void:
	if replay_job.done or not active or token != request_epoch: return
	var path := str(stage_config.get("replay_image_path", ""))
	if path.is_empty() or not FileAccess.file_exists(path):
		replay_job.complete(Result.failure("replay_missing", "已有结果图片不存在；请检查回放路径。"))
		return
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		replay_job.complete(Result.failure("replay_invalid", "已有结果图片无法解码。"))
		return
	# Same Job.finished -> _received -> save/display/result path, without a service.
	replay_job.complete(Result.success(image))

func cancel_request() -> void:
	if state != "waiting": return
	request_epoch += 1
	var previous = job
	job = null
	if previous != null and not previous.done: previous.cancel()
	_set_state("cancelled", "已停止本地等待；服务可能继续处理，结果与费用待核对，不自动重试。" if backend == "local_official" else "已取消本次等待，不自动重试。可手动重试。")

func _received(result: RefCounted, token: int) -> void:
	if not active or token != request_epoch or _reported: return
	job = null
	if not result.ok:
		if backend == "recorded_replay":
			_set_state("failed", "离线回放失败 [%s]：%s 不发送请求；可检查路径后手动重试或返回绘画。" % [result.error.code, result.error.message])
			return
		var note := "结果或费用待核对；" if backend == "local_official" and result.error.get("outcome_unknown", false) else ""
		_set_state("failed", "请求失败 [%s]：%s；%s不自动重试。本机服务须与所选模式一致。" % [result.error.code, result.error.message, note])
		return
	var path := str(stage_config.get("output_path", ""))
	var error: Error = result.image.save_png(path)
	if error != OK:
		_set_state("failed", "结果保存失败：%s；不自动重试。" % error_string(error))
		return
	output_image = result.image
	output_view.texture = ImageTexture.create_from_image(output_image)
	_set_state("succeeded", "真实官方生成成功（本机服务校验 official 来源）。" if backend == "local_official" else "本机 STUB HTTP 联通成功：回传原始绘画，非真实 AI。" if backend == "local_stub" else "离线 MOCK 完成：仅按提示词哈希着色，不理解语义，非真实 AI 生成。")
	if backend == "recorded_replay":
		_set_state("succeeded", "离线回放完成 · %d × %d · 保持原图比例。此图来自此前独立真实 API 调用，本次未发送请求，也未根据左侧画纸重新生成。" % [output_image.get_width(), output_image.get_height()])
	report("completed", {"texture_path": path, "input_texture_path": stage_context.results[stage_config.input_stage].payload.texture_path,
		"prompt": submitted_prompt, "mock_generation": backend != "local_official", "generation_mode": backend,
		"replay": backend == "recorded_replay",
		"source": "recorded_official_result" if backend == "recorded_replay" else "volcengine_official" if backend == "local_official" else "local_stub" if backend == "local_stub" else "offline_mock",
		"contains_placeholder_assets": stage_context.results[stage_config.input_stage].payload.get("contains_placeholder_assets", false)})

func exit_stage() -> void:
	super.exit_stage()
	request_epoch += 1
	if job != null and not job.done: job.cancel()
	job = null
	state = "closed"

func _exit_tree() -> void:
	if active: exit_stage()

func _set_state(value: String, message: String) -> void:
	state = value
	status.text = message
	generate_button.disabled = value == "waiting" or value == "succeeded" or backend == "local_official" and not official_enabled
	generate_button.text = "手动重试 / 读取回执" if value in ["failed", "cancelled"] else "提交一次真实生成请求" if backend == "local_official" else "发送本机 STUB 请求" if backend == "local_stub" else "运行离线模拟"
	cancel_button.disabled = value != "waiting"
	prompt.editable = value != "waiting" and value != "succeeded"
	mode.disabled = value == "waiting" or value == "succeeded"
	if backend == "recorded_replay":
		generate_button.text = "重试读取已有图片" if value in ["failed", "cancelled"] else "显示已生成图片（离线）"
		prompt.editable = false

func _build_ui() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var title := Label.new()
	title.text = "真实绘画 PNG → 本机服务 → 官方 AI" if backend == "local_official" else "真实绘画 PNG → 本机 HTTP STUB（非 AI）" if backend == "local_stub" else "真实绘画 PNG → 离线 MOCK（非真实 AI 生图）"
	title.add_theme_font_size_override("font_size", 24)
	if backend == "recorded_replay": title.text = "已生成结果 · 离线回放（本次不发送请求）"
	column.add_child(title)
	var pictures := HBoxContainer.new()
	pictures.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(pictures)
	_picture(pictures, "输入：上一步导出的纸面", input_image)
	output_view = _picture(pictures, "输出：真实官方结果" if backend == "local_official" else "输出：STUB 原图回传（非 AI）" if backend == "local_stub" else "输出：离线模拟结果", null)
	prompt = LineEdit.new()
	if backend == "recorded_replay": (output_view.get_parent().get_child(0) as Label).text = "此前官方结果 · 等比显示 · 非本次新生成"
	prompt.text = str(stage_config.get("prompt", "请根据完整输入画布生成图片，保留主要内容与构图。"))
	prompt.tooltip_text = prompt.text
	prompt.placeholder_text = "输入提示词"
	column.add_child(prompt)
	prompt.visible = backend != "recorded_replay"
	var actions := HBoxContainer.new()
	column.add_child(actions)
	mode = OptionButton.new()
	for label in ["成功模拟", "限流失败", "超时", "无效响应", "网络错误"]: mode.add_item(label)
	mode.visible = backend == "offline_mock"
	actions.add_child(mode)
	generate_button = Button.new()
	generate_button.pressed.connect(request_generation)
	actions.add_child(generate_button)
	cancel_button = Button.new()
	cancel_button.text = "停止本地等待" if backend == "local_official" else "取消当前请求"
	cancel_button.pressed.connect(cancel_request)
	actions.add_child(cancel_button)
	var return_button := Button.new()
	return_button.text = "返回绘画"
	return_button.pressed.connect(func(): return_requested.emit())
	actions.add_child(return_button)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.y = 48
	column.add_child(status)

func _picture(parent: Control, caption: String, image: Image) -> TextureRect:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var label := Label.new()
	label.text = caption
	column.add_child(label)
	var view := TextureRect.new()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(260, 180)
	if image != null: view.texture = ImageTexture.create_from_image(image)
	column.add_child(view)
	return view
