extends "res://levels/stage.gd"
## Deliberate invalid lifecycle: a completion during enter, then another on exit.
func enter_stage(config: Dictionary, context: Dictionary) -> String:
	super.enter_stage(config, context)
	report("completed", {"premature": true})
	return "Deliberate enter failure."

func exit_stage() -> void:
	stage_result.emit(stage_id, {"schema": 1, "status": "completed", "payload": {"late": true}, "simulated": false})
	super.exit_stage()
