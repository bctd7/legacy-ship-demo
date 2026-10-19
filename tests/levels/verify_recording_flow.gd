extends SceneTree
## Run only after the pinned final boat package is imported. No native mouse acceptance claim.
## Recording regression: bridge pointer events, boat public actions with complete natural animations, drawing pointer events, HTTP STUB.
const Catalog = preload("res://levels/level_catalog.gd")
const Generation = preload("res://levels/generation_stage.gd")
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var routes: Array[Dictionary] = []
var out := "user://real_boat_level"
var app: Control
var actual_boat_loaded := false
var started := 0
var local_port := 0
var pointer := Vector2.ZERO
var source_poses: Dictionary = {}

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
		"native_mouse_acceptance": false, "paid_generation_calls": 0, "official_model_result_rerun": false, "visible_frame_review": "pending separate observed window inspection",
		"completion_methods": {"bridge": "Godot pointer-event injection; all 20 placements and withdrawal; no restore", "boat": "Godot pointer-event injection through final shared input; all 28 natural connection animations; no skip", "drawing": "Godot pointer-event injection", "generation": "actual loopback HTTP STUB"},
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
	await mouse(model_to_root(start), true)
	if not check(play.drag.held and play.drag.drag_source.get("item_id", "") == id, "shared mapped pointer press captures boat group " + id): return false
	var end: Vector2 = play.view.global_position + play.camera.unproject_position(play.preview_grab_point)
	await move(model_to_root(start + Vector2(0, -20)))
	await move(model_to_root(end))
	await mouse(model_to_root(end), false)
	if not check(await wait_until(func(): return play.mode == "lesson" and play.pending_id == id), "legal drop enters real pending connection " + id): return false
	if id in ["shell_port", "mast_bed_main", "rudder"]:
		check(await wait_until(func(): return play.lesson_stage == "fixed", 12.0), "natural fixed phase is observable " + id)
		await frames(3)
		await capture("boat_fixed_" + id)
	await frames(2)
	check(play.step_card.get_global_rect().end.y <= play.view.get_global_rect().end.y + 1, "long boat step panel fits model view above feedback and tray " + id)
	if not check(await wait_until(func(): return play.mode == "assembly" and play.pending_id.is_empty(), 25.0), "full natural animation and return complete without skipping " + id): return false
	if play.groups.find(play.groups.filter(func(g): return g.id == id)[0]) in [0, 13, 27]: await capture("boat_" + id)
	check(play.lesson_nails == null and play.lesson_context_materials.is_empty() and play.lesson_hidden_nails.is_empty() and play.lesson_homes.is_empty(), "natural return clears temporary nail fade and motion effects " + id)
	var poses_match := true
	for mesh in play.boat.find_children("*", "MeshInstance3D", true, false):
		if not mesh.global_transform.is_equal_approx(source_poses[str(mesh.name)]): poses_match = false
	check(poses_match, "source geometry transforms remain exact after natural assembly " + id)
	return check(id in play.placed, "model rules commit accepted group " + id)

