extends "res://image_generation/demo.gd"
## A directly runnable real HTTP loopback demo, STUB by default; no boats.
const LocalProvider = preload("res://image_generation/loopback_provider.gd")
const LocalTransport = preload("res://image_generation/loopback_transport.gd")
var local_mode := "stub"
var local_port := 8769
var request_timeout := 120.0
var send_button: Button
var cancel_button: Button

static func bridge_drawing() -> Image:
	var drawing := Image.create(320, 240, false, Image.FORMAT_RGBA8)
	drawing.fill(Color(0.97, 0.95, 0.9))
	drawing.fill_rect(Rect2i(35, 125, 250, 18), Color(0.40, 0.24, 0.12))
	for x in [65, 145, 225]:
		drawing.fill_rect(Rect2i(x, 140, 18, 58), Color(0.50, 0.31, 0.15))
	for x in range(45, 275, 30):
		drawing.fill_rect(Rect2i(x, 100, 6, 26), Color(0.50, 0.31, 0.15))
	drawing.fill_rect(Rect2i(42, 100, 237, 6), Color(0.50, 0.31, 0.15))
	drawing.fill_rect(Rect2i(18, 207, 284, 5), Color(0.2, 0.5, 0.7))
	# A drawn blue pencil line, synthesized without external/ship assets.
	for x in range(45, 280): drawing.fill_rect(Rect2i(x, 53 + x / 20, 3, 3), Color(0.16, 0.35, 0.7))
	return drawing

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--local-port="): local_port = int(argument.trim_prefix("--local-port="))
		if argument == "--local-mode=official": local_mode = "official"
	super._ready()
	service.queue_free()
	service = Service.new()
	var provider := LocalProvider.new()
	provider.port = local_port
	provider.expected_mode = local_mode
	service.provider = provider
	service.transport_factory = func(): return LocalTransport.new()
	add_child(service)
	input = bridge_drawing()
	var pictures := find_children("*", "TextureRect", true, false)
	pictures[0].texture = ImageTexture.create_from_image(input)
	for label in find_children("*", "Label", true, false):
		if label.text.begins_with("图像服务独立验收"):
			label.text = "本机 HTTP 联通 · STUB 回传 · 非真实 AI" if local_mode == "stub" else "真实 AI 模式 · 本机服务 → 火山官方 Seedream Pro"
		elif label.text.begins_with("合成图片 +"):
			label.text = "仅桥与绘画的合成测试图，不含船。默认 stub 原图回传，用于验证真正本机 HTTP。"
		elif label.text.begins_with("输入："): label.text = "输入：桥＋绘画合成图（无个人内容）"
		elif label.text.begins_with("输出："): label.text = "输出：STUB 原图回传（非 AI）" if local_mode == "stub" else "输出：真实官方生成结果"
	for button in find_children("*", "Button", true, false):
		if button.text == "运行离线模拟": send_button = button
		if button.text == "取消当前请求": cancel_button = button
	mode.hide()
	send_button.text = "发送本机 STUB 请求" if local_mode == "stub" else "提交一次真实生成请求"
	prompt.text = "保持这座木桥的轮廓与手绘构图，转为细腻的水彩画。"
	status.text = "尚未发送请求。服务须在本机启动；模式不匹配会停止，不会自动切换。"

func _generate() -> void:
	if job != null and not job.done: return # Repeated clicks never submit concurrently.
	output.texture = null
	var request := Request.new(input, prompt.text)
	request.timeout_seconds = request_timeout
	send_button.disabled = true
	prompt.editable = false
	status.text = "等待本机 STUB 回传（非 AI）……" if local_mode == "stub" else "等待火山官方生成；可取消本地等待，费用可能已发生。"
	job = service.generate(request)
	job.finished.connect(func(result):
		send_button.disabled = false
		prompt.editable = true
		if result.ok:
			output.texture = ImageTexture.create_from_image(result.image)
			status.text = "STUB HTTP 往返成功：回传输入图，非真实 AI，未调用外部模型。" if local_mode == "stub" else "真实官方生成成功。重复相同内容会复用本机已有结果。"
		else:
			status.text = "请求结束 [%s]：%s；不自动重试。" % [result.error.code, result.error.message])
