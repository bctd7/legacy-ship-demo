extends SceneTree
## Run only after the pinned final boat package is imported. No native mouse acceptance claim.
## Bridge uses valid snapshot restore; boat uses public actions and explicit skip_lesson.
const Catalog = preload("res://levels/level_catalog.gd")
const Generation = preload("res://levels/generation_stage.gd")
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var routes: Array[Dictionary] = []
var out := "user://real_boat_level"
var app: Control
var actual_boat_loaded := false
var started := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> bool:
	checks.append({"label": label, "passed": ok})
	if ok: print("REAL_BOAT_PASS: ", label)
	else: failures.append(label); push_error("REAL_BOAT_FAIL: " + label)
	return ok

func frames(count: int = 2) -> void:
	for i in range(count): await process_frame

func wait_until(predicate: Callable, seconds: float = 8.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await frames()
	return bool(predicate.call())

func finish(status: String, missing: Array = []) -> void:
	var report := {"status": status, "engine": Engine.get_version_info().string,
		"headless": DisplayServer.get_name() == "headless", "checks": checks, "failures": failures,
		"missing_dependencies": missing, "actual_boat_package_loaded": actual_boat_loaded,
		"native_mouse_acceptance": false, "paid_generation_calls": 0,
		"completion_methods": {"bridge": "valid session snapshot restore", "boat": "shared handle_pointer commands plus explicit skip_lesson; normal return duration", "drawing": "public document API", "generation": "offline_mock"},
		"routes": routes, "elapsed_ms": Time.get_ticks_msec() - started}
	var file := FileAccess.open(out.path_join("real_flow.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t")); file.close()
	if is_instance_valid(app): app.flow.stop(); app.queue_free()
	print("REAL_BOAT_RESULT: ", status, "; ", checks.size(), " checks; ", failures.size(), " failures")
	quit(0 if status == "passed" else 2 if status == "blocked" else 1)

func place_group(play: Control, id: String) -> bool:
	var scroll: Node = play.cards[id].get_parent()
	while scroll != null and not scroll is ScrollContainer: scroll = scroll.get_parent()
	if scroll is ScrollContainer: scroll.ensure_control_visible(play.cards[id])
	await frames(4)
	var start: Vector2 = play.cards[id].get_global_rect().get_center()
	play.drag.handle_pointer({"phase":"begin","intent":"primary","contact":"mouse:1","position":start})
	if not check(play.drag.held and play.drag.drag_source.get("item_id", "") == id, "shared command press captures boat group " + id): return false
	var end: Vector2 = play.view.global_position + play.camera.unproject_position(play.preview_grab_point)
	play.drag.handle_pointer({"phase":"move","position":start+Vector2(0,-20),"delta":Vector2(0,-20)})
	play.drag.handle_pointer({"phase":"move","position":end,"delta":end-start})
	play.drag.handle_pointer({"phase":"end","intent":"primary","contact":"mouse:1","position":end})
	if not check(await wait_until(func(): return play.mode == "lesson" and play.pending_id == id), "legal drop enters real pending connection " + id): return false
	play.skip_lesson()
	if not check(await wait_until(func(): return play.mode == "assembly" and play.pending_id.is_empty()), "explicit skip returns through normal lifecycle " + id): return false
	return check(id in play.placed, "model rules commit accepted group " + id)

func run() -> void:
	started = Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="): out = argument.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(out)
	var missing: Array = []
	for path in ["res://content/quanzhou_boat/stage_adapter.gd", "res://content/quanzhou_boat/demo.tscn", "res://interaction/mouse_input_adapter.gd", "res://interaction/gesture_router.gd", "res://interaction/orbit_camera.gd"]:
		if not ResourceLoader.exists(path): missing.append(path)
	if not missing.is_empty(): finish("blocked", missing); return
	if OS.get_cmdline_user_args().has("--preflight-only"):
		finish("blocked", ["preflight_only_requested; real package execution intentionally withheld"]); return
	check(not DirAccess.dir_exists_absolute("res://content/quanzhou_boat/interaction"), "boat package does not carry a second public interaction directory")
	root.size = Vector2i(1400, 900)
	app = load("res://levels/integrated_demo.tscn").instantiate()
	root.add_child(app)
	await frames(8)
	if not check(app.flow.progress().stage_id == "assembly" and app.flow.progress().total == 3, "full ordinary entry starts registered three-stage level"): finish("failed"); return
	app.flow.config.stages[-1].export_path = out.path_join("real_drawing.png")
	check(not app.flow.can_advance(), "incomplete bridge cannot advance")
	var workshop = app.flow.current_stage.adapter.workshop
	var bridge_ref: WeakRef = weakref(workshop)
	check(workshop.orbit.get_script().resource_path == "res://interaction/orbit_camera.gd", "bridge stage uses main project's shared camera controller")
	check(workshop.interaction.input_adapter.get_script().resource_path == "res://interaction/mouse_input_adapter.gd", "bridge model uses main shared input mapping")
	check(workshop.interaction.gestures.get_script().resource_path == "res://interaction/gesture_router.gd", "bridge model uses main shared gesture ownership")
	var saved: Dictionary = workshop.session.snapshot()
	for step in workshop.data.steps:
		if step.action_kind == "install": saved.placements[step.slot.id] = workshop.data.slot_type_map[step.slot.id]
	saved.completed_actions = [workshop.data.withdraw_action_id]
	if not check(workshop.session.restore(saved).ok and app.flow.can_advance(), "real bridge valid completion snapshot reaches generic flow"): finish("failed"); return
	app.next_button.pressed.emit()
	await frames(5)
	if not check(app.flow.progress().stage_id == "ship" and is_instance_valid(app.flow.current_stage) and is_instance_valid(app.flow.current_stage.adapter), "next-stage control loads actual registered boat adapter"): finish("failed"); return
	var play: Control = app.flow.current_stage.adapter.play
	actual_boat_loaded = true
	var boat_ref: WeakRef = weakref(play)
	check(bridge_ref.get_ref() == null, "bridge scene is freed before boat use")
	check(not app.flow.can_advance() and not app.flow.advance().is_empty(), "incomplete real boat cannot skip to drawing")
	if not check(play.groups.size() == 28, "actual boat package exposes accepted 28 groups"): finish("failed"); return
	for method in ["handle_pointer"]:
		if not check(play.drag.has_method(method), "boat public action seam provides " + method): finish("failed"); return
	for group in play.groups:
		var before := Time.get_ticks_msec()
		if not await place_group(play, str(group.id)): finish("failed"); return
		routes.append({"id": group.id, "elapsed_ms": Time.get_ticks_msec()-before, "route": "public_drag_actions_then_explicit_skip"})
	check(app.flow.can_advance() and app.flow.results.ship.payload.content_snapshot.complete, "actual model completion reaches standard stage result")
	check(app.flow.results.ship.payload.model_id == "quanzhou_boat" and app.flow.results.ship.payload.content_snapshot.placed_groups.size() == 28, "completion preserves stable model identity and all real groups")
	app.next_button.pressed.emit()
	await frames(5)
	if not check(app.flow.progress().stage_id == "drawing", "full entry proceeds from actual boat to drawing"): finish("failed"); return
	check(boat_ref.get_ref() == null, "boat scene and live input owner are freed before drawing")
	check(app.host.find_children("*", "SubViewport", true, false).is_empty(), "drawing retains no model viewport")
	var drawing: Control = app.flow.current_stage
	var document = drawing.surface.document
	check(document.materials.size() == 2, "both actual model completion results provide required artwork")
	app.finish_drawing()
	check(not app.flow.can_advance(), "both image placements required before drawing completion")
	for item in document.materials: check(document.place_material(item.id, item.target_position), "document API places model artwork " + str(item.id))
	document.begin_stroke(Vector2(560, 360), Color("688b84"), 4)
	document.append_stroke(Vector2(720, 350))
	document.end_stroke()
	app.finish_drawing()
	if not check(app.flow.progress().finished and app.flow.results.size() == 3, "real two-model flow completes after full drawing export"): finish("failed"); return
	var image := Image.load_from_file(out.path_join("real_drawing.png"))
	check(image.get_size() == Vector2i(1920,1280) and image.get_data() == document.compose(Vector2i(1920,1280)).get_data(), "export is exact full paper with both artworks and ink")
	var generation := Generation.new()
	app.add_child(generation)
	var cfg: Dictionary = app.flow.config.optional_generation.duplicate(true)
	cfg.backend = "offline_mock"
	cfg.output_path = out.path_join("real_flow_mock.png")
	if not check(generation.enter_stage(cfg, {"results":app.flow.results,"mock_mode":false,"demonstration":true}).is_empty(), "existing generation boundary accepts real full-level drawing"): finish("failed"); return
	check(generation.state == "idle" and generation.input_image.get_data() == image.get_data(), "generation remains idle with exact exported pixels")
	generation.mock_delay = 0.01
	generation.request_generation()
	check(await wait_until(func(): return generation.state == "succeeded", 20), "existing package offline mock succeeds without paid generation")
	generation.exit_stage()
	generation.queue_free()
	app.restart()
	await frames(5)
	check(app.flow.progress().stage_id == "assembly" and app.flow.results.is_empty() and app.next_button.disabled, "restart clears real bridge, boat and drawing progress")
	finish("passed" if failures.is_empty() else "failed")
