extends "res://content/quanzhou_boat/verify_sequence.gd"
var measurements: Array = []

func _ready() -> void:
	super._ready()
	evidence = "res://content/quanzhou_boat/evidence/tolerance_zoom"

func _run() -> void:
	await _frames(25)
	var center := view.get_global_rect().get_center()
	var distances: Array = [orbit.distance]
	for index in 22:
		await _mouse(center,true,MOUSE_BUTTON_WHEEL_UP)
		await _mouse(center,false,MOUSE_BUTTON_WHEEL_UP)
		distances.append(orbit.distance)
	measurements.append({"kind":"zoom_in_22_notches","distances":distances,"min":orbit.min_distance,"focus":str(orbit.focus),"camera_enabled":drag.camera_enabled})
	if "baseline" in OS.get_cmdline_user_args():
		_check(is_equal_approx(orbit.distance,2.2),"REPRO wheel reaches restrictive 2.2m assembly clamp")
		await _capture("baseline_zoom_limit")
		await _button_click("视角复位")
		await _offset_drag("keel_center",Vector2(0,-55))
		_check(pending_id.is_empty() and placed.is_empty(),"REPRO visible 55px offset rejects first source")
		await _capture("baseline_strict_drop")
		_write("baseline.json")
		get_tree().quit()
		return
	_check(orbit.distance<0.5,"assembly wheel zoom passes old 2.2m clamp and reaches detail scale")
	_check(orbit.focus.distance_to(Drag.vector(slots.keel_center.anchor_m))<0.02,"zoom focuses current actual connection instead of empty whole-boat center")
	await _capture("01_zoomed_current_part")
	var before: float = orbit.distance
	await _button_click("－ 缩小")
	_check(orbit.distance>before,"actual zoom-out UI changes camera distance")
	before = orbit.distance
	await _button_click("＋ 放大")
	_check(orbit.distance<before,"actual zoom-in UI changes camera distance")
	await _button_click("视角复位")
	await _boundary_drag(Vector2(0,-82),false,Vector2(0.28,0.5),"outside_default")
	await _boundary_drag(Vector2(0,-49),true,Vector2(0.72,0.5),"inside_default")
	await _wait_installed("keel_center")
	await _wait_assembly("boundary_default_auto")
	await _button_click("撤回一步")
	for index in 8:
		await _mouse(center,true,MOUSE_BUTTON_WHEEL_UP)
		await _mouse(center,false,MOUSE_BUTTON_WHEEL_UP)
	await _mouse(center,true,MOUSE_BUTTON_RIGHT)
	await _move(center+Vector2(48,18),Vector2(48,18))
	await _mouse(center+Vector2(48,18),false,MOUSE_BUTTON_RIGHT)
	var saved_focus: Vector3 = orbit.focus
	var saved_distance: float = orbit.distance
	var saved_yaw: float = orbit.yaw
	await _pointer_only_miss()
	await _boundary_drag(Vector2(0,-82),false,Vector2(0.7,0.5),"outside_zoom_rotated")
	await _boundary_drag(Vector2(0,-49),true,Vector2(0.28,0.5),"inside_zoom_rotated")
	await _wait_installed("keel_center")
	await _wait_assembly("boundary_zoom_auto")
	_check(orbit.focus.is_equal_approx(saved_focus) and is_equal_approx(orbit.distance,saved_distance) and is_equal_approx(orbit.yaw,saved_yaw),"lesson return preserves user's zoom focus distance and angle")
	await _button_click("重置装配")
	_write("boundary_zoom.json")
	# Parent runs all 13 routes, undo/reinstall, runtime resize and manual joint.
	# Virtual dispatch uses the actual-object drag below, not its old mouse anchor.
	await super._run()
	_write("mapping_and_input.json")

func _input_state() -> Dictionary:
	var state := super._input_state()
	state["distance"] = orbit.distance
	state["focus"] = str(orbit.focus)
	state["grab_world"] = str(preview_grab_point)
	state["connection_world"] = str(preview_anchor)
	state["preview_translation"] = str(preview_group.position)
	return state

func _grab_start(id: String, uv: Vector2) -> Vector2:
	var rect: Rect2 = card_pictures[id].get_global_rect()
	var image_size := Vector2(224,120)*minf(rect.size.x/224.0,rect.size.y/120.0)
	return rect.get_center()+(uv-Vector2(0.5,0.5))*image_size

func _pointer_for_anchor_offset(offset: Vector2) -> Vector2:
	var projected := camera.unproject_position(preview_anchor)+offset
	var normal := camera.global_basis.z
	var hit = Plane(normal,normal.dot(preview_anchor)).intersects_ray(camera.project_ray_origin(projected),camera.project_ray_normal(projected))
	return view.global_position+camera.unproject_position(preview_grab_point+hit-preview_anchor)

