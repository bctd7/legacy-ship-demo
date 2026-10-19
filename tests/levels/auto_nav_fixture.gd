extends "res://levels/stage.gd"
var complete := false
var visual_ready := false
var pending_id := ""
var mode := "lesson"
var lesson_stage := "complete"
func complete_model(allowed_to_leave: bool = true) -> void:
	complete = true
	visual_ready = allowed_to_leave
	report("completed", {"fixture":true})
func is_stage_complete() -> bool: return active and complete
func is_ready_to_leave() -> bool: return is_stage_complete() and visual_ready
func snapshot() -> Dictionary: return {"complete":complete}
