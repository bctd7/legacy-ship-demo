extends RefCounted
## Validates the completed drawing descriptor without dispatching I/O.
## generation_stage owns PNG loading and invokes the independent image service.
static func prepare(drawing_result: Dictionary, prompt: String) -> Dictionary:
	if drawing_result.get("schema") != 1 or drawing_result.get("status") != "completed":
		return {"ok": false, "message": "A completed drawing result is required."}
	if drawing_result.get("simulated", true):
		return {"ok": false, "message": "Mock results cannot be submitted to image generation."}
	var payload = drawing_result.get("payload", {})
	if not payload is Dictionary or str(payload.get("texture_path", "")).is_empty():
		return {"ok": false, "message": "Drawing result needs an exported texture_path."}
	if prompt.strip_edges().is_empty(): return {"ok": false, "message": "A prompt is required."}
	return {"ok": true, "request": {"schema": 1, "input_texture_path": str(payload.texture_path),
		"prompt": prompt, "dispatch_status": "not_dispatched"}}
