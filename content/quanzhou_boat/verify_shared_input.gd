extends "res://content/quanzhou_boat/verify_camera_full.gd"
## Current common adapter, real GUI event injection, one serial low-load window.
var simulated_buttons := 0
var previous_pointer := Vector2.ZERO
var prelude_count := 0

func _ready() -> void:
	super._ready()
	evidence = "res://content/quanzhou_boat/evidence/shared_input"

func _mouse(point: Vector2, down: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var record := {"kind":"press" if down else "release","button":button,"logical":str(point),"before":_input_state(),"time_ms":Time.get_ticks_msec()}
	if button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		var mask := 1<<(button-1)
		if down: simulated_buttons |= mask
		else: simulated_buttons &= ~mask
	var event := InputEventMouseButton.new()
	event.position = get_tree().root.get_final_transform()*point
	event.global_position = event.position
	event.button_index = button
	event.pressed = down
	event.button_mask = simulated_buttons
	Input.parse_input_event(event)
	previous_pointer = point
	await _frames()
	record.after = _input_state()
	event_log.append(record)

func _move(point: Vector2, _relative := Vector2.ZERO) -> void:
	var record := {"kind":"move","logical":str(point),"before":_input_state(),"time_ms":Time.get_ticks_msec()}
	var transform := get_tree().root.get_final_transform()
	var event := InputEventMouseMotion.new()
	event.position = transform*point
	event.global_position = event.position
	event.relative = transform*point-transform*previous_pointer
	event.button_mask = simulated_buttons
	Input.parse_input_event(event)
	previous_pointer = point
	await _frames()
	record.after = _input_state()
	event_log.append(record)

func _input_state() -> Dictionary:
	var state := super._input_state()
	state["owner"] = drag.gestures.owner
	state["contact"] = drag.gestures.contact
	return state

func _escape_event() -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = down
		Input.parse_input_event(event)
		await _frames(1)
	event_log.append({"kind":"escape_key_injection","state":_input_state()})

func _blank_point() -> Vector2:
	for fraction in [Vector2(0.78,0.24),Vector2(0.72,0.35),Vector2(0.55,0.15)]:
		var point: Vector2 = view.global_position+view.size*fraction
		if not _pointer_blocked(point) and pointer_part_at(point).is_empty(): return point
	return view.get_global_rect().get_center()

func _run() -> void:
	var deadline := Time.get_ticks_msec()+15000
	while thumbnail_grab_maps.size()!=groups.size() and Time.get_ticks_msec()<deadline: await _frames(1)
	await _frames(3)
	_check(placed.is_empty() and groups.size()==28,"current input cold-start retains all 28 groups")
	var blank := _blank_point()
	var ui := step_card.global_position+Vector2(6,6)
	var card := _grab_start("keel_center",Vector2(0.38,0.5))
	var original := _camera_snapshot()
	await _mouse(blank,true)
	_check(drag.gestures.owner=="rotate" and not drag.held,"left blank press belongs to rotation")
	await _move(blank+Vector2(24,8))
	_check(not is_equal_approx(orbit.yaw,float(original.yaw)) and pending_id.is_empty(),"left blank motion rotates without installing")
	var paused := _camera_snapshot()
	await _move(card)
	_check(_camera_snapshot()==paused and drag.gestures.owner=="rotate" and not drag.held,"rotation pauses over tray without becoming a part gesture")
	await _mouse(card,true,MOUSE_BUTTON_RIGHT)
	await _mouse(card,false,MOUSE_BUTTON_RIGHT)
	_check(drag.gestures.owner=="rotate" and drag.gestures.contact=="mouse:1","second button and wrong release cannot steal left ownership")
	await _mouse(card,false)
	_check(drag.gestures.idle(),"matching left release ends rotation capture")
	paused = _camera_snapshot()
	await _mouse(ui,true)
	_check(drag.gestures.owner=="ui","visible panel owns its initial press")
	await _move(blank)
	await _mouse(blank,true,MOUSE_BUTTON_WHEEL_UP)
	await _mouse(blank,false,MOUSE_BUTTON_WHEEL_UP)
	_check(_camera_snapshot()==paused and not drag.held and drag.gestures.owner=="ui","UI press cannot become camera or part after entering the view")
	await _mouse(blank,false)
	await _mouse(ui,true,MOUSE_BUTTON_WHEEL_UP)
	await _mouse(ui,false,MOUSE_BUTTON_WHEEL_UP)
	_check(_camera_snapshot()==paused,"idle wheel over visible panel is blocked")
	await _mouse(blank,true,MOUSE_BUTTON_MIDDLE)
	_check(drag.gestures.owner=="pan","middle press owns pan")
	await _move(blank+Vector2(40,20))
	_check(not orbit.focus.is_equal_approx(paused.focus) and is_equal_approx(orbit.yaw,float(paused.yaw)) and is_equal_approx(orbit.distance,float(paused.distance)),"middle motion pans while retaining bearing and scale")
	paused = _camera_snapshot()
	await _move(ui)
	_check(_camera_snapshot()==paused and drag.gestures.owner=="pan","pan pauses over panel and retains ownership")
	await _mouse(ui,false,MOUSE_BUTTON_MIDDLE)
	await _mouse(blank,true,MOUSE_BUTTON_RIGHT)
	await _move(blank+Vector2(-12,5))
	await _mouse(blank+Vector2(-12,5),false,MOUSE_BUTTON_RIGHT)
	_check(not is_equal_approx(orbit.yaw,float(paused.yaw)),"right rotation remains available")
	for index in 14:
		await _mouse(blank,true,MOUSE_BUTTON_WHEEL_DOWN)
		await _mouse(blank,false,MOUSE_BUTTON_WHEEL_DOWN)
	_check(is_equal_approx(orbit.distance,12.0),"wheel can zoom farther to the configured twelve-metre bound")
	await _button_click("视角复位")
	_check(orbit.focus.is_equal_approx(Drag.vector(cameras.overview.focus)) and is_equal_approx(orbit.distance,float(cameras.overview.distance)),"shared reset restores model-configured view")
	blank = _blank_point()
	card = _grab_start("keel_center",Vector2(0.38,0.5))
	await _mouse(card,true)
	_check(drag.gestures.owner=="part" and drag.held and not preview_group.visible,"available card owns part drag without press flash")
	await _move(card+Vector2(4,0))
	_check(not drag.dragging and not preview_group.visible,"sub-threshold part movement stays hidden")
	original = _camera_snapshot()
	await _mouse(card,true,MOUSE_BUTTON_MIDDLE)
	await _mouse(card,false,MOUSE_BUTTON_MIDDLE)
	await _mouse(blank,true,MOUSE_BUTTON_WHEEL_UP)
	await _mouse(blank,false,MOUSE_BUTTON_WHEEL_UP)
	_check(drag.gestures.owner=="part" and drag.held and _camera_snapshot()==original,"held part keeps ownership and freezes middle/wheel camera changes")
	await _escape_event()
	_check(drag.gestures.idle() and not drag.held and not preview_group.visible and drag.world_grab==null,"Escape clears owner, held source and preview")
	await _mouse(blank,false)
	_check(placed.is_empty() and pending_id.is_empty(),"late release after Escape cannot install")
	await _mouse(card,true)
	await _move(blank)
	drag.notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	event_log.append({"kind":"simulated_focus_out_notification","note":"Notification delivered to this test node only; not an OS focus action.","state":_input_state()})
	_check(drag.gestures.idle() and not drag.held and not preview_group.visible,"focus-loss cleanup clears shared capture and preview")
	await _mouse(blank,false)
	_check(placed.is_empty() and pending_id.is_empty(),"late release after focus cleanup cannot install")
	await _mouse(card,true)
	await _move(ui)
	_check(drag.gestures.owner=="part" and drag.hover_slot_id.is_empty(),"part crossing UI retains ownership but loses valid target")
	await _mouse(ui,false)
	_check(pending_id.is_empty() and placed.is_empty() and drag.gestures.idle(),"part release on UI is rejected and capture clears")
	var hit: Dictionary = {}
	var surface_screen := Vector2.ZERO
	for mesh in _part_meshes("keel_center"):
		var faces := mesh.mesh.get_faces()
		for index in range(0,faces.size(),3):
			var surface: Vector3 = mesh.global_transform*((faces[index]+faces[index+1]+faces[index+2])/3.0)
			surface_screen = view.global_position+camera.unproject_position(surface)
			hit = pointer_part_at(surface_screen)
			if hit.get("source","")=="scene": break
		if hit.get("source","")=="scene": break
	_check(hit.get("source","")=="scene","find an actual visible operable source triangle")
	await _mouse(surface_screen,true)
	_check(drag.gestures.owner=="part" and drag.world_grab is Vector3 and preview_grab_point==drag.world_grab,"scene press captures actual surface grip and part ownership")
	await _move(surface_screen+Vector2(12,0))
	_check(drag.dragging and preview_group.visible and _camera_snapshot()==original,"scene part moves after threshold without rotating the camera")
	await _escape_event()
	await _mouse(surface_screen,false)
	await _button_click("－ 缩小")
	var farther: float = orbit.distance
	await _button_click("＋ 放大")
	_check(orbit.distance<farther,"existing zoom buttons still work with shared UI ownership")
	await _button_click("视角复位")
	blank = _blank_point()
	await _mouse(blank,true,MOUSE_BUTTON_MIDDLE)
	await _move(blank+Vector2(42,22))
	await _mouse(blank+Vector2(42,22),false,MOUSE_BUTTON_MIDDLE)
	await _mouse(blank,true,MOUSE_BUTTON_RIGHT)
	await _move(blank+Vector2(12,-4))
	await _mouse(blank+Vector2(12,-4),false,MOUSE_BUTTON_RIGHT)
	await _mouse(blank,true,MOUSE_BUTTON_WHEEL_UP)
	await _mouse(blank,false,MOUSE_BUTTON_WHEEL_UP)
	original = _camera_snapshot()
	await _button_click("单独观察所选接头")
	_check(mode=="joint" and joint!=null,"actual explicit joint button enters the source joint scene")
	await _button_click("返回整船")
	_check(mode=="assembly" and _camera_snapshot()==original,"joint return preserves pan, rotation and zoom from actual injected gestures")
	await _capture("00_shared_input_before_28")
	prelude_count = checks.size()
	var method := FileAccess.open(evidence.path_join("method.json"),FileAccess.WRITE)
	method.store_string(JSON.stringify({"prelude_checks":prelude_count,"method":"Current shared mouse_input_adapter/gesture_router/orbit_camera plus boat-only context/grip adaptation. One serial low-load render; actual Godot GUI event injection for pointer, camera, assembly, undo/reset and manual joint. Focus loss is a simulated node notification. Not native Windows mouse acceptance or target-machine performance measurement."},"\t"))
	method.close()
	await super._run()
