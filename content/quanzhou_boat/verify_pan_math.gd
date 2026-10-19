extends "res://content/quanzhou_boat/boat_play.gd"
## Small headless camera-action check, separate from mouse-input acceptance.
func _ready() -> void:
	super._ready()
	_run.call_deferred()

func _run() -> void:
	var checks: Array = []
	var initial := _camera_snapshot()
	var point: Vector3 = orbit.focus
	var before := camera.unproject_position(point)
	orbit.pan_view(Vector2(80,40),view.size)
	var after := camera.unproject_position(point)
	checks.append({"name":"shared pan moves screen framing and focus together","passed":after.distance_to(before+Vector2(80,40))<0.05 and not orbit.focus.is_equal_approx(point)})
	var ray_origin := camera.project_ray_origin(after)
	var ray_direction := camera.project_ray_normal(after)
	var hit = Plane(camera.global_basis.z,camera.global_basis.z.dot(point)).intersects_ray(ray_origin,ray_direction)
	checks.append({"name":"pan projection and picking rays remain inverse","passed":hit!=null and hit.distance_to(point)<0.00001})
	var adjusted := _camera_snapshot()
	orbit.pan_view(Vector2(100000,-100000),view.size)
	var offset: Vector3 = orbit.focus-point
	checks.append({"name":"shared pan respects model metre bounds","passed":offset.length()<=orbit.pan_limit+0.00001 and offset.y>=-orbit.pan_limit/3.0-0.00001 and offset.y<=orbit.pan_limit*2.0/3.0+0.00001})
	orbit.zoom(1000.0)
	checks.append({"name":"farther zoom remains bounded at twelve metres","passed":is_equal_approx(orbit.distance,12.0)})
	orbit.zoom(0.0001)
	checks.append({"name":"close zoom lower bound retained","passed":is_equal_approx(orbit.distance,0.28)})
	_blend_camera(1.0,_camera_snapshot(),adjusted)
	checks.append({"name":"camera snapshot blending restores shared focus pan and pose","passed":orbit.focus.is_equal_approx(adjusted.focus) and is_equal_approx(orbit.distance,float(adjusted.distance))})
	reset_camera()
	checks.append({"name":"shared model-configured view reset clears pan","passed":orbit.focus.is_equal_approx(initial.focus) and is_equal_approx(orbit.distance,float(initial.distance))})
	var card_point: Vector2 = cards.keel_center.get_global_rect().get_center()
	var card_hit := pointer_part_at(card_point)
	checks.append({"name":"part lookup reports the available card through boat callback","passed":card_hit.get("id","")=="keel_center" and bool(card_hit.get("operable",false))})
	var surface_point := Vector3.ZERO
	var surface_screen := Vector2.ZERO
	var surface_hit: Dictionary = {}
	for mesh in _part_meshes("keel_center"):
		var faces := mesh.mesh.get_faces()
		for index in range(0,faces.size(),3):
			surface_point = mesh.global_transform*((faces[index]+faces[index+1]+faces[index+2])/3.0)
			surface_screen = view.global_position+camera.unproject_position(surface_point)
			surface_hit = pointer_part_at(surface_screen)
			if surface_hit.get("source","")=="scene": break
		if surface_hit.get("source","")=="scene": break
	checks.append({"name":"boat scene callback resolves an actual source triangle and world grip","passed":surface_hit.get("id","")=="keel_center" and surface_hit.get("grab_world") is Vector3})
	var grip: Vector3 = surface_hit.get("grab_world",Vector3.ZERO)
	var began: bool = drag.handle_pointer({"phase":"begin","intent":"primary","contact":"unit:primary","position":surface_screen})
	checks.append({"name":"part action captures existing placement contract without displaying or installing","passed":began and drag.held and drag.drag_source.get("item_id","")=="keel_center" and drag.world_grab==grip and preview_grab_point==grip and not preview_group.visible and pending_id.is_empty()})
	drag.handle_pointer({"phase":"move","position":surface_screen+Vector2(4,0),"delta":Vector2(4,0)})
	checks.append({"name":"part action retains existing no-flash drag threshold","passed":not drag.dragging and not preview_group.visible})
	var blocked_point := step_card.get_global_rect().get_center()
	drag.handle_pointer({"phase":"move","position":blocked_point,"delta":Vector2.ZERO})
	checks.append({"name":"boat action rejects a held object's release over UI","passed":drag.dragging and drag.hover_slot_id.is_empty()})
	drag.handle_pointer({"phase":"end","contact":"unit:primary","position":blocked_point})
	checks.append({"name":"invalid action release clears capture and does not install","passed":not drag.held and drag.world_grab==null and drag.drag_source.is_empty() and pending_id.is_empty() and placed.is_empty()})
	var passed := true
	for row in checks:
		print("PASS " if row.passed else "FAIL ",row.name)
		if not row.passed: passed = false
	var f := FileAccess.open("res://content/quanzhou_boat/evidence/shared_input/action_math.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":passed,"checks":checks,"screen_delta":str(after-before),"method":"Headless camera/part action and geometry-callback checks only; not mouse mapping, GUI gestures or native input acceptance."},"\t"))
	get_tree().quit(0 if passed else 1)
