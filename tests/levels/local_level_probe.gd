extends "res://tests/levels/integrated_entry_probe.gd"
## Only run under verify_local_level.py's known STUB server, never port 8769.
func run() -> void:
	app = get_parent()
	var test_case := "flow"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="): evidence = argument.trim_prefix("--evidence-dir=")
		if argument.begins_with("--case="): test_case = argument.trim_prefix("--case=")
	DirAccess.make_dir_recursive_absolute(evidence)
	await frames(8)
	var official_preview := test_case == "official_idle"
	check(app.local_mode == ("official" if official_preview else "stub") and app.official_enabled == official_preview, "startup mode is explicit and never inferred from service availability")
	check(app.flow.config.stages[1].materials.size() == 1, "test drawing requires only the current model image")
	await finish_bridge()
	await draw_and_export(true)
	check(app.local_button.is_visible_in_tree() and app.local_button.text.contains("真实" if official_preview else "STUB"), "completed drawing exposes the explicitly selected local mode")
	app.open_local_generation()
	await frames(8)
	var stage = app.optional_stage
	check(stage.backend == ("local_official" if official_preview else "local_stub") and stage.state == "idle" and stage.job == null, "opening local panel creates no generation job")
	check(stage.output_view.texture == null and app.flow.progress().finished, "local panel starts without output and preserves completed drawing progress")
	if test_case in ["idle", "official_idle"]:
		await frames(12)
		finish_case(test_case)
		return
	var submitted := {"result": {}}
	stage.stage_result.connect(func(_id: String, result: Dictionary): submitted.result = result.duplicate(true))
	stage.prompt.text = "finite level local HTTP test"
	stage.generate_button.pressed.emit()
	stage.request_generation()
	check(stage.state == "waiting" and stage.generate_button.disabled, "one explicit send disables duplicate submission")
	var succeeded: bool = await wait_state(stage, "succeeded")
	if not succeeded:
		finish_case(test_case)
		return
	check(stage.output_image.get_data() == stage.input_image.get_data(), "real loopback HTTP STUB returns exact exported drawing pixels")
	check(submitted.result.payload.source == "local_stub" and submitted.result.payload.mock_generation, "STUB result is labelled as non-AI with validated local source")
	check(FileAccess.file_exists(stage.stage_config.output_path) and app.flow.results.size() == 2, "local output saves separately from model and drawing progress")
	await capture("local_stub_success")
	app.open_local_generation()
	stage = app.optional_stage
	stage.prompt.text = "finite level cancel test"
	stage.request_generation()
	await frames(3)
	var previous_job = stage.job
	var token: int = stage.request_epoch
	var image: Image = stage.input_image
	stage.cancel_request()
	stage._received(Result.success(image), token)
	check(previous_job.done and stage.state == "cancelled" and stage.output_image == null, "cancel closes job and rejects late local reply")
	await capture("local_stub_cancelled")
	# Explicitly exercise a blocked official preview, without any network request.
	app._open_generation("local_official")
	stage = app.optional_stage
	stage.request_generation()
	check(stage.state == "blocked" and stage.job == null and stage.generate_button.disabled, "official preview cannot send without explicit official startup")
	# This flag is only enabled against the harness's known STUB server. Its
	# session handshake must refuse official mode before POST or external calls.
	app.official_enabled = true
	app.open_local_generation()
	stage = app.optional_stage
	stage.prompt.text = "mode mismatch fixture"
	stage.request_generation()
	await wait_state(stage, "failed")
	check(stage.output_image == null and not stage._reported, "official-to-STUB mode mismatch never displays success or falls back")
	app.official_enabled = false
	app.open_local_generation()
	stage = app.optional_stage
	stage.prompt.text = "finite reset test"
	stage.request_generation()
	await frames(3)
	previous_job = stage.job
	token = stage.request_epoch
	var path: String = stage.stage_config.output_path
	app.restart()
	stage._received(Result.success(image), token)
	check(previous_job.done and app.flow.results.is_empty() and not FileAccess.file_exists(path), "reset cancels active HTTP job and prevents stale output writes")
	await frames(3)
	check(app.optional_window == null and app.flow.progress().stage_id == "assembly", "reset closes local preview and returns to model stage")
	finish_case(test_case)

func finish_case(test_case: String) -> void:
	var file := FileAccess.open(evidence.path_join(test_case + "_checks.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "test_case": test_case}, "\t"))
		file.close()
	print("LEVEL_LOCAL_RESULT: %s %d checks %d failures" % [test_case, checks, failures.size()])
	app.close_optional_mock()
	app.flow.stop()
	get_tree().quit(0 if failures.is_empty() else 1)
