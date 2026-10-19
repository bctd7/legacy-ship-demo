extends "res://content/quanzhou_boat/boat_play.gd"
## Headless production boat, Godot mouse events and real camera transitions.
var checks: Array = []
var trace: Array = []
var pointer := Vector2.ZERO
var mask := 0
var sampling := false
const OldCamera = preload("res://tests/interaction/boat_camera_evidence/before/content/quanzhou_boat/boat_camera.gd")
func _ready() -> void:
	super._ready()
	_run.call_deferred()
func _bake_thumbnails() -> void:
	pass # No GPU images are needed for headless navigation/continuity assertions.
func _process(delta: float) -> void:
	super._process(delta)
	if sampling: trace.append({"time_ms":Time.get_ticks_msec(),"mode":mode,"stage":lesson_stage,"focus":orbit.focus,"yaw":orbit.yaw,"pitch":orbit.pitch,"distance":orbit.distance})
func frames(count := 2) -> void:
	for i in count: await get_tree().process_frame
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	print("BOAT_CAMERA_PASS " if ok else "BOAT_CAMERA_FAIL ",label)
func button(point: Vector2, down: bool, which := MOUSE_BUTTON_RIGHT) -> void:
	var bit := 1 << (which-1)
	mask = mask | bit if down else mask & ~bit
	var e := InputEventMouseButton.new()
	e.position=get_tree().root.get_final_transform()*point;e.global_position=e.position
	e.button_index=which;e.pressed=down;e.button_mask=mask
	Input.parse_input_event(e);pointer=point
	await frames()
func move(point: Vector2) -> void:
	var tr := get_tree().root.get_final_transform()
	var e := InputEventMouseMotion.new()
	e.position=tr*point;e.global_position=e.position
	e.relative=tr*point-tr*pointer;e.button_mask=mask
	Input.parse_input_event(e);pointer=point
	await frames()
func gesture(point: Vector2, delta: Vector2, which := MOUSE_BUTTON_RIGHT) -> void:
	await button(point,true,which)
	await move(point+delta)
	await button(point+delta,false,which)
func same_pose(a: Dictionary,b: Dictionary) -> bool:
	return (a.focus as Vector3).is_equal_approx(b.focus) and absf(float(a.yaw)-float(b.yaw))<0.0001 and is_equal_approx(float(a.pitch),float(b.pitch)) and is_equal_approx(float(a.distance),float(b.distance))
