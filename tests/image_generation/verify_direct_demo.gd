extends SceneTree
## Engine loads the explicit command-line scene. Never creates/loads demo nodes.
var checks := 0
var failures := 0
var evidence_dir := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="):
			evidence_dir = argument.trim_prefix("--evidence-dir=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("DIRECT_DEMO_PASS: " if ok else "DIRECT_DEMO_FAIL: ") + label)

func frames(count: int = 3) -> void:
	for _i in range(count): await process_frame

func click(control: Control) -> void:
	var point := root.get_final_transform() * control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event)
		await frames(2)

func capture(name: String) -> void:
	if evidence_dir.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(evidence_dir.path_join(name + ".png"))
	check(error == OK, "save actual rendered viewport " + name)

func run() -> void:
	await frames(8)
	check(current_scene != null and current_scene.scene_file_path == "res://image_generation/demo.tscn", "engine directly launches demo.tscn as current_scene")
	if current_scene == null:
		quit(1)
		return
	var demo := current_scene
	check(demo.is_visible_in_tree() and demo.size.x >= 600 and demo.size.y >= 400, "main scene is visible with nonzero viewport layout")
	check(demo.prompt.is_visible_in_tree() and not demo.prompt.text.is_empty(), "prompt input is visible and initialized")
	var generate: Button
	var cancel: Button
	for button in demo.find_children("*", "Button", true, false):
		if button.text == "运行离线模拟": generate = button
		if button.text == "取消当前请求": cancel = button
	check(generate != null and cancel != null and generate.is_visible_in_tree(), "default mock actions are present and visible")
	await capture("direct_demo_initial")
	if generate == null or cancel == null:
		quit(1)
		return
	await click(generate)
	check(demo.job != null, "mouse press/release on default action starts a job")
	await create_timer(1.0).timeout
	check(demo.job != null and demo.job.done and demo.job.result.ok and demo.output.texture != null, "default mock completes and displays an output image after real GUI input events")
	await capture("direct_demo_success")
	demo.mode.select(2)
	await click(generate)
	await click(cancel)
	check(demo.job != null and demo.job.done and demo.job.result.error.code == "cancelled", "mouse click on cancel returns a structured cancellation")
	await capture("direct_demo_cancel")
	var summary := {"engine": Engine.get_version_info().string, "scene": demo.scene_file_path,
		"passed": checks - failures, "total": checks, "exit_code": 1 if failures else 0,
		"launch": "Explicit demo.tscn command-line main scene plus passive SceneTree verification driver; no demo node instantiation or project changes.",
		"input": "Godot Input.parse_input_event mouse press/release; not physical mouse hardware acceptance.",
		"network_requests": 0, "real_generation_calls": 0}
	if not evidence_dir.is_empty():
		var file := FileAccess.open(evidence_dir.path_join("direct_demo_validation.json"), FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify(summary, "\t") + "\n")
	print("DIRECT_DEMO_CHECKS: %d passed / %d total; offline only" % [checks - failures, checks])
	quit(1 if failures else 0)
