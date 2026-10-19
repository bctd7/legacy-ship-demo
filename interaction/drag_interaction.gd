extends Node
## Generic pointer gestures. State changes only through emitted requests.
signal install_requested(request: Dictionary)
signal part_picked(part_id: String)
signal drag_changed(active: bool, near: bool)
signal target_changed(target: Dictionary,near: bool)
signal cancel_requested
const Contract=preload("res://interaction/drag_contract.gd")
const MouseInput = preload("res://interaction/mouse_input_adapter.gd")
const GestureRouter = preload("res://interaction/gesture_router.gd")
var input_adapter: RefCounted = MouseInput.new()
var gestures := GestureRouter.new()
var camera: Camera3D
var view: Control
var tray: Control
var card_lookup: Callable
var pick_id_lookup: Callable
var pointer_blocked: Callable
var presenter
var orbit
var selection: Dictionary = {}
var behavior: Dictionary = {"mode":"place"}
var expected_revision: int = 0
var enabled: bool = true
var camera_enabled: bool = true
var eligible: bool = true
var dragging: bool = false
var held: bool = false
var rotating: bool = false
var press_position: Vector2
var drop_point: Vector3
var grabbed_id: String = ""
var pull_distance: float = 0
var lateral_distance: float = 0
var candidates: Array=[]
var hover_slot_id: String=""
var hover_target: Dictionary={}
var drag_source: Dictionary={}

func choose(part_id: String, slot: Dictionary, allowed: bool, revision: int, gesture: Dictionary = {"mode":"place"},targets: Array=[]) -> void:
	if held:return # A live gesture owns its source until release or cancellation.
	if gestures.owner not in ["rotate", "pan"]: cancel()
	selection = {"item_id":part_id,"origin_slot":slot.duplicate(true)}
	behavior = gesture
	candidates=targets
	eligible = allowed
	expected_revision = revision
	presenter.set_target(slot,enabled and allowed,behavior)
	presenter.set_highlight(part_id)
	presenter.set_compatible_targets(candidates,enabled and gesture.mode=="place")

