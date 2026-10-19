extends RefCounted
## Device-neutral, single gesture ownership. No picking, scene or assembly rules.
var owner := ""
var contact := ""

func begin(source: String, intent: String, context: Dictionary) -> String:
	if not owner.is_empty() or source.is_empty(): return ""
	contact = source
	owner = "ui"
	if context.get("blocked", false): return owner
	var inside: bool = context.get("inside_world", false)
	var camera_allowed: bool = inside and context.get("camera_enabled", false)
	if intent == "primary":
		if context.get("part_hit", false):
			if context.get("part_operable", false): owner = "part"
		elif camera_allowed: owner = "rotate"
	elif intent == "rotate" and camera_allowed: owner = "rotate"
	elif intent == "pan" and camera_allowed: owner = "pan"
	return owner

func release(source: String) -> String:
	if source != contact: return ""
	var previous := owner
	cancel()
	return previous

func cancel() -> void:
	owner = ""
	contact = ""

func idle() -> bool:
	return owner.is_empty()

func camera_motion_allowed(context: Dictionary) -> bool:
	return owner in ["rotate", "pan"] and context.get("inside_world", false) and not context.get("blocked", false) and context.get("camera_enabled", false)
