extends SceneTree
const Provider = preload("res://image_generation/ark_seedream_provider.gd")
const Service = preload("res://image_generation/service.gd")
const Request = preload("res://image_generation/request.gd")
const Http = preload("res://image_generation/http_transport.gd")
const Jpeg = preload("res://image_generation/jpeg_codec.gd")
const Budget = preload("res://image_generation/ark_call_budget.gd")
const ArkHttp = preload("res://image_generation/ark_http_transport.gd")
var checks := 0
var failures := 0

class FixtureTransport extends Node:
	var body: PackedByteArray
	var hang := false
	func start(_wire: Dictionary, callback: Callable) -> int:
		if not hang: callback.call({"status": 200, "body": body})
		return OK
	func cancel() -> void:
		pass

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("ARK_OFFLINE_PASS: " if ok else "ARK_OFFLINE_FAIL: ") + label)

func run() -> void:
	var source := Image.create(32, 24, false, Image.FORMAT_RGB8)
	source.fill(Color(0.2, 0.4, 0.6))
	var provider := Provider.new()
	var snapshot := {"png": source.save_png_to_buffer(), "prompt": "合成测试图，保持构图"}
	check(provider.encode(snapshot).has("failure") and provider.model == Provider.MODEL_FLASH, "Flash is the selected default while direct network remains disabled")
	provider.enable_direct_local_development = true
	provider.model = "unverified-model"
	check(provider.encode(snapshot).has("failure"), "unverified model cannot silently change protocol")
	provider.model = Provider.MODEL_ID
	var wire: Dictionary = provider.encode(snapshot).wire
	var payload: Dictionary = JSON.parse_string(wire.body.get_string_from_utf8())
	check(wire.url == "https://ark.cn-beijing.volces.com/api/v3/images/generations" and payload.model == "doubao-seedream-4-5-251128", "verified mainland official endpoint and exact model ID")
	check(payload.image == "data:image/png;base64," + Marshalls.raw_to_base64(snapshot.png) and payload.prompt == snapshot.prompt, "one PNG data URL plus original prompt")
	check(payload.response_format == "b64_json" and payload.sequential_image_generation == "disabled" and payload.stream == false and payload.size == "2048x2048", "single image nonstream base64 response requested")
	check(payload.watermark and not payload.has("output_format") and not payload.has("n") and not payload.has("quality"), "4.5 format constraints and visible AI watermark preserved")
	check(not str(wire.headers).contains("Authorization"), "provider neither fetches nor stores credentials")
	var tiny := Image.create(14, 16, false, Image.FORMAT_RGB8)
	check(provider.encode({"png": tiny.save_png_to_buffer(), "prompt": "x"}).failure.error.code == "invalid_input", "official minimum input edge enforced before dispatch")
	var thin := Image.create(300, 16, false, Image.FORMAT_RGB8)
	check(provider.encode({"png": thin.save_png_to_buffer(), "prompt": "x"}).has("failure"), "official input aspect ratio enforced")
	var jpeg := source.save_jpg_to_buffer()
	var fixture := {"model": Provider.MODEL_ID, "data": [{"b64_json": Marshalls.raw_to_base64(jpeg), "size": "32x24"}]}
	var fixture_body := JSON.stringify(fixture).to_utf8_buffer()
	var result = provider.decode(200, fixture_body)
	check(result.ok and result.image.get_size() == source.get_size(), "official JPEG base64 response decoded to Image")
	var texture := ImageTexture.create_from_image(result.image)
	check(texture.get_size() == Vector2(source.get_size()), "decoded result can be displayed as a texture")
	provider.model = Provider.MODEL_LITE
	var lite_wire: Dictionary = provider.encode(snapshot).wire
	var lite_payload: Dictionary = JSON.parse_string(lite_wire.body.get_string_from_utf8())
	check(lite_payload.model == Provider.MODEL_LITE and lite_payload.output_format == "png" and lite_payload.sequential_image_generation == "disabled" and lite_payload.stream == false, "injected verified Lite ID uses separately verified PNG single-image parameters")
	var png_fixture := {"model": Provider.MODEL_LITE, "data": [{"b64_json": Marshalls.raw_to_base64(source.save_png_to_buffer())}]}
	result = provider.decode(200, JSON.stringify(png_fixture).to_utf8_buffer())
	check(result.ok and result.image.get_size() == source.get_size(), "Lite PNG output decoded without using 4.5 JPEG profile")
	check(not provider.decode(200, fixture_body).ok, "Lite profile rejects JPEG rather than silently accepting incorrect output")
	provider.model = "doubao-seedream-5-0-260128"
	check(provider.encode(snapshot).wire.url == Provider.ENDPOINT, "documented Lite canonical ID is injectable without changing official endpoint")
	provider.model = Provider.MODEL_PRO
	var pro_wire: Dictionary = provider.encode(snapshot).wire
	var pro_payload: Dictionary = JSON.parse_string(pro_wire.body.get_string_from_utf8())
	check(pro_payload.model == "doubao-seedream-5-0-pro-260628" and pro_wire.url == Provider.ENDPOINT, "selected Pro profile remains explicit and mainland official only")
	check(pro_payload.size == "2K" and pro_payload.optimize_prompt_options.mode == "standard" and pro_payload.layer_decomposition == false, "Pro quality-first standard 2K generation excludes layer decomposition")
	check(not pro_payload.has("sequential_image_generation") and not pro_payload.has("stream") and pro_payload.image is String and pro_payload.output_format == "png", "Pro omits unsupported group and streaming fields and uses one PNG reference")
	var pro_fixture := {"model": Provider.MODEL_PRO, "data": [{"b64_json": Marshalls.raw_to_base64(source.save_png_to_buffer())}]}
	check(provider.decode(200, JSON.stringify(pro_fixture).to_utf8_buffer()).ok, "Pro PNG output decodes independently of legacy JPEG restrictions")
	provider.model = Provider.MODEL_FLASH
	var flash_wire: Dictionary = provider.encode(snapshot).wire
	var flash_payload: Dictionary = JSON.parse_string(flash_wire.body.get_string_from_utf8())
	check(flash_payload.model == "doubao-seedream-5-0-flash-260915" and flash_wire.url == Provider.ENDPOINT, "Flash uses the verified exact official ID and mainland endpoint")
	check(flash_payload.size == "2K" and flash_payload.output_format == "png" and flash_payload.response_format == "b64_json" and not flash_payload.layer_decomposition, "Flash retains one reference, 2K PNG/base64 and disables layer decomposition")
	check(not flash_payload.has("stream") and not flash_payload.has("sequential_image_generation") and flash_payload.optimize_prompt_options.mode == "standard", "Flash omits unsupported stream/group/fast options")
	check(provider.decode(200, JSON.stringify(pro_fixture).to_utf8_buffer()).ok, "Flash decodes a synthetic single PNG response without live generation")
	provider.model = Provider.MODEL_ID
	check(not Jpeg.from_base64(Marshalls.raw_to_base64(source.save_png_to_buffer())).ok, "JPEG decoder rejects PNG instead of assuming a supported format")
	check(not Jpeg.from_base64("bad base64!").ok, "invalid base64 fails safely")
	var oversized_header := PackedByteArray([255, 216, 255, 192, 0, 8, 8, 127, 255, 127, 255, 0])
	check(not Jpeg.from_base64(Marshalls.raw_to_base64(oversized_header)).ok, "JPEG oversized dimensions rejected before pixel decode")
	check(not Jpeg.from_base64(Marshalls.raw_to_base64(PackedByteArray([255, 216, 255, 224, 255, 255]))).ok, "truncated JPEG segment rejected")
	for data in [{"data": []}, {"data": [{"url": "https://not-used.invalid/image.jpg"}]}, {"data": [{"error": {"message": "private"}}]}]:
		result = provider.decode(200, JSON.stringify(data).to_utf8_buffer())
		check(not result.ok and not str(result.error).contains("private"), "missing image and per-image errors never trigger URL download or expose upstream text")
	result = provider.decode(429, "{}".to_utf8_buffer())
	check(result.error.code == "rate_limited" and not result.error.automatic_retry, "rate limiting remains non-retrying")
	var http := Http.new()
	root.add_child(http)
	check(http.start(wire, func(_r): pass) == ERR_UNAUTHORIZED, "HTTP transport cannot send by default")
	http.queue_free()
	var budget := Budget.new()
	check(budget.reserve() == 0, "real generation authorization defaults to absent")
	budget.generation_authorized = true
	check(budget.reserve() == 0, "unknown unit price blocks generation even with approved ceiling")
	budget.unit_price_fen = 600 # Synthetic test price, not a vendor quote.
	var ticket := budget.reserve()
	budget.mark_started(ticket)
	check(ticket > 0 and budget.reserve() == 0 and budget.audit().call_count == 1 and budget.audit().reserved_fen == 600, "concurrent jobs share conservative budget reservations")
	budget.release_unstarted(ticket)
	check(budget.audit().reserved_fen == 600, "started or ambiguous calls cannot release budget on cancel or timeout")
	var rejected_budget := Budget.new()
	rejected_budget.generation_authorized = true
	rejected_budget.unit_price_fen = 100
	ticket = rejected_budget.reserve()
	rejected_budget.release_unstarted(ticket)
	check(rejected_budget.audit().call_count == 0 and rejected_budget.audit().reserved_fen == 0, "only a definitely unstarted request releases its reservation")
	var pro_budget := Budget.new()
	pro_budget.generation_authorized = true
	pro_budget.unit_price_fen = 60 # Approved public tier, no real calls in this test.
	for _i in range(16): pro_budget.mark_started(pro_budget.reserve())
	check(pro_budget.audit().call_count == 16 and pro_budget.audit().reserved_fen == 960 and pro_budget.reserve() == 0, "CNY 0.60 tier permits at most 16 calls within CNY 10")
	var first_test := Budget.new()
	first_test.generation_authorized = true
	first_test.unit_price_fen = 60
	first_test.max_calls = 1
	first_test.mark_started(first_test.reserve())
	check(first_test.reserve() == 0 and first_test.audit().call_count == 1, "host can cap initial real validation to one call")
	var ark_http := ArkHttp.new()
	ark_http.budget = rejected_budget
	root.add_child(ark_http)
	check(ark_http.start(wire, func(_r): pass) == ERR_UNAUTHORIZED and rejected_budget.audit().call_count == 0, "official budget transport defaults to no network and no credential callback")
	ark_http.enabled = true
	ark_http.allowed_urls = PackedStringArray([Provider.ENDPOINT])
	ark_http.transient_headers = func():
		push_error("Credential callback must never run in this offline test.")
		return PackedStringArray()
	var wrong_wire := wire.duplicate()
	wrong_wire.url = "https://third-party.invalid/images/generations"
	check(ark_http.start(wrong_wire, func(_r): pass) == ERR_UNAUTHORIZED and rejected_budget.audit().call_count == 0, "third-party endpoint rejected before credential supplier or network")
	var unknown_price := Budget.new()
	unknown_price.generation_authorized = true
	ark_http.budget = unknown_price
	check(ark_http.start(wire, func(_r): pass) == ERR_UNAUTHORIZED and unknown_price.audit().call_count == 0, "unknown price blocks official transport before credentials or network")
	ark_http.queue_free()
	var service := Service.new()
	service.provider = provider
	service.transport_factory = func():
		var transport := FixtureTransport.new()
		transport.body = fixture_body
		return transport
	root.add_child(service)
	var job = service.generate(Request.new(source, "offline integration"))
	result = await job.finished
	check(result.ok, "unchanged unified service returns JPEG-backed output through offline injected transport")
	service.transport_factory = func():
		var transport := FixtureTransport.new()
		transport.hang = true
		return transport
	var request := Request.new(source, "offline timeout")
	request.timeout_seconds = 0.02
	job = service.generate(request)
	result = await job.finished
	check(result.error.code == "timeout" and result.error.outcome_unknown and not result.error.automatic_retry, "timeout is local and ambiguous without automatic retry")
	service.queue_free()
	await process_frame
	print("ARK_OFFLINE_CHECKS: %d passed / %d total; no network or credentials" % [checks - failures, checks])
	quit(1 if failures else 0)
