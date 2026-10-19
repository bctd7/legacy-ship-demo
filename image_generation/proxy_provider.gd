extends "res://image_generation/provider.gd"
## Proposed application-owned proxy v1 contract; backend is a separate decision.
const Codec = preload("res://image_generation/codec.gd")
var endpoint := ""

func encode(snapshot: Dictionary) -> Dictionary:
	if not endpoint.begins_with("https://") or endpoint.contains("?") or endpoint.contains("#") or endpoint.contains("@"):
		return {"failure": Result.failure("configuration", "Configure a controlled HTTPS proxy endpoint without URL credentials.")}
	var payload := {"schema_version": 1, "prompt": snapshot.prompt,
		"image": {"mime_type": "image/png", "base64": Marshalls.raw_to_base64(snapshot.png)}}
	return {"wire": {"url": endpoint, "headers": PackedStringArray(["Content-Type: application/json"]),
		"body": JSON.stringify(payload).to_utf8_buffer()}}

func decode(status: int, body: PackedByteArray):
	var parsed := Codec.json_response(status, body)
	if parsed.has("failure"): return parsed.failure
	var output = parsed.data.get("image")
	if parsed.data.get("schema_version") != 1 or not output is Dictionary or output.get("mime_type") != "image/png":
		return Result.failure("invalid_response", "Expected proxy v1 PNG response.", status, true)
	return Codec.from_base64(output.get("base64"))
