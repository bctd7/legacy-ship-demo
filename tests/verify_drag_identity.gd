extends SceneTree
var app
var failed=false
var checks=0
var requests:Array=[]
func _initialize() -> void:call_deferred("run")
func frames(n:int=3) -> void:
	for i in range(n):await process_frame
func check(ok:bool,label:String) -> void:
	checks+=1
	if ok:print("IDENTITY_PASS: ",label)
	else:failed=true;push_error("IDENTITY_FAILED: "+label)
func mouse(p:Vector2,down:bool) -> void:
	var e=InputEventMouseButton.new();e.position=root.get_final_transform()*p;e.global_position=e.position;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e);await process_frame
func move(p:Vector2) -> void:
	var e=InputEventMouseMotion.new();e.position=root.get_final_transform()*p;e.global_position=e.position;e.button_mask=MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e);await process_frame
func key(code:int) -> void:
	var e=InputEventKey.new();e.keycode=code;e.pressed=true;Input.parse_input_event(e);await process_frame
func slot(i:int) -> Vector2:return app.view.get_global_rect().position+app.camera.unproject_position(app.Rules.vector(app.data.steps[i].slot.anchor_m))
func choose(id:String) -> void:
	for i in range(app.data.tray_entries.size()):
		if app.data.tray_entries[i].id==id:app._choose(i);break
	await frames()
func carry_ok(id:String,mesh) -> bool:return app.interaction.drag_source.get("item_id")==id and app.interaction.selection.item_id==id and app.presenter.preview.mesh==mesh and app.presenter.preview.visible
func clean() -> bool:return app.interaction.drag_source.is_empty() and app.interaction.hover_target.is_empty() and not app.interaction.held and not app.presenter.preview.visible
func settled() -> void:
	var n=0
	while app.session.is_busy() and n<300:await process_frame;n+=1
	check(not app.session.is_busy(),"animation settled")
func run() -> void:
	root.size=Vector2i(1400,900);app=load("res://scenes/workshop.tscn").instantiate();root.add_child(app);await frames(12);app.presenter.duration_scale=0.04
	app.interaction.install_requested.connect(func(r):requests.append(r.duplicate(true)))
	await choose("beam_end");await mouse(app.tray.get_global_rect().get_center(),true);await move(slot(0))
	var source_mesh=app.presenter.meshes.Beam_Front_01.mesh
	check(carry_ok("beam_end",source_mesh),"press locks beam_end source mesh")
	var source_basis:Basis=app.presenter.preview.basis
	for i in [9,1,10,15,4]:
		await move(slot(i))
		check(carry_ok("beam_end",source_mesh),"sweep target "+str(i+1)+" retains source geometry while preview may align pose")
		check(app.interaction.hover_slot_id==app.data.steps[i].slot.id,"hover reports actual target "+str(i+1))
		if i==1 or i==10 or i==15:check(app.presenter.preview.material_override.albedo_color.g<0.7,"incompatible target cannot show green")
		if i==10 and not OS.get_cmdline_user_args().is_empty():
			await RenderingServer.frame_post_draw
			var saved=root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("drag_identity_over_rod.png"))
			if saved!=OK:failed=true;push_error("Failed to save drag identity evidence")
	var outside=app.view.get_global_rect().position+Vector2(1160,90)
	await move(outside);check(carry_ok("beam_end",source_mesh) and app.interaction.hover_slot_id.is_empty(),"leaving targets clears hover without replacing source")
	var rod_card: int=0
	for index in range(app.data.tray_entries.size()):
		if app.data.tray_entries[index].id=="round_rod":rod_card=index;break
	await move(app.ui.cards[rod_card].get_global_rect().get_center());check(carry_ok("beam_end",source_mesh) and app.selected==0,"crossing rod tray card does not reselect source")
	app._choose(rod_card);check(app.selected==0 and carry_ok("beam_end",source_mesh),"selection refresh cannot replace held source")
	await move(slot(9));await mouse(slot(9),false)
	check(requests.back().inventory_type_id=="beam_end" and requests.back().slot_id=="slot_10","release uses locked source and current legal target")
	check(app.session.availability("beam_end").remaining==4,"pending animation has not consumed source")
	await settled();check(app.session.placements.get("slot_10")=="beam_end" and app.session.availability("beam_end").remaining==3 and clean(),"legal commit consumes once and clears drag state")
	await choose("beam_end");await mouse(app.tray.get_global_rect().get_center(),true);await move(slot(9))
	check(carry_ok("beam_end",source_mesh) and app.presenter.preview.material_override.albedo_color.g<0.7,"next drag over occupied target retains source and rejects snap")
	await move(slot(1));await mouse(slot(1),false)
	check(app.session.placements.size()==1 and app.session.availability("beam_end").remaining==3 and clean(),"incompatible release consumes nothing and clears preview")
	await choose("beam_flank");await mouse(app.tray.get_global_rect().get_center(),true);await move(slot(1))
	check(carry_ok("beam_flank",app.presenter.meshes.Beam_Front_02.mesh),"next distinct type starts its own stable geometry")
	await mouse(slot(1),false);await settled();check(app.session.placements.get("slot_02")=="beam_flank" and app.session.availability("beam_flank").remaining==3,"next type commits only its own inventory")
	for mode in ["escape","observe","reset"]:
		await choose("beam_end");await mouse(app.tray.get_global_rect().get_center(),true);await move(slot(0))
		if mode=="escape":await key(KEY_ESCAPE)
		elif mode=="observe":app._toggle_observe();await frames();app._toggle_observe()
		else:app.reset_workshop()
		await frames();check(clean(),mode+" clears source lock, target and preview")
		await mouse(outside,false);check(not app.session.is_busy(),mode+" late release submits nothing")
	check(app.session.placements.is_empty() and app.session.availability("beam_end").remaining==4,"reset restores original stock")
	# The newly verified central pair shares stock; hovering never replaces its source mesh.
	await choose("beam_crown");await mouse(app.tray.get_global_rect().get_center(),true);await move(slot(7))
	check(carry_ok("beam_crown",app.presenter.meshes.Beam_Front_03.mesh) and app.presenter.preview.material_override.albedo_color.g>0.7,"certified back centre accepts same locked centre stock without switching mesh")
	await key(KEY_ESCAPE);await mouse(outside,false)
	if not failed:print("DRAG_IDENTITY_ALL_PASS checks=",checks,"; input=Godot-events; physical_mouse=untested; touch=untested")
	quit(1 if failed else 0)
