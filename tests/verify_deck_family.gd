extends SceneTree
## Focused operation-family checks using the real graphical scene and injected events.
var app
var failed=false
var checks=0
func _initialize() -> void:call_deferred("run")
func frames(n:int=3) -> void:
	for i in range(n):await process_frame
func check(ok:bool,label:String) -> void:
	checks+=1
	if ok:print("DECK_PASS: ",label)
	else:failed=true;push_error("DECK_FAILED: "+label)
func mouse(p:Vector2,down:bool) -> void:
	var e=InputEventMouseButton.new();e.position=root.get_final_transform()*p;e.global_position=e.position;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e);await process_frame
func move(p:Vector2) -> void:
	var e=InputEventMouseMotion.new();e.position=root.get_final_transform()*p;e.global_position=e.position;e.button_mask=MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e);await process_frame
func screen(i:int) -> Vector2:
	return app.view.get_global_rect().position+app.camera.unproject_position(app.Rules.vector(app.data.steps[i].slot.trigger_points_m[0]))
func choose() -> void:
	for i in range(app.data.tray_entries.size()):
		if app.data.tray_entries[i].id=="deck":app._choose(i);break
	await frames()
func finish() -> void:
	var n=0
	while app.session.is_busy() and n<300:await process_frame;n+=1
	check(not app.session.is_busy(),"animation completes within finite budget")
func request(i:int,id:String="") -> Dictionary:
	var step:Dictionary=app.data.steps[i]
	return {"inventory_type_id":app.data.slot_type_map[step.slot.id] if id.is_empty() else id,"slot_id":step.slot.id,"release_m":step.slot.trigger_points_m[0] if i>=15 else step.slot.anchor_m,"expected_revision":app.session.revision}
func prepare(i:int) -> void:
	var result:Dictionary=app.session.request_install(request(i))
	if not result.ok:failed=true;push_error("DECK_FAILED: setup "+result.message);quit(1);return
	var n=0
	while app.session.is_busy() and n<300:await process_frame;n+=1
	if app.session.is_busy():failed=true;quit(1)
func begin(i:int) -> Vector2:
	await choose();await mouse(app.tray.get_global_rect().get_center(),true)
	var p=screen(i);await move(p);return p
func stable(p:Vector2,mesh:Mesh) -> bool:
	var centre=app.presenter.preview.transform*app.presenter.preview_source_anchor
	var pixel=app.view.get_global_rect().position+app.camera.unproject_position(centre)
	return app.interaction.drag_source.get("item_id")=="deck" and app.presenter.preview_source_id=="deck" and app.presenter.preview.mesh==mesh and pixel.distance_to(p)<0.75 and not app.presenter.hoist.visible
func escape() -> void:
	var e=InputEventKey.new();e.keycode=KEY_ESCAPE;e.pressed=true;Input.parse_input_event(e);await process_frame
func capture(name:String) -> void:
	if OS.get_cmdline_user_args().is_empty():return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join(name))==OK,"save "+name)