func _run() -> void:
	await frames(4)
	var old := OldCamera.new(camera,_camera_settings(cameras.overview))
	old.focus=Vector3(-1.5,0.7,0);old.zoom_focus=Vector3(2,0.3,0);old.zoom_focus_enabled=true
	var old_start: Vector3=old.focus
	for i in 8:old.zoom(0.9)
	check(old.focus.distance_to(old_start)>3.0,"baseline reproduces >3m orbit-centre drift from eight zooms")
	reset_camera()
	set_mode("overview")
	var point: Vector2=view.global_position+view.size*Vector2(0.56,0.45)
	check(not _pointer_blocked(point+Vector2(PI/2.0/0.007,0)),"test drag is inside world and clear of UI")
	var home := _camera_snapshot()
	for i in 4:
		await gesture(point,Vector2(PI/2.0/0.007,0))
		var expected := float(home.yaw)-(i+1)*PI/2.0
		check(absf(orbit.yaw-expected)<0.0001,"mouse rotation reaches cardinal quarter %d without yaw clamp"%(i+1))
		var radial: Vector3 = (camera.position-orbit.focus).normalized()
		var wanted := Vector3(sin(expected)*cos(orbit.pitch),sin(orbit.pitch),cos(expected)*cos(orbit.pitch))
		check(radial.distance_to(wanted)<0.0001,"camera position follows quarter %d around same centre"%(i+1))
	check(camera.position.distance_to(Drag.vector(cameras.overview.focus)+Vector3(sin(float(home.yaw))*cos(float(home.pitch)),sin(float(home.pitch)),cos(float(home.yaw))*cos(float(home.pitch)))*float(home.distance))<0.001,"full 360 returns to initial world position")
	await gesture(point,Vector2(-200,0))
	check(orbit.yaw>float(home.yaw)-TAU,"horizontal rotation reverses freely after full turn")
	orbit.rotate_view(Vector2(0,-1e6));check(is_equal_approx(orbit.pitch,0.03),"boat lower pitch reaches near-horizontal without crossing ground")
	orbit.rotate_view(Vector2(0,1e6));check(is_equal_approx(orbit.pitch,1.48) and camera.position.is_finite(),"boat upper pitch reaches near-top view without pole singularity")
	reset_camera()
	for i in 24:await gesture(point,Vector2(120,0),MOUSE_BUTTON_MIDDLE)
	check(orbit.focus.distance_to(home.focus)>5.9 and orbit.focus.distance_to(home.focus)<=6.0001,"middle mouse can pan beyond old 2m bound up to boat 6m bound")
	orbit.zoom_focus=Vector3(2,0.3,0);orbit.zoom_focus_enabled=true
	var held_focus: Vector3=orbit.focus
	for i in 8:orbit.zoom(0.9)
	check(orbit.focus.is_equal_approx(held_focus),"zoom preserves manually chosen centre even with active connection target")
	orbit.zoom(1e6);check(is_equal_approx(orbit.distance,20.0),"boat zoom reaches new 20m far bound")
	orbit.zoom(1e-6);check(is_equal_approx(orbit.distance,0.28),"boat close zoom retains 0.28m bound")
	reset_camera()
	await gesture(point,Vector2(120,32),MOUSE_BUTTON_MIDDLE)
	for i in 5:await gesture(point,Vector2(200,0))
	orbit.zoom(1.2)
	var saved := _camera_snapshot()
	sampling=true
	_start_lesson("keel_bow")
	check(mode=="lesson" and not drag.camera_enabled,"real closeup begins with input temporarily gated")
	var deadline := Time.get_ticks_msec()+12000
	while mode=="lesson" and not drag.camera_enabled and Time.get_ticks_msec()<deadline:await frames(1)
	lesson_return_timer.stop()
	check(mode=="lesson" and drag.camera_enabled,"real approach completes and observation input resumes")
	check(orbit.focus.distance_to(lesson_focus)<0.001 and orbit.distance<float(saved.distance),"production tween smoothly reaches connection closeup")
	check(absf(angle_difference(float(saved.yaw),orbit.yaw))<0.0001 and is_equal_approx(orbit.pitch,float(saved.pitch)),"closeup retains user bearing beyond full revolution")
	_leave_lesson(false,true)
	deadline=Time.get_ticks_msec()+5000
	while mode=="lesson" and Time.get_ticks_msec()<deadline:await frames(1)
	sampling=false
	check(mode=="overview" and same_pose(_camera_snapshot(),saved) and drag.camera_enabled,"smooth return exactly restores user pan yaw pitch and distance")
	var max_focus_step := 0.0
	for i in range(1,trace.size()):max_focus_step=maxf(max_focus_step,(trace[i].focus as Vector3).distance_to(trace[i-1].focus))
	check(trace.size()>20 and max_focus_step<0.3,"sampled approach and return keep continuous focus increments")
	show_joint(0);check(is_equal_approx(orbit.pan_limit,1.0),"standalone boat joint gets independent expanded pan")
	leave_joint();check(same_pose(_camera_snapshot(),saved),"joint return preserves full user view")
	reset_camera();check(same_pose(_camera_snapshot(),home),"reset returns configured boat view after all navigation")
	check(placed.is_empty() and pending_id.is_empty(),"all camera checks leave assembly progress untouched")
	var failed := 0
	for row in checks:if not row.passed:failed+=1
	var report := {"checks":checks,"count":checks.size(),"failures":failed,"headless":true,"native_mouse":"not tested","method":"Godot Input.parse_input_event on production boat; real CPU geometry and production camera tweens; thumbnail rendering skipped; no user's window interaction","max_focus_step_m":max_focus_step,"trace":trace,"official_network_calls":0}
	var f:=FileAccess.open("res://tests/interaction/boat_camera_evidence/navigation.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"));f.close()
	print("BOAT_CAMERA_RESULT ",checks.size()," checks ",failed," failures")
	get_tree().quit(0 if failed==0 else 1)