func run() -> void:
	started = Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="): out = argument.trim_prefix("--evidence-dir=")
		if argument.begins_with("--local-port="): local_port = int(argument.trim_prefix("--local-port="))
	DirAccess.make_dir_recursive_absolute(out)
	var missing: Array = []
	for path in ["res://content/quanzhou_boat/stage_adapter.gd", "res://content/quanzhou_boat/demo.tscn", "res://interaction/mouse_input_adapter.gd", "res://interaction/gesture_router.gd", "res://interaction/orbit_camera.gd"]:
		if not ResourceLoader.exists(path): missing.append(path)
	if not missing.is_empty(): finish("blocked", missing); return
	if OS.get_cmdline_user_args().has("--preflight-only"):
		finish("blocked", ["preflight_only_requested; real package execution intentionally withheld"]); return
	check(not DirAccess.dir_exists_absolute("res://content/quanzhou_boat/interaction"), "boat package does not carry a second public interaction directory")
	if local_port < 1 or local_port == 8769:
		finish("blocked", ["isolated_STUB_port_required; use verify_recording_flow.py"]); return
	if DisplayServer.get_name() == "headless": root.size = Vector2i(1400, 900)
	app = load("res://levels/integrated_demo.tscn").instantiate()
	root.add_child(app)
	app.local_mode = "stub"
	app.official_enabled = false
	app.local_port = local_port
	await frames(8)
	if not check(app.flow.progress().stage_id == "assembly" and app.flow.progress().total == 3, "full ordinary entry starts registered three-stage level"): finish("failed"); return
	app.flow.config.stages[-1].export_path = out.path_join("real_drawing.png")
	check(not app.flow.can_advance(), "incomplete bridge cannot advance")
	var workshop = app.flow.current_stage.adapter.workshop
	var bridge_ref: WeakRef = weakref(workshop)
	check(workshop.orbit.get_script().resource_path == "res://interaction/orbit_camera.gd", "bridge stage uses main project's shared camera controller")
	check(workshop.interaction.input_adapter.get_script().resource_path == "res://interaction/mouse_input_adapter.gd", "bridge model uses main shared input mapping")
	check(workshop.interaction.gestures.get_script().resource_path == "res://interaction/gesture_router.gd", "bridge model uses main shared gesture ownership")
	await capture("01_bridge_start")
	if not await bridge_pointer_assembly(workshop): finish("failed"); return
	await capture("02_bridge_complete")
	app.next_button.pressed.emit()
	await frames(5)
	if not check(app.flow.progress().stage_id == "ship" and is_instance_valid(app.flow.current_stage) and is_instance_valid(app.flow.current_stage.adapter), "next-stage control loads actual registered boat adapter"): finish("failed"); return
	var play: Control = app.flow.current_stage.adapter.play
	actual_boat_loaded = true
	for mesh in play.boat.find_children("*", "MeshInstance3D", true, false): source_poses[str(mesh.name)] = mesh.global_transform
	check(source_poses.size() == 1286, "main integration retains all 1286 source mesh identities")
	await capture("03_boat_initial")
	var boat_ref: WeakRef = weakref(play)
	check(bridge_ref.get_ref() == null, "bridge scene is freed before boat use")
	check(not app.flow.can_advance() and app.next_button.disabled, "incomplete real boat cannot skip to drawing")
	if not check(play.groups.size() == 28, "actual boat package exposes accepted 28 groups"): finish("failed"); return
	for method in ["handle_pointer"]:
		if not check(play.drag.has_method(method), "boat public action seam provides " + method): finish("failed"); return
	for group in play.groups:
		var before := Time.get_ticks_msec()
		if not await place_group(play, str(group.id)): finish("failed"); return
		routes.append({"id": group.id, "elapsed_ms": Time.get_ticks_msec()-before, "route": "shared_pointer_events_then_full_natural_animation"})
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
	for index in document.materials.size():
		var item: Dictionary = document.materials[index]
		var surface: Control = drawing.surface
		await mouse(surface.get_global_transform_with_canvas() * surface.tray_rect(index).get_center(), true)
		var target: Vector2 = surface.get_global_transform_with_canvas() * surface.paper_to_local(item.target_position * Vector2(document.paper_size))
		await move(target)
		await mouse(target, false)
		check(document.placements.has(item.id), "pointer events place actual model artwork " + str(item.id))
	var surface: Control = drawing.surface
	await mouse(surface.get_global_transform_with_canvas() * surface.paper_to_local(Vector2(550, 360)), true)
	await move(surface.get_global_transform_with_canvas() * surface.paper_to_local(Vector2(650, 345)))
	await move(surface.get_global_transform_with_canvas() * surface.paper_to_local(Vector2(760, 360)))
	await mouse(surface.get_global_transform_with_canvas() * surface.paper_to_local(Vector2(760, 360)), false)
	check(document.strokes.size() == 1, "pointer stroke reaches paper")
	check(not app.status.text.contains("请先将所有"), "placing artwork clears prior export prerequisite warning")
	await capture("06_drawing_two_materials_and_ink")
	app.finish_drawing()
	if not check(app.flow.progress().finished and app.flow.results.size() == 3, "real two-model flow completes after full drawing export"): finish("failed"); return
	var image := Image.load_from_file(out.path_join("real_drawing.png"))
	check(image.get_size() == Vector2i(1920,1280) and image.get_data() == document.compose(Vector2i(1920,1280)).get_data(), "export is exact full paper with both artworks and ink")
	app.open_local_generation()
	await frames(5)
	var generation: Control = app.optional_stage
	if not check(is_instance_valid(generation) and generation.backend == "local_stub", "full entry opens known STUB generation panel"): finish("failed"); return
	check(root.gui_embed_subwindows, "generation subwindow is embedded in single native app window")
	check(generation.state == "idle" and generation.job == null and generation.input_image.get_data() == image.get_data(), "opening panel stays idle with exact full exported pixels")
	await capture("07_stub_idle_no_auto_send")
	generation.generate_button.pressed.emit()
	generation.request_generation()
	check(generation.state == "waiting" and generation.generate_button.disabled, "one explicit STUB send prevents duplicate submission")
	if not check(await wait_until(func(): return generation.state == "succeeded", 20), "loopback HTTP STUB succeeds without official API"): finish("failed"); return
	check(generation.output_image.get_data() == image.get_data() and generation.status.text.contains("非真实 AI"), "STUB result displays original full drawing with explicit non-AI label")
	check(generation.output_view.texture != null, "result picture is available to visible panel")
	generation.output_image.save_png(out.path_join("stub_result.png"))
	await capture("08_stub_result")
	generation.return_requested.emit()
	await frames(3)
	check(app.optional_window == null and app.flow.progress().finished and document.strokes.size() == 1, "return closes result panel and preserves completed drawing and ink")
	await capture("09_return_to_drawing")
	app.open_local_generation()
	await frames(3)
	generation = app.optional_stage
	check(generation.state == "idle" and generation.job == null and generation.output_view.texture == null, "reopening panel starts idle without stale output or auto resend")
	generation.request_generation()
	var old_job = generation.job
	var token: int = generation.request_epoch
	generation.cancel_request()
	check(old_job != null and old_job.done and generation.state == "cancelled" and generation.output_view.texture == null, "cancel terminates local wait with no stale success image")
	await create_timer(1.2).timeout
	check(generation.request_epoch >= token and generation.state == "cancelled" and generation.output_view.texture == null, "late HTTP reply cannot restore cancelled result")
	generation.return_requested.emit()
	await frames(3)
	app.open_local_generation()
	await frames(3)
	generation = app.optional_stage
	generation.prompt.text = ""
	generation.request_generation()
	check(await wait_until(func(): return generation.state == "failed", 4), "empty prompt gives an explicit recoverable error")
	check(not generation.generate_button.disabled and generation.output_view.texture == null, "error allows manual retry and shows no invented result")
	await capture("10_stub_validation_error")
	generation.return_requested.emit()
	await frames(3)
	app.restart()
	await frames(5)
	check(app.flow.progress().stage_id == "assembly" and app.flow.results.is_empty() and app.next_button.disabled, "restart clears real bridge, boat and drawing progress")
	await capture("11_fresh_entry_after_restart")
	finish("passed" if failures.is_empty() else "failed")

