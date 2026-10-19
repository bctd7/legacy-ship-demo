extends SceneTree
var app
var failed=false
var checks=0
func _initialize() -> void:call_deferred("run")
func frames(n:int=3) -> void:
	for i in range(n):await process_frame
func check(ok:bool,label:String) -> void:
	checks+=1
	if ok:print("SURFACE_PASS: ",label)
	else:failed=true;push_error("SURFACE_FAILED: "+label)
func mouse(p:Vector2,down:bool) -> void:
	var e=InputEventMouseButton.new();e.position=root.get_final_transform()*p;e.global_position=e.position;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e);await process_frame
func move(p:Vector2) -> void:
	var e=InputEventMouseMotion.new();e.position=root.get_final_transform()*p;e.global_position=e.position;e.button_mask=MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e);await process_frame
func screen(v:Array) -> Vector2:return app.view.get_global_rect().position+app.camera.unproject_position(app.Rules.vector(v))
func choose(id:String) -> void:
	id=app.session.rules.display_item_for_type(id)
	for i in range(app.data.tray_entries.size()):
		if app.data.tray_entries[i].id==id:app._choose(i);break
	await frames()
func finish() -> void:
	var n=0
	while app.session.is_busy() and n<300:await process_frame;n+=1
	if app.session.is_busy():failed=true;push_error("SURFACE_FAILED: finite animation budget");quit(1)
func request(i:int,point:Array=[]) -> Dictionary:
	var step:Dictionary=app.data.steps[i]
	return {"inventory_type_id":app.data.slot_type_map[step.slot.id],"slot_id":step.slot.id,"release_m":step.slot.anchor_m if point.is_empty() else point,"expected_revision":app.session.revision}
func prepare(i:int) -> void:
	var result:Dictionary=app.session.request_install(request(i))
	if not result.ok:failed=true;push_error("SURFACE_FAILED: fixture preparation "+result.message);quit(1);return
	await finish()
func begin(id:String,point:Array) -> Vector2:
	await choose(id);await mouse(app.tray.get_global_rect().get_center(),true)
	var p=screen(point);await move(p);return p
func source_stable(id:String,p:Vector2) -> bool:
	id=app.session.rules.display_item_for_type(id)
	var common:Mesh=app.presenter.common_preview_mesh(id)
	var source_mesh:Mesh=common if common!=null else app.presenter.meshes[app.session.rules.type_for(id).representative_part_id].mesh
	var world=app.presenter.preview.transform*app.presenter.preview_source_anchor
	var projected=app.view.get_global_rect().position+app.camera.unproject_position(world)
	return app.interaction.drag_source.get("item_id")==id and app.presenter.preview.mesh==source_mesh and projected.distance_to(p)<0.75
func capture() -> void:
	if OS.get_cmdline_user_args().is_empty():return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("deck_surface_interchange.png"))==OK,"save deck surface evidence")
