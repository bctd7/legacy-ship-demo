extends "res://tests/levels/integrated_entry_probe.gd"
## Real bridge asset + actual pointer painting + complete export + offline package callback.
func stroke(surface: Control, points: Array, color: Color, width: float) -> void:
	surface.brush_color = color
	surface.brush_width = width
	await mouse(surface.get_global_transform_with_canvas() * surface.paper_to_local(points[0]), true)
	for point in points.slice(1):
		await move(surface.get_global_transform_with_canvas() * surface.paper_to_local(point))
	await mouse(surface.get_global_transform_with_canvas() * surface.paper_to_local(points[-1]), false)

func run() -> void:
	app = get_parent()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="): evidence = argument.trim_prefix("--evidence-dir=")
	if evidence.is_empty(): evidence = "user://bridge_canvas_evidence"
	DirAccess.make_dir_recursive_absolute(evidence)
	await frames(12)
	await finish_bridge()
	var drawing = app.flow.current_stage
	var surface: Control = drawing.surface
	var document = surface.document
	var item: Dictionary = document.materials[0]
	var source: Image = item.texture.get_image()
	if source.is_compressed(): source.decompress()
	check(source.get_size() == Vector2i(2046,769) and not item.placeholder, "active bridge asset is approved complete stylized illustration, not placeholder")
	check(app.flow.results.assembly.payload.drawing_asset.texture_path == "res://levels/assets/bridge_illustration_v2.png", "generic model result supplies approved bridge illustration path")
	check(source.get_pixel(0,0).a <= 0.005 and source.detect_alpha() != Image.ALPHA_NONE, "approved illustration preserves transparent alpha")
	await mouse(surface.get_global_transform_with_canvas() * surface.tray_rect(0).get_center(), true)
	await move(surface.get_global_transform_with_canvas() * surface.paper_to_local(item.target_position * Vector2(document.paper_size)))
	await mouse(surface.get_global_transform_with_canvas() * surface.paper_to_local(item.target_position * Vector2(document.paper_size)), false)
	check(document.placements.has(item.id), "pointer drag places real model image on paper")
	await stroke(surface, [Vector2(65,206),Vector2(137,107),Vector2(190,158),Vector2(233,120),Vector2(317,221)],Color("65775e"),4)
	await stroke(surface, [Vector2(70,226),Vector2(145,189),Vector2(183,214),Vector2(237,182),Vector2(325,229)],Color("87957d"),3)
	await stroke(surface, [Vector2(521,262),Vector2(468,323),Vector2(484,389),Vector2(426,463),Vector2(389,532),Vector2(292,615)],Color("5c807e"),5)
	await stroke(surface, [Vector2(674,265),Vector2(722,324),Vector2(695,390),Vector2(755,464),Vector2(806,526),Vector2(865,614)],Color("5c807e"),5)
	await stroke(surface, [Vector2(544,370),Vector2(594,363),Vector2(642,370)],Color("86a8a4"),3)
	await stroke(surface, [Vector2(500,463),Vector2(567,453),Vector2(658,464)],Color("86a8a4"),3)
	await stroke(surface, [Vector2(468,543),Vector2(554,535),Vector2(661,545)],Color("86a8a4"),3)
	check(document.strokes.size() == 7, "actual pointer strokes draw landscape semantics without fixed test line")
	var ink: Array = document.strokes.duplicate(true)
	await capture("bridge_painting_ui")
	await click(app.export_button)
	check(app.flow.progress().finished and app.flow.results.size() == 2, "real model and drawing stages complete")
	var path: String = app.flow.results.drawing.payload.texture_path
	var full := Image.load_from_file(path)
	check(full.get_size() == Vector2i(1920,1280) and app.flow.results.drawing.payload.export_size == Vector2i(1920,1280), "export contains complete paper at 1920x1280")
	check(not app.flow.results.drawing.payload.contains_placeholder_assets and full.get_pixel(0,0).is_equal_approx(Color.WHITE), "full exported paper is opaque white with real material provenance")
	check(full.get_data() == document.compose(Vector2i(1920,1280)).get_data(), "export equals full model-plus-ink compositor, not viewport crop")
	check(full.save_png(evidence.path_join("complete_canvas_1920x1280.png")) == OK, "save exact submitted full-canvas evidence")
	source.save_png(evidence.path_join("bridge_illustration_2046x769.png"))
	app.open_optional_mock()
	await frames(4)
	var stage = app.optional_stage
	check(stage.input_image.get_data() == full.get_data(), "generation input is exact full exported canvas including all ink and material")
	check(stage.prompt.text.contains("完整画布") and stage.prompt.text.contains("前后关系") and stage.prompt.text.contains("国风") and stage.prompt.text.contains("空气透视"), "default prompt preserves user composition and requests depth")
	check(not stage.prompt.text.contains("三组") and not stage.prompt.text.contains("蓝色") and not stage.prompt.text.contains("桥"), "prompt has no hardcoded model, support count or colored test line")
	var result := {"count":0,"value":{}}
	stage.stage_result.connect(func(_id:String, value:Dictionary): result.count += 1; result.value=value.duplicate(true))
	stage.mode.select(1)
	stage.mock_delay = 0.01
	stage.request_generation()
	await wait_state(stage,"failed")
	check(not stage.generate_button.disabled and document.strokes == ink, "generation failure allows manual retry without losing drawing")
	stage.mode.select(0)
	stage.mock_delay = 0.02
	stage.request_generation()
	var epoch: int = stage.request_epoch
	stage.request_generation()
	check(stage.request_epoch == epoch and stage.generate_button.disabled, "duplicate submit blocked while request pending")
	var deadline := Time.get_ticks_msec()+15000
	while stage.state != "succeeded" and Time.get_ticks_msec()<deadline: await frames()
	check(stage.state == "succeeded" and result.count == 1, "offline package job returns once through actual completion callback")
	check(stage.output_image.get_size() == full.get_size() and stage.output_image.get_data() != full.get_data(), "offline transformation returns full-size output, explicitly not AI")
	check(result.value.payload.source == "offline_mock" and result.value.payload.mock_generation and not result.value.payload.replay, "callback result has truthful offline provenance")
	check(result.value.payload.input_texture_path == path and result.value.payload.prompt == stage.prompt.text, "result preserves exact full-canvas reference and submitted prompt")
	check(stage.output_view.texture.get_size() == Vector2(1920,1280) and stage.output_view.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "result UI displays full output without distortion")
	stage.output_image.save_png(evidence.path_join("offline_result_1920x1280.png"))
	await capture("bridge_canvas_offline_result_ui")
	stage.return_requested.emit()
	await frames(3)
	check(app.flow.current_stage == drawing and document.strokes == ink and app.flow.progress().finished, "return preserves original painted canvas and progress")
	await capture("bridge_canvas_return_ui")
	var report := {"checks":checks,"failures":failures,"engine":Engine.get_version_info().string,
		"input":"complete_canvas_1920x1280.png","model_asset":"bridge_illustration_2046x769.png",
		"model_source":"res://levels/assets/bridge_illustration_v2.png","model_placeholder":false,
		"painting":"actual pointer input; mountain, river banks, water strokes", "drawing_strokes":ink.size(),
		"required_stages":["assembly","drawing"],"generation":"existing package offline_mock, not AI",
		"real_api_calls":0,"credential_reads":0,"bridge_completion":"valid snapshot fixture", "real_click_api_e2e":false}
	var file := FileAccess.open(evidence.path_join("validation.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("BRIDGE_CANVAS_RESULT: %d checks %d failures" % [checks,failures.size()])
	app.flow.stop()
	get_tree().quit(0 if failures.is_empty() else 1)
