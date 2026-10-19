extends RefCounted
## Model identities and package entry points. No interaction or completion rules.
static func defaults() -> Dictionary:
	return {
		"luban_bridge": {"id": "luban_bridge", "adapter_script": "res://levels/bridge_stage_adapter.gd",
			"scene": "res://scenes/workshop.tscn", "drawing_asset": _asset("res://levels/assets/bridge_illustration_v2.png")},
		"quanzhou_boat": {"id": "quanzhou_boat", "canvas_size": Vector2i(1400, 900), "adapter_script": "res://content/quanzhou_boat/stage_adapter.gd",
			"scene": "res://content/quanzhou_boat/demo.tscn", "drawing_asset": _asset("res://levels/assets/boat_illustration.png")}
	}

static func _asset(path: String) -> Dictionary:
	return {"kind": "image_2d", "texture_path": path, "preview_texture_path": path,
		"placed_texture_path": path, "transparent_background": true, "placeholder": false}

static func resolve(id: String, registry: Dictionary) -> Dictionary:
	var entry = registry.get(id, {})
	return entry.duplicate(true) if entry is Dictionary else {}

static func validation_error(model: Dictionary) -> String:
	if str(model.get("id", "")).is_empty(): return "Model descriptor needs a stable id."
	if str(model.get("adapter_script", "")).is_empty() and str(model.get("scene", "")).is_empty():
		return "Model %s needs an adapter_script or stage scene." % model.id
	if model.has("drawing_asset"):
		var asset = model.drawing_asset
		if not asset is Dictionary or asset.get("kind", "image_2d") != "image_2d":
			return "Model drawing_asset must describe a 2D image."
	return ""