func mouse(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	pointer = point
	Input.parse_input_event(event)
	await frames()

func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.relative = root.get_final_transform().basis_xform(point - pointer)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	pointer = point
	Input.parse_input_event(event)
	await frames()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await frames(2)
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(out.path_join(name + ".png")) == OK, "capture visible rendered stage " + name)

func bridge_pointer_assembly(workshop: Node) -> bool:
	var container: Control = app.flow.current_stage.adapter.get_child(0)
	for index in range(20):
		var step: Dictionary = workshop.data.steps[index]
		var inventory: String = workshop.data.slot_type_map[step.slot.id]
		var display_item: String = workshop.session.rules.display_item_for_type(inventory)
		var card_index := -1
		for i in workshop.data.tray_entries.size():
			if workshop.data.tray_entries[i].id == display_item: card_index = i; break
		if not check(card_index >= 0, "inventory card exists for bridge slot " + str(step.slot.id)): return false
		workshop.ui.tray_scroll.ensure_control_visible(workshop.ui.cards[card_index])
		await frames(3)
		var start: Vector2 = container.get_global_transform_with_canvas() * workshop.ui.cards[card_index].get_global_rect().get_center()
		var anchor: Vector3 = workshop.Rules.vector(step.slot.anchor_m)
		var target: Vector2 = container.get_global_transform_with_canvas() * (workshop.view.get_global_rect().position + workshop.camera.unproject_position(anchor))
		await mouse(start, true)
		await move(start.lerp(target, 0.5))
		await move(target)
		await mouse(target, false)
		var installed: bool = await wait_until(func(): return not workshop.session.is_busy(), 10) and workshop.session.placements.has(step.slot.id)
		if not installed:
			print("BRIDGE_DROP_DIAGNOSTIC slot=", step.slot.id, " start=", start, " target=", target, " status=", workshop.session.view_state())
			await capture("bridge_failure_" + str(step.slot.id))
		if not check(installed, "pointer input completes natural bridge installation " + str(step.slot.id)): return false
		if index in [0, 9, 19]: await capture("bridge_%02d" % (index + 1))
	if not check(not workshop.ui.withdraw_button.disabled, "support withdrawal unlocks after all bridge parts"): return false
	var button: Vector2 = container.get_global_transform_with_canvas() * workshop.ui.withdraw_button.get_global_rect().get_center()
	await mouse(button, true)
	await mouse(button, false)
	return check(await wait_until(func(): return not workshop.session.is_busy(), 12) and workshop.session.view_state().finished and app.flow.can_advance(), "pointer withdrawal completes real bridge before next stage")

func model_to_root(point: Vector2) -> Vector2:
	var container = app.flow.current_stage.canvas_container
	return container.get_global_transform_with_canvas() * point if is_instance_valid(container) else point
