extends Node
## Coordinates lifecycle, progress and results. No interaction or content rules.
signal progress_changed(progress: Dictionary)
signal flow_error(message: String)
const Catalog = preload("res://levels/level_catalog.gd")
var config: Dictionary = {}
var results: Dictionary = {}
var index := -1
var current_stage: Control
var stage_host: Control
var last_error := ""
var mock_mode := false
var _factories: Dictionary = {}
var _epoch := 0
var _entering_token := -1
var _entering_results: Array[Dictionary] = []

func start(level: Dictionary, host: Control, factories: Dictionary, use_mocks: bool = false, completed_prefix: Dictionary = {}) -> String:
	var error := Catalog.validation_error(level)
	if not error.is_empty(): return _fail(error)
	if not is_instance_valid(host): return _fail("A stage host is required.")
	if completed_prefix.size() >= level.stages.size(): return _fail("Resume prefix must leave a stage to enter.")
	for i in completed_prefix.size():
		var id: String = str(level.stages[i].id)
		var value = completed_prefix.get(id)
		if not value is Dictionary or value.get("schema") != 1 or value.get("status") != "completed" or not value.get("payload") is Dictionary or not value.get("simulated") is bool or value.simulated != use_mocks:
			return _fail("Resume results must be a valid completed stage prefix.")
	stop()
	config = level.duplicate(true)
	stage_host = host
	_factories = factories.duplicate()
	mock_mode = use_mocks
	results = completed_prefix.duplicate(true)
	index = completed_prefix.size()
	return _enter()

func stop() -> void:
	_epoch += 1
	_entering_token = -1
	_entering_results.clear()
	if is_instance_valid(current_stage):
		current_stage.exit_stage()
		current_stage.get_parent().remove_child(current_stage)
		current_stage.queue_free()
	current_stage = null
	index = -1

func can_advance() -> bool:
	if index < 0 or index >= config.get("stages", []).size(): return false
	if not results.has(str(config.stages[index].id)): return false
	return bool(current_stage.is_ready_to_leave()) if is_instance_valid(current_stage) and current_stage.has_method("is_ready_to_leave") else true

func advance() -> String:
	if not can_advance(): return _fail("Current stage is not completed; cannot advance.")
	if index == config.stages.size() - 1: return ""
	if is_instance_valid(current_stage):
		current_stage.exit_stage()
		current_stage.get_parent().remove_child(current_stage)
		current_stage.queue_free()
	current_stage = null
	index += 1
	return _enter()

func progress() -> Dictionary:
	var total: int = config.get("stages", []).size()
	return {"level_id": config.get("id", ""), "index": index, "total": total,
		"stage_id": str(config.stages[index].id) if index >= 0 and index < total else "",
		"completed_count": results.size(), "finished": total > 0 and results.size() == total,
		"simulated": mock_mode, "demonstration": bool(config.get("demonstration", false)),
		"results": results.duplicate(true), "error": last_error}

func _enter() -> String:
	_epoch += 1
	last_error = ""
	var item: Dictionary = config.stages[index]
	var key := str(item.component)
	if not _factories.has(key) or not _factories[key] is Callable:
		return _fail("Stage %s: missing component factory '%s'." % [item.id, key])
	var candidate = _factories[key].call()
	if not candidate is Control:
		if candidate is Node: candidate.free()
		return _fail("Stage %s: component must be a Control." % item.id)
	for method in ["enter_stage", "exit_stage"]:
		if not candidate.has_method(method):
			candidate.free()
			return _fail("Stage %s: missing method %s." % [item.id, method])
	if not candidate.has_signal("stage_result"):
		candidate.free()
		return _fail("Stage %s: missing stage_result signal." % item.id)
	current_stage = candidate
	current_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage_host.add_child(current_stage)
	var token := _epoch
	current_stage.stage_result.connect(func(id: String, result: Dictionary): _receive(id, result, token))
	var context := {"level_id": config.id, "results": results.duplicate(true), "mock_mode": mock_mode,
		"demonstration": bool(config.get("demonstration", false))}
	_entering_token = token
	_entering_results.clear()
	var error: String = current_stage.enter_stage(item.duplicate(true), context)
	if not error.is_empty():
		_epoch += 1
		_entering_token = -1
		_entering_results.clear()
		results.erase(str(item.id))
		current_stage.exit_stage()
		stage_host.remove_child(current_stage)
		current_stage.queue_free()
		current_stage = null
		return _fail("Stage %s: %s" % [item.id, error])
	_entering_token = -1
	var pending := _entering_results.duplicate(true)
	_entering_results.clear()
	for event in pending: _receive(event.id, event.result, token)
	progress_changed.emit(progress())
	return ""

func _receive(id: String, result: Dictionary, token: int) -> void:
	if token != _epoch or index < 0 or id != str(config.stages[index].id): return
	if token == _entering_token:
		_entering_results.append({"id": id, "result": result.duplicate(true)})
		return
	if results.has(id): return
	if result.get("schema") != 1 or result.get("status") != "completed": return
	if not result.get("payload") is Dictionary: return
	if not result.get("simulated") is bool or bool(result.simulated) != mock_mode: return
	results[id] = result.duplicate(true)
	last_error = ""
	progress_changed.emit(progress())

func _fail(message: String) -> String:
	last_error = message
	flow_error.emit(message)
	progress_changed.emit(progress())
	return message

func revoke_current_completion() -> void:
	if index < 0 or index >= config.get("stages", []).size(): return
	results.erase(str(config.stages[index].id))
	if is_instance_valid(current_stage) and current_stage.has_method("invalidate_completion"): current_stage.invalidate_completion()
	progress_changed.emit(progress())
