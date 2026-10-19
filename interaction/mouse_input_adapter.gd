extends RefCounted
## Mouse/key mapping only. Operations consume these commands without mouse APIs.
func map_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		return {"phase":"cancel"}
	if event is InputEventMouseMotion:
		return {"phase":"move", "position":event.position, "delta":event.relative}
	if not event is InputEventMouseButton: return {}
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if not event.pressed: return {}
		var ticks := clampf(absf(event.factor), 1.0, 4.0)
		return {"phase":"zoom", "position":event.position,
			"factor":pow(0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1, ticks)}
	var intent := ""
	match event.button_index:
		MOUSE_BUTTON_LEFT: intent = "primary"
		MOUSE_BUTTON_RIGHT: intent = "rotate"
		MOUSE_BUTTON_MIDDLE: intent = "pan"
	if intent.is_empty(): return {}
	return {"phase":"begin" if event.pressed else "end", "intent":intent,
		"contact":"mouse:%d" % event.button_index, "position":event.position}
