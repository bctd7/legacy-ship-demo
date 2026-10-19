extends "res://content/quanzhou_boat/verify_camera.gd"
## Complete current animations, serial low-load settings inherited unchanged.
var full_routes: Array = []
var initial_transforms: Dictionary = {}

func _ready() -> void:
	super._ready()
	evidence = "res://content/quanzhou_boat/evidence/camera_full_28"

func _run() -> void:
	var deadline := Time.get_ticks_msec()+15000
	while thumbnail_grab_maps.size()!=groups.size() and Time.get_ticks_msec()<deadline: await _frames(1)
	await _frames(3)
	_check(get_window().size==Vector2i(640,360) and Engine.max_fps==15,"single low-load 640x360 15fps run")
	_check(groups.size()==28 and placed.is_empty(),"cold start of current 28-group sequence")
	for mesh in _meshes(boat): initial_transforms[str(mesh.name)] = mesh.global_transform
	_check(initial_transforms.size()==1286,"all 1286 fitted source meshes retained")
	recording = true
	for index in groups.size():
		var id: String = groups[index].id
		var trace_start := lesson_trace.size()
		var nail_start := nail_trace.size()
		var original := await _drag_actual(id)
		await _wait_returned(original,id)
		_check(placed.size()==index+1 and id in placed and pending_id.is_empty(),"exactly one committed group "+id)
		var stages: Array[String] = []
		for entry in lesson_trace.slice(trace_start):
			if entry.group==id and str(entry.stage) not in stages: stages.append(str(entry.stage))
		var complete_stages := true
		for stage in ["holding","settle","wood","fixed","complete"]:
			if stage not in stages: complete_stages = false
		_check(complete_stages,"all contact/fixing/completion stages execute "+id)
		if id in _director().key_groups:
			_check("approach" in stages and "returning" in stages,"key interface has continuous approach and return "+id)
		else:
			_check("approach" not in stages,"ordinary component does not force a long closeup "+id)
		var max_error := 0.0
		var bases_match := true
		var all_members_visible := true
		for mesh in _part_meshes(id):
			var expected: Transform3D = initial_transforms[str(mesh.name)]
			max_error = maxf(max_error,mesh.global_position.distance_to(expected.origin))
			if not mesh.global_basis.is_equal_approx(expected.basis): bases_match = false
			if not mesh.is_visible_in_tree(): all_members_visible = false
		_check(max_error<0.00001 and bases_match and all_members_visible,"source poses and visible members restored "+id)
		_check(lesson_nails==null and lesson_context_materials.is_empty() and lesson_hidden_nails.is_empty() and lesson_homes.is_empty(),"no lingering effects or motion state "+id)
		var nail_exact := true
		var nail_final_count := 0
		var prepared_count := 0
		for entry in nail_trace.slice(nail_start):
			if entry.phase=="prepared": prepared_count += 1
			if entry.phase=="fixed_final":
				nail_final_count += 1
				if float(entry.position_error_m)>0.00001 or not entry.basis_matches: nail_exact = false
		if _group(id).lesson.kind=="sheathing":
			_check(prepared_count==0,"cover step does not misrepresent buried structural nails as outer light nails "+id)
		elif _group(id).lesson.has("nail_side"):
			_check(prepared_count>0 and nail_final_count==prepared_count*2 and nail_exact,"nail pairs finish at fitted surface targets "+id)
		full_routes.append({"id":id,"order":index+1,"stages":stages,"placed":placed.duplicate(),"camera_before":original,"camera_after":_camera_snapshot(),"max_pose_error_m":max_error,"basis_matches":bases_match,"prepared_nail_pairs":prepared_count,"nail_final_meshes":nail_final_count,"nails_exact":nail_exact})
		print("FULL_PROGRESS ",index+1,"/",groups.size()," ",id)
		if id in ["shell_port","outer_port","mast_bed_main","deck_bow","mast_rig_fore","mast_rig_main","rudder"]: await _capture("step_%02d_%s"%[index+1,id])
	_check(placed.size()==28 and snapshot().complete and completion_count==1,"complete new-animation sequence commits all 28 groups once")
	var visible_count := 0
	for mesh in _meshes(boat):
		if mesh.is_visible_in_tree(): visible_count += 1
	_check(visible_count==1286,"complete scene retains all 1286 source meshes")
	var nail_nodes := 0
	var max_nail_shift_error := 0.0
	for mesh in _meshes(boat):
		if mesh.has_meta("nail_raw_transform"):
			nail_nodes += 1
			var raw: Transform3D = mesh.get_meta("nail_raw_transform")
			var expected: Vector3 = raw.origin+mesh.get_meta("nail_seating_delta")
			max_nail_shift_error = maxf(max_nail_shift_error,mesh.global_position.distance_to(expected))
	_check(nail_nodes==768 and max_nail_shift_error<0.00001,"all 768 final fastener nodes retain their fitted positions after all covering/rigging steps")
	await _capture("01_complete_28")
	await _button_click("撤回一步")
	_check(placed.size()==27 and "rudder" not in placed and guide_id=="rudder","actual undo removes only completed rudder group")
	var original := await _drag_actual("rudder")
	await _wait_returned(original,"rudder_reinstall")
	_check(placed.size()==28 and completion_count==2,"last group re-installs with full current animation and return")
	await _button_click("重置装配")
	await _frames(10)
	_check(placed.is_empty() and history.is_empty() and pending_id.is_empty() and mode=="assembly" and drag.enabled and guide_id=="keel_center","actual reset clears completed sequence and restores first input")
	_check(lesson_stage.is_empty() and lesson_nails==null and lesson_context_materials.is_empty(),"reset leaves no director effects or delayed work")
	await _capture("02_reset_after_full")
	var originals_only := true
	for frame in camera_frames:
		if frame.alternate_model or not frame.boat_visible: originals_only = false
	_check(originals_only,"every recorded automatic frame uses original boat without alternate model")
	var passed := true
	for row in checks: if not row.passed: passed = false
	var file := FileAccess.open(evidence.path_join("full_result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"checks":checks,"routes":full_routes,"events":event_log,"frames":camera_frames,"nails":nail_trace,"source_meshes_visible":visible_count,"fastener_nodes":nail_nodes,"max_fastener_target_error_m":max_nail_shift_error,"settings":{"window":"640x360","fps":15,"3d_scale":0.35,"shadows":false,"thumbnails":"112x60 sequential"},"method":"Single serial full 28-group run, actual Godot GUI event injection. No direct installation, undo/reset calls or assembly-state assignment. Not native mouse acceptance, HD visual approval or target-hardware benchmarking."},"\t"))
	print("FULL_CAMERA_28 checks=",checks.size()," passed=",passed," frames=",camera_frames.size()," events=",event_log.size())
	get_tree().quit(0 if passed else 1)
