extends SceneTree
var app
var failed=false
var checks=0
func _initialize() -> void:call_deferred("run")
func frames(n:int=3) -> void:
	for i in range(n):await process_frame
func check(ok:bool,label:String) -> void:
	checks+=1
	if ok:print("CENTRE_PASS: ",label)
	else:failed=true;push_error("CENTRE_FAILED: "+label)
func mouse(p:Vector2,down:bool) -> void:
	var e=InputEventMouseButton.new();e.position=root.get_final_transform()*p;e.global_position=e.position;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e);await process_frame
func move(p:Vector2) -> void:
	var e=InputEventMouseMotion.new();e.position=root.get_final_transform()*p;e.global_position=e.position;e.button_mask=MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e);await process_frame
func choose() -> void:
	for i in range(app.data.tray_entries.size()):
		if app.data.tray_entries[i].id=="beam_crown":app._choose(i);break
	await frames()
func screen(point:Vector3) -> Vector2:return app.view.get_global_rect().position+app.camera.unproject_position(point)
func begin(point:Vector3) -> Vector2:
	await choose();await mouse(app.tray.get_global_rect().get_center(),true);var p=screen(point);await move(p);return p
func stable(p:Vector2) -> bool:
	var world=app.presenter.preview.transform*app.presenter.preview_source_anchor
	var projected=app.view.get_global_rect().position+app.camera.unproject_position(world)
	return app.interaction.drag_source.get("item_id")=="beam_crown" and app.presenter.preview.mesh==app.presenter.meshes.Beam_Front_03.mesh and projected.distance_to(p)<0.75 and not app.presenter.hoist.visible
func finish() -> void:
	var n=0
	while app.session.is_busy() and n<300:await process_frame;n+=1
	if app.session.is_busy():failed=true;push_error("CENTRE_FAILED: finite animation budget");quit(1)
func request(slot_id:String,point:Vector3) -> Dictionary:return {"inventory_type_id":"beam_crown","slot_id":slot_id,"release_m":[point.x,point.y,point.z],"expected_revision":app.session.revision}
func run() -> void:
	root.size=Vector2i(1400,900);app=load("res://scenes/workshop.tscn").instantiate();root.add_child(app);await frames(12);app.presenter.duration_scale=0.08
	var proof=JSON.parse_string(FileAccess.get_file_as_string("res://content/luban_bridge/reference/centre_beam_equivalence.json"))
	check(proof.equivalence_confirmed and proof.all_face_projected_coverage.forward["pass"] and proof.all_face_projected_coverage.backward["pass"],"both directions of full actual triangle-face coverage pass")
	check(proof.proper_rotation_determinant==1 and absf(proof.translation_m[2]+0.21)<0.000001,"equivalence is proper rigid translation without mirror or scale")
	check(app.data.inventory_types.size()==7 and app.session.availability("beam_crown").remaining==2 and app.session.rules.type_for("unique_Beam_Back_03").is_empty(),"one centre type has two stock units and no duplicate old card")
	var empty:Dictionary=app.session.snapshot()
	for i in [2,7]:
		var step:Dictionary=app.data.steps[i];var centre=app.presenter.meshes[step.part_id].mesh.get_aabb().get_center()
		for offset in [-0.095,0.0,0.095]:
			app.session.restore(empty);await frames()
			var point=centre+Vector3(offset,0.006 if offset!=0 else 0,0)
			var p=await begin(point)
			check(app.interaction.hover_slot_id==step.slot.id and app.presenter.preview.material_override.albedo_color.g>0.7,"visible centre/edge "+str(offset)+" selects "+step.slot.id)
			check(stable(p),"expanded segment capture preserves one source and pointer plane")
			await mouse(p,false)
			check(app.session.is_busy() and app.session.availability("beam_crown").remaining==2 and app.presenter.active.step.path.from_m==step.path.from_m,"accepted centre starts original path without early consumption")
			await finish()
			check(app.session.placements.get(step.slot.id)=="beam_crown" and app.session.availability("beam_crown").remaining==1,"front/back completion consumes one shared unit")
			check(not app.session.request_install(request(step.slot.id,centre)).ok and app.session.availability("beam_crown").remaining==1,"occupied centre rejects duplicate and double consumption")
	app.session.restore(empty);await frames()
	for i in [7,2]:
		var step:Dictionary=app.data.steps[i];var c=app.presenter.meshes[step.part_id].mesh.get_aabb().get_center();var p=await begin(c)
		check(stable(p) and app.interaction.hover_slot_id==step.slot.id,"same stock card can fill back then front")
		if i==7 and not OS.get_cmdline_user_args().is_empty():
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("centre_beam_interchange.png"))==OK,"save centre interchange evidence")
		await mouse(p,false);await finish()
	check(app.session.placements.size()==2 and app.session.availability("beam_crown").remaining==0,"two target slots exhaust exactly two centre units")
	# Schema 3 snapshots from the prior type policy migrate only their formerly legal slot mappings.
	var legacy:Dictionary=empty.duplicate(true);legacy.ruleset_version="inventory_slots_1";legacy.placements={"slot_03":"beam_crown","slot_08":"unique_Beam_Back_03"}
	check(app.session.restore(legacy).ok and app.session.placements=={"slot_03":"beam_crown","slot_08":"beam_crown"} and app.session.availability("beam_crown").remaining==0,"old front/back inventory snapshot migrates to canonical shared type")
	check(legacy.placements.slot_08=="unique_Beam_Back_03" and app.session.snapshot().ruleset_version=="inventory_slots_2","migration does not mutate caller and saves current rule version")
	var bad:Dictionary=legacy.duplicate(true);bad.placements={"slot_03":"unique_Beam_Back_03"}
	check(not app.session.restore(bad).ok,"formerly invalid old back type in front slot remains rejected")
	bad=legacy.duplicate(true);bad.placements={"slot_08":"beam_crown"}
	check(not app.session.restore(bad).ok,"formerly invalid old front type in back slot remains rejected")
	var older={"schema":2,"content_id":app.data.id,"content_version":app.data.version,"completed_ids":["Beam_Front_03","Beam_Back_03"]}
	check(app.session.restore(older).ok and app.session.availability("beam_crown").remaining==0,"schema2 original part IDs still restore both centres")
	app.session.restore(empty);await frames()
	for i in [1,3,6,8]:
		var step:Dictionary=app.data.steps[i];var p=await begin(app.Rules.vector(step.slot.anchor_m))
		check(not app.interaction.hover_target.get("allowed",true),"adjacent different-spec slot "+step.slot.id+" is not captured as centre")
		await mouse(p,false)
		check(app.session.placements.is_empty() and app.session.availability("beam_crown").remaining==2,"adjacent slot release leaves shared stock untouched")
	var p=await begin(app.presenter.meshes.Beam_Back_03.mesh.get_aabb().get_center())
	var e=InputEventKey.new();e.keycode=KEY_ESCAPE;e.pressed=true;Input.parse_input_event(e);await frames();await mouse(p,false)
	check(app.interaction.drag_source.is_empty() and not app.presenter.preview.visible and app.session.availability("beam_crown").remaining==2,"cancel clears centre source and leaves both units")
	app.reset_workshop();await frames();check(app.session.placements.is_empty() and app.session.availability("beam_crown").remaining==2,"reset restores both shared centre units")
	if not failed:print("CENTRE_BEAMS_ALL_PASS checks=",checks,"; input=Godot-events; physical_mouse=untested; touch=untested")
	quit(1 if failed else 0)