func run() -> void:
	root.size=Vector2i(1400,900);app=load("res://scenes/workshop.tscn").instantiate();root.add_child(app);await frames(12);app.presenter.duration_scale=0.08
	var certificate=JSON.parse_string(FileAccess.get_file_as_string("res://content/luban_bridge/reference/placement_geometry_certificate.json"))
	check(certificate.deck_geometry.size()==5 and certificate.pair_checks.size()==2,"five actual deck geometries checked with two rigid-equivalent pairs")
	check(absf(certificate.deck_geometry[0].foot_centre_span_mm-150)<0.001 and absf(certificate.deck_geometry[1].foot_centre_span_mm-180)<0.001 and absf(certificate.deck_geometry[2].foot_centre_span_mm-210)<0.001,"actual foot spans remain 150,180,210mm behind unified operation card")
	for i in range(10):await prepare(i)
	var beams:Dictionary=app.session.snapshot()
	var deck:Dictionary=app.data.steps[15]
	var p:Vector2=await begin("deck_narrow_support",deck.slot.trigger_points_m[0])
	check(not app.interaction.hover_target.get("allowed",true) and source_stable("deck_narrow_support",p),"deck centre before rods remains dependent with stable source")
	await mouse(p,false)
	check(app.session.placements.size()==10 and app.session.availability("deck_narrow_support").remaining==2,"missing dependency rejects deck placement without stock consumption")
	for i in range(10,15):
		var step:Dictionary=app.data.steps[i]
		var left:Array=step.slot.trigger_points_m[0];var right:Array=step.slot.trigger_points_m[1]
		check(absf(left[2]+right[2])<0.000001 and absf(left[0]-right[0])<0.000001 and absf(left[1]-right[1])<0.000001,"rod "+str(i-9)+" actual endpoints are symmetric")
		for side in range(2):
			app.session.restore(beams);await frames()
			p=await begin("round_rod",step.slot.trigger_points_m[side])
			check(app.interaction.hover_slot_id==step.slot.id and app.presenter.preview.material_override.albedo_color.g>0.7,"rod "+str(i-9)+" side "+str(side)+" triggers same intended slot")
			check(source_stable("round_rod",p),"rod endpoint retains source mesh and pointer-following preview")
			await mouse(p,false)
			check(app.session.is_busy() and app.presenter.active.step.path.from_m==step.path.from_m and app.Rules.vector(step.path.from_m).z<0,"both sides start original verified negative-z path only after release")
			await finish()
			check(app.session.placements.get(step.slot.id)=="round_rod" and app.session.availability("round_rod").remaining==4,"endpoint completion occupies one slot and consumes one unit")
			check(not app.session.request_install(request(i,step.slot.trigger_points_m[1-side])).ok and app.session.availability("round_rod").remaining==4,"opposite-side repeat rejects duplicate slot and double consumption")
	app.session.restore(beams);await frames()
	for i in range(10,15):await prepare(i)
	var frame:Dictionary=app.session.snapshot()
	for i in [18,15,19,16,17]:
		var step:Dictionary=app.data.steps[i];var type_id:String=app.data.slot_type_map[step.slot.id]
		p=await begin(type_id,step.slot.trigger_points_m[0]);await create_timer(0.20).timeout
		check(app.interaction.hover_slot_id==step.slot.id and app.presenter.preview.material_override.albedo_color.g>0.7,"deck "+step.part_id+" actual surface centre selects intended compatible slot")
		check(source_stable(type_id,p),"deck operation keeps shared panel mesh and pointer centre")
		var pose:Transform3D=app.presenter.mapped_source_pose(step.slot.id).pose
		check(app.presenter.preview.basis.get_rotation_quaternion().angle_to(pose.basis.get_rotation_quaternion())<0.001,"deck target previews its rigid orientation")
		if i==18:await capture()
		var before:int=app.session.availability(type_id).remaining
		await mouse(p,false);await finish()
		check(app.session.placements.get(step.slot.id)==type_id and app.session.availability(type_id).remaining==before-1,"deck completion consumes selected type exactly once")
		check(not app.session.request_install(request(i,step.slot.trigger_points_m[0])).ok,"occupied deck surface rejects repeated install")
	check(app.session.placements.size()==20 and app.session.availability("deck_narrow_support").remaining==0 and app.session.availability("deck_mid_support").remaining==0,"both interchangeable pairs fill opposite-order slots without fixed source binding")
	app.session.restore(frame);await frames()
	var wrong=request(16,app.data.steps[16].slot.trigger_points_m[0]);wrong.inventory_type_id="deck_narrow_support"
	check(not app.session.request_install(wrong).ok,"direct real-type request still rejects incompatible foot spacing")
	check(app.session.placements.size()==15 and app.session.availability("deck").remaining==5,"rejected real-type request leaves unified deck stock unchanged")
	app.reset_workshop();await frames()
	check(app.session.placements.is_empty() and app.interaction.drag_source.is_empty() and not app.presenter.preview.visible and app.session.availability("round_rod").remaining==5,"reset clears trigger state and restores stock")
	if not failed:print("SURFACE_TARGETS_ALL_PASS checks=",checks,"; input=Godot-events; physical_mouse=untested; touch=untested")
	quit(1 if failed else 0)
