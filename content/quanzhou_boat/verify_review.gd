extends "res://content/quanzhou_boat/verify_play.gd"

func _ready() -> void:
	evidence = "res://content/quanzhou_boat/evidence/review_after"
	super._ready()

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	# Windows may stop presentation for an occluded window; draw this viewport
	# explicitly so capture does not wait forever or need to steal focus.
	await _frames(2) # Flush queued frees, transforms and Control redraws first.
	RenderingServer.force_draw(false)
	var error := get_viewport().get_texture().get_image().save_png(evidence.path_join(name+".png"))
	_check(error == OK,"capture "+name)

func _wait_phase(needle: String) -> bool:
	var deadline := Time.get_ticks_msec()+6000
	while Time.get_ticks_msec()<deadline:
		if lesson_phase.contains(needle): return true
		await _frames(1)
	_check(false,"phase timeout: "+needle+" / "+lesson_id+" / "+lesson_phase)
	return false

func _run() -> void:
	if "nails-only" in OS.get_cmdline_user_args():
		await _run_nail_review()
		return
	await _frames(30)
	_check(_meshes(boat).size()==1286,"source geometry remains 1286 meshes")
	_check(groups.all(func(g: Dictionary): return g.has("lesson") and g.has("anchor_m") and g.has("preview_meshes")),"13 separate connection targets, cameras and source notes")
	await _capture("01_overview")
	set_mode("assembly")
	await _frames()
	var point: Vector2 = cards.keel_center.get_global_rect().get_center()
	await _mouse(point,true)
	_check(preview_group.get_child_count()>0,"drag carries actual mesh geometry")
	var preview_mesh: MeshInstance3D = preview_group.get_child(0)
	_check(preview_mesh.transform.basis.is_equal_approx(mesh_lookup["Keel segment 1"].global_basis),"preview orientation and scale match final source pose")
	await _mouse(point,false)
	_check(placed.is_empty() and pending_id.is_empty(),"click still only selects")
	await _drop("keel_center",false)
	_check(placed.is_empty() and pending_id.is_empty(),"outside release does not start camera or install")
	await _drop("masts")
	_check(placed.is_empty() and pending_id.is_empty(),"locked group cannot bypass installation order")
	await _drop("keel_center")
	_check(mode=="lesson" and pending_id=="keel_center" and placed.is_empty(),"legal release starts a pending animation instead of instant placement")
	_check(not drag.held and not drag.dragging,"camera starts after pointer release")
	await _wait_phase("龙骨基准")
	await get_tree().create_timer(0.25).timeout
	await _capture("02_keel_motion")
	undo()
	await _frames(40)
	_check(mode=="assembly" and placed.is_empty() and pending_id.is_empty(),"undo cancels pending animation without committing or removing another group")
	_check(lesson_homes.is_empty() and lesson_nails==null,"undo clears animation geometry and effects")
	await _drop("keel_center")
	skip_lesson()
	await _frames(5)
	_check(mode=="assembly" and placed==["keel_center"],"skip completes accepted placement and returns to original camera")
	reset_assembly()
	var home_camera := camera.transform
	for index in groups.size():
		var g: Dictionary = groups[index]
		await _drop(g.id)
		_check(mode=="lesson" and g.id not in placed,"pending connection "+str(g.id))
		while lesson_phase=="定位连接处": await _frames(1)
		await get_tree().create_timer(0.20).timeout
		if g.id in ["mast_beds","deck"]:
			_check(moving!=null and not moving.position.is_equal_approx(moving_home),"tenon visibly travels toward actual mortise "+str(g.id))
			await _capture("step_%02d_%s_entering"%[index+1,g.id])
			toggle_cutaway()
		if g.lesson.has("nail_side"):
			await _wait_phase("斜钉进入")
			_check(lesson_nails!=null and lesson_nails.get_child_count()==6,"three source nail pairs animate after wood "+str(g.id))
			await get_tree().create_timer(0.12).timeout
			await _capture("step_%02d_%s_nailing"%[index+1,g.id])
		elif g.id not in ["mast_beds","deck"]:
			await _capture("step_%02d_%s_motion"%[index+1,g.id])
		await _wait_phase("固定完成")
		_check(g.id in placed and pending_id.is_empty(),"commit after fixed phase "+str(g.id))
		_check(camera.position.distance_to(Drag.vector(g.lesson.focus_m))<float(g.lesson.distance_m)+0.01,"camera targets real connection "+str(g.id))
		await _capture("step_%02d_%s_fixed"%[index+1,g.id])
		if g.id in ["mast_beds","deck"]:
			_check(moving.position.is_equal_approx(moving_home),"tenon ends in authored fitted pose "+str(g.id))
			_check(source_label.text.contains("非考古"),"extension warning remains visible "+str(g.id))
		leave_joint()
		await _frames(3)
		_check(mode=="assembly" and camera.transform.is_equal_approx(home_camera),"return restores overview camera "+str(g.id))
	_check(completion_count==1 and placed.size()==13,"all 13 fixed groups complete exactly once")
	_check(lesson_homes.is_empty() and lesson_materials.is_empty(),"all source transforms and reveal materials restored")
	await _capture("03_complete")
	undo()
	_check(placed.size()==12 and "rigging" not in placed,"completed group can be withdrawn")
	reset_assembly()
	_check(placed.is_empty() and history.is_empty(),"reset restores empty assembly")
	# A reset during an actual nail animation must invalidate its late completion.
	for id in ["keel_center","keel_ends"]:
		await _drop(id)
		skip_lesson()
		await _frames()
	await _drop("shell_port")
	await _wait_phase("斜钉进入")
	reset_assembly()
	await get_tree().create_timer(1.3).timeout
	_check(placed.is_empty() and pending_id.is_empty() and mode=="assembly","reset during nailing stops late commits and restores camera")
	_check(lesson_nails==null and lesson_materials.is_empty(),"reset removes nail effects and temporary section materials")
	set_mode("overview")
	show_joint(3)
	await _frames(5)
	toggle_cutaway()
	await _capture("04_manual_joint_cutaway")
	leave_joint()
	_check(not cutaway and boat.visible,"manual joint return restores whole uncut boat")
	await _capture("05_final_overview")
	var passed := true
	for c in checks: if not c.passed: passed = false
	var file := FileAccess.open(evidence.path_join("checks.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"checks":checks,"phase_trace":lesson_trace,"input_method":"Real Godot input events; screenshots captured from running rendered viewport. User acceptance remains pending.","renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name()},"\t"))
	print("REVIEW_CHECKS ",checks.size()," passed=",passed)
	get_tree().quit(0 if passed else 1)

