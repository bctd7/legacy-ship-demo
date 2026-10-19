extends Control
const Service = preload("res://image_generation/service.gd")
const Request = preload("res://image_generation/request.gd")
const Proxy = preload("res://image_generation/proxy_provider.gd")
const Mock = preload("res://image_generation/mock_transport.gd")
var service: Node
var input: Image
var prompt: LineEdit
var status: Label
var output: TextureRect
var mode: OptionButton
var job: RefCounted

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]: margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)
	var title := Label.new()
	title.text = "图像服务独立验收 · OFFLINE MOCK · 非真实 AI 生图"
	title.add_theme_font_size_override("font_size", 25)
	column.add_child(title)
	var note := Label.new()
	note.text = "合成图片 + 提示词 → 按提示词哈希着色的模拟图片。全程离线，无密钥、上传或费用。"
	column.add_child(note)
	var pictures := HBoxContainer.new()
	pictures.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(pictures)
	input = Image.create(320, 240, false, Image.FORMAT_RGBA8)
	input.fill(Color(0.88, 0.92, 0.96))
	input.fill_rect(Rect2i(60, 60, 200, 120), Color(0.18, 0.38, 0.58))
	for label in ["输入：代码合成图片", "输出：MOCK 模拟结果"]:
		var panel := VBoxContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pictures.add_child(panel)
		var caption := Label.new()
		caption.text = label
		panel.add_child(caption)
		var view := TextureRect.new()
		view.custom_minimum_size = Vector2(320, 240)
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		panel.add_child(view)
		if output == null: view.texture = ImageTexture.create_from_image(input)
		output = view
	prompt = LineEdit.new()
	prompt.text = "将画面变为暖色水彩风格（模拟）"
	column.add_child(prompt)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	mode = OptionButton.new()
	for label in ["成功模拟", "限流错误", "超时", "无效响应", "网络错误"]: mode.add_item(label)
	actions.add_child(mode)
	var generate := Button.new()
	generate.text = "运行离线模拟"
	generate.pressed.connect(_generate)
	actions.add_child(generate)
	var cancel := Button.new()
	cancel.text = "取消当前请求"
	cancel.pressed.connect(func():
		if job != null: job.cancel())
	actions.add_child(cancel)
	status = Label.new()
	status.text = "等待运行。先选“超时”再取消，可验收取消路径。"
	column.add_child(status)
	service = Service.new()
	var provider := Proxy.new()
	provider.endpoint = "https://offline.invalid/image-generation"
	service.provider = provider
	service.transport_factory = func():
		var transport := Mock.new()
		transport.mode = ["success", "error", "hang", "malformed", "network"][mode.selected]
		transport.delay_seconds = 0.8
		return transport
	add_child(service)

func _generate() -> void:
	if job != null and not job.done: job.cancel()
	output.texture = null
	var request := Request.new(input, prompt.text)
	request.timeout_seconds = 3.0
	status.text = "运行离线模拟中……"
	job = service.generate(request)
	job.finished.connect(func(result):
		if result.ok:
			output.texture = ImageTexture.create_from_image(result.image)
			status.text = "MOCK 成功：模拟图片已返回；非真实 AI 生图。"
		else:
			status.text = "MOCK 结果：%s · %s（不自动重试）" % [result.error.code, result.error.message])
