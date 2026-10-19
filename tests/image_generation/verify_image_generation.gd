extends SceneTree
const Service = preload("res://image_generation/service.gd")
const Request = preload("res://image_generation/request.gd")
const Proxy = preload("res://image_generation/proxy_provider.gd")
const OpenAI = preload("res://image_generation/openai_provider.gd")
const Mock = preload("res://image_generation/mock_transport.gd")
const Http = preload("res://image_generation/http_transport.gd")
const Codec = preload("res://image_generation/codec.gd")
const Demo = preload("res://image_generation/demo.gd")
var checks := 0
var failures := 0
var calls := 0
var mode := "success"
var last_transport: Node

class ImmediateTransport extends Node:
	var reply: Dictionary
	var callback: Callable
	func start(_wire: Dictionary, target: Callable) -> int:
		callback = target
		target.call(reply)
		target.call({"status": 503}) # A duplicate callback must not replace success.
		return OK
	func cancel() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("IMAGE_GENERATION_PASS: " if value else "IMAGE_GENERATION_FAIL: ") + label)

func factory() -> Node:
	calls += 1
	last_transport = Mock.new()
	last_transport.mode = mode
	last_transport.delay_seconds = 0.02
	return last_transport

func wait_job(job: RefCounted):
	if job.done: return job.result
	return await job.finished

