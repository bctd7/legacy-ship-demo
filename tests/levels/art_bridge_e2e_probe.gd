extends "res://tests/levels/bridge_canvas_probe.gd"
## Explicit one-shot acceptance harness. Godot pointer events, not native OS input.
## No restore, direct install calls, animation acceleration, or model skipping.
var began_ms := 0
var timings := {}
var assembly_events: Array = []
var official := false
var request_id := "bridge-art-v2-flash-20261016-once"
var request_sent := false
var outcome := {}

func save_json(name: String, value: Dictionary) -> void:
	var file := FileAccess.open(evidence.path_join(name),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(value,"\t")); file.close()

func end_run() -> void:
	var report := {"checks":checks,"failures":failures,"official":official,"request_sent":request_sent,
		"request_id":request_id if official else "", "timings_ms":timings,"total_ms":Time.get_ticks_msec()-began_ms,
		"input_method":"Godot Input.parse_input_event for model, drawing, navigation; generation Button.pressed signal; native OS input untested", "model_completion":"20 real drag placements + withdrawal UI; no snapshot restore or direct install",
		"assembly_events":assembly_events,"outcome":outcome,"automatic_retry":false,"credential_reads":0}
	save_json("validation.json",report)
	print("ART_BRIDGE_E2E_RESULT: ",JSON.stringify(report))
	app.close_optional_mock()
	app.flow.stop()
	get_tree().quit(0 if failures.is_empty() else 1)

func finish_bridge() -> void:
	var workshop = app.flow.current_stage.adapter.workshop
	var container: Control = app.flow.current_stage.adapter.get_child(0)
	await capture("01_assembly_start")
	for i in range(20):
		var step: Dictionary = workshop.data.steps[i]
		var inventory: String = workshop.data.slot_type_map[step.slot.id]
		var display_item: String = workshop.session.rules.display_item_for_type(inventory)
		var index := -1
		for c in range(workshop.data.tray_entries.size()):
			if workshop.data.tray_entries[c].id == display_item: index=c;break
		if index < 0: check(false,"inventory UI card exists"); return
		# UI scrolling changes no model/session state. Press selects the real card.
		workshop.ui.tray_scroll.ensure_control_visible(workshop.ui.cards[index])
		await frames(3)
		var from: Vector2 = container.get_global_transform_with_canvas() * workshop.ui.cards[index].get_global_rect().get_center()
		var anchor: Vector3 = workshop.Rules.vector(step.slot.anchor_m)
		var target: Vector2 = container.get_global_transform_with_canvas() * (workshop.view.get_global_rect().position + workshop.camera.unproject_position(anchor))
		await mouse(from,true)
		await move(from.lerp(target,0.5))
		await move(target)
		var selected: String = workshop.interaction.hover_slot_id
		await mouse(target,false)
		var deadline := Time.get_ticks_msec()+8000
		while workshop.session.is_busy() and Time.get_ticks_msec()<deadline: await frames()
		var installed: bool = workshop.session.placements.has(step.slot.id)
		assembly_events.append({"slot":step.slot.id,"inventory":inventory,"hover_slot":selected,"installed":installed,"elapsed_ms":Time.get_ticks_msec()-began_ms})
		check(installed,"pointer drag installs real bridge slot "+step.slot.id)
		if not installed: await capture("assembly_failed"); return
		if i in [0,9,14,19]: await capture("assembly_%02d" % (i+1))
	check(not workshop.ui.withdraw_button.disabled,"withdrawal UI unlocks after 20 real placements")
	await click_at(container.get_global_transform_with_canvas() * workshop.ui.withdraw_button.get_global_rect().get_center())
	var deadline := Time.get_ticks_msec()+10000
	while workshop.session.is_busy() and Time.get_ticks_msec()<deadline: await frames()
	check(workshop.session.view_state().finished and app.flow.can_advance(),"withdrawal completes through UI and enables drawing stage")
	await capture("02_assembly_complete")
	if failures.is_empty(): await click(app.next_button)

func click_at(point: Vector2) -> void:
	await mouse(point,true)
	await mouse(point,false)

