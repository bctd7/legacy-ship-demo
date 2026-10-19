extends "res://image_generation/provider.gd"
## Official Images Edit JSON protocol, checked 2026-10-16. No credentials here.
const Codec = preload("res://image_generation/codec.gd")
var enable_direct_local_development := false
var model := "" # Explicit deployment choice; no implicit paid model selection.

func encode(snapshot: Dictionary) -> Dictionary:
	if not enable_direct_local_development or model.is_empty() or model.contains("\n"):
		return {"failure": Result.failure("configuration", "Direct provider use requires explicit local development configuration and model.")}
	var payload := {"model": model, "prompt": snapshot.prompt, "n": 1,
		"output_format": "png", "size": "1024x1024", "quality": "low",
		"images": [{"image_url": "data:image/png;base64," + Marshalls.raw_to_base64(snapshot.png)}]}
	return {"wire": {"url": "https://api.openai.com/v1/images/edits",
		"headers": PackedStringArray(["Content-Type: application/json"]),
		"body": JSON.stringify(payload).to_utf8_buffer()}}

func decode(status: int, body: PackedByteArray):
	var parsed := Codec.json_response(status, body)
	if parsed.has("failure"): return parsed.failure
	var rows = parsed.data.get("data")
	if not rows is Array or rows.size() != 1 or not rows[0] is Dictionary:
		return Result.failure("invalid_response", "Expected exactly one generated image.", status, true)
	return Codec.from_base64(rows[0].get("b64_json"))
