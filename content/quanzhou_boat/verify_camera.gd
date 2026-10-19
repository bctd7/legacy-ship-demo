extends "res://content/quanzhou_boat/verify_tolerance.gd"
## Test-only low load. Product defaults and the user's windows are untouched.
var camera_frames: Array = []
var recording := false

func _init() -> void:
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)

func _ready() -> void:
	Engine.max_fps = 15
	super._ready()
	evidence = "res://content/quanzhou_boat/evidence/camera_continuity"
	viewport.scaling_3d_scale = 0.35
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	for light in world.find_children("*","DirectionalLight3D",true,false): light.shadow_enabled = false

func _process(delta: float) -> void:
	super._process(delta)
	if recording:
		camera_frames.append({"time_ms":Time.get_ticks_msec(),"id":lesson_id,"mode":mode,"stage":lesson_stage,"camera":_camera_snapshot(),"position":[camera.position.x,camera.position.y,camera.position.z],"boat_visible":boat.visible,"alternate_model":joint!=null,"pending":pending_id,"placed":placed.duplicate()})

func _bake_thumbnails() -> void:
	# One tiny thumbnail viewport at a time, rather than the normal startup batch.
	for g in groups:
		var sources := _part_meshes(g.id)
		var thumb := SubViewport.new()
		thumb.size = Vector2i(112,60)
		thumb.own_world_3d = true
		thumb.transparent_bg = true
		add_child(thumb)
		var stage := Node3D.new()
		thumb.add_child(stage)
		var box: AABB = bounds[g.id]
		var geometry := Node3D.new()
		stage.add_child(geometry)
		var names: Array[String] = []
		for source in sources:
			var copy := MeshInstance3D.new()
			copy.mesh = source.mesh
			copy.transform = source.global_transform
			geometry.add_child(copy)
			for surface in source.mesh.get_surface_count(): copy.set_surface_override_material(surface,source.get_active_material(surface))
			names.append(str(source.name))
		geometry.position = -box.get_center()
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-48,-25,0)
		stage.add_child(light)
		var env := WorldEnvironment.new()
		var environment := Environment.new()
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color.WHITE
		environment.ambient_light_energy = 0.7
		env.environment = environment
		stage.add_child(env)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = maxf(box.size.length()*0.82,0.04)
		cam.position = Vector3(0.6,0.9,1.7)*maxf(box.size.length(),0.1)
		stage.add_child(cam)
		cam.look_at(Vector3.ZERO)
		thumbnail_grab_maps[g.id] = {"basis":cam.global_basis,"size":cam.size,"mesh_count":sources.size(),"mesh_names":names}
		await _frames(2)
		RenderingServer.force_draw(false)
		card_pictures[g.id].texture = ImageTexture.create_from_image(thumb.get_texture().get_image())
		thumb.queue_free()
		await _frames(1)

func _drag_actual(id: String) -> Dictionary:
	await _reveal_card_with_wheel(id)
	var start := _grab_start(id,Vector2(0.38,0.5))
	await _hover_pointer(start)
	await _mouse(start,true)
	var original := _camera_snapshot()
	_check(not preview_group.visible and not drag.dragging,"press stays hidden "+id)
	var end := _pointer_for_anchor_offset(Vector2(0,-24))
	for index in range(1,6): await _move(start.lerp(end,float(index)/5))
	_check(_camera_snapshot()==original,"main camera remains fixed throughout actual held drag "+id)
	_check(drag.dragging and drag.hover_slot_id==id,"same object's anchor accepts drag "+id)
	await _mouse(end,false)
	_check(pending_id==id and mode=="lesson","release starts original-world lesson "+id)
	return original

func _wait_stage(stage: String) -> void:
	var deadline := Time.get_ticks_msec()+10000
	while mode=="lesson" and lesson_stage!=stage and Time.get_ticks_msec()<deadline: await _frames(1)
	_check(mode=="lesson" and lesson_stage==stage,"director reaches "+stage)

