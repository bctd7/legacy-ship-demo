extends SceneTree
const Adapter = preload("res://interaction/mouse_input_adapter.gd")
const Router = preload("res://interaction/gesture_router.gd")
const CameraOps = preload("res://interaction/orbit_camera.gd")
var app
var checks := 0
var failures: Array[String] = []
var evidence := "user://mouse_operation_checks.json"
var _mask := 0
var _last := Vector2.ZERO
var requests: Array = []

func _initialize() -> void: call_deferred("run")
func frames(n: int = 2) -> void:
	for i in range(n): await process_frame
func check(value: bool, message: String) -> void:
	checks += 1
	if value: print("MOUSE_PASS: ", message)
	else: failures.append(message); push_error("MOUSE_FAILED: " + message)
func button(point: Vector2, which: int, down: bool) -> void:
	if which in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_RIGHT]:
		var bit := 1 << (which-1)
		_mask = _mask | bit if down else _mask & ~bit
	var event := InputEventMouseButton.new()
	event.position=root.get_final_transform()*point; event.global_position=event.position
	event.button_index=which;event.pressed=down;event.button_mask=_mask
	Input.parse_input_event(event)
	_last=point
	await frames()
func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position=root.get_final_transform()*point;event.global_position=event.position
	event.relative=root.get_final_transform().basis_xform(point-_last);event.button_mask=_mask
	Input.parse_input_event(event);_last=point
	await frames()
func escape() -> void:
	var event := InputEventKey.new();event.keycode=KEY_ESCAPE;event.pressed=true
	Input.parse_input_event(event);await frames()
func wait_animation() -> void:
	var until := Time.get_ticks_msec()+5000
	while app.session.is_busy() and Time.get_ticks_msec()<until: await frames()
	check(not app.session.is_busy(),"original assembly animation settles")
func blank() -> Vector2:
	var rect: Rect2=app.view.get_global_rect()
	for x in [0.9,0.8,0.7,0.5]:
		for y in [0.15,0.85,0.5]:
			var point:=rect.position+rect.size*Vector2(x,y)
			if app.ui.world_input_blocked(point): continue
			var local:=point-rect.position
			if app.presenter.pick(app.camera.project_ray_origin(local),app.camera.project_ray_normal(local)).is_empty():return point
	return rect.get_center()
func operable_point() -> Vector2:
	# Pick an actually visible, eligible surface rather than assuming its center is unoccluded.
	for id in app.data.parts:
		var mesh:MeshInstance3D=app.presenter.meshes[id]
		if not mesh.is_visible_in_tree():continue
		var box:AABB=mesh.get_aabb()
		for corner in range(9):
			var local:Vector3=box.get_center() if corner==8 else box.get_center().lerp(box.get_endpoint(corner),0.8)
			var point:Vector2=app.view.get_global_rect().position+app.camera.unproject_position(mesh.to_global(local))
			if not app.view.get_global_rect().has_point(point) or app.ui.world_input_blocked(point):continue
			var screen:Vector2=point-app.view.get_global_rect().position
			var picked:String=app.presenter.pick(app.camera.project_ray_origin(screen),app.camera.project_ray_normal(screen))
			var operation:String=app._resolve_pick(picked)
			if not operation.is_empty() and app.session.availability(operation).allowed:return point
	return Vector2(INF,INF)
func verify_commands() -> void:
	var adapter:=Adapter.new()
	for which in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		var e:=InputEventMouseButton.new();e.button_index=which;e.pressed=true;e.position=Vector2(20,40)
		var command:Dictionary=adapter.map_event(e)
		check(command.phase=="begin" and command.contact=="mouse:%d"%which and command.position==Vector2(20,40),"mouse adapter translates button "+str(which))
	var touch:=InputEventScreenTouch.new();touch.pressed=true
	check(adapter.map_event(touch).is_empty(),"mouse adapter does not pretend to implement touch")
	var router:=Router.new()
	check(router.begin("test:1","primary",{"part_hit":true,"part_operable":true,"inside_world":true,"camera_enabled":true})=="part","part hit wins over camera action")
	check(router.begin("test:2","pan",{"inside_world":true,"camera_enabled":true}).is_empty() and router.owner=="part","second contact cannot steal captured part gesture")
	check(router.release("test:2").is_empty() and router.owner=="part","wrong release cannot unlock gesture")
	check(router.release("test:1")=="part" and router.idle(),"matching release unlocks gesture")
	check(router.begin("other:touch","primary",{"blocked":true,"part_hit":true,"part_operable":true})=="ui","UI blocking has priority independent of device")
	router.cancel()
	check(router.idle(),"shared cancellation clears owner and contact")
	var another_camera:=Camera3D.new();root.add_child(another_camera)
	var operations:=CameraOps.new(another_camera,{"focus":Vector3(2,0.5,1),"distance":4.0,"distance_limits":Vector2(2,6),"pan_limit":0.4})
	check(operations.focus.is_equal_approx(Vector3(2,0.5,1)) and operations.distance==4.0,"camera operations accept another model's center and scale")
	operations.pan_view(Vector2(10000,10000),Vector2(1000,600));operations.zoom(1000);operations.reset_view()
	check(operations.focus.is_equal_approx(Vector3(2,0.5,1)) and operations.distance==4.0,"reset restores per-model camera settings")
	another_camera.free()