func run() -> void:
	app=get_parent()
	began_ms=Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence-dir="): evidence=argument.trim_prefix("--evidence-dir=")
		if argument == "--one-real-flash": official=true
	if evidence.is_empty(): evidence="user://art_bridge_offline"
	DirAccess.make_dir_recursive_absolute(evidence)
	if official and FileAccess.file_exists(evidence.path_join("single_attempt_latch.json")):
		check(false,"single attempt latch already exists; refusing any resend")
		end_run();return
	await frames(18)
	await finish_bridge()
	timings.assembly=Time.get_ticks_msec()-began_ms
	if not failures.is_empty(): end_run();return
	var drawing=app.flow.current_stage
	var surface: Control=drawing.surface
	var document=drawing.surface.document
	var item: Dictionary=document.materials[0]
	check(item.texture.get_size()==Vector2(2046,769) and not item.placeholder,"approved full stylized bridge asset is loaded")
	await mouse(surface.get_global_transform_with_canvas()*surface.tray_rect(0).get_center(),true)
	await move(surface.get_global_transform_with_canvas()*surface.paper_to_local(item.target_position*Vector2(document.paper_size)))
	await mouse(surface.get_global_transform_with_canvas()*surface.paper_to_local(item.target_position*Vector2(document.paper_size)),false)
	check(document.placements.has(item.id),"actual pointer drag places complete illustration onto white paper")
	await stroke(surface,[Vector2(65,206),Vector2(137,107),Vector2(190,158),Vector2(233,120),Vector2(317,221)],Color("65775e"),4)
	await stroke(surface,[Vector2(70,226),Vector2(145,189),Vector2(183,214),Vector2(237,182),Vector2(325,229)],Color("87957d"),3)
	await stroke(surface,[Vector2(525,232),Vector2(468,323),Vector2(484,389),Vector2(426,463),Vector2(389,532),Vector2(292,615)],Color("5c807e"),5)
	await stroke(surface,[Vector2(735,232),Vector2(722,324),Vector2(695,390),Vector2(755,464),Vector2(806,526),Vector2(865,614)],Color("5c807e"),5)
	await stroke(surface,[Vector2(544,370),Vector2(594,363),Vector2(642,370)],Color("86a8a4"),3)
	await stroke(surface,[Vector2(500,463),Vector2(567,453),Vector2(658,464)],Color("86a8a4"),3)
	await stroke(surface,[Vector2(468,543),Vector2(554,535),Vector2(661,545)],Color("86a8a4"),3)
	check(document.strokes.size()==7,"seven actual pointer strokes reach drawing document")
	await capture("03_painting")
	var ink: Array=document.strokes.duplicate(true)
	await click(app.export_button)
	var input_path: String=app.flow.results.get("drawing",{}).get("payload",{}).get("texture_path","")
	if input_path.is_empty(): check(false,"full canvas export exists");end_run();return
	var image:=Image.load_from_file(input_path)
	check(image.get_size()==Vector2i(1920,1280) and image.get_data()==document.compose(Vector2i(1920,1280)).get_data(),"complete 1920x1280 canvas includes model and all ink exactly")
	image.save_png(evidence.path_join("complete_canvas_input.png"))
	timings.model_to_export=Time.get_ticks_msec()-began_ms
	if not failures.is_empty(): end_run();return
	if official:
		check(app.official_enabled,"explicit official mode startup is enabled")
		await click(app.local_button)
	else: await click(app.optional_button)
	await frames(5)
	var stage=app.optional_stage
	if stage==null: check(false,"generation panel opened");end_run();return
	check(stage.input_image.get_data()==image.get_data() and stage.state=="idle","generation panel receives full export and opens without automatic submission")
	var prompt_file:=FileAccess.open(evidence.path_join("submitted_prompt.txt"),FileAccess.WRITE)
	prompt_file.store_string(stage.prompt.text);prompt_file.close()
	if official:
		check(stage.backend=="local_official","existing local official service route selected")
		stage.service.provider.request_id=request_id
	if not failures.is_empty(): end_run();return
	await capture("04_before_submit")
	if official: save_json("single_attempt_latch.json",{"request_id":request_id,"attempted_once":true,"automatic_retry":false,"submitted_at_unix":Time.get_unix_time_from_system()})
	var submitted_ms:=Time.get_ticks_msec()
	request_sent=official
	# Explicit button intent. Report as signal injection, not a native pointer click.
	await submit_button(stage.generate_button)
	check(stage.state=="waiting" or stage.state=="succeeded","one explicit generation button signal starts generation")
	await capture("05_generation_waiting")
	var deadline:=Time.get_ticks_msec()+(130000 if official else 15000)
	while stage.state=="waiting" and Time.get_ticks_msec()<deadline: await frames()
	timings.submit_to_terminal=Time.get_ticks_msec()-submitted_ms
	outcome={"state":stage.state,"status":stage.status.text,"backend":stage.backend}
	if stage.state=="succeeded":
		stage.output_image.save_png(evidence.path_join("official_flash_output.png" if official else "offline_output.png"))
		outcome.output_dimensions=str(stage.output_image.get_size())
		outcome.input_sha256=FileAccess.get_sha256(evidence.path_join("complete_canvas_input.png"))
		outcome.output_sha256=FileAccess.get_sha256(evidence.path_join("official_flash_output.png" if official else "offline_output.png"))
		check(stage.output_view.texture!=null,"actual result is displayed in generation UI")
	else: check(false,"generation reached success; no retry was attempted")
	await capture("06_actual_result")
	stage.return_requested.emit()
	await frames(4)
	check(app.flow.current_stage==drawing and document.strokes==ink,"return preserves original complete painting")
	await capture("07_return_painting")
	end_run()

func submit_button(button:Button) -> void:
	button.pressed.emit()
	await frames(2)