func _boundary_drag(offset: Vector2, accepted: bool, uv: Vector2, tag: String) -> void:
	await _reveal_card_with_wheel("keel_center")
	var start := _grab_start("keel_center",uv)
	await _hover_pointer(start)
	await _mouse(start,true)
	_check(placed.is_empty() and pending_id.is_empty(),"source press never installs "+tag)
	var end := _pointer_for_anchor_offset(offset)
	for index in range(1,11): await _move(start.lerp(end,float(index)/10))
	await get_tree().create_timer(0.2).timeout
	_check((drag.hover_slot_id=="keel_center")==accepted,"connection-anchor tolerance "+tag)
	if accepted: _check(preview_group.position.length()<0.01,"green actual object settles at final transform "+tag)
	measurements.append({"kind":"boundary","tag":tag,"offset":str(offset),"uv":str(uv),"grab":str(preview_grab_point),"anchor":str(preview_anchor),"hover":drag.hover_slot_id,"radius_m":selected_drop_slot.radius_m,"pointer":str(end),"connection_screen":str(connection_screen_point(end)),"preview_transform":str(preview_group.transform)})
	await _capture(tag+"_hover")
	await _mouse(end,false)
	_check((pending_id=="keel_center")==accepted,"release respects visible green state "+tag)

func _pointer_only_miss() -> void:
	var start := _grab_start("keel_center",Vector2(0.08,0.5))
	await _hover_pointer(start)
	await _mouse(start,true)
	var end := view.global_position+camera.unproject_position(preview_anchor)
	for index in range(1,11): await _move(start.lerp(end,float(index)/10))
	_check(drag.hover_slot_id.is_empty(),"mouse on target alone does not align off-center grabbed object")
	measurements.append({"kind":"cursor_only_miss","pointer":str(end),"connection_screen":str(connection_screen_point(end)),"grab_world":str(preview_grab_point),"anchor_world":str(preview_anchor),"hover":drag.hover_slot_id})
	await _capture("cursor_on_target_object_outside")
	await _mouse(end,false)
	_check(pending_id.is_empty() and placed.is_empty(),"cursor-only target drop is rejected for misplaced actual object")

func _drag_group(id: String) -> void:
	await _reveal_card_with_wheel(id)
	var before := _input_state()
	var start := _grab_start(id,Vector2(0.35,0.5) if groups.find(_group(id))%2==0 else Vector2(0.67,0.5))
	await _hover_pointer(start)
	await _mouse(start,true)
	_check(drag.held and drag.drag_source.get("item_id","")==id and drag.eligible,"press captures permitted source "+id)
	var installed_names: Array[String] = []
	for source in _part_meshes(id): installed_names.append(str(source.name))
	var carried_names: Array[String] = []
	var same_materials := true
	for copy in preview_group.get_children():
		var name_value := str(copy.get_meta("source_mesh_name",""))
		carried_names.append(name_value)
		var source: MeshInstance3D = mesh_lookup.get(name_value)
		if source==null or copy.mesh!=source.mesh: same_materials = false; continue
		for surface in source.mesh.get_surface_count():
			if copy.get_active_material(surface)!=source.get_active_material(surface): same_materials = false
	installed_names.sort(); carried_names.sort()
	var thumbnail_names: Array = thumbnail_grab_maps[id].mesh_names.duplicate()
	thumbnail_names.sort()
	_check(installed_names==carried_names and installed_names==thumbnail_names,"card carry install exact same mesh set "+id)
	_check(same_materials,"carried source mesh and materials are identical "+id)
	var end := _pointer_for_anchor_offset(Vector2(0,-32))
	for index in range(1,11): await _move(start.lerp(end,float(index)/10))
	await get_tree().create_timer(0.2).timeout
	_check(drag.dragging and drag.hover_slot_id==id,"actual object's connection aligns after off-center grab "+id)
	_check(preview_group.position.length()<0.01,"green whole group matches final world transform "+id)
	measurements.append({"kind":"mesh_mapping","group":id,"installed":installed_names,"card":thumbnail_names,"carried":carried_names,"materials_same":same_materials,"grab_world":str(preview_grab_point),"connection_world":str(preview_anchor),"end":str(end)})
	if id in ["shell_port","shell_starboard"]: await _capture(id+"_whole_group_green")
	await _mouse(end,false)
	_check(pending_id==id and mode=="lesson","release starts accepted installation "+id)
	if id in ["shell_port","shell_starboard"]:
		await _capture(id+"_01_align")
		await get_tree().create_timer(0.78).timeout
		await _capture(id+"_02_contact")
		await get_tree().create_timer(0.8).timeout
		await _capture(id+"_03_fix")
	route_log.append({"group":id,"before_press":before,"after_release":_input_state(),"release_logical":str(end)})

func _offset_drag(id: String, offset: Vector2) -> void:
	await _reveal_card_with_wheel(id)
	var start: Vector2 = cards[id].get_global_rect().get_center()
	await _hover_pointer(start)
	await _mouse(start,true)
	var end: Vector2 = view.global_position+camera.unproject_position(Drag.vector(slots[id].anchor_m))+offset
	for index in range(1,11): await _move(start.lerp(end,float(index)/10))
	measurements.append({"kind":"offset_drag","id":id,"offset":str(offset),"end":str(end),"source":drag.drag_source.duplicate(true),"hover":drag.hover_slot_id,"drop_point":str(drag.drop_point)})
	await _mouse(end,false)

func _write(name: String) -> void:
	var file := FileAccess.open(evidence.path_join(name),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"measurements":measurements,"events":event_log,"method":"Actual GUI mouse-event injection. No native Windows mouse CUA; not human-equivalent acceptance."},"\t"))