func _wait_returned(original: Dictionary, id: String) -> void:
	var deadline := Time.get_ticks_msec()+12000
	while mode!="assembly" and Time.get_ticks_msec()<deadline: await _frames(1)
	_check(mode=="assembly" and drag.enabled and drag.camera_enabled,"input restored after camera return "+id)
	_check(orbit.focus.is_equal_approx(original.focus) and is_equal_approx(orbit.distance,float(original.distance)) and is_equal_approx(orbit.yaw,float(original.yaw)) and is_equal_approx(orbit.pitch,float(original.pitch)),"return restores exact user's original pose "+id)
	_check(joint==null and boat.visible,"automatic flow keeps original boat without alternate asset "+id)

func _run() -> void:
	var deadline := Time.get_ticks_msec()+15000
	while thumbnail_grab_maps.size()!=groups.size() and Time.get_ticks_msec()<deadline: await _frames(1)
	await _frames(3)
	_check(groups.size()==28,"existing 28 connected groups retained")
	_check(get_window().size==Vector2i(640,360) and Engine.max_fps==15,"test-only 640x360 at 15fps")
	recording = true
	if "handoff" in OS.get_cmdline_user_args():
		await _run_handoff()
		return
	var original := await _drag_actual("keel_center")
	_check(not lesson_detail,"ordinary reference piece avoids a long forced closeup")
	await _wait_returned(original,"keel_center")
	var center := view.get_global_rect().get_center()
	await _mouse(center,true,MOUSE_BUTTON_RIGHT)
	await _move(center+Vector2(22,8),Vector2(22,8))
	await _mouse(center+Vector2(22,8),false,MOUSE_BUTTON_RIGHT)
	await _mouse(center,true,MOUSE_BUTTON_WHEEL_UP)
	await _mouse(center,false,MOUSE_BUTTON_WHEEL_UP)
	original = await _drag_actual("keel_bow")
	await _wait_stage("settle")
	_check(is_equal_approx(orbit.yaw,float(original.yaw)) and is_equal_approx(orbit.pitch,float(original.pitch)),"approach keeps the user's manually rotated bearing")
	await _capture("01_same_interface_settled")
	await _wait_returned(original,"keel_bow")
	original = await _drag_actual("keel_stern")
	await _wait_returned(original,"keel_stern")
	original = await _drag_actual("shell_port")
	await _wait_stage("fixed")
	_check(lesson_nails!=null and lesson_nails.get_child_count()>0,"real source nail pairs selected locally")
	var normal_depth := true
	for pair in lesson_nails.get_children():
		for copy in pair.get_children():
			for surface in copy.mesh.get_surface_count():
				var material: Material = copy.get_active_material(surface)
				if material is StandardMaterial3D and material.no_depth_test: normal_depth = false
	_check(normal_depth,"embedded shafts use actual depth instead of drawing through wood")
	await _capture("02_nails_prepared")
	await _frames(4)
	await _capture("03_nails_entering")
	await _wait_stage("complete")
	var final_nails := true
	var ended := 0
	for entry in nail_trace:
		if entry.phase=="fixed_final":
			ended += 1
			if entry.position_error_m>0.00001 or not entry.basis_matches: final_nails = false
	_check(final_nails and ended>0,"completed nail heads and shafts exactly recover original placement scale and axis")
	_check(lesson_nails==null,"completed demonstration leaves no protruding temporary clones")
	var source_visible := 0
	for mesh in _meshes(boat.find_child("F-1",true,false)):
		if mesh.is_visible_in_tree(): source_visible += 1
	_check(source_visible==384,"final state retains all 384 original side fastener meshes rather than hiding all nails")
	await _capture("04_nails_fixed_original_surface")
	await _wait_returned(original,"shell_port")
	original = await _drag_actual("shell_starboard")
	await _wait_returned(original,"shell_starboard")
	original = await _drag_actual("bulkhead_01")
	await _button_click("撤回一步")
	_check(pending_id.is_empty() and "bulkhead_01" not in placed and mode=="assembly","undo interrupts pending motion without stale commit")
	original = await _drag_actual("bulkhead_01")
	await _wait_returned(original,"bulkhead_01")
	for id in ["bulkhead_05","bulkhead_06"]:
		original = await _drag_actual(id)
		await _wait_returned(original,id)
	original = await _drag_actual("mast_bed_main")
	await _wait_stage("settle")
	_check(joint==null and boat.visible,"former tenon step no longer swaps to a detached v3 scene")
	await _capture("05_original_mast_bed_interface")
	await _wait_stage("wood")
	await _mouse(center,true,MOUSE_BUTTON_RIGHT)
	await _move(center+Vector2(-15,5),Vector2(-15,5))
	await _mouse(center+Vector2(-15,5),false,MOUSE_BUTTON_RIGHT)
	await _mouse(center,true,MOUSE_BUTTON_WHEEL_UP)
	await _mouse(center,false,MOUSE_BUTTON_WHEEL_UP)
	await _wait_stage("complete")
	_check(lesson_user_inspecting,"manual closeup rotation/zoom pauses automatic return")
	await _button_click("返回整船")
	await _wait_returned(original,"mast_bed_main")
	original = await _drag_actual("mast_bed_fore")
	await _wait_returned(original,"mast_bed_fore")
	original = await _drag_actual("deck_bow")
	await _wait_stage("approach")
	await _button_click("重置装配")
	await _frames(8)
	_check(mode=="assembly" and placed.is_empty() and pending_id.is_empty() and lesson_stage.is_empty(),"reset interrupts approach and clears all pending callbacks")
	_check(lesson_nails==null and lesson_context_materials.is_empty(),"reset releases demonstration objects and fading materials")
	await _capture("06_reset_after_interruption")
	var alternate := false
	var largest_step := 0.0
	var previous: Dictionary = {}
	for frame in camera_frames:
		if frame.alternate_model or not frame.boat_visible: alternate = true
		if not previous.is_empty() and frame.mode=="lesson" and previous.mode=="lesson" and frame.id==previous.id:
			var a := Drag.vector(frame.position)
			var b := Drag.vector(previous.position)
			if frame.stage in ["approach","settle","wood","fixed","complete","returning"]: largest_step = maxf(largest_step,a.distance_to(b))
		previous = frame
	_check(not alternate,"every automatic frame stays in the original boat world")
	_check(largest_step<0.65,"15fps camera trace has no abrupt second-shot jump")
	var passed := true
	for item in checks: if not item.passed: passed = false
	var f := FileAccess.open(evidence.path_join("low_load_result.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":passed,"checks":checks,"events":event_log,"frames":camera_frames,"nails":nail_trace,"largest_camera_step_m":largest_step,"settings":{"window":"640x360","fps":15,"scaling_3d":0.35,"shadows":false,"thumbnails":"112x60 sequential"},"method":"Godot GUI mouse-event injection; no native Windows mouse actions or user-window input. Selected interfaces only, not full 28-group regression or target-machine performance acceptance."},"\t"))
	print("LOW_LOAD_CAMERA checks=",checks.size()," passed=",passed)
	get_tree().quit(0 if passed else 1)

