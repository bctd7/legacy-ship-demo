extends SceneTree
## Offline contract test. Fixture completions and document API calls are not native mouse acceptance.
const Catalog = preload("res://levels/level_catalog.gd")
const Registry = preload("res://levels/model_registry.gd")
const Flow = preload("res://levels/level_flow.gd")
const Model = preload("res://levels/model_stage.gd")
const Drawing = preload("res://levels/drawing_stage.gd")
const Generation = preload("res://levels/generation_stage.gd")
var checks: Array[Dictionary] = []
var failures: Array[String] = []
var out := ""

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append({"label": label, "passed": ok})
	if not ok: failures.append(label); push_error("REGISTERED_FAIL: " + label)
	else: print("REGISTERED_PASS: ", label)

func frames(count: int = 2) -> void:
	for i in range(count): await process_frame

func run() -> void:
	out = OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://registered_models"
	DirAccess.make_dir_recursive_absolute(out)
	var actual := Catalog.integrated_demo(out)
	check(Catalog.validation_error(actual).is_empty(), "default registered level validates before package loading")
	check(actual.stages.size() == 3 and actual.stages[0].component == "model" and actual.stages[1].component == "model" and actual.stages[2].component == "drawing", "default order has two model stages then drawing")
	check(actual.stages[0].model.id == "luban_bridge" and actual.stages[1].model.id == "quanzhou_boat", "default model identities come from registry")
	var art: Array = actual.stages[2].materials
	check(art.size() == 2 and not art[1].optional and not art[1].placeholder, "both approved images required without placeholders")
	check(art[0].target_position.y < art[1].target_position.y and art[0].layer < art[1].layer and art[0].display_size.x < art[1].display_size.x, "composition places smaller distant image behind larger nearer image")
	check(Catalog.integrated_demo(out, {"profile": "bridge_only"}).stages.size() == 2, "prior bridge-only regression profile remains available")
	var models := {
		"fixture_alpha": {"id": "fixture_alpha", "adapter_script": "res://tests/levels/fake_model.gd", "drawing_asset": Registry.defaults().luban_bridge.drawing_asset},
		"fixture_beta": {"id": "fixture_beta", "scene": "res://tests/levels/fake_model.tscn", "drawing_asset": Registry.defaults().quanzhou_boat.drawing_asset}}
	var config := Catalog.integrated_demo(out, {"models": models, "model_stages": [
		{"id": "assembly", "model_key": "fixture_alpha"}, {"id": "ship", "model_key": "fixture_beta"}]})
	models.fixture_alpha.id = "mutated"
	check(config.stages[0].model.id == "fixture_alpha", "registry descriptors are copied into configuration")
	var missing := Catalog.integrated_demo(out, {"model_stages": [{"id": "missing", "model_key": "unknown"}]})
	check(not Catalog.validation_error(missing).is_empty(), "unknown model registration rejected before flow enters")
	var host := Control.new()
	root.add_child(host)
	var flow := Flow.new()
	root.add_child(flow)
	var factories := {"model": func(): return Model.new(), "drawing": func(): return Drawing.new()}
	check(flow.start(config, host, factories).is_empty(), "same generic factory starts arbitrary registered adapter")
	check(not flow.can_advance() and not flow.advance().is_empty() and flow.index == 0, "unfinished first model cannot be skipped")
	var old_adapter: Control = flow.current_stage.adapter
	old_adapter.complete_model()
	check(flow.can_advance() and flow.results.assembly.payload.model_id == "fixture_alpha", "model result supplies stable identity and completion")
	check(flow.results.assembly.payload.drawing_asset.texture_path == actual.stages[0].model.drawing_asset.texture_path, "model result supplies independent approved image descriptor")
	flow.advance()
	check(flow.index == 1 and not flow.can_advance() and not old_adapter.active, "second model enters incomplete after first exits")
	check(not flow.advance().is_empty() and flow.index == 1, "unfinished second model cannot skip to drawing")
	old_adapter.stage_result.emit("ship", {"schema": 1, "status": "completed", "payload": {}, "simulated": false})
	check(not flow.can_advance(), "stale first adapter cannot complete second model")
	flow.current_stage.adapter.complete_model()
	check(flow.results.ship.payload.model_id == "fixture_beta", "scene-only arbitrary model uses identical completion seam")
	check(flow.advance().is_empty() and flow.index == 2, "drawing enters only after both models complete")
	var drawing: Control = flow.current_stage
	var document = drawing.surface.document
	check(document.materials.size() == 2 and drawing.find_children("*", "Node3D", true, false).is_empty(), "drawing receives two 2D images without model nodes")
	check(document.materials[0].texture.get_size() == Vector2(2046,769) and document.materials[1].texture.get_size() == Vector2(1372,1147), "drawing resolves original approved image dimensions through results")
	var far_size: Vector2 = document.material_size(document.materials[0], Vector2(document.paper_size))
	var near_size: Vector2 = document.material_size(document.materials[1], Vector2(document.paper_size))
	check(near_size.x > far_size.x and near_size.y > far_size.y, "actual aspect-preserving foreground image is larger than distant image")
	for item in document.materials:
		var extent: Vector2 = document.material_size(item, Vector2(document.paper_size))
		var center: Vector2 = item.target_position * Vector2(document.paper_size)
		check(center.x - extent.x / 2 >= 0 and center.y - extent.y / 2 >= 0 and center.x + extent.x / 2 <= document.paper_size.x and center.y + extent.y / 2 <= document.paper_size.y, "full artwork bounds stay inside exported paper " + str(item.id))
	check(not drawing.export_to(out.path_join("drawing.png")).is_empty() and not flow.progress().finished, "required unplaced material prevents export completion")
	for item in document.materials:
		check(document.place_material(item.id, item.target_position), "document API places required material " + str(item.id))
	document.begin_stroke(Vector2(550, 350), Color("688b84"), 4)
	document.append_stroke(Vector2(650, 340))
	document.append_stroke(Vector2(740, 350))
	document.end_stroke()
	check(drawing.export_to(out.path_join("drawing.png")).is_empty() and flow.progress().finished and flow.results.size() == 3, "two model completions plus full paper export finish required flow")
	var image := Image.load_from_file(out.path_join("drawing.png"))
	check(image.get_size() == Vector2i(1920,1280) and image.get_data() == document.compose(Vector2i(1920,1280)).get_data(), "export equals complete material-and-stroke compositor at 1920x1280")
	check(not flow.results.drawing.payload.contains_placeholder_assets, "export provenance contains no placeholder art")
	var generation := Generation.new()
	host.add_child(generation)
	var generation_config: Dictionary = config.optional_generation.duplicate(true)
	generation_config.backend = "offline_mock"
	generation_config.output_path = out.path_join("mock_result.png")
	check(generation.enter_stage(generation_config, {"results": flow.results, "mock_mode": false, "demonstration": true}).is_empty(), "existing generation stage accepts completed multi-model drawing")
	check(generation.state == "idle" and generation.output_image == null, "generation entry remains idle until explicit test dispatch")
	check(generation.input_image.get_data() == image.get_data(), "generation receives exact complete drawing pixels")
	generation.mock_delay = 0.01
	generation.request_generation()
	var deadline := Time.get_ticks_msec() + 20000
	while generation.state == "waiting" and Time.get_ticks_msec() < deadline: await frames()
	check(generation.state == "succeeded" and FileAccess.file_exists(generation_config.output_path), "offline mock completes and writes independent output without paid API")
	check(flow.results.size() == 3 and flow.progress().finished, "optional generation leaves required progress unchanged")
	generation.exit_stage()
	generation.queue_free()
	flow.stop()
	await frames()
	check(flow.start(config, host, factories).is_empty() and flow.results.is_empty() and not flow.can_advance(), "restart clears both model results and drawing")
	flow.stop()
	flow.queue_free()
	host.queue_free()
	await frames()
	var report := {"engine": Engine.get_version_info().string, "headless": DisplayServer.get_name() == "headless",
		"checks": checks, "failures": failures, "count": checks.size(), "generation_backend": "offline_mock",
		"model_completion_method": "contract fixture events", "drawing_method": "public document API",
		"native_mouse_acceptance": false, "actual_boat_package_loaded": false}
	var file := FileAccess.open(out.path_join("registration.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("REGISTERED_RESULT: %d checks, %d failures" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)
