extends SceneTree
## Passive driver: the engine directly loads loopback_demo.tscn as main scene.
var evidence_dir := ""
var failures := 0
var checks := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="): evidence_dir = argument.trim_prefix("--evidence-dir=")
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("LOOPBACK_SCENE_PASS: " if ok else "LOOPBACK_SCENE_FAIL: ") + label)

func click(button: Control) -> void:
	var point := root.get_final_transform() * button.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event)
		await process_frame

func capture(name: String) -> void:
	if evidence_dir.is_empty(): return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(evidence_dir.path_join(name)) == OK, "capture actual loopback demo viewport")

func run() -> void:
	for _i in range(8): await process_frame
	check(current_scene != null and current_scene.scene_file_path == "res://image_generation/loopback_demo.tscn", "direct main scene launch")
	if current_scene == null:
		quit(1)
		return
	var demo := current_scene
	check(demo.local_mode == "stub" and demo.send_button.is_visible_in_tree(), "visible explicit STUB controls")
	await capture("loopback_http_initial.png")
	await click(demo.send_button)
	var first_job = demo.job
	await click(demo.send_button)
	check(first_job != null and demo.job == first_job, "repeated physical-style GUI event does not create another job")
	await create_timer(0.65).timeout
	check(demo.job != null and demo.job.done and demo.job.result.ok and demo.output.texture != null and demo.status.text.contains("非真实 AI"), "actual local HTTP result displays with truthful non-AI label")
	await capture("loopback_http_stub.png")
	print("LOOPBACK_SCENE_CHECKS: %d passed / %d total" % [checks - failures, checks])
	quit(1 if failures else 0)