func run() -> void:
	var source := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	source.fill(Color.BLUE)
	var service := Service.new()
	var proxy := Proxy.new()
	proxy.endpoint = "https://offline.invalid/image-generation"
	service.provider = proxy
	service.transport_factory = factory
	root.add_child(service)
	var request := Request.new(source, "synthetic warm tint")
	var job = service.generate(request)
	var result = await wait_job(job)
	check(result.ok and result.image.get_size() == source.get_size(), "image plus prompt returns exactly one image offline")
	check(result.image.get_pixel(0, 0) != source.get_pixel(0, 0), "mock changes output and preserves caller image")
	var first: PackedByteArray = result.image.get_data()
	result = await wait_job(service.generate(request))
	check(result.image.get_data() == first, "mock is deterministic")
	var snapshot_job = service.generate(request)
	request.prompt = "changed after generate"
	source.fill(Color.RED)
	result = await wait_job(snapshot_job)
	check(result.image.get_data() == first, "request snapshots prompt and image before deferred dispatch")
	var concurrent_a = service.generate(request)
	var concurrent_b = service.generate(request)
	var concurrent_result_a = await wait_job(concurrent_a)
	var concurrent_result_b = await wait_job(concurrent_b)
	check(concurrent_result_a.ok and concurrent_result_b.ok, "concurrent jobs use separate transports")
	var original_calls := calls
	result = await wait_job(service.generate(Request.new(null, "x")))
	check(not result.ok and result.error.code == "invalid_input" and calls == original_calls, "null image rejected before transport")
	result = await wait_job(service.generate(Request.new(source, "  ")))
	check(result.error.code == "invalid_input" and calls == original_calls, "empty prompt rejected before transport")
	var invalid := Request.new(source, "x")
	invalid.timeout_seconds = NAN
	result = await wait_job(service.generate(invalid))
	check(result.error.code == "invalid_input", "nonfinite timeout rejected")
	var cancelled = service.generate(request)
	cancelled.cancel()
	result = await wait_job(cancelled)
	check(result.error.code == "cancelled" and not result.error.outcome_unknown and calls == original_calls, "cancel before dispatch has no transport")
	mode = "hang"
	request.timeout_seconds = 0.03
	result = await wait_job(service.generate(request))
	check(result.error.code == "timeout" and result.error.outcome_unknown and not result.error.automatic_retry, "timeout reports unknown remote outcome and no retry")
	request.timeout_seconds = 1.0
	job = service.generate(request)
	await process_frame
	var finished_count := [0]
	job.finished.connect(func(_r): finished_count[0] += 1)
	job.cancel()
	job.cancel()
	check(job.result.error.code == "cancelled" and job.result.error.outcome_unknown and finished_count[0] == 1, "inflight cancellation completes once")
	mode = "error"
	original_calls = calls
	result = await wait_job(service.generate(request))
	check(result.error.code == "rate_limited" and result.error.http_status == 429 and calls == original_calls + 1, "429 produces structured error with one attempt")
	mode = "network"
	result = await wait_job(service.generate(request))
	check(result.error.code == "network" and result.error.outcome_unknown, "network failure is ambiguous")
	mode = "malformed"
	result = await wait_job(service.generate(request))
	check(result.error.code == "invalid_response", "malformed success rejected")
	check(not Codec.from_base64("bad!data").ok, "invalid base64 rejected")
	var bomb := source.save_png_to_buffer()
	bomb[16] = 127
	check(not Codec.from_base64(Marshalls.raw_to_base64(bomb)).ok, "oversized PNG header rejected before decoder")
	var openai := OpenAI.new()
	check(openai.encode({}).has("failure"), "direct provider disabled by default")
	openai.enable_direct_local_development = true
	openai.model = "gpt-image-2"
	var wire: Dictionary = openai.encode({"png": source.save_png_to_buffer(), "prompt": "synthetic"}).wire
	var body = JSON.parse_string(wire.body.get_string_from_utf8())
	check(wire.url == "https://api.openai.com/v1/images/edits" and body.n == 1 and body.output_format == "png" and body.images[0].image_url.begins_with("data:image/png;base64,"), "OpenAI official JSON edit request shape")
	check(not str(wire.headers).contains("Authorization"), "adapter does not contain or fetch credentials")
	service.provider = openai
	mode = "success"
	result = await wait_job(service.generate(request))
	check(result.ok, "OpenAI response contract tested against offline fixture")
	var fixture := {"data": [{"b64_json": Marshalls.raw_to_base64(source.save_png_to_buffer())}]}
	service.transport_factory = func():
		var transport := ImmediateTransport.new()
		transport.reply = {"status": 200, "body": JSON.stringify(fixture).to_utf8_buffer()}
		return transport
	job = service.generate(request)
	result = await wait_job(job)
	check(result.ok and job.result.ok, "synchronous and duplicate transport callbacks finish once")
	service.transport_factory = factory
	result = openai.decode(503, "{\"error\":\"private upstream text\"}".to_utf8_buffer())
	check(result.error.code == "provider_error" and result.error.outcome_unknown and not str(result.error).contains("private"), "provider errors are sanitized")
	var http := Http.new()
	root.add_child(http)
	check(http.start(wire, func(_r): pass) == ERR_UNAUTHORIZED, "HTTP transport defaults to deny without network access")
	http.enabled = true
	check(http.start(wire, func(_r): pass) == ERR_UNAUTHORIZED, "HTTP exact endpoint allowlist required")
	http.queue_free()
	service.provider = proxy
	mode = "hang"
	job = service.generate(request)
	await process_frame
	service.queue_free()
	await process_frame
	check(job.done and job.result.error.code == "cancelled", "service teardown cancels outstanding jobs")
	var demo := Demo.new()
	root.add_child(demo)
	await process_frame
	demo._generate()
	await create_timer(0.95).timeout
	check(demo.job.done and demo.job.result.ok and demo.output.texture != null, "standalone demo success path")
	if DisplayServer.get_name() != "headless":
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--capture="):
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(argument.trim_prefix("--capture="))
	demo.mode.select(2)
	demo._generate()
	await process_frame
	demo.job.cancel()
	check(demo.job.result.error.code == "cancelled", "standalone demo cancel path")
	demo.queue_free()
	await process_frame
	print("IMAGE_GENERATION_CHECKS: %d passed / %d total; offline only" % [checks - failures, checks])
	quit(1 if failures else 0)
