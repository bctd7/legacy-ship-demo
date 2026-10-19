extends "res://levels/stage.gd"
## Contract fixture only. No new playable model or content rules.
func complete_model() -> void:
	report("completed", {"fixture_completion": true})