func run() -> void:
	if not OS.get_cmdline_user_args().is_empty(): evidence=OS.get_cmdline_user_args()[0]
	verify_commands()
	root.size=Vector2i(1400,900)
	app=load("res://scenes/workshop.tscn").instantiate();root.add_child(app)
	await frames(10)
	app.presenter.duration_scale=0.04
	app.interaction.install_requested.connect(func(request): requests.append(request.duplicate(true)))
	var home_focus:Vector3=app.orbit.focus
	var home_yaw:float=app.orbit.yaw
	var home_pitch:float=app.orbit.pitch
	var home_distance:float=app.orbit.distance
	var p:=blank()
	await button(p,MOUSE_BUTTON_LEFT,true);await move(p+Vector2(35,15))
	check(app.interaction.gestures.owner=="rotate" and not app.interaction.held and not is_equal_approx(app.orbit.yaw,home_yaw),"blank left drag rotates immediately without part drag")
	app._choose(1)
	check(app.interaction.gestures.owner=="rotate","selection refresh cannot cancel captured camera gesture")
	app._choose(0)
	await button(p,MOUSE_BUTTON_RIGHT,true);await button(p,MOUSE_BUTTON_RIGHT,false)
	check(app.interaction.gestures.owner=="rotate","secondary press/release cannot end left rotation")
	var locked_yaw:float=app.orbit.yaw
	await move(app.tray.get_global_rect().get_center())
	check(app.interaction.gestures.owner=="rotate" and app.interaction.drag_source.is_empty() and is_equal_approx(app.orbit.yaw,locked_yaw),"camera pauses outside 3D region while keeping rotation ownership")
	await button(p,MOUSE_BUTTON_LEFT,false)
	check(app.interaction.gestures.idle() and requests.is_empty(),"rotation release clears ownership and never installs")
	app.orbit.reset_view();p=blank()
	await button(p,MOUSE_BUTTON_MIDDLE,true);await move(p+Vector2(26,-18))
	check(app.interaction.gestures.owner=="pan" and app.orbit.focus.distance_to(home_focus)>0 and is_equal_approx(app.orbit.yaw,home_yaw),"middle drag pans without rotation")
	var pan_distance:float=app.orbit.distance
	await button(p,MOUSE_BUTTON_WHEEL_UP,true)
	check(is_equal_approx(app.orbit.distance,pan_distance),"wheel cannot zoom during captured pan")
	await button(p,MOUSE_BUTTON_LEFT,true);await button(p,MOUSE_BUTTON_LEFT,false)
	check(app.interaction.gestures.owner=="pan","left button cannot steal middle pan")
	await button(p,MOUSE_BUTTON_MIDDLE,false)
	app.ui.view_reset_requested.emit();await frames()
	check(app.orbit.focus.is_equal_approx(home_focus) and is_equal_approx(app.orbit.distance,home_distance) and is_equal_approx(app.orbit.yaw,home_yaw),"existing UI reset restores pan, zoom and rotation")
	p=blank();await button(p,MOUSE_BUTTON_RIGHT,true);await move(p+Vector2(20,8));await button(p,MOUSE_BUTTON_RIGHT,false)
	check(not is_equal_approx(app.orbit.yaw,home_yaw),"original right drag still rotates")
	app.orbit.reset_view();p=blank();await button(p,MOUSE_BUTTON_WHEEL_UP,true)
	check(app.orbit.distance<home_distance,"wheel zooms within 3D region")
	app.orbit.reset_view()
	var ui_point:Vector2=app.ui.step_card.get_global_rect().get_center()
	for which in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		await button(ui_point,which,true);await move(blank()+Vector2(30,10))
		check(app.interaction.gestures.owner=="ui" and app.orbit.focus.is_equal_approx(home_focus) and is_equal_approx(app.orbit.yaw,home_yaw),"UI press never leaks into world for button "+str(which))
		await button(blank(),which,false)
	await button(ui_point,MOUSE_BUTTON_WHEEL_UP,true)
	await button(Vector2(650,30),MOUSE_BUTTON_WHEEL_DOWN,true)
	check(is_equal_approx(app.orbit.distance,home_distance),"wheel on overlay or outside 3D region does not zoom")
	app.ui.hint_panel.show();await frames()
	var hint:Vector2=app.ui.hint_panel.get_global_rect().get_center()
	await button(hint,MOUSE_BUTTON_RIGHT,true);await move(blank());await button(blank(),MOUSE_BUTTON_RIGHT,false)
	check(is_equal_approx(app.orbit.yaw,home_yaw),"visible help panel blocks camera input")
	app.ui.hint_panel.hide()
	var from:Vector2=app.tray.get_global_rect().get_center()
	var target:Vector2=app.view.get_global_rect().position+app.camera.unproject_position(app.Rules.vector(app.data.steps[0].slot.anchor_m))
	await button(from,MOUSE_BUTTON_LEFT,true);await move(target)
	check(app.interaction.gestures.owner=="part" and app.interaction.held and app.interaction.dragging,"tray drag locks original part operation")
	var before_pan:Vector3=app.orbit.focus
	await button(target,MOUSE_BUTTON_MIDDLE,true);await button(target,MOUSE_BUTTON_MIDDLE,false);await button(target,MOUSE_BUTTON_WHEEL_DOWN,true)
	check(app.interaction.gestures.owner=="part" and app.orbit.focus.is_equal_approx(before_pan) and is_equal_approx(app.orbit.distance,home_distance),"part capture prevents secondary camera operations")
	await button(target,MOUSE_BUTTON_LEFT,false);await wait_animation()
	check(app.session.placements.get("slot_01")=="beam_end" and requests.size()==1,"original drag contract commits exactly one legal placement")
	var hit_point:=operable_point()
	check(hit_point.is_finite(),"an unoccluded operable model surface can be found")
	if hit_point.is_finite():await button(hit_point,MOUSE_BUTTON_LEFT,true)
	check(app.interaction.gestures.owner=="part" and app.interaction.held and not app.interaction.rotating,"operable 3D part hit has priority over left camera rotation")
	app.interaction.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(app.interaction.gestures.idle() and app.interaction.drag_source.is_empty() and not app.interaction.held and not app.presenter.preview.visible,"focus loss clears ownership and part preview")
	await button(target,MOUSE_BUTTON_LEFT,false)
	check(requests.size()==1,"late release after focus loss submits nothing")
	p=blank();await button(p,MOUSE_BUTTON_MIDDLE,true);await move(p+Vector2(20,10));await escape()
	check(app.interaction.gestures.idle(),"Escape clears camera gesture ownership")
	await button(p,MOUSE_BUTTON_MIDDLE,false)
	app.ui.reset_dialog.show();await frames()
	p=blank();await button(p,MOUSE_BUTTON_LEFT,true);await move(p+Vector2(25,10));await button(p,MOUSE_BUTTON_LEFT,false)
	check(not app.interaction.camera_enabled and not app.interaction.held,"modal dialog disables world gestures")
	app.ui.reset_dialog.hide();await frames()
	app.orbit.pan_view(Vector2(1e6,-1e6),app.view.size)
	check(app.orbit.focus.distance_to(home_focus)<=app.orbit.pan_limit+0.00001,"pan has a bounded model-scale offset")
	app.orbit.zoom(1e-12);check(is_equal_approx(app.orbit.distance,0.38),"zoom lower bound preserved")
	app.orbit.zoom(1e12);check(is_equal_approx(app.orbit.distance,1.65),"zoom upper bound preserved")
	app.orbit.rotate_view(Vector2(0,1e6));check(is_equal_approx(app.orbit.pitch,1.25),"rotation pitch upper bound preserved")
	app.orbit.rotate_view(Vector2(0,-1e6));check(is_equal_approx(app.orbit.pitch,0.12),"rotation pitch lower bound preserved")
	app.orbit.reset_view()
	check(app.orbit.focus.is_equal_approx(home_focus) and is_equal_approx(app.orbit.pitch,home_pitch) and app.camera.position.is_finite(),"reset returns finite original camera state")
	check(app.session.placements.size()==1 and app.session.completed_actions.is_empty(),"all view gestures leave assembly progress unchanged")
	var report:Dictionary={"checks":checks,"failures":failures,"headless":DisplayServer.get_name()=="headless","input":"Godot event injection + shared command unit checks","native_mouse":"not tested","touch":"not implemented","official_calls":0,"model_requests":requests.size()}
	var file:=FileAccess.open(evidence,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MOUSE_OPERATION_RESULT: %d checks %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
