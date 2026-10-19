extends RefCounted
## Bounded JPEG response decoder for Seedream 4.5, independent of PNG protocols.
const Result = preload("res://image_generation/result.gd")
const Codec = preload("res://image_generation/codec.gd")

static func from_base64(value: Variant):
	if not value is String or value.is_empty() or value.length() > (Codec.MAX_IMAGE_BYTES + 2) / 3 * 4:
		return _failure()
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9+/]+={0,2}$")
	if value.length() % 4 != 0 or pattern.search(value) == null: return _failure()
	var bytes := Marshalls.base64_to_raw(value)
	if bytes.size() < 4 or bytes.size() > Codec.MAX_IMAGE_BYTES or bytes[0] != 0xff or bytes[1] != 0xd8:
		return _failure()
	# Walk JPEG segments up to SOF; validate dimensions before allocating pixels.
	var offset := 2
	while offset < bytes.size():
		if bytes[offset] != 0xff: return _failure()
		while offset < bytes.size() and bytes[offset] == 0xff: offset += 1
		if offset >= bytes.size(): return _failure()
		var marker := int(bytes[offset])
		offset += 1
		if marker == 0xda or marker == 0xd9: return _failure()
		if marker == 0x01 or (marker >= 0xd0 and marker <= 0xd7): continue
		if offset + 2 > bytes.size(): return _failure()
		var length := (int(bytes[offset]) << 8) | int(bytes[offset + 1])
		if length < 2 or offset + length > bytes.size(): return _failure()
		if marker in [0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]:
			if length < 8: return _failure()
			var height := (int(bytes[offset + 3]) << 8) | int(bytes[offset + 4])
			var width := (int(bytes[offset + 5]) << 8) | int(bytes[offset + 6])
			if not Codec.valid_extent(width, height): return _failure()
			var image := Image.new()
			if image.load_jpg_from_buffer(bytes) != OK or image.is_empty(): return _failure()
			return Result.success(image)
		offset += length
	return _failure()

static func _failure():
	return Result.failure("invalid_image", "Expected a valid bounded JPEG response.", 0, true)
