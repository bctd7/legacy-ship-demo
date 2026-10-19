extends SceneTree
## Finite stock/slot integration, graphical event dispatch, two legal completions.
var app
var failed: bool=false
var checks: int=0
var out: String
func _initialize() -> void:
	out=OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else ProjectSettings.globalize_path("user://inventory_validation")
	call_deferred("run")
func check(ok: bool,name: String) -> bool:
	checks+=1
	if ok:print("STOCK_PASS: ",name)
	else:failed=true;push_error("STOCK_FAILED: "+name)
	return ok
func frames(n: int=3) -> void:
	for i in range(n):await process_frame
func mouse(p: Vector2,down: bool) -> void:
	var e=InputEventMouseButton.new();e.position=root.get_final_transform()*p;e.global_position=e.position;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e);await process_frame
func click(p: Vector2) -> void:
	var e=InputEventMouseMotion.new();e.position=root.get_final_transform()*p;e.global_position=e.position
	Input.parse_input_event(e);await process_frame
	await mouse(p,true);await mouse(p,false)
func move(p: Vector2,delta: Vector2) -> void:
	var e=InputEventMouseMotion.new();e.position=root.get_final_transform()*p;e.global_position=e.position;e.relative=root.get_final_transform().basis_xform(delta);e.button_mask=MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e);await process_frame
func drag(a: Vector2,b: Vector2) -> void:await mouse(a,true);await move(b,b-a);await mouse(b,false)
func wait_animation() -> void:
	var count: int=0
	while app.session.is_busy() and count<300:await process_frame;count+=1
	check(not app.session.is_busy(),"animation finishes within finite budget")
func request(i: int) -> Dictionary:
	var step: Dictionary=app.data.steps[i]
	return {"inventory_type_id":app.data.slot_type_map[step.slot.id],"slot_id":step.slot.id,"release_m":step.slot.anchor_m.duplicate(),"expected_revision":app.session.revision}
func shortcut() -> Dictionary:return {"action_id":app.data.withdraw_action_id,"source":"shortcut","expected_revision":app.session.revision}
func screen_slot(i: int) -> Vector2:return app.view.get_global_rect().position+app.camera.unproject_position(app.Rules.vector(app.data.steps[i].slot.anchor_m))
func choose_type(id: String) -> void:
	for i in range(app.data.tray_entries.size()):
		if app.data.tray_entries[i].id==id:app._choose(i);break
	await frames()
func invariant() -> bool:
	var remaining: int=0
	for t in app.data.inventory_types:remaining+=app.session.availability(t.id).remaining
	return remaining+app.session.placements.size()==20
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(out.path_join(name+".png"))==OK,"capture "+name)
func visible_meshes() -> int:
	var n: int=0
	for node in app.presenter.find_children("*","MeshInstance3D",true,false):
		if node.is_visible_in_tree():n+=1
	return n
