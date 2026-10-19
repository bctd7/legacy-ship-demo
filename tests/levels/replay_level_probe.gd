extends "res://tests/levels/integrated_entry_probe.gd"
## Recorded PNG only. No local server, credentials, provider or HTTP transport.
func run() -> void:
	app = get_parent()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="): evidence = argument.trim_prefix("--evidence-dir=")
	DirAccess.make_dir_recursive_absolute(evidence)
	await frames(8)
	check(not app.replay_image_path.is_empty(), "replay path explicitly supplied")
	await finish_bridge()
	await draw_and_export(true)
	var drawing = app.flow.current_stage
	var document = drawing.surface.document
	var strokes: Array = document.strokes.duplicate(true)
	var placements: Dictionary = document.placements.duplicate(true)
	var input_path: String = app.flow.results.drawing.payload.texture_path
	var drawing_pixels := Image.load_from_file(input_path).get_data()
	check(app.replay_button.is_visible_in_tree(), "completed drawing exposes explicit replay entry")
	app.replay_button.pressed.emit()
	await frames(4)
	var stage = app.optional_stage
	check(stage.backend == "recorded_replay" and stage.service == null and stage.job == null and stage.state == "idle", "opening replay creates no network service or job")
	check(stage.input_image.get_data() == drawing_pixels and stage.output_image == null, "replay receives real current drawing export without invented output")
	check(stage.status.text.contains("离线回放") and not stage.prompt.visible, "UI distinguishes archived result from current drawing generation")
	await capture("replay_idle")
	var correct_path: String = stage.stage_config.replay_image_path
	stage.stage_config.replay_image_path = "user://deliberately_missing_replay.png"
	stage.request_generation()
	await wait_state(stage, "failed")
	check(stage.status.text.contains("replay_missing") and not stage.generate_button.disabled and not stage._reported, "missing file fails visibly and permits explicit retry")
	check(app.flow.current_stage == drawing and document.strokes == strokes and app.flow.results.size() == 2, "replay failure leaves drawing and progress intact")
	await capture("replay_failed")
	stage.stage_config.replay_image_path = correct_path
	# Cancel before deferred completion, then explicitly retry the same component.
	stage.request_generation()
	var cancelled_job = stage.job
	var cancelled_token: int = stage.request_epoch
	stage.cancel_request()
	stage._received(Result.success(stage.input_image), cancelled_token)
	await frames(2)
	check(cancelled_job.done and stage.state == "cancelled" and stage.output_image == null, "cancelled replay rejects stale callback")
	var emitted := {"count": 0, "result": {}}
	stage.stage_result.connect(func(_id: String, result: Dictionary):
		emitted.count += 1
		emitted.result = result.duplicate(true))
	stage.generate_button.pressed.emit()
	var epoch: int = stage.request_epoch
	var first_job = stage.job
	stage.request_generation()
	check(stage.state == "waiting" and stage.generate_button.disabled and stage.request_epoch == epoch and stage.job == first_job, "duplicate click while loading creates only one job")
	await wait_state(stage, "succeeded")
	var original := Image.load_from_file(correct_path)
	check(original.get_size() == Vector2i(2368, 1776) and stage.output_image.get_data() == original.get_data(), "real archived 2368x1776 PNG reaches unchanged result callback")
	check(stage.output_view.texture.get_size() == Vector2(2368, 1776) and stage.output_view.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "result texture preserves dimensions and uses aspect-centered display")
	var fit := minf(stage.output_view.size.x / 2368.0, stage.output_view.size.y / 1776.0)
	var fitted := Vector2(2368, 1776) * fit
	check(is_equal_approx(fitted.x / fitted.y, 4.0 / 3.0) and fitted.x <= stage.output_view.size.x + 0.01 and fitted.y <= stage.output_view.size.y + 0.01, "4:3 result fits available viewport without crop or stretch")
	check(emitted.count == 1 and emitted.result.payload.replay and emitted.result.payload.source == "recorded_official_result" and emitted.result.payload.generation_mode == "recorded_replay", "result provenance explicitly records offline replay")
	check(stage.status.text.contains("本次未发送请求") and stage.service == null, "successful replay remains explicitly labelled and owns no service")
	check(Image.load_from_file(stage.stage_config.output_path).get_data() == original.get_data(), "shared callback saves original result pixels separately")
	stage.request_generation()
	stage._received(Result.success(stage.input_image), epoch)
	check(emitted.count == 1 and stage.request_epoch == epoch and stage.output_image.get_data() == original.get_data(), "completion is idempotent and duplicate callback cannot replace output")
	await frames(4)
	await capture("replay_success")
	stage.return_requested.emit()
	await frames(4)
	check(app.optional_stage == null and app.optional_window == null and app.flow.current_stage == drawing, "return action closes only replay and keeps original drawing node")
	check(drawing.surface.document == document and document.strokes == strokes and document.placements == placements and strokes.size() == 1, "return preserves same document, ink points and placed materials")
	check(Image.load_from_file(input_path).get_data() == drawing_pixels and app.flow.progress().finished and app.flow.results.size() == 2, "return preserves original exported pixels and level progress")
	await capture("replay_return_drawing")
	# Closing while pending also cancels before a deferred write can occur.
	app.open_recorded_replay()
	stage = app.optional_stage
	stage.request_generation()
	var pending = stage.job
	var pending_path: String = stage.stage_config.output_path
	app.close_optional_mock()
	await frames(4)
	check(pending.done and not FileAccess.file_exists(pending_path), "closing pending replay prevents late output write")
	var report := {"checks": checks, "failures": failures, "engine": Engine.get_version_info().string,
		"mode": "offline_recorded_result_replay", "real_click_to_api_e2e": false,
		"source_file": correct_path, "source_sha256": FileAccess.get_sha256(correct_path),
		"source_dimensions": [2368, 1776], "display_area": [fitted.x, fitted.y],
		"provider_instances": 0, "http_requests": 0, "credential_reads": 0,
		"bridge_completion": "valid snapshot fixture", "drawing": "actual pointer drag/stroke/export"}
	var file := FileAccess.open(evidence.path_join("validation.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("LEVEL_REPLAY_RESULT: %d checks %d failures" % [checks, failures.size()])
	app.flow.stop()
	get_tree().quit(0 if failures.is_empty() else 1)
