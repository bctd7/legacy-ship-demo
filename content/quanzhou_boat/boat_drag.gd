extends "res://interaction/drag_interaction.gd"
## Boat hit context and grab-plane adaptation; mouse mapping/ownership stay shared.
signal view_action_started(action: String)
var world_grab: Variant = null

func handle_pointer(command: Dictionary) -> bool:
	var phase := str(command.get("phase",""))
	var zoom_started := phase=="zoom" and gestures.idle() and camera_enabled and view.get_global_rect().has_point(command.position) and not _blocked(command.position)
	var consumed := super.handle_pointer(command)
	if phase=="begin" and gestures.contact==str(command.get("contact","")) and gestures.owner in ["rotate","pan"]:
		view_action_started.emit(gestures.owner)
	elif zoom_started: view_action_started.emit("zoom")
	return consumed

func _begin_pointer(command: Dictionary) -> bool:
	var point: Vector2 = command.position
	var hit: Dictionary = presenter.pointer_part_at(point) if command.intent=="primary" else {}
	var id := str(hit.get("id",""))
	# Cards are explicit sources outside the 3D rectangle. Other UI remains blocked.
	var blocked: bool = _blocked(point) and hit.get("source","")!="card"
	if not id.is_empty(): part_picked.emit(id)
	var owner := gestures.begin(str(command.contact),str(command.intent),{
		"inside_world":view.get_global_rect().has_point(point),"blocked":blocked,
		"camera_enabled":camera_enabled,"part_hit":not id.is_empty(),
		"part_operable":enabled and bool(hit.get("operable",false)) and selection.get("item_id","")==id})
	press_position = point
	rotating = owner=="rotate"
	if owner=="part":
		grabbed_id = id
		world_grab = hit.get("grab_world")
		held = true
		drag_source = Contract.capture(selection,behavior,candidates,eligible,expected_revision,grabbed_id)
		presenter.begin_preview(id)
	return owner in ["part","rotate","pan"]

func cancel() -> void:
	world_grab = null
	super.cancel()

func update_drag(screen_point: Vector2) -> void:
	if drag_source.is_empty(): return
	super.update_drag(presenter.connection_screen_point(screen_point))
	if _blocked(screen_point):
		hover_slot_id = ""
		hover_target.clear()
		presenter.move_preview(str(drag_source.item_id),drop_point,vector(drag_source.origin_slot.anchor_m),false,{})
		drag_changed.emit(true,false)
		target_changed.emit({},false)
