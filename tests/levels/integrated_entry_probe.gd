extends Node
## Inherits the ordinary entry. No root resizing or manually instantiated demo.
const Result = preload("res://image_generation/result.gd")
var app: Control
var checks := 0
var failures: Array[String] = []
var evidence := ""

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("INTEGRATED_PASS: ", label)
	else:
		failures.append(label)
		push_error("INTEGRATED_FAILED: " + label)

func frames(n: int = 2) -> void:
	for i in range(n): await get_tree().process_frame

func mouse(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = get_tree().root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(event)
	await frames()

func click(button: Button) -> void:
	await mouse(button.get_global_rect().get_center(), true)
	await mouse(button.get_global_rect().get_center(), false)

func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = get_tree().root.get_final_transform() * point
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await frames()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var viewport: Viewport = app.optional_window if is_instance_valid(app.optional_window) else get_tree().root
	check(viewport.get_texture().get_image().save_png(evidence.path_join(name + ".png")) == OK, "capture " + name)

func wait_state(stage: Control, expected: String) -> bool:
	var deadline := Time.get_ticks_msec() + 4000
	while stage.state != expected and Time.get_ticks_msec() < deadline:
		await frames()
	var reached: bool = stage.state == expected
	check(reached, "generation reaches " + expected + " within finite wait")
	if not reached: print("GENERATION_ACTUAL_STATE: ", stage.state, "; ", stage.status.text)
	return reached

func finish_bridge() -> void:
	var workshop = app.flow.current_stage.adapter.workshop
	var saved: Dictionary = workshop.session.snapshot()
	for step in workshop.data.steps:
		if step.action_kind == "install": saved.placements[step.slot.id] = workshop.data.slot_type_map[step.slot.id]
	saved.completed_actions = [workshop.data.withdraw_action_id]
	check(workshop.session.restore(saved).ok and app.flow.can_advance(), "accepted bridge completion event enables next")
	await click(app.next_button)

func draw_and_export(use_input: bool) -> void:
	var stage = app.flow.current_stage
	var surface: Control = stage.surface
	if use_input:
		for i in range(surface.document.materials.size()):
			var material: Dictionary = surface.document.materials[i]
			await mouse(surface.get_global_transform_with_canvas() * surface.tray_rect(i).get_center(), true)
			await move(surface.get_global_transform_with_canvas() * surface.paper_to_local(material.target_position * Vector2(surface.document.paper_size)))
			await mouse(surface.get_global_transform_with_canvas() * surface.paper_to_local(material.target_position * Vector2(surface.document.paper_size)), false)
		await mouse(surface.get_global_transform_with_canvas() * surface.paper_to_local(Vector2(120, 100)), true)
		await move(surface.get_global_transform_with_canvas() * surface.paper_to_local(Vector2(400, 160)))
		await mouse(surface.get_global_transform_with_canvas() * surface.paper_to_local(Vector2(400, 160)), false)
	else:
		for item in surface.document.materials: surface.document.place_material(item.id, item.target_position)
		surface.document.begin_stroke(Vector2(100, 80), Color("235877"), 12)
		surface.document.append_stroke(Vector2(350, 130))
		surface.document.end_stroke()
	if use_input:
		check(surface.document.placements.size() == surface.document.materials.size() and surface.document.strokes.size() == 1, "pointer drag places configured 2D pictures and pointer stroke reaches paper")
		await capture("integrated_drawing")
	await click(app.export_button)
	check(app.flow.can_advance() and FileAccess.file_exists(app.flow.results.drawing.payload.texture_path), "drawing exports a real PNG and enables next")

func verify_model_seam() -> void:
	var host := Control.new()
	app.add_child(host)
	var flow = load("res://levels/level_flow.gd").new()
	app.add_child(flow)
	var descriptor := {"id": "fixture_alpha", "adapter_script": "res://tests/levels/fake_model.gd",
		"drawing_asset": {"kind": "image_2d", "texture_path": "res://levels/assets/bridge_placeholder.svg", "transparent_background": true}}
	var config := {"id": "replacement_fixture", "stages": [
		{"id": "fixture_stage", "component": "model", "model": descriptor},
		{"id": "fixture_paper", "component": "drawing", "surface_script": "res://drawing/drawing_surface.gd", "config_script": "res://drawing/drawing_config.gd",
			"materials": [{"id": "fixture_image", "result_stage": "fixture_stage", "target_position": Vector2(0.5, 0.5),
				"display_size": Vector2(0.3, 0.3), "allowed_drop_rect": Rect2(0.3, 0.3, 0.4, 0.4), "layer": 15}]}]}
	var factories := {"model": func(): return load("res://levels/model_stage.gd").new(), "drawing": func(): return load("res://levels/drawing_stage.gd").new()}
	check(flow.start(config, host, factories).is_empty(), "unrelated fake model descriptor enters through generic seam")
	flow.current_stage.adapter.complete_model()
	check(flow.results.fixture_stage.payload.model_id == "fixture_alpha" and flow.results.fixture_stage.payload.fixture_completion, "generic seam relays stable model id and completion payload")
	check(flow.advance().is_empty() and flow.current_stage.surface.document.materials[0].id == "fixture_image", "unrelated model 2D asset reaches unchanged generic drawing adapter")
	config.stages[0].model = {"id": "fixture_beta", "scene": "res://tests/levels/fake_model.tscn", "drawing_asset": descriptor.drawing_asset}
	check(flow.start(config, host, factories).is_empty(), "scene-only model also enters through the same generic seam")
	flow.stop()
	flow.queue_free()
	host.queue_free()

func run() -> void:
	app = get_parent()
	var args := OS.get_cmdline_user_args()
	evidence = args[0] if not args.is_empty() else "user://integrated_evidence"
	DirAccess.make_dir_recursive_absolute(evidence)
	await frames(8)
	check(app.size.x >= 1000 and app.size.y >= 700 and app.host.size.y > 400, "ordinary entry receives project layout without forced root size")
	check(app.flow.progress().stage_id == "assembly" and app.flow.progress().total == 2, "default entry contains only real assembly then drawing")
	check(app.flow.progress().demonstration and not app.flow.mock_mode, "mixed demo is explicitly marked and retains real component stages")
	check(app.next_button.disabled, "bridge cannot be skipped before completion")
	check(app.flow.config.disabled_stages.size() == 1 and not app.flow.config.disabled_stages[0].enabled, "future model stage is configured but disabled")
	check(app.flow.config.stages[1].materials.size() == 1, "default integration canvas requires only the active model image")
	var materials: Array = load("res://levels/level_catalog.gd").bridge_demo(app.output_directory, {"include_optional_materials": true}).stages[1].materials
	check(materials[0].layer < materials[1].layer and materials[0].target_position.y < materials[1].target_position.y and materials[0].display_size.x < materials[1].display_size.x, "level configuration places smaller far image behind larger near image")
	check(materials[0].preview_texture_path == materials[0].placed_texture_path and materials[1].placement_transition.kind == "reserved", "separate preview and placed asset fields reserve transition while sharing one image")
	await verify_model_seam()
	await capture("integrated_bridge")
	await finish_bridge()
	check(app.flow.progress().stage_id == "drawing" and app.flow.current_stage.surface.size.y > 300, "real drawing component is hosted with visible paper")
	app.finish_drawing()
	check(not app.flow.can_advance() and app.status.text.contains("拖"), "configured 2D material must be placed before export")
	var surface: Control = app.flow.current_stage.surface
	check(surface.find_children("*", "Node3D", true, false).is_empty(), "paper stage contains 2D pictures and no interactive 3D nodes")
	for material in surface.document.materials:
		var image: Image = material.texture.get_image()
		check(image.get_pixel(0, 0).a <= 0.005, "2D model image preserves transparent background")
	# Exercise actual pointer dispatch once, then inspect the component's public document.
	await draw_and_export(true)
	check(app.flow.progress().finished and app.flow.results.size() == 2 and app.optional_button.visible, "assembly plus drawing completes acceptance before any generation")
	await capture("integrated_complete")
	app.open_optional_mock()
	await frames(3)
	var generation = app.optional_stage
	var original := Image.load_from_file(app.flow.results.drawing.payload.texture_path)
	check(generation.input_image.get_data() == original.get_data(), "generation receives exact real drawing export pixels")
	check(generation.state == "idle" and generation.output_view.texture == null, "generation starts idle with no invented output")
	generation.mode.select(0)
	generation.mock_delay = 0.7
	generation.generate_button.pressed.emit()
	await frames(2)
	check(generation.state == "waiting" and not generation.cancel_button.disabled and generation.generate_button.disabled, "waiting state exposes cancel and prevents duplicate start")
	var cancelled_token: int = generation.request_epoch
	generation.cancel_button.pressed.emit()
	check(generation.state == "cancelled" and app.flow.progress().finished, "optional cancellation leaves completed drawing flow intact")
	generation._received(Result.success(original), cancelled_token)
	check(generation.state == "cancelled" and generation.output_image == null, "late cancelled result cannot overwrite state")
	await capture("integrated_cancelled")
	generation.mode.select(1)
	generation.mock_delay = 0.02
	generation.generate_button.pressed.emit()
	await wait_state(generation, "failed")
	check(generation.status.text.contains("rate_limited") and not generation.generate_button.disabled and app.flow.results.size() == 2, "optional failure permits manual retry without changing level results")
	await capture("integrated_failed")
	generation.mode.select(2)
	generation.timeout_seconds = 0.1
	generation.generate_button.pressed.emit()
	await wait_state(generation, "failed")
	check(generation.status.text.contains("timeout"), "offline hang reaches a visible timeout state")
	generation.mode.select(0)
	generation.timeout_seconds = 2
	generation.prompt.text = "integration demonstration mock"
	generation.generate_button.pressed.emit()
	await wait_state(generation, "succeeded")
	check(generation._reported and generation.submitted_prompt == "integration demonstration mock", "retry passes prompt into existing offline service and marks mock provenance")
	check(generation.output_image.get_data() != original.get_data() and generation.output_image.get_size() == original.get_size(), "package mock returns transformed drawing pixels with original dimensions")
	check(FileAccess.file_exists(generation.stage_config.output_path) and app.flow.results.size() == 2, "optional output saves separately without adding required stages")
	check(generation.output_view.texture != null and generation.status.text.contains("非真实"), "optional result is visible with offline mock label")
	await capture("integrated_result")
	var first_directory: String = app.output_directory
	app.restart()
	await frames(2)
	check(app.flow.progress().stage_id == "assembly" and app.flow.results.is_empty() and app.next_button.disabled, "reset starts a fresh incomplete model stage")
	check(app.output_directory != first_directory, "reset uses a new output directory")
	await finish_bridge()
	await draw_and_export(false)
	app.open_optional_mock()
	var previous = app.optional_stage
	previous.mock_delay = 1.0
	previous.request_generation()
	await frames(2)
	var old_job = previous.job
	var old_token: int = previous.request_epoch
	var old_path: String = previous.stage_config.output_path
	app.restart()
	previous._received(Result.success(original), old_token)
	check(old_job.done and old_job.result.error.code == "cancelled", "reset cancels the in-flight package job")
	check(app.flow.results.is_empty() and app.flow.progress().stage_id == "assembly" and not FileAccess.file_exists(old_path), "late result after reset cannot write output or replace new progress")
	await frames(6)
	await capture("integrated_reset")
	var report := {"engine": Engine.get_version_info().string, "checks": checks, "failures": failures,
		"headless": DisplayServer.get_name() == "headless", "bridge_completion_uses_valid_snapshot": true,
		"required_stages": ["assembly", "drawing"], "future_model_stage": "disabled",
		"materials": "approved_stylized_bridge_illustration", "generation": "optional_existing_package_offline_mock"}
	var file := FileAccess.open(evidence.path_join("integrated_validation.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("INTEGRATED_RESULT: %d checks, %d failures" % [checks, failures.size()])
	app.flow.stop()
	get_tree().quit(0 if failures.is_empty() else 1)
