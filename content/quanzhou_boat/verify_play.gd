extends "res://content/quanzhou_boat/boat_play.gd"
var checks: Array = []
var evidence := "res://content/quanzhou_boat/evidence"
var completion_count := 0
var captured_drag := false

func _ready() -> void:
	super._ready()
	completed.connect(func(_state: Dictionary): completion_count += 1)
	_run.call_deferred()

func _check(value: bool, name: String) -> void:
	checks.append({"name":name,"passed":value})
	print("PASS " if value else "FAIL ",name)

func _frames(count := 3) -> void:
	for i in count: await get_tree().process_frame

func _mouse(point: Vector2, down: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.position = get_tree().root.get_final_transform() * point
	e.global_position = e.position
	e.button_index = button
	e.pressed = down
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if down and button == MOUSE_BUTTON_LEFT else 0
	Input.parse_input_event(e)
	await _frames()

func _move(point: Vector2, relative := Vector2.ZERO) -> void:
	var e := InputEventMouseMotion.new()
	e.position = get_tree().root.get_final_transform() * point
	e.global_position = e.position
	e.relative = relative
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e)
	await _frames()

func _drop(id: String, legal := true) -> void:
	panel.get_parent().ensure_control_visible(cards[id])
	await _frames()
	var start: Vector2 = cards[id].get_global_rect().get_center()
	var end: Vector2 = view.global_position + camera.unproject_position(Drag.vector(slots[id].anchor_m)) if legal else view.global_position+Vector2(25,25)
	await _mouse(start,true)
	await _move(start.lerp(end,0.5))
	await _move(end)
	if legal and id == "keel_center" and not captured_drag:
		_check(drag.dragging and drag.hover_slot_id == id and placed.is_empty(),"valid hover previews without installing before release")
		await _capture("02_valid_drag")
		captured_drag = true
	await _mouse(end,false)

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(evidence.path_join(name+".png"))
	_check(error == OK,"capture "+name)

func _run() -> void:
	await _frames(20)
	_check(_meshes(boat).size()==1286,"real full boat has 1286 meshes")
	var total := 0
	for nodes in group_nodes.values(): total += nodes.size()
	_check(total==59,"59 authored groups mapped exactly once")
	await _capture("01_overview")
	var old_yaw: float = orbit.yaw
	var center := view.get_global_rect().get_center()
	await _mouse(center,true,MOUSE_BUTTON_RIGHT)
	await _move(center+Vector2(80,25),Vector2(80,25))
	await _mouse(center+Vector2(80,25),false,MOUSE_BUTTON_RIGHT)
	_check(orbit.yaw != old_yaw,"right pointer drag rotates camera")
	var old_distance: float = orbit.distance
	await _mouse(center,true,MOUSE_BUTTON_WHEEL_UP)
	_check(orbit.distance < old_distance and orbit.distance > 2,"wheel zoom respects boat scale")
	reset_camera()
	set_mode("assembly")
	await _frames()
	var card_center: Vector2 = cards.keel_center.get_global_rect().get_center()
	await _mouse(card_center,true)
	await _mouse(card_center,false)
	_check(placed.is_empty(),"card click only selects, never installs")
	await _drop("keel_center",false)
	_check(placed.is_empty(),"outside release rejects placement")
	await _drop("masts")
	_check(placed.is_empty(),"dependency-locked card cannot install")
	await _drop("keel_center")
	_check(placed==["keel_center"],"real pointer drag into radius installs one group")
	await _capture("02_first_drop")
	undo()
	_check(placed.is_empty(),"undo removes last group")
	await _drop("keel_center")
	var before := snapshot()
	var old_position := camera.position
	show_joint(3)
	await _frames(10)
	_check(disclosure.text.contains("非考古"),"mast extension disclosure is visible")
	_check(moving.position != moving_home,"joint opens separated")
	joint_slider.value = 0
	_check(moving.position.is_equal_approx(moving_home),"slider joins real source meshes")
	joint_slider.value = 0.8
	await _capture("03_mast_joint")
	leave_joint()
	await _frames()
	_check(snapshot()==before and camera.position.is_equal_approx(old_position),"joint return preserves progress and camera")
	for index in [0,1,2,4]:
		show_joint(index)
		await _frames(5)
		_check(_meshes(joint).size()==2,"real two-part joint "+str(index))
		if index==4: await _capture("04_deck_joint")
		leave_joint()
	_check(completion_count==0,"partial assembly does not report completion")
	for g in groups:
		if g.id not in placed:
			await _drop(g.id)
			_check(g.id in placed,"pointer placement "+str(g.id))
	_check(completion_count==1 and snapshot().complete,"complete only after all 13 legal pointer placements")
	await _capture("05_complete")
	reset_assembly()
	_check(placed.is_empty() and history.is_empty(),"reset clears progress and withdrawal history")
	await _capture("06_reset")
	set_mode("overview")
	await _frames(180)
	var sample: Array[float] = []
	for i in 120:
		var now := Time.get_ticks_usec()
		await get_tree().process_frame
		sample.append((Time.get_ticks_usec()-now)/1000.0)
	sample.sort()
	var perf := {"resolution":str(get_viewport().size),"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"os":OS.get_name(),"processor":OS.get_processor_name(),"logical_processors":OS.get_processor_count(),"memory":OS.get_memory_info(),"frames":120,"median_frame_ms":sample[60],"p95_frame_ms":sample[114],"note":"Current development machine only; full model, two directional lights, no shadows; no target-machine FPS claim."}
	var adapter: Control = load("res://content/quanzhou_boat/stage_adapter.gd").new()
	add_child(adapter)
	_check(adapter.enter_stage({"id":"boat_contract"},{"mock_mode":false}).is_empty(),"existing stage lifecycle enters without shared changes")
	adapter.exit_stage()
	_check(not adapter.play.drag.enabled and not adapter.play.drag.is_processing_input(),"stage exit stops input")
	adapter.queue_free()
	var passed := true
	for c in checks: if not c.passed: passed = false
	var file := FileAccess.open(evidence.path_join("checks.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"checks":checks,"development_machine":perf},"\t"))
	print("BOAT_CHECKS ",checks.size()," passed=",passed)
	get_tree().quit(0 if passed else 1)
