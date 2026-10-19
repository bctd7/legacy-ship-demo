extends SceneTree
const Registry = preload("res://levels/model_registry.gd")
const Bridge = preload("res://levels/bridge_stage_adapter.gd")
const Boat = preload("res://content/quanzhou_boat/stage_adapter.gd")
const Fixture = preload("res://tests/levels/auto_nav_fixture.gd")
var checks: Array = []
var failures: Array = []
var app: Control
var out := "user://auto_navigation"
func _initialize() -> void: call_deferred("run")
func frames(n: int = 2) -> void:
	for i in n: await process_frame
func check(ok: bool, label: String) -> void:
	checks.append({"passed":ok,"label":label})
	if not ok: failures.append(label); push_error("AUTO_FAIL: " + label)
	else: print("AUTO_PASS: ",label)
func options() -> Dictionary:
	var models := Registry.defaults()
	for id in models: models[id].adapter_script = "res://tests/levels/auto_nav_fixture.gd"; models[id].erase("canvas_size")
	return {"models":models}
func run() -> void:
	if not OS.get_cmdline_user_args().is_empty(): out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	root.size = Vector2i(1400,900)
	app = load("res://levels/integrated_demo.tscn").instantiate()
	app.level_options = options()
	root.add_child(app)
	await frames(3)
	app.set_process(false)
	check(app.flow.config.auto_advance.enabled and app.flow.config.auto_advance.delay_seconds == 2.0,"default auto navigation is enabled with two-second dwell")
	var first = app.flow.current_stage.adapter
	first.complete_model(false)
	app._process(20.0)
	check(app.flow.index == 0 and not app.flow.can_advance(),"completion before visual cleanup cannot advance even after long wait")
	first.visual_ready = true
	app._process(1.0)
	check(app.flow.index == 0 and app.status.text.contains("鲁班桥已完成") and app.status.text.contains("继续搭建古船"),"completed stage displays configured completion and next-stage notice")
	check(not app.next_button.visible,"automatic route does not require a next button")
	first.complete = false
	app._process(0.1)
	check(app.flow.results.is_empty() and app._auto_elapsed == 0,"undo revokes completion and cancels pending navigation")
	app._process(5.0)
	check(app.flow.index == 0,"revoked completion never advances on old elapsed time")
	first.complete_model()
	app._process(1.5)
	app.restart()
	app._process(5.0)
	check(app.flow.index == 0 and app.flow.results.is_empty(),"restart cancels old dwell and preserves fresh incomplete stage")
	first = app.flow.current_stage.adapter
	first.complete_model()
	first.stage_result.emit("assembly",{"schema":1,"status":"completed","payload":{},"simulated":false})
	app._process(1.9)
	check(app.flow.index == 0 and app.flow.results.size() == 1,"duplicate completion remains idempotent and no early transition")
	app._process(0.2)
	check(app.flow.index == 1 and app._advancing,"one dwell enters exactly the configured next model")
	var second = app.flow.current_stage.adapter
	second.complete_model(false)
	app.advance_stage()
	check(app.flow.index == 1,"reentrant navigation cannot cross a second stage")
	await frames(2)
	app._process(20.0)
	check(app.flow.index == 1,"second model waits for camera/cleanup readiness")
	second.visual_ready = true
	app._process(1.9)
	check(app.status.text.contains("古船已完成") and app.status.text.contains("进入绘画") and app.flow.index == 1,"second configured completion notice appears before drawing")
	app._process(0.2)
	check(app.flow.index == 2 and app.flow.current_stage.has_method("export_to"),"second ready dwell enters actual drawing component")
	await frames(2)
	var document = app.flow.current_stage.surface.document
	for item in document.materials: document.place_material(item.id,item.target_position)
	check(app.flow.current_stage.export_to(out.path_join("drawing.png")).is_empty(),"drawing can complete after automatic navigation")
	app._process(99.0)
	check(app.flow.progress().finished and app.optional_window == null,"terminal drawing does not auto-open or submit generation")
	app.restart()
	app.set_process(true)
	var start := Time.get_ticks_msec()
	app.flow.current_stage.adapter.complete_model()
	await create_timer(1.0).timeout
	check(app.flow.index == 0,"real process time keeps completed model visible for first second")
	while app.flow.index == 0 and Time.get_ticks_msec()-start < 3500: await frames()
	check(app.flow.index == 1 and Time.get_ticks_msec()-start >= 1800,"real process automatically advances after approximately two seconds")
	app.flow.stop()
	app._process(10.0)
	check(app.flow.index == -1 and app._auto_elapsed == 0,"stage exit cancels pending navigation")
	app.queue_free()
	await frames()
	var bridge := Bridge.new()
	root.add_child(bridge)
	check(bridge.enter_stage({"id":"bridge_probe","scene":"res://scenes/workshop.tscn"},{"mock_mode":false}).is_empty(),"real bridge adapter enters without changing user process")
	var saved: Dictionary = bridge.workshop.session.snapshot()
	for step in bridge.workshop.data.steps:
		if step.action_kind == "install": saved.placements[step.slot.id] = bridge.workshop.data.slot_type_map[step.slot.id]
	bridge.workshop.session.restore(saved)
	check(not bridge.is_ready_to_leave(),"twenty installed bridge parts without withdrawal are not navigation-ready")
	saved.completed_actions = [bridge.workshop.data.withdraw_action_id]
	bridge.workshop.session.restore(saved)
	check(bridge.is_ready_to_leave(),"real bridge navigation waits for accepted full cleanup completion")
	bridge.exit_stage(); bridge.queue_free()
	await frames()
	var boat := Boat.new()
	var play := Fixture.new()
	boat.active = true; boat.play = play; play.complete = true
	check(boat.is_stage_complete() and not boat.is_ready_to_leave(),"real boat adapter separates completed snapshot from final camera return")
	play.mode = "assembly"; play.lesson_stage = ""
	check(boat.is_ready_to_leave(),"real boat adapter becomes ready only after normal assembly view is restored")
	play.pending_id = "pending"
	check(not boat.is_ready_to_leave(),"boat pending connection blocks readiness")
	boat.free(); play.free()
	app = load("res://levels/integrated_demo.tscn").instantiate()
	app.level_options = options()
	app._resume_file = "C:/Users/USER/Documents/Codex/2026-10-16/task-7/user_completed_bridge_resume.json"
	root.add_child(app)
	await frames(3)
	check(app.flow.index == 1 and app.flow.results.has("assembly"),"verified user completion receipt resumes at ship without rebuilding bridge")
	check(app.flow.current_stage.stage_context.results.assembly.payload.drawing_asset.texture_path.ends_with("bridge_illustration_v2.png"),"resume preserves completed bridge drawing material")
	app.restart()
	check(app.flow.index == 0 and app.flow.results.is_empty(),"explicit restart consumes resume once and starts a clean level")
	app.flow.stop(); app.queue_free()
	await frames()
	var report := {"checks":checks,"failures":failures,"count":checks.size(),"native_mouse":false,"generation_requests":0,"user_process_touched":false,"methods":"contract fixtures, real bridge accepted completion snapshots, real boat adapter readiness fixture, actual process-time dwell, completed-prefix resume"}
	var file := FileAccess.open(out.path_join("validation.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("AUTO_RESULT ",checks.size()," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
