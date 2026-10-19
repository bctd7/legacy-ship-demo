extends "res://levels/stage.gd"
## Existing public lifecycle; no shared files require modification.
var play: Control

func enter_stage(config: Dictionary, context: Dictionary) -> String:
	var error := super.enter_stage(config,context)
	if not error.is_empty(): return error
	if play: play.deactivate(); play.queue_free()
	play = load("res://content/quanzhou_boat/demo.tscn").instantiate()
	play.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	play.completed.connect(func(state: Dictionary): report("completed",{"content_snapshot":state}))
	add_child(play)
	play.set_mode("assembly")
	return ""

func exit_stage() -> void:
	super.exit_stage()
	if play: play.deactivate()

## Integration lifecycle only: a completed snapshot precedes the final camera return.
func is_stage_complete() -> bool:
	return active and is_instance_valid(play) and bool(play.snapshot().get("complete", false))

func is_ready_to_leave() -> bool:
	return is_stage_complete() and play.pending_id.is_empty() and play.mode in ["assembly", "overview"] and play.lesson_stage.is_empty()