func run() -> void:
	root.size=Vector2i(1400,900);app=load("res://scenes/workshop.tscn").instantiate();root.add_child(app);await frames(12);app.presenter.duration_scale=0.08
	var cards=0
	for entry in app.data.tray_entries:
		if entry.id=="deck":cards+=1
	check(cards==1 and app.ui.cards.size()==6 and app.session.availability("deck").remaining==5,"single deck card starts at five, with five stock cards total")
	var panel:Mesh=app.presenter.common_preview_mesh("deck")
	check(panel is BoxMesh and panel.get_aabb().size.is_equal_approx(Vector3(0.09,0.0075,0.134)),"drag and thumbnail use common 90x134x7.5mm panel without arms or feet")
	for i in range(15):await prepare(i)
	var frame:Dictionary=app.session.snapshot()
	var legal=0
	for option in app.session.target_options("deck"):
		if option.allowed:legal+=1
	check(legal==5 and app._summary().available_units==5,"all five vacant deck slots available after rods")
	var p:Vector2=await begin(15)
	for i in range(15,20):
		p=screen(i);await move(p);await create_timer(0.18).timeout
		check(app.interaction.hover_slot_id==app.data.steps[i].slot.id and stable(p,panel),"held source remains one panel, follows pointer at slot "+str(i+1))
		var expected=Basis(Vector3(0,0,1),deg_to_rad(40.0-(i-15)*20.0))
		check(app.presenter.preview.basis.get_rotation_quaternion().angle_to(expected.get_rotation_quaternion())<0.001,"common panel adopts original target orientation "+str(i+1))
	await escape();await mouse(p,false)
	check(app.session.placements.size()==15 and app.session.availability("deck").remaining==5 and not app.presenter.preview.visible,"Esc during hold cancels without consumption or residual preview")
	for i in [15,16,17]:
		p=await begin(i)
		var actual_type:String=app.data.slot_type_map[app.data.steps[i].slot.id]
		var real_source:String=app.session.rules.type_for(actual_type).representative_part_id
		check(stable(p,panel),"three foot-span cases retain common source before release: "+actual_type)
		var before:int=app.session.availability("deck").remaining
		await mouse(p,false)
		check(app.session.is_busy() and app.presenter.preview_source_id==real_source and app.presenter.preview.mesh==app.presenter.meshes[real_source].mesh,"legal release selects correct original full mesh: "+actual_type)
		check(app.presenter.active.step.path==app.data.steps[i].path and app.session.availability("deck").remaining==before,"original full animation preserved; no early stock decrement")
		check(not app.session.request_install(request(i,"deck")).ok,"busy duplicate cannot consume stock twice")
		await finish()
		check(app.session.placements.get(app.data.steps[i].slot.id)==actual_type and app.session.availability("deck").remaining==before-1,"commit stores actual target type and decrements family once")
	app.session.restore(frame);await frames();await prepare(15);await prepare(18);await choose()
	var saved:Dictionary=app.session.snapshot()
	check(app.session.placements.size()==17 and app.session.availability("deck").remaining==3 and app.ui.captions[app.selected].text=="桥面 ×3","17/20 state shows one deck card with three remaining")
	check(app.session.availability("deck_narrow_support").remaining==0 and app.session.availability("deck_mid_support").remaining==2 and app.session.availability("deck_wide_support").remaining==1,"remaining count combines depleted and available real stock types correctly")
	check(app._resolve_pick("Deck_panel_01")=="deck" and app._resolve_pick("Deck_panel_04")=="deck","scene picks map installed real deck parts to visible operation family")
	p=await begin(15)
	check(app.interaction.hover_slot_id=="slot_16" and not app.interaction.hover_target.allowed and stable(p,panel),"occupied target rejects while source remains common panel")
	await mouse(p,false)
	check(not app.session.is_busy() and app.session.placements.size()==17 and app.session.availability("deck").remaining==3,"occupied release cannot overwrite or consume")
	p=await begin(16);await escape();await mouse(p,false)
	check(app.session.placements.size()==17 and app.session.availability("deck").remaining==3,"cancel at remaining legal target leaves 17/20 unchanged")
	await choose();await capture("deck_family_17_of_20.png")
	app.reset_workshop();await frames()
	check(app.session.restore(saved).ok and app.session.snapshot().placements==saved.placements and app.session.availability("deck").remaining==3,"existing schema3 actual-type placements restore without migration or family IDs")
	await frames()
	for i in [16,17,19]:
		p=await begin(i);await mouse(p,false);await finish()
	check(app.session.placements.size()==20 and app.session.availability("deck").remaining==0,"all remaining targets resolve to their own real variants")
	var withdraw=app.session.request_install({"action_id":app.data.withdraw_action_id,"source":"shortcut","expected_revision":app.session.revision})
	check(withdraw.ok,"full bridge enables original withdrawal")
	await finish()
	var visible=0
	for node in app.presenter.find_children("*","MeshInstance3D",true,false):
		if node.is_visible_in_tree():visible+=1
	check(app._summary().finished and visible==22 and not app.presenter.preview.visible,"withdrawal completes with 22 original formal meshes and no preview")
	if not failed:print("DECK_FAMILY_ALL_PASS checks=",checks,"; input=Godot-events; physical_mouse=untested; touch=untested")
	quit(1 if failed else 0)
