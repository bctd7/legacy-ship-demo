extends "res://content/quanzhou_boat/verify_first_input.gd"
var sequence_states: Array = []
var event_log: Array = []
var route_log: Array = []

func _ready() -> void:
	super._ready()
	evidence = "res://content/quanzhou_boat/evidence/sequence"
	for button in find_children("*","Button",true,false):
		button.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton:
				event_log.append({"kind":"gui_input","control_text":button.text,"position_local":str(event.position),"pressed":event.pressed,"button":event.button_index}))

func _input(event: InputEvent) -> void:
	super._input(event)
	if event is InputEventMouseButton:
		event_log.append({"kind":"root_input","position":str(event.position),"global_position":str(event.global_position),"pressed":event.pressed,"button":event.button_index})

func _state(tag: String) -> void:
	sequence_states.append({"tag":tag,"mode":mode,"enabled":drag.enabled,"camera_enabled":drag.camera_enabled,"held":drag.held,"pending":pending_id,"placed":placed.duplicate(),"guide":guide_id,"phase":lesson_phase})

func _baseline_run() -> void:
	await _frames(25)
	await _physical_drag("keel_center",(bounds.keel_center as AABB).get_center())
	await _wait_installed("keel_center")
	_state("first_animation_finished_without_return_click")
	await _capture("baseline_first_finished")
	await _physical_drag("keel_ends",Drag.vector(slots.keel_ends.anchor_m))
	_state("second_drag_without_extra_button")
	_check(mode=="lesson" and not drag.enabled and pending_id.is_empty(),"REPRO completed closeup still locks next card input")
	_check(not input_trace.back().held and input_trace.back().hover.is_empty(),"REPRO second press never starts a held gesture")
	await _capture("baseline_second_blocked")
	await _button_click("返回整船")
	await _physical_drag("keel_ends",Drag.vector(slots.keel_ends.anchor_m))
	_check(pending_id=="keel_ends","actual explicit return button unlocks same second-card input")
	_state("second_drag_after_explicit_return")
	var file := FileAccess.open(evidence.path_join("baseline.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"states":sequence_states,"events":input_trace,"method":"Godot input-event injection through actual controls; no native CUA mouse capability is exposed, so this is not human-equivalent acceptance."},"\t"))
	get_tree().quit()

func _mouse(point: Vector2, down: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var record := {"kind":"press" if down else "release","button":button,"logical":str(point),"window_pixels":str(get_tree().root.get_final_transform()*point),"time_ms":Time.get_ticks_msec(),"before":_input_state()}
	await super._mouse(point,down,button)
	record["after"] = _input_state()
	event_log.append(record)

func _move(point: Vector2, relative := Vector2.ZERO) -> void:
	var record := {"kind":"move","logical":str(point),"window_pixels":str(get_tree().root.get_final_transform()*point),"time_ms":Time.get_ticks_msec(),"before":_input_state()}
	await super._move(point,relative)
	record["after"] = _input_state()
	event_log.append(record)

func _input_state() -> Dictionary:
	return {"mode":mode,"enabled":drag.enabled,"camera_enabled":drag.camera_enabled,"held":drag.held,"dragging":drag.dragging,"source":drag.drag_source.get("item_id",""),"hover":drag.hover_slot_id,"eligible":drag.eligible,"revision":revision,"pending":pending_id,"placed":placed.duplicate(),"phase":lesson_phase}

func _button_click(text: String) -> void:
	for b in find_children("*","Button",true,false):
		if b.text==text and b.is_visible_in_tree():
			var observed: Array[bool] = [false]
			var listener := func():
				observed[0] = true
				event_log.append({"kind":"ui_pressed","button_text":text,"time_ms":Time.get_ticks_msec(),"state":_input_state()})
			b.pressed.connect(listener)
			await _hover_pointer(b.get_global_rect().get_center())
			await _mouse(b.get_global_rect().get_center(),true)
			await _mouse(b.get_global_rect().get_center(),false)
			if b.pressed.is_connected(listener): b.pressed.disconnect(listener)
			_check(observed[0],"actual GUI pressed signal "+text)
			return
	_check(false,"visible actual UI button missing: "+text)

func _hover_pointer(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = get_tree().root.get_final_transform()*point
	event.global_position = event.position
	event.button_mask = 0
	Input.parse_input_event(event)
	await _frames(3)
	var hovered := get_viewport().gui_get_hovered_control()
	event_log.append({"kind":"hover_move","logical":str(point),"window_pixels":str(event.position),"viewport_mouse":str(get_viewport().get_mouse_position()),"hovered":str(hovered.get_path()) if hovered else "","state":_input_state()})

func _reveal_card_with_wheel(id: String) -> void:
	var scroll: ScrollContainer = panel.get_parent()
	for attempt in 35:
		var rect := scroll.get_global_rect()
		var card: Rect2 = cards[id].get_global_rect()
		if card.position.x>=rect.position.x and card.end.x<=rect.end.x: return
		var direction := MOUSE_BUTTON_WHEEL_RIGHT if card.end.x>rect.end.x else MOUSE_BUTTON_WHEEL_LEFT
		await _mouse(rect.get_center(),true,direction)
		await _mouse(rect.get_center(),false,direction)
	_check(false,"wheel could not reveal tray card "+id)

func _drag_group(id: String) -> void:
	await _reveal_card_with_wheel(id)
	var before := _input_state()
	var start: Vector2 = cards[id].get_global_rect().get_center()
	await _hover_pointer(start)
	await _mouse(start,true)
	_check(drag.held and drag.drag_source.get("item_id","")==id and drag.eligible,"press captures permitted source "+id)
	# A finished closeup may return on this press. Project the now-visible guide
	# after actual input dispatch, as a person would drag toward the restored view.
	var end: Vector2 = view.global_position+camera.unproject_position(Drag.vector(slots[id].anchor_m))
	for i in range(1,11): await _move(start.lerp(end,float(i)/10.0))
	_check(drag.dragging and drag.hover_slot_id==id,"move aligns with visible target "+id)
	await _mouse(end,false)
	_check(pending_id==id and mode=="lesson","release starts accepted installation "+id)
	route_log.append({"group":id,"before_press":before,"after_release":_input_state(),"release_logical":str(end)})

func _wait_assembly(tag: String) -> void:
	var deadline := Time.get_ticks_msec()+6000
	while mode!="assembly" and Time.get_ticks_msec()<deadline: await _frames(1)
	_check(mode=="assembly" and drag.enabled and drag.camera_enabled and not drag.held,"assembly input restored "+tag)
	_state(tag)

func _run() -> void:
	if "gui-probe" in OS.get_cmdline_user_args():
		await _frames(25)
		await _button_click("整船查看")
		get_window().size = Vector2i(1920,1080)
		await _frames(10)
		for text in ["分组装配","整船查看","分组装配","撤回一步"]: await _button_click(text)
		var file := FileAccess.open(evidence.path_join("gui_probe.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks":checks,"events":event_log,"window":str(get_window().size),"root_transform":str(get_tree().root.get_final_transform())},"\t"))
		get_tree().quit()
		return
	if "sequence-baseline" in OS.get_cmdline_user_args():
		await _baseline_run()
		return
	await _frames(25)
	_check(mode=="assembly" and fixed_guide.visible,"cold entry ready with fixed guide")
	await _capture("01_cold_ready")
	var routes: Array[String] = ["auto","return_pending","skip_pending","inspect_then_direct","auto","return_finished","skip_pending","auto","overview_then_direct","return_pending","auto","skip_pending","auto"]
	for index in groups.size():
		var id: String = groups[index].id
		if index==7:
			var previous := get_window().size
			get_window().size = Vector2i(1920,1080)
			await _frames(10)
			event_log.append({"kind":"window_resize_api","from":str(previous),"to":str(get_window().size),"root_transform":str(get_tree().root.get_final_transform()),"note":"Window resize API only; assembly state is never assigned."})
		await _drag_group(id)
		_state("released_"+id)
		var route: String = routes[index]
		if route=="return_pending":
			await _button_click("返回整船")
			await _wait_assembly("explicit_return_"+id)
		elif route=="skip_pending":
			await _button_click("跳过镜头，继续装配")
			await _wait_assembly("explicit_skip_"+id)
		else:
			await _wait_installed(id)
			if route=="inspect_then_direct":
				var center := view.get_global_rect().get_center()
				await _mouse(center,true,MOUSE_BUTTON_RIGHT)
				await _mouse(center,false,MOUSE_BUTTON_RIGHT)
				_check(mode=="lesson" and not pending_id.length(),"inspection holds finished closeup before direct next-card press")
			elif route=="return_finished":
				await _button_click("返回整船")
				await _wait_assembly("finished_return_"+id)
			elif route=="overview_then_direct":
				await _button_click("整船查看")
				_check(mode=="overview","overview remains a view until next actual card press")
			else:
				await _wait_assembly("automatic_end_"+id)
		_check(id in placed,"group committed through route "+route+" / "+id)
		route_log.back()["completion_route"] = route
		route_log.back()["after_route"] = _input_state()
		await _capture("step_%02d_%s_%s"%[index+1,id,route])
	_check(placed.size()==13 and snapshot().complete,"continuous input completes all 13 groups")
	_check(completion_count==1,"initial full sequence reports completion once")
	await _capture("02_complete_13")
	await _button_click("撤回一步")
	_check(placed.size()==12 and guide_id=="rigging","actual undo restores final group and guide")
	await _drag_group("rigging")
	await _wait_installed("rigging")
	await _wait_assembly("automatic_end_after_undo_reinstall")
	_check(placed.size()==13 and completion_count==2,"last group reinstalls through mouse input")
	await _capture("03_reinstalled_13")
	await _button_click("重置装配")
	_check(placed.is_empty() and history.is_empty() and guide_id=="keel_center" and drag.enabled,"actual reset clears progress and restores first guide")
	await _button_click("单独观察所选接头")
	_check(mode=="joint" and joint!=null,"actual manual joint control enters source closeup")
	await _capture("04_manual_joint")
	await _button_click("返回整船")
	_check(mode=="assembly" and drag.enabled and placed.is_empty() and fixed_guide.visible,"manual joint return restores empty assembly and input")
	var center := view.get_global_rect().get_center()
	var previous_yaw: float = orbit.yaw
	await _mouse(center,true,MOUSE_BUTTON_RIGHT)
	await _move(center+Vector2(65,12),Vector2(65,12))
	await _mouse(center+Vector2(65,12),false,MOUSE_BUTTON_RIGHT)
	_check(not is_equal_approx(previous_yaw,orbit.yaw),"actual right drag still rotates after reset and closeup return")
	var previous_distance: float = orbit.distance
	await _mouse(center,true,MOUSE_BUTTON_WHEEL_UP)
	await _mouse(center,false,MOUSE_BUTTON_WHEEL_UP)
	_check(orbit.distance<previous_distance,"actual wheel still zooms after reset and closeup return")
	await _capture("05_reset_ready")
	var passed := true
	for item in checks: if not item.passed: passed = false
	var file := FileAccess.open(evidence.path_join("continuous.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"checks":checks,"routes":route_log,"states":sequence_states,"events":event_log,"method":"Godot mouse-event injection through actual GUI and input handlers, including tray wheel scrolling. No native CUA capability is available: not human-equivalent acceptance. Only window size is changed through Window API; no assembly internals or action methods are invoked."},"\t"))
	print("CONTINUOUS_SEQUENCE ",checks.size()," passed=",passed," events=",event_log.size())
	get_tree().quit(0 if passed else 1)
