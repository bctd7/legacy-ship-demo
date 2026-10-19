extends "res://content/quanzhou_boat/verify_play.gd"
var input_trace: Array = []

func _ready() -> void:
	if DisplayServer.get_name()!="headless": DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS,true)
	evidence = "res://content/quanzhou_boat/evidence/first_input"
	super._ready()

func _capture(name: String) -> void:
	if DisplayServer.get_name()=="headless": return
	await _frames(2)
	RenderingServer.force_draw(false)
	_check(get_viewport().get_texture().get_image().save_png(evidence.path_join(name+".png"))==OK,"capture "+name)

func _button_click(text: String) -> void:
	for b in find_children("*","Button",true,false):
		if b.text == text:
			await _mouse(b.get_global_rect().get_center(),true)
			await _mouse(b.get_global_rect().get_center(),false)
			return
	_check(false,"missing actual UI button "+text)

func _physical_drag(id: String, world_target: Vector3) -> void:
	panel.get_parent().ensure_control_visible(cards[id])
	await _frames(3)
	var start: Vector2 = cards[id].get_global_rect().get_center()
	var end: Vector2 = view.global_position+camera.unproject_position(world_target)
	var before := {"id":id,"mode":mode,"enabled":drag.enabled,"revision":revision,"card":str(start),"release":str(end),"viewport":str(viewport.size),"control_rect":str(view.get_global_rect()),"root_transform":str(get_tree().root.get_final_transform())}
	await _mouse(start,true)
	for i in range(1,11): await _move(start.lerp(end,float(i)/10.0))
	before["held"] = drag.held
	before["dragging"] = drag.dragging
	before["hover"] = drag.hover_slot_id
	before["preview_translation"] = str(preview_group.position)
	if id=="keel_center" and drag.hover_slot_id==id and "baseline" not in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.22).timeout
		_check(pending_id.is_empty() and drag.held,"valid hover still waits for physical release")
		_check(preview_group.position.distance_to(Drag.vector(_group(id).approach_m))<0.015,"near preview settles without a high jump")
		before["stable_preview_translation"] = str(preview_group.position)
		await _capture("fixed_valid_hover")
	await _mouse(end,false)
	before["pending_after_release"] = pending_id
	before["mode_after_release"] = mode
	input_trace.append(before)

func _run() -> void:
	await _frames(25)
	if "baseline" in OS.get_cmdline_user_args():
		await _physical_drag("keel_center",(bounds.keel_center as AABB).get_center())
		_check(mode=="overview" and pending_id.is_empty(),"REPRO cold entry is overview with assembly input disabled")
		await _capture("baseline_cold_drag_rejected")
		await _button_click("分组装配")
		_check(mode=="assembly" and drag.enabled,"real toolbar click enables assembly")
		await _physical_drag("keel_center",(bounds.keel_center as AABB).get_center())
		_check(pending_id.is_empty(),"REPRO natural source-mesh center is outside hidden first anchor")
		await _capture("baseline_center_drop_rejected")
		await _physical_drag("keel_center",Drag.vector(slots.keel_center.anchor_m))
		_check(pending_id=="keel_center","exact hidden anchor accepts same real input path")
		_save("baseline.json")
		get_tree().quit()
		return
	_check(mode=="assembly" and drag.enabled,"cold start immediately accepts assembly input")
	_check(fixed_guide.visible and guide_label.visible and guide_id=="keel_center","fixed first assembly outline and label visible before selection")
	var natural_center := (bounds.keel_center as AABB).get_center()
	_check(Drag.vector(slots.keel_center.anchor_m).distance_to(natural_center)<0.001,"first target matches natural center of actual source geometry")
	_check(not _pointer_blocked(view.global_position+camera.unproject_position(natural_center)),"fixed first target is visible outside blocking UI")
	await _capture("fixed_cold_start")
	# A real click must not install, including the now-enabled cold entry.
	var card: Vector2 = cards.keel_center.get_global_rect().get_center()
	await _mouse(card,true)
	await _mouse(card,false)
	_check(pending_id.is_empty() and placed.is_empty(),"real card click selects without installation")
	await _physical_drag("keel_center",natural_center+Vector3(0,0.5,0))
	_check(pending_id.is_empty() and placed.is_empty() and not preview_group.visible,"wrong-region release returns carried item without installation")
	_check(fixed_guide.visible,"wrong release keeps fixed assembly guide visible")
	await _capture("fixed_wrong_drop")
	await _physical_drag("keel_center",natural_center)
	_check(pending_id=="keel_center" and mode=="lesson","natural center release starts actual installation")
	_check(input_trace.back().hover=="keel_center","pointer hover locks the visible first target")
	await _wait_installed("keel_center")
	await _capture("fixed_first_installed")
	await _button_click("返回整船")
	_check(mode=="assembly" and placed==["keel_center"],"actual return button preserves first placement")
	await _button_click("撤回一步")
	_check(placed.is_empty() and guide_id=="keel_center" and fixed_guide.visible,"actual undo restores cold first guide")
	await _capture("fixed_undo_ready")
	# Drop at a different visible part of the same dashed outline, not a magic pixel.
	await _physical_drag("keel_center",Drag.vector(slots.keel_center.trigger_points_m[1]))
	_check(pending_id=="keel_center","another position along first outline also accepts release")
	await _wait_installed("keel_center")
	await _button_click("返回整船")
	_check(guide_id=="keel_ends" and fixed_guide.visible,"next legal group gets its own persistent guide")
	await _physical_drag("keel_ends",Drag.vector(slots.keel_ends.anchor_m))
	_check(pending_id=="keel_ends","second group accepts same actual mouse path")
	await _button_click("跳过镜头，继续装配")
	_check(placed==["keel_center","keel_ends"] and mode=="assembly","actual skip button completes second group")
	await _physical_drag("shell_port",Drag.vector(slots.shell_port.anchor_m))
	_check(pending_id=="shell_port","following board group accepts actual drag after first two groups")
	await _wait_installed("shell_port")
	await _button_click("返回整船")
	_check(placed.size()==3 and fixed_guide.visible,"third group commits and next target remains visible")
	await _capture("fixed_following_steps")
	var passed := true
	for item in checks: if not item.passed: passed = false
	_save("fixed_%dx%d.json"%[get_viewport().size.x,get_viewport().size.y])
	print("COLD_INPUT_CHECKS ",checks.size()," passed=",passed)
	get_tree().quit(0 if passed else 1)

func _wait_installed(id: String) -> void:
	var deadline := Time.get_ticks_msec()+6000
	while id not in placed and Time.get_ticks_msec()<deadline: await _frames(1)
	_check(id in placed,"animation commits accepted release "+id)

func _save(name: String) -> void:
	var passed := true
	for item in checks: if not item.passed: passed = false
	var f := FileAccess.open(evidence.path_join(name),FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":passed,"checks":checks,"input_trace":input_trace,"method":"Mouse press/motion/release through actual Godot input and actual toolbar buttons; no direct install or mode calls. Background probe does not take OS focus."},"\t"))
