extends "res://image_generation/provider.gd"
## Official mainland Ark REST protocol checked 2026-10-16; no credentials or I/O.
const Codec = preload("res://image_generation/codec.gd")
const Jpeg = preload("res://image_generation/jpeg_codec.gd")
const ENDPOINT := "https://ark.cn-beijing.volces.com/api/v3/images/generations"
const MODEL_ID := "doubao-seedream-4-5-251128"
const MODEL_LITE := "doubao-seedream-5-0-lite-260128"
const MODEL_PRO := "doubao-seedream-5-0-pro-260628"
const MODEL_FLASH := "doubao-seedream-5-0-flash-260915"
const VERIFIED_OUTPUT_FORMATS := {
	"doubao-seedream-4-5-251128": "jpeg",
	"doubao-seedream-5-0-lite-260128": "png",
	"doubao-seedream-5-0-260128": "png",
	"doubao-seedream-5-0-pro-260628": "png",
	"doubao-seedream-5-0-flash-260915": "png",
}
var enable_direct_local_development := false
var model := MODEL_FLASH # User-selected default; direct network still disabled, no fallback.

func encode(snapshot: Dictionary) -> Dictionary:
	if not enable_direct_local_development or not VERIFIED_OUTPUT_FORMATS.has(model):
		return {"failure": Result.failure("configuration", "Explicitly approve and configure the verified mainland Seedream model before use.")}
	# Ark requires both input edges >14 and an aspect ratio in [1/16, 16].
	var input = Codec.from_base64(Marshalls.raw_to_base64(snapshot.png))
	if not input.ok:
		return {"failure": Result.failure("invalid_input", "Expected a bounded PNG input.")}
	var extent: Vector2i = input.image.get_size()
	if extent.x < 15 or extent.y < 15 or extent.x > extent.y * 16 or extent.y > extent.x * 16:
		return {"failure": Result.failure("invalid_input", "Seedream input edges must exceed 14 pixels and aspect ratio must be within 1:16 to 16:1.")}
	var payload := {"model": model, "prompt": snapshot.prompt,
		"image": "data:image/png;base64," + Marshalls.raw_to_base64(snapshot.png),
		"size": "2048x2048", "response_format": "b64_json", "watermark": true}
	if model in [MODEL_PRO, MODEL_FLASH]:
		payload.size = "2K"
		payload.layer_decomposition = false
		payload.optimize_prompt_options = {"mode": "standard"}
		# Pro and Flash generate one image; neither supports sequential/stream options.
	else:
		payload.sequential_image_generation = "disabled"
		payload.stream = false
	# 4.5 cannot select format; Lite independently supports explicit PNG output.
	if VERIFIED_OUTPUT_FORMATS[model] == "png": payload.output_format = "png"
	return {"wire": {"url": ENDPOINT, "headers": PackedStringArray(["Content-Type: application/json"]),
		"body": JSON.stringify(payload).to_utf8_buffer()}}

func decode(status: int, body: PackedByteArray):
	var parsed := Codec.json_response(status, body)
	if parsed.has("failure"): return parsed.failure
	if parsed.data.has("error"):
		return Result.failure("provider_error", "Official generation endpoint returned an error.", status, true)
	var rows = parsed.data.get("data")
	if not rows is Array or rows.size() != 1 or not rows[0] is Dictionary:
		return Result.failure("invalid_response", "Expected exactly one Seedream image.", status, true)
	if rows[0].has("error"):
		return Result.failure("provider_error", "Official generation endpoint did not return the requested image.", status, true)
	if not VERIFIED_OUTPUT_FORMATS.has(model):
		return Result.failure("configuration", "Configure a verified model profile before decoding.")
	if VERIFIED_OUTPUT_FORMATS[model] == "png":
		return Codec.from_base64(rows[0].get("b64_json"))
	return Jpeg.from_base64(rows[0].get("b64_json"))