func assemble(order: Array,label: String) -> void:
	app.reset_workshop()
	for i in order:
		var result: Dictionary=app.session.request_install(request(i))
		if not check(result.ok,label+" target "+str(app.data.steps[i].slot.id)):return
		await wait_animation()
	check(app.session.placements.size()==20 and invariant(),label+" consumes exactly 20 stock units into 20 slots")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(out);root.size=Vector2i(1400,900)
	app=load("res://scenes/workshop.tscn").instantiate();root.add_child(app);await frames(12)
	app.presenter.duration_scale=0.04
	check(app.data.inventory_types.size()==7 and app.ui.pictures.size()==6,"7 real stock types shown as 5 operation cards plus auxiliary action")
	check(invariant() and app.session.placements.is_empty(),"initial stock total 20 and no occupied slots")
	check(app.ui.withdraw_button.disabled and app.ui.withdraw_note.text.contains("20"),"early shortcut disabled with missing-piece explanation")
	check(not app.session.request_install(shortcut()).ok and invariant(),"early action request rejects")
	await choose_type("beam_end")
	var from: Vector2=app.tray.get_global_rect().get_center()
	await click(from)
	check(app.session.placements.is_empty(),"stock click selects without installation")
	await mouse(from,true);await move(screen_slot(9),screen_slot(9)-from)
	check(app.interaction.hover_slot_id=="slot_10" and app.presenter.preview.material_override.albedo_color.g>0.7,"same end-beam type previews a different compatible target green")
	await capture("inventory_swap_preview")
	await mouse(screen_slot(9),false);await wait_animation()
	check(app.session.placements.get("slot_10")=="beam_end" and app.session.availability("beam_end").remaining==3,"stock installs in selected compatible slot instead of fixed origin")
	await choose_type("beam_end")
	await drag(app.tray.get_global_rect().get_center(),screen_slot(5));await wait_animation()
	check(app.session.placements.get("slot_06")=="beam_end" and app.session.availability("beam_end").remaining==2,"same inventory type can fill second compatible target")
	check(not app.session.request_install(request(9)).ok and app.session.placements.size()==2 and invariant(),"occupied target rejects without consuming stock twice")
	var wrong=request(0);wrong.inventory_type_id="round_rod"
	check(not app.session.request_install(wrong).ok and app.feedback.text.contains("兼容") and invariant(),"different-spec stock rejected at end-beam target")
	check(not app.session.request_install(request(10)).ok and app.feedback.text.contains("梁"),"group dependency remains tied to occupied target slots")
	var snapshot: Dictionary=app.session.snapshot()
	app.reset_workshop();check(app.session.restore(snapshot).ok and app.session.placements.size()==2 and invariant(),"inventory and non-prefix target occupancy restore together")
	var bad: Dictionary=snapshot.duplicate(true);bad.placements["slot_01"]="round_rod"
	check(not app.session.restore(bad).ok and app.session.placements.size()==2,"restore rejects incompatible target mapping")
	var stale: int=app.session.revision
	var pending: Dictionary=app.session.request_install(request(0))
	check(pending.ok and app.session.availability("beam_end").remaining==2,"pending animation does not prematurely consume stock")
	check(not app.session.request_install(request(0)).ok,"concurrent duplicate request cannot reserve stock twice")
	await wait_animation();check(app.session.placements.size()==3 and invariant(),"animation commits exactly one inventory unit and slot")
	var stale_request=request(4);stale_request.expected_revision=stale
	check(not app.session.request_install(stale_request).ok and invariant(),"stale inventory revision rejects")
	await capture("inventory_interchange")
	await assemble(range(20),"recommended")
	app.presenter.duration_scale=0.7;await frames()
	check(not app.ui.withdraw_button.disabled,"withdraw shortcut available after all formal slots filled")
	await click(app.ui.withdraw_button.get_global_rect().get_center())
	check(app._withdraw_busy() and app.session.completed_actions.is_empty(),"button starts same controlled withdrawal without early commit")
	if not app._withdraw_busy():quit(1);return
	var old_ticket: int=app.session.pending_ticket()
	await click(app.ui.withdraw_button.get_global_rect().get_center())
	check(not app.session.is_busy() and not app._summary().finished and app.session.placements.size()==20,"cancel withdrawal keeps stock and all formal placements")
	check(not app.session.finish_animation(old_ticket),"cancel invalidates old animation ticket")
	await click(app.ui.withdraw_button.get_global_rect().get_center());await wait_animation()
	check(app._summary().finished and visible_meshes()==22,"shortcut completes with only 22 real bridge meshes")
	await capture("inventory_complete")
	app.ui.more_button.get_popup().id_pressed.emit(0);app.ui.more_button.get_popup().id_pressed.emit(0);await frames()
	check(app._summary().finished and visible_meshes()==22,"observation return retains exact occupied slots without helpers")
	app.ui.more_button.get_popup().id_pressed.emit(1);await frames();await click(app.ui.reset_confirm.get_global_rect().get_center());await frames()
	check(app.session.placements.is_empty() and app.session.completed_actions.is_empty() and invariant(),"confirmed reset restores full stock and empties target slots")
	var reverse: Array=[]
	for i in range(9,-1,-1):reverse.append(i)
	for i in range(14,9,-1):reverse.append(i)
	for i in range(19,14,-1):reverse.append(i)
	app.presenter.duration_scale=0.04;await assemble(reverse,"reverse groups")
	await choose_type(app.data.withdraw_action_id)
	var anchor: Vector3=app.Rules.vector(app.data.steps[20].slot.anchor_m)
	var axis: Vector2=app.camera.unproject_position(anchor+Vector3(0,-0.1,0))-app.camera.unproject_position(anchor)
	from=app.tray.get_global_rect().get_center()
	var delta=axis*0.35+Vector2(axis.y,-axis.x).normalized()*axis.length()*0.25
	print("PULL_DIAGNOSTIC before: card=",app.ui.card_at(from)," enabled=",app.interaction.enabled," selected=",app.interaction.selection," delta=",delta)
	await mouse(from,true)
	print("PULL_DIAGNOSTIC pressed: held=",app.interaction.held," grabbed=",app.interaction.grabbed_id)
	await move(from+delta,delta)
	print("PULL_DIAGNOSTIC moved: held=",app.interaction.held," dragging=",app.interaction.dragging," distance=",app.interaction.pull_distance," lateral=",app.interaction.lateral_distance)
	check(app.interaction.pull_distance>=0.018 and app.presenter.pull_preview.visible,"short diagonal downward gesture previews withdrawal")
	await mouse(from+delta,false);await wait_animation()
	check(app._summary().finished and visible_meshes()==22 and invariant(),"short diagonal drag completes second legal assembly with correct stock")
	if not failed:print("INVENTORY_ALL_PASS checks=",checks,"; two_orders; input=Godot-events; physical_mouse=untested; touch=untested")
	quit(1 if failed else 0)
