extends Node
## Offline deterministic PNG transformation. This is NOT AI image generation.
var mode := "success" # success / error / hang / malformed / network
var delay_seconds := 0.25
var calls := 0
var _cancelled := false

func start(wire: Dictionary, callback: Callable) -> int:
	calls += 1
	var payload = JSON.parse_string(wire.body.get_string_from_utf8())
	if not payload is Dictionary: return ERR_INVALID_DATA
	_deliver(payload, callback)
	return OK

func cancel() -> void:
	_cancelled = true

func _deliver(payload: Dictionary, callback: Callable) -> void:
	if mode == "hang": return
	await get_tree().create_timer(maxf(0.01, delay_seconds)).timeout
	if _cancelled: return
	if mode == "error":
		callback.call({"status": 429, "body": "{}".to_utf8_buffer()})
		return
	if mode == "network":
		callback.call({"transport_error": true})
		return
	if mode == "malformed":
		callback.call({"status": 200, "body": "{}".to_utf8_buffer()})
		return
	var source: String = payload.get("image", {}).get("base64", "")
	var openai := payload.has("images")
	if openai: source = payload.images[0].image_url.trim_prefix("data:image/png;base64,")
	var image := Image.new()
	if image.load_png_from_buffer(Marshalls.base64_to_raw(source)) != OK:
		callback.call({"status": 400, "body": "{}".to_utf8_buffer()})
		return
	# Prompt hash controls a visible tint; preserve the original geometry.
	var tint := Color.from_hsv(float(absi(str(payload.prompt).hash()) % 360) / 360.0, 0.65, 0.9)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			image.set_pixel(x, y, image.get_pixel(x, y).lerp(tint, 0.35))
	var b64 := Marshalls.raw_to_base64(image.save_png_to_buffer())
	var body := {"data": [{"b64_json": b64}]} if openai else {"schema_version": 1, "image": {"mime_type": "image/png", "base64": b64}}
	callback.call({"status": 200, "body": JSON.stringify(body).to_utf8_buffer()})
