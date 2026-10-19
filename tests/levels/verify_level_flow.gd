extends SceneTree
const Flow = preload("res://levels/level_flow.gd")
const Catalog = preload("res://levels/level_catalog.gd")
const Mock = preload("res://levels/mock_stage.gd")
const Pending = preload("res://levels/pending_stage.gd")
const Bridge = preload("res://levels/bridge_stage_adapter.gd")
const DrawingStage = preload("res://levels/drawing_stage.gd")
const Generation = preload("res://levels/generation_handoff.gd")
const Failing = preload("res://tests/levels/failing_stage_fixture.gd")
var checks := 0
var failures: Array[String] = []
var host: Control
var flow: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("LEVEL_PASS: ", label)
	else:
		failures.append(label)
		push_error("LEVEL_FAILED: " + label)

func mock_factories() -> Dictionary:
	return {"bridge": func(): return Mock.new(), "pending": func(): return Mock.new(), "drawing": func(): return Mock.new()}

func run() -> void:
	root.size = Vector2i(1400, 900)
	host = Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	flow = Flow.new()
	root.add_child(flow)
	var config := Catalog.first_level()
	check(Catalog.validation_error(config).is_empty(), "first-level config validates")
	check(flow.start(config, host, mock_factories(), true).is_empty(), "mock flow starts without drawing or ship")
	check(not flow.can_advance() and not flow.progress().finished, "entry is incomplete")
	check(not flow.advance().is_empty() and flow.index == 0, "incomplete stage cannot advance")
	var first = flow.current_stage
	first.report("pending_integration")
	first.report("failed", {}, "deliberate test failure")
	check(not flow.can_advance(), "pending and failed events cannot advance")
	first.stage_result.emit("ship", {"schema": 1, "status": "completed", "payload": {}, "simulated": true})
	check(flow.results.is_empty(), "wrong-stage completion rejected")
	first.stage_result.emit("bridge", {"schema": 1, "status": "completed", "payload": "invalid", "simulated": true})
	check(flow.results.is_empty(), "malformed result rejected")
	first.stage_result.emit("bridge", {"schema": 1, "status": "completed", "payload": {}, "simulated": false})
	check(flow.results.is_empty(), "mixed real/mock completion rejected")
	var payload := {"texture_path": "mock://bridge", "nested": {"value": 1}}
	first.complete(payload)
	payload.nested.value = 99
	check(flow.can_advance() and flow.results.bridge.payload.nested.value == 1, "completion stores an isolated result")
	first.stage_result.emit("bridge", {"schema": 1, "status": "completed", "payload": {"replacement": true}, "simulated": true})
	check(flow.results.bridge.payload.has("texture_path") and flow.results.size() == 1, "duplicate completion is idempotent")
	check(flow.advance().is_empty() and not first.active and flow.index == 1, "advance exits prior stage and enters next")
	check(flow.current_stage.stage_context.results.bridge.payload.texture_path == "mock://bridge", "next stage receives prior results")
	flow.current_stage.stage_context.results.bridge.payload.nested.value = 22
	check(flow.results.bridge.payload.nested.value == 1, "stage context cannot mutate stored progress")
	first.stage_result.emit("ship", {"schema": 1, "status": "completed", "payload": {}, "simulated": true})
	check(not flow.can_advance(), "event from exited stage cannot complete current stage")
	flow.current_stage.complete({"texture_path": "mock://ship"})
	flow.advance()
	check(flow.current_stage.stage_context.results.size() == 2, "drawing receives bridge and ship results")
	check(not flow.progress().finished, "entering last stage does not finish level")
	flow.current_stage.complete({"texture_path": "mock://drawing"})
	check(flow.progress().finished and flow.progress().simulated and flow.results.size() == 3, "all mock stages finish with explicit simulated progress")
	flow.advance()
	check(flow.index == 2 and host.get_child_count() == 1, "advance at terminal stage is idempotent")
	var copy: Dictionary = flow.progress()
	copy.results.clear()
	check(flow.results.size() == 3, "progress snapshots are isolated")
	check(not flow.start(config, host, {}, false).is_empty() and flow.last_error.contains("bridge"), "missing factory names the component")
	check(flow.current_stage == null and flow.results.is_empty(), "failed start does not retain mock progress")
	check(not flow.start(config, host, {"bridge": func(): return Control.new()}, false).is_empty() and flow.last_error.contains("enter_stage"), "component interface failure is clear")
	var missing := config.duplicate(true)
	missing.stages = [config.stages[2].duplicate(true)]
	missing.stages[0].surface_script = "res://absent_surface.gd"
	check(not flow.start(missing, host, {"drawing": func(): return DrawingStage.new()}).is_empty() and flow.last_error.contains("absent_surface"), "missing drawing component reports its path")
	var ship_only := config.duplicate(true)
	ship_only.stages = [config.stages[1]]
	check(flow.start(ship_only, host, {"pending": func(): return Pending.new()}).is_empty(), "real ship placeholder enters")
	check(not flow.can_advance() and not flow.progress().finished and flow.results.is_empty(), "ship placeholder never fakes completion")
	var invalid := config.duplicate(true)
	invalid.stages[1].id = "bridge"
	check(not flow.start(invalid, host, mock_factories(), true).is_empty(), "duplicate stage ids reject")
	var bridge_only := config.duplicate(true)
	bridge_only.stages = [config.stages[0]]
	check(flow.start(bridge_only, host, {"bridge": func(): return Bridge.new()}).is_empty(), "accepted bridge loads through external wrapper")
	await process_frame
	check(not flow.can_advance(), "incomplete real bridge does not complete")
	var workshop = flow.current_stage.workshop
	var snapshot: Dictionary = workshop.session.snapshot()
	for step in workshop.data.steps:
		if step.action_kind == "install": snapshot.placements[step.slot.id] = workshop.data.slot_type_map[step.slot.id]
	snapshot.completed_actions = [workshop.data.withdraw_action_id]
	check(workshop.session.restore(snapshot).ok, "bridge restores a valid completed content snapshot")
	check(flow.can_advance() and flow.results.bridge.payload.content_snapshot.schema == 3 and not flow.progress().simulated, "bridge completion relays accepted session state")
	flow.stop()
	await process_frame
	await process_frame
	var drawing_only := config.duplicate(true)
	drawing_only.stages = [config.stages[2].duplicate(true)]
	check(not flow.start(drawing_only, host, {"drawing": func(): return DrawingStage.new()}).is_empty() and flow.last_error.contains("texture_path"), "unresolved art fails clearly instead of inventing bridge/ship assets")
	drawing_only.stages[0].materials = []
	check(flow.start(drawing_only, host, {"drawing": func(): return DrawingStage.new()}).is_empty(), "blank-paper drawing can be hosted independently")
	check(not flow.current_stage.export_to("res://absent_folder/drawing.png").is_empty() and not flow.can_advance(), "failed PNG export cannot complete stage")
	var out := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://level_result.png"
	check(flow.current_stage.export_to(out).is_empty() and flow.progress().finished, "successful PNG export supplies drawing result")
	check(flow.results.drawing.payload.texture_path == out, "drawing result preserves exported asset reference")
	var handoff := Generation.prepare(flow.results.drawing, "Wooden bridge and ship")
	check(handoff.ok and handoff.request.dispatch_status == "not_dispatched", "generation boundary prepares a descriptor without dispatch")
	var simulated: Dictionary = flow.results.drawing.duplicate(true)
	simulated.simulated = true
	check(not Generation.prepare(simulated, "test").ok, "generation boundary rejects simulated results")
	check(not flow.current_stage.export_to(out).is_empty(), "drawing result cannot be submitted twice")
	drawing_only.stages[0].materials = [config.stages[2].materials[0].duplicate(true)]
	drawing_only.stages[0].materials[0].texture_path = out
	check(flow.start(drawing_only, host, {"drawing": func(): return DrawingStage.new()}).is_empty(), "drawing config loads a supplied PNG file without import dependencies")
	var failing := Failing.new()
	var failed_config := {"id": "invalid_lifecycle", "stages": [{"id": "entry_failure", "component": "failure"}]}
	check(not flow.start(failed_config, host, {"failure": func(): return failing}).is_empty() and flow.results.is_empty(), "completion during failed enter is discarded atomically")
	failing.stage_result.emit("entry_failure", {"schema": 1, "status": "completed", "payload": {}, "simulated": false})
	check(flow.results.is_empty() and not flow.can_advance(), "exit and queued late completion after failed enter cannot advance")
	flow.stop()
	flow.queue_free()
	host.queue_free()
	await process_frame
	if OS.get_cmdline_user_args().size() > 1:
		var demo = load("res://levels/level_demo.tscn").instantiate()
		root.add_child(demo)
		for i in range(12): await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[1].get_base_dir().path_join("real_bridge_demo.png")) == OK, "capture real bridge inside independent level demo")
		demo._start(true)
		await process_frame
		await process_frame
		var toolbar: Control = demo.get_child(1).get_child(0)
		check(toolbar.get_global_rect().end.y <= demo.status.get_global_rect().position.y and demo.status.get_global_rect().end.y <= demo.host.get_global_rect().position.y, "demo toolbar, status and stage occupy separate rows")
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[1]) == OK, "capture independent level demo in mock mode")
		demo.flow.stop()
		demo.queue_free()
		await process_frame
	print("LEVEL_RESULT: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
