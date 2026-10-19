extends Control
## A stage owns its interaction. The flow only consumes this result envelope.
signal stage_result(stage_id: String, result: Dictionary)
var stage_id := ""
var stage_config: Dictionary = {}
var stage_context: Dictionary = {}
var active := false
var _reported := false

func enter_stage(config: Dictionary, context: Dictionary) -> String:
	stage_id = str(config.get("id", ""))
	stage_config = config.duplicate(true)
	stage_context = context.duplicate(true)
	active = true
	_reported = false
	return "" if not stage_id.is_empty() else "Stage id is required."

func exit_stage() -> void:
	active = false

func report(status: String, payload: Dictionary = {}, message: String = "") -> void:
	if not active or _reported: return
	if status == "completed": _reported = true
	stage_result.emit(stage_id, {
		"schema": 1, "status": status, "payload": payload.duplicate(true),
		"message": message, "simulated": bool(stage_context.get("mock_mode", false))
	})

## Completion may be revoked by undo/reset; readiness additionally waits for visual cleanup.
func is_stage_complete() -> bool:
	return active and _reported

func is_ready_to_leave() -> bool:
	return is_stage_complete()

func invalidate_completion() -> void:
	_reported = false