func _run_nail_review() -> void:
	await _frames(20)
	set_mode("assembly")
	var trace: Array = []
	for index in groups.size():
		var g: Dictionary = groups[index]
		await _drop(g.id)
		if not g.lesson.has("nail_side"):
			skip_lesson()
			await _frames()
			continue
		await _wait_phase("斜钉进入")
		await get_tree().create_timer(0.12).timeout
		_check(lesson_nails.get_child_count()==6,"source nail pairs "+str(g.id))
		var states: Array = []
		for nail in lesson_nails.get_children():
			var center: Vector3 = (nail.global_transform*nail.get_aabb()).get_center()
			states.append({"center":str(center),"screen":str(camera.unproject_position(center)),"remaining_translation":str(nail.position-nail.get_meta("home"))})
		trace.append({"group":g.id,"phase":lesson_phase,"nails":states})
		await _capture("step_%02d_%s_nailing"%[index+1,g.id])
		await _wait_phase("固定完成")
		var seated := true
		for nail in lesson_nails.get_children():
			if not nail.position.is_equal_approx(nail.get_meta("home")): seated = false
		_check(seated,"nails finish at authored final pose "+str(g.id))
		await _capture("step_%02d_%s_fixed"%[index+1,g.id])
		leave_joint()
		await _frames()
		if g.id=="fasteners": break
	var passed := true
	for item in checks: if not item.passed: passed = false
	var file := FileAccess.open(evidence.path_join("nailing_checks.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"checks":checks,"motion_trace":trace,"display":"Temporary source nail clones use an explicitly labeled x-ray pass so the shank entering wood stays visible."},"\t"))
	print("NAILING_REVIEW ",checks.size()," passed=",passed)
	get_tree().quit(0 if passed else 1)
