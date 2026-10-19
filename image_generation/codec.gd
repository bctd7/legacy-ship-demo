extends RefCounted
const Result = preload("res://image_generation/result.gd")
const MAX_IMAGE_BYTES := 8 * 1024 * 1024
const MAX_BODY_BYTES := 24 * 1024 * 1024
const MAX_EDGE := 4096

static func valid_extent(width: int, height: int) -> bool:
	return width > 0 and height > 0 and width <= MAX_EDGE and height <= MAX_EDGE

static func from_base64(value: Variant):
	if not value is String or value.is_empty() or value.length() > (MAX_IMAGE_BYTES + 2) / 3 * 4:
		return Result.failure("invalid_image", "Missing or oversized output PNG.", 0, true)
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9+/]+={0,2}$")
	if value.length() % 4 != 0 or pattern.search(value) == null:
		return Result.failure("invalid_image", "Invalid base64 output.", 0, true)
	var bytes := Marshalls.base64_to_raw(value)
	# Inspect PNG IHDR before the decoder allocates pixel storage.
	if bytes.size() < 33 or bytes.size() > MAX_IMAGE_BYTES or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]) or bytes.slice(12, 16).get_string_from_ascii() != "IHDR":
		return Result.failure("invalid_image", "Expected a bounded PNG output.", 0, true)
	var width := _big_endian(bytes, 16)
	var height := _big_endian(bytes, 20)
	if not valid_extent(width, height):
		return Result.failure("invalid_image", "Output dimensions exceed package limits.", 0, true)
	var output := Image.new()
	if output.load_png_from_buffer(bytes) != OK or output.is_empty():
		return Result.failure("invalid_image", "Output PNG could not be decoded.", 0, true)
	return Result.success(output)

static func _big_endian(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])

static func json_response(status: int, bytes: PackedByteArray) -> Dictionary:
	# Never copy provider messages/raw bodies into results or logs.
	if status < 200 or status >= 300:
		var code := "provider_error"
		if status == 401 or status == 403: code = "unauthorized"
		elif status == 429: code = "rate_limited"
		elif status == 400 or status == 422: code = "rejected"
		return {"failure": Result.failure(code, "Generation endpoint rejected the request.", status, status >= 500)}
	if bytes.size() > MAX_BODY_BYTES:
		return {"failure": Result.failure("response_too_large", "Response exceeds package limits.", status, true)}
	var data = JSON.parse_string(bytes.get_string_from_utf8())
	if not data is Dictionary:
		return {"failure": Result.failure("invalid_response", "Expected a JSON object.", status, true)}
	return {"data": data}
