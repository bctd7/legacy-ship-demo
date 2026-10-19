extends "res://levels/stage.gd"
## Model-neutral seam: only a model descriptor and the standard stage contract.
const Registry = preload("res://levels/model_registry.gd")
var canvas_container: SubViewportContainer
var canvas_viewport: SubViewport
var adapter: Control
var model: Dictionary = {}

func enter_stage(config: Dictionary, context: Dictionary) -> String:
	var error := super.enter_stage(config, context)
	if not error.is_empty(): return error
	if not config.get("model", {}) is Dictionary: return "Model descriptor must be a Dictionary."
	model = config.get("model", {}).duplicate(true)
	error = Registry.validation_error(model)
	if not error.is_empty(): return error
	var path := str(model.get("adapter_script", ""))
	if path.is_empty(): path = str(model.get("scene", ""))
	if path.is_empty() or not ResourceLoader.exists(path): return "Model adapter or stage scene is missing: " + path
	var resource = load(path)
	var candidate = resource.instantiate() if resource is PackedScene else resource.new() if resource is Script else null
	if not candidate is Control:
		if candidate is Node: candidate.free()
		return "Model adapter/stage must be a Control."
	if not candidate.has_method("enter_stage") or not candidate.has_method("exit_stage") or not candidate.has_signal("stage_result"):
		candidate.free()
		return "Model component must expose enter_stage/exit_stage/stage_result."
	adapter = candidate
	adapter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var canvas: Vector2i = model.get("canvas_size", Vector2i.ZERO)
	if canvas.x > 0 and canvas.y > 0:
		canvas_container = SubViewportContainer.new()
		canvas_container.stretch = false
		add_child(canvas_container)
		canvas_viewport = SubViewport.new()
		canvas_viewport.size = canvas
		canvas_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		canvas_container.add_child(canvas_viewport)
		canvas_viewport.add_child(adapter)
		resized.connect(_fit_canvas)
		_fit_canvas()
	else:
		add_child(adapter)
	adapter.stage_result.connect(_forward)
	var adapter_config := config.duplicate(true)
	adapter_config["model_id"] = model.id
	if model.has("scene"): adapter_config["scene"] = model.scene
	return adapter.enter_stage(adapter_config, context.duplicate(true))

func _forward(id: String, result: Dictionary) -> void:
	if not active or id != stage_id or result.get("schema") != 1 or not result.get("payload") is Dictionary: return
	if bool(result.get("simulated", false)) != bool(stage_context.get("mock_mode", false)): return
	var payload: Dictionary = result.payload.duplicate(true)
	payload["model_id"] = model.id
	if not payload.has("drawing_asset") and model.has("drawing_asset"):
		payload["drawing_asset"] = model.drawing_asset.duplicate(true)
	report(str(result.get("status", "failed")), payload, str(result.get("message", "")))

func exit_stage() -> void:
	super.exit_stage()
	if is_instance_valid(adapter): adapter.exit_stage()
	if is_instance_valid(canvas_viewport): canvas_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

func _fit_canvas() -> void:
	if not is_instance_valid(canvas_container): return
	var canvas := Vector2(canvas_viewport.size)
	var factor := maxf(0.001, minf(size.x / canvas.x, size.y / canvas.y))
	canvas_container.size = canvas
	canvas_container.scale = Vector2.ONE * factor
	canvas_container.position = (size - canvas * factor) * 0.5

func is_stage_complete() -> bool:
	if not super.is_stage_complete() or not is_instance_valid(adapter): return false
	return bool(adapter.is_stage_complete()) if adapter.has_method("is_stage_complete") else true

func is_ready_to_leave() -> bool:
	if not is_stage_complete(): return false
	return bool(adapter.is_ready_to_leave()) if adapter.has_method("is_ready_to_leave") else true

func invalidate_completion() -> void:
	super.invalidate_completion()
	if is_instance_valid(adapter) and adapter.has_method("invalidate_completion"): adapter.invalidate_completion()
