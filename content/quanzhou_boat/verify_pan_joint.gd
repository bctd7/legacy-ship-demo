extends "res://content/quanzhou_boat/verify_camera.gd"
## Focused correction of the navigation test's stale button label.

func _ready() -> void:
	super._ready()
	evidence = "res://content/quanzhou_boat/evidence/navigation"

func _run() -> void:
	var deadline := Time.get_ticks_msec()+15000
	while thumbnail_grab_maps.size()!=groups.size() and Time.get_ticks_msec()<deadline: await _frames(1)
	var home_focus: Vector3 = orbit.focus
	orbit.pan_view(Vector2(42,22),view.size)
	orbit.rotate_view(Vector2(12,-4))
	orbit.zoom(0.92)
	var before := _camera_snapshot()
	_check(orbit.focus.distance_to(home_focus)>0.01,"direct shared camera-action setup supplies nonzero pan")
	await _button_click("单独观察所选接头")
	_check(mode=="joint" and joint!=null,"actual current joint button loads the source model")
	await _capture("joint_open_pan_reset")
	await _button_click("返回整船")
	_check(mode=="assembly" and joint==null and _camera_snapshot()==before,"actual joint return restores complete pan/zoom/rotation snapshot")
	await _capture("joint_return_pan_restored")
	await _button_click("视角复位")
	_check(orbit.focus.is_equal_approx(home_focus),"actual view-reset button clears framing pan")
	var passed := true
	for row in checks: if not row.passed: passed = false
	var file := FileAccess.open(evidence.path_join("joint_result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"checks":checks,"events":event_log,"camera_before":before,"method":"One focused 640x360 15fps render after fixing the test button label. Pan setup uses direct camera action; actual joint-open/return/reset buttons use Godot GUI event injection. Not native mouse or middle-button mapping acceptance."},"\t"))
	print("PAN_JOINT checks=",checks.size()," passed=",passed)
	get_tree().quit(0 if passed else 1)