func cancel() -> void:
	gestures.cancel()
	held = false
	dragging = false
	rotating = false
	pull_distance = 0
	lateral_distance = 0
	drag_source.clear()
	hover_target.clear()
	hover_slot_id=""
	if is_instance_valid(presenter):
		presenter.hide_preview()
	drag_changed.emit(false,false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		cancel()

func _input(event: InputEvent) -> void:
	var command: Dictionary = input_adapter.map_event(event)
	if not command.is_empty() and handle_pointer(command):
		get_viewport().set_input_as_handled()

func handle_pointer(command: Dictionary) -> bool:
	# Public operation boundary: adapters supply commands, not assembly requests.
	var phase := str(command.get("phase", ""))
	if phase == "cancel":
		cancel()
		cancel_requested.emit()
		return true
	if phase == "zoom":
		if not gestures.idle(): return gestures.owner != "ui"
		var point: Vector2 = command.position
		if camera_enabled and view.get_global_rect().has_point(point) and not _blocked(point):
			orbit.zoom(float(command.factor))
			return true
		return false
	if phase == "begin":
		if not gestures.idle(): return gestures.owner != "ui"
		return _begin_pointer(command)
	if phase == "end":
		var previous := gestures.release(str(command.get("contact", "")))
		if previous.is_empty(): return not gestures.idle() and gestures.owner != "ui"
		if previous == "part" and dragging and enabled and not drag_source.is_empty():
			update_drag(command.position)
			var request = Contract.withdrawal(drag_source,pull_distance,lateral_distance) if drag_source.gesture.mode=="pull" else Contract.placement(drag_source,hover_slot_id,drop_point)
			cancel()
			install_requested.emit(request)
		else: cancel()
		return previous != "ui"
	if phase == "move":
		if gestures.owner == "part":
			if not enabled: cancel(); return true
			if not dragging and command.position.distance_to(press_position)>8: dragging = true
			if dragging: update_drag(command.position)
			return true
		if gestures.owner in ["rotate", "pan"]:
			if not camera_enabled: cancel(); return true
			if not gestures.camera_motion_allowed({"inside_world":view.get_global_rect().has_point(command.position), "blocked":_blocked(command.position), "camera_enabled":camera_enabled}): return true
			if gestures.owner == "rotate": orbit.rotate_view(command.delta)
			else: orbit.pan_view(command.delta, view.size)
			return true
	return false

func _blocked(point: Vector2) -> bool:
	return pointer_blocked.is_valid() and bool(pointer_blocked.call(point))

func _begin_pointer(command: Dictionary) -> bool:
	var point: Vector2 = command.position
	var inside := view.get_global_rect().has_point(point)
	var blocked := _blocked(point)
	var item_id := ""
	var raw_id := ""
	if command.intent == "primary" and not blocked and enabled:
		item_id = str(card_lookup.call(point)) if card_lookup.is_valid() else ""
		if not item_id.is_empty(): raw_id = item_id
		elif inside:
			var local := point - view.get_global_rect().position
			raw_id = presenter.pick(camera.project_ray_origin(local), camera.project_ray_normal(local))
			item_id = str(pick_id_lookup.call(raw_id)) if pick_id_lookup.is_valid() else raw_id
		if not item_id.is_empty(): part_picked.emit(item_id)
	var owner := gestures.begin(str(command.contact), str(command.intent), {
		"inside_world":inside, "blocked":blocked, "camera_enabled":camera_enabled,
		"part_hit":not raw_id.is_empty(),
		# Drag-preview availability is separate from placement eligibility. Rules keep
		# rejecting unmet dependencies while retaining the accepted red preview.
		"part_operable":enabled and not item_id.is_empty() and selection.get("item_id", "") == item_id})
	press_position = point
	rotating = owner == "rotate"
	if owner == "part":
		grabbed_id = raw_id
		held = true
		drag_source = Contract.capture(selection,behavior,candidates,eligible,expected_revision,grabbed_id)
		presenter.begin_preview(str(drag_source.item_id))
	return owner in ["part", "rotate", "pan"]

func _exit_tree() -> void:
	cancel()

static func vector(v: Array) -> Vector3:
	return Vector3(v[0],v[1],v[2])

func update_drag(screen_point: Vector2) -> void:
	if drag_source.is_empty():return
	var anchor = vector(drag_source.origin_slot.anchor_m)
	var gesture: Dictionary=drag_source.gesture
	if gesture.mode == "pull":
		var axis = vector(gesture.axis_m).normalized()
		var direction = camera.unproject_position(anchor+axis*0.1)-camera.unproject_position(anchor)
		var pixels_per_metre = maxf(direction.length()/0.1,1)
		var delta = screen_point-press_position
		pull_distance = delta.dot(direction.normalized())/pixels_per_metre
		lateral_distance = absf(delta.cross(direction.normalized()))/pixels_per_metre
		drop_point = anchor+axis*pull_distance
		var ready: bool = drag_source.eligible and pull_distance>=float(gesture.min_distance_m) and pull_distance<=float(gesture.max_distance_m) and lateral_distance<=float(gesture.max_lateral_m)
		presenter.move_pull_preview(axis,clampf(pull_distance,0,0.1),ready)
		drag_changed.emit(true,ready)
		return
	var best: Dictionary={}
	var distance: float=INF
	var local_point=screen_point-view.get_global_rect().position
	var latched: Dictionary={}
	for option in drag_source.candidates:
		var points: Array=option.get("trigger_points_m",[option.anchor_m])
		for index in range(points.size()):
			var center=vector(points[index])
			var projected=camera.unproject_position(center)
			var radius=(camera.unproject_position(center+camera.global_basis.x*float(option.radius_m))-projected).length()
			var d=local_point.distance_to(projected)
			var candidate: Dictionary=option.duplicate(true)
			candidate["trigger_point_m"]=points[index];candidate["trigger_index"]=index
			if option.id==hover_target.get("id","") and index==hover_target.get("trigger_index",-1) and option.allowed and d<=radius*1.18:latched=candidate
			var better: bool=d<distance
			# In an overlapping screen neighbourhood prefer an eligible compatible slot.
			# Capture radius is unchanged; a clearly closer wrong slot still reports rejection.
			if not best.is_empty() and absf(d-distance)<=6.0 and bool(candidate.allowed)!=bool(best.allowed):better=candidate.allowed
			if d<=radius and better:
				distance=d;best=candidate
	# Retain an eligible target inside a small exit band, unless a new target is clearly closer.
	if not latched.is_empty():
		var old_d=local_point.distance_to(camera.unproject_position(vector(latched.trigger_point_m)))
		if best.is_empty() or not best.allowed or (best.id==latched.id and best.trigger_index==latched.trigger_index) or distance+7.0>=old_d:best=latched
	hover_slot_id=""
	hover_target=best
	if not best.is_empty():
		anchor=vector(best.trigger_point_m)
	var normal = camera.global_basis.z
	# Keep the carry plane and geometry stable; hover cannot change the carried source.
	var plane = Plane(normal,normal.dot(vector(drag_source.origin_slot.anchor_m)))
	var point = screen_point-view.get_global_rect().position
	var hit = plane.intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))
	if hit == null:
		return
	drop_point = hit
	# A target uses its own plane for the final legal release point, without changing carry pose.
	var target_hit = Plane(normal,normal.dot(anchor)).intersects_ray(camera.project_ray_origin(point),camera.project_ray_normal(point))
	var in_range=not best.is_empty() and target_hit!=null and target_hit.distance_to(anchor)<=float(best.radius_m)
	if in_range:hover_slot_id=str(best.id)
	var near: bool=in_range and bool(best.get("allowed",false))
	var visual_target=best.duplicate(true)
	visual_target["pose_active"]=not best.is_empty() and not latched.is_empty() and best.id==latched.id
	presenter.move_preview(str(drag_source.item_id),drop_point,anchor,near,visual_target)
	if in_range:drop_point=target_hit
	drag_changed.emit(true,near)
	target_changed.emit(best,near)
