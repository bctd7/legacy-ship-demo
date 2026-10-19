extends "res://levels/stage.gd"
## Wraps the accepted workshop without modifying input, rules, UI or session.
var workshop: Node
var _session

func enter_stage(config: Dictionary, context: Dictionary) -> String:
	var error := super.enter_stage(config, context)
	if not error.is_empty(): return error
	var path := str(config.get("scene", ""))
	if not ResourceLoader.exists(path): return "Bridge scene is missing: " + path
	var scene = load(path)
	if not scene is PackedScene: return "Bridge component must be a PackedScene."
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	workshop = scene.instantiate()
	viewport.add_child(workshop)
	if not workshop.get("session") is Object: return "Bridge component did not expose its session."
	_session = workshop.session
	if not _session.has_signal("changed") or not _session.has_method("view_state") or not _session.has_method("snapshot"):
		return "Bridge session is missing changed/view_state/snapshot."
	_session.changed.connect(_on_changed)
	_on_changed({})
	return ""

func _on_changed(_snapshot: Dictionary) -> void:
	if active and bool(_session.view_state().get("finished", false)):
		report("completed", {"content_snapshot": _session.snapshot()})

func exit_stage() -> void:
	super.exit_stage()
	if is_instance_valid(workshop): workshop.process_mode = Node.PROCESS_MODE_DISABLED
	for viewport in find_children("*", "SubViewport", true, false):
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _session != null and _session.changed.is_connected(_on_changed):
		_session.changed.disconnect(_on_changed)

func is_stage_complete() -> bool:
	return active and _session != null and bool(_session.view_state().get("finished", false)) and not _session.is_busy()

func is_ready_to_leave() -> bool:
	return is_stage_complete()