func _run_handoff() -> void:
	var seating: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/quanzhou_boat/config/nail_seating.json"))
	var max_surface_error := 0.0
	var max_shaft_proud := 0.0
	var min_head_visible := 100.0
	var axes_preserved := true
	for pair in seating.pairs:
		var head: MeshInstance3D = mesh_lookup[pair.head]
		var shank: MeshInstance3D = mesh_lookup[pair.shank]
		var expected := Drag.vector(pair.head_center_source_m)+Drag.vector(pair.delta_world_m)
		var actual := (head.global_transform*head.get_aabb()).get_center()
		max_surface_error = maxf(max_surface_error,actual.distance_to(expected))
		max_shaft_proud = maxf(max_shaft_proud,float(pair.shaft_projection_after_m))
		min_head_visible = minf(min_head_visible,float(pair.head_top_after_m))
		if not head.global_basis.is_equal_approx((head.get_meta("nail_raw_transform") as Transform3D).basis) or not shank.global_basis.is_equal_approx((shank.get_meta("nail_raw_transform") as Transform3D).basis): axes_preserved = false
	_check(seating.pairs.size()==384 and seating.unresolved.is_empty(),"all 384 source head/shaft pairs fitted against actual timber triangles")
	_check(max_surface_error<0.00001 and axes_preserved,"runtime seating matches offline world coordinates without changing nail scale or axis")
	_check(max_shaft_proud<0.000101 and min_head_visible>0.0002,"shaft exterior projection is below 0.1mm tolerance while every head retains visible geometry")
	var original := await _drag_actual("keel_center")
	await _wait_returned(original,"keel_center")
	original = await _drag_actual("keel_bow")
	await _wait_stage("returning")
	await _capture("handoff_01_return_in_motion")
	original = await _drag_actual("keel_stern")
	_check("keel_bow" in placed and pending_id=="keel_stern","next real press interrupts return and starts next source without stale callbacks")
	await _wait_returned(original,"keel_stern")
	await _capture("handoff_02_next_piece_camera_held")
	original = await _drag_actual("shell_port")
	await _wait_stage("fixed")
	var kept_solid := true
	for mesh in _part_meshes("shell_port"):
		for surface in mesh.mesh.get_surface_count():
			if mesh.has_meta("context_material_"+str(surface)): kept_solid = false
	_check(kept_solid,"current part remains solid; only pre-existing foreground occluders can fade")
	await _capture("handoff_03_nails_start")
	await _wait_stage("complete")
	_check(lesson_nails==null,"fixed state removes temporary nail pairs")
	var final_exact := true
	for row in nail_trace:
		if row.phase=="fixed_final" and (row.position_error_m>0.00001 or not row.basis_matches): final_exact = false
	_check(final_exact,"final normal-depth nail geometry matches the fitted timber-surface targets")
	await _capture("handoff_04_nails_fixed_solid_wood")
	await _wait_returned(original,"shell_port")
	original = await _drag_actual("shell_starboard")
	await _wait_returned(original,"shell_starboard")
	original = await _drag_actual("bulkhead_01")
	await _button_click("返回整船")
	await _wait_returned(original,"bulkhead_01")
	await _button_click("撤回一步")
	_check("bulkhead_01" not in placed,"undo after explicit return removes only the completed local group")
	original = await _drag_actual("bulkhead_01")
	await _button_click("重置装配")
	await _frames(12)
	_check(placed.is_empty() and pending_id.is_empty() and mode=="assembly" and lesson_context_materials.is_empty(),"reset cancels repeat motion and frees all effect resources")
	var passed := true
	for row in checks: if not row.passed: passed = false
	var f := FileAccess.open(evidence.path_join("handoff_result.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":passed,"checks":checks,"events":event_log,"frames":camera_frames,"nails":nail_trace,"seating":{"pairs":seating.pairs.size(),"max_world_position_error":max_surface_error,"max_shaft_proud_m":max_shaft_proud,"min_visible_head_m":min_head_visible,"axes_and_scale_preserved":axes_preserved},"settings":"640x360, 15fps, 0.35 3D scale, shadows off, sequential 112x60 thumbnails","method":"Actual Godot GUI event injection. Focused final-material and camera-handoff checks only; no native mouse actions or full 28-group re-run."},"\t"))
	print("LOW_LOAD_HANDOFF checks=",checks.size()," passed=",passed)
	get_tree().quit(0 if passed else 1)
