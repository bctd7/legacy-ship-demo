extends SceneTree
const Service = preload("res://image_generation/service.gd")
const Request = preload("res://image_generation/request.gd")
const Provider = preload("res://image_generation/loopback_provider.gd")
const Transport = preload("res://image_generation/loopback_transport.gd")
const Demo = preload("res://image_generation/loopback_demo.gd")
var checks := 0
var failures := 0
var port := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--local-port="): port = int(argument.trim_prefix("--local-port="))
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("LOOPBACK_HTTP_PASS: " if ok else "LOOPBACK_HTTP_FAIL: ") + label)

func run() -> void:
	var provider := Provider.new()
	provider.port = port
	var service := Service.new()
	service.provider = provider
	service.transport_factory = func(): return Transport.new()
	root.add_child(service)
	var source: Image = Demo.bridge_drawing()
	var request := Request.new(source, "synthetic bridge plus blue pencil line; no boat")
	var job = service.generate(request)
	var result = await job.finished
	check(result.ok and result.image.get_data() == source.get_data(), "actual localhost HTTP echoes bridge drawing as explicit stub")
	check(result.ok and ImageTexture.create_from_image(result.image).get_width() == 320, "returned HTTP image is displayable")
	job = service.generate(request)
	result = await job.finished
	check(result.ok, "identical content can reuse the local receipt without a second generation")
	request.prompt = "synthetic bridge cancellation; no boat"
	job = service.generate(request)
	await create_timer(0.12).timeout
	job.cancel()
	check(job.done and job.result.error.code == "cancelled", "cancel stops a real HTTP wait")
	await create_timer(0.35).timeout
	check(job.result.error.code == "cancelled", "late HTTP completion cannot replace cancellation")
	request.prompt = "synthetic bridge timeout; no boat"
	request.timeout_seconds = 0.12
	job = service.generate(request)
	result = await job.finished
	check(result.error.code == "timeout" and result.error.outcome_unknown, "real HTTP deadline returns timeout without pretending remote cancellation")
	await create_timer(0.35).timeout
	provider.expected_mode = "official"
	job = service.generate(Request.new(source, "mode mismatch must not submit"))
	result = await job.finished
	check(not result.ok, "official-selected client does not submit to or relabel a stub server")
	var transport := Transport.new()
	root.add_child(transport)
	check(transport.start({"url": "http://192.168.0.1:8769/v1/images/generate", "local_mode": "stub"}, func(_r): pass) == ERR_UNAUTHORIZED, "LAN endpoint rejected before request")
	check(transport.start({"url": "http://127.0.0.1:8769/v1/images/generate?url=https://elsewhere.invalid", "local_mode": "stub"}, func(_r): pass) == ERR_UNAUTHORIZED, "query-based forwarding cannot bypass loopback policy")
	transport.queue_free()
	service.queue_free()
	var demo := Demo.new()
	root.add_child(demo)
	await process_frame
	check(demo.local_mode == "stub" and demo.input.get_data() == source.get_data(), "demo defaults to explicit stub and synthetic bridge-only input")
	demo._generate()
	var first_job = demo.job
	demo._generate()
	check(demo.job == first_job and demo.send_button.disabled, "duplicate button action cannot create a second inflight job")
	await create_timer(0.4).timeout
	check(demo.job.done and demo.job.result.ok and demo.output.texture != null and demo.status.text.contains("STUB"), "local HTTP demo displays output and labels it non-AI")
	demo.queue_free()
	await process_frame
	print("LOOPBACK_HTTP_CHECKS: %d passed / %d total; actual HTTP, stub only" % [checks - failures, checks])
	quit(1 if failures else 0)
