extends "res://content/quanzhou_boat/verify_shared_input.gd"
## Focused visible captures of current nail stages after the full input run.
func _ready() -> void:
	super._ready()
	evidence = "res://content/quanzhou_boat/evidence/shared_visual"

func _run() -> void:
	var deadline := Time.get_ticks_msec()+15000
	while thumbnail_grab_maps.size()!=groups.size() and Time.get_ticks_msec()<deadline: await _frames(1)
	recording = true
	for id in ["keel_center","keel_bow","keel_stern"]:
		var before := await _drag_actual(id)
		await _wait_returned(before,id)
	var before := await _drag_actual("shell_port")
	await _wait_stage("fixed")
	_check(lesson_nails!=null and lesson_nails.get_child_count()==3,"current closeup prepares three actual source nail pairs")
	var normal_depth := true
	for pair in lesson_nails.get_children():
		for copy in pair.get_children():
			for surface in copy.mesh.get_surface_count():
				var material: Material = copy.get_active_material(surface)
				if material is StandardMaterial3D and material.no_depth_test: normal_depth = false
	_check(normal_depth,"current nail geometry keeps ordinary depth testing")
	await _capture("01_nails_prepared")
	await _wait_stage("complete")
	_check(lesson_nails==null,"completed fixing removes all temporary nail clones")
	await _capture("02_nails_seated")
	var blank := _blank_point()
	await _mouse(blank,true,MOUSE_BUTTON_RIGHT)
	await _move(blank+Vector2(8,3))
	await _mouse(blank+Vector2(8,3),false,MOUSE_BUTTON_RIGHT)
	await _mouse(blank,true,MOUSE_BUTTON_MIDDLE)
	await _move(blank+Vector2(8,4))
	await _mouse(blank+Vector2(8,4),false,MOUSE_BUTTON_MIDDLE)
	await _mouse(blank,true,MOUSE_BUTTON_WHEEL_UP)
	await _mouse(blank,false,MOUSE_BUTTON_WHEEL_UP)
	_check(mode=="lesson" and lesson_user_inspecting,"shared view actions pause the finished automatic closeup")
	await _capture("03_nails_after_view_actions")
	await _button_click("返回整船")
	await _wait_returned(before,"shell_port_manual_return")
	_check(lesson_nails==null and lesson_context_materials.is_empty() and lesson_hidden_nails.is_empty() and lesson_homes.is_empty(),"explicit return clears all nail/fade/motion helpers")
	await _button_click("重置装配")
	await _button_click("整船查看")
	_check(mode=="overview" and placed.is_empty(),"full-boat viewing remains separate from assembly completion")
	await _capture("04_current_full_boat")
	var passed := true
	for row in checks: if not row.passed: passed = false
	var file := FileAccess.open(evidence.path_join("visual_result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"checks":checks,"events":event_log,"nails":nail_trace,"frames":camera_frames,"method":"Focused serial 640x360 15fps current-version graphic run with actual Godot GUI event injection. Screenshots are rendered pixels for separate visual inspection; assertion counts alone are not appearance approval. Not native mouse or target-hardware acceptance."},"\t"))
	print("SHARED_VISUAL checks=",checks.size()," passed=",passed)
	get_tree().quit(0 if passed else 1)
