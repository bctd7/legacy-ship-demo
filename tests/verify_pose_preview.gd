extends SceneTree
var app
var failed=false
var checks=0
func _initialize() -> void:call_deferred("run")
func frames(n:int=3) -> void:
	for i in range(n):await process_frame
func settle_pose() -> void:await create_timer(0.22).timeout
func check(ok:bool,label:String) -> void:
	checks+=1
	if ok:print("POSE_PASS: ",label)
	else:failed=true;push_error("POSE_FAILED: "+label)
func mouse(p:Vector2,down:bool) -> void:
	var e=InputEventMouseButton.new();e.position=root.get_final_transform()*p;e.global_position=e.position;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(e);await process_frame
func move(p:Vector2) -> void:
	var e=InputEventMouseMotion.new();e.position=root.get_final_transform()*p;e.global_position=e.position;e.button_mask=MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(e);await process_frame
func slot(i:int) -> Vector2:return app.view.get_global_rect().position+app.camera.unproject_position(app.Rules.vector(app.data.steps[i].slot.anchor_m))
func angle(a:Basis,b:Basis) -> float:return a.get_rotation_quaternion().angle_to(b.get_rotation_quaternion())
func saved_pose(slot_id:String) -> Transform3D:return app.presenter.mapped_source_pose(slot_id).pose
func source_preview_count(mesh) -> int:
	var count=0
	for node in app.presenter.get_children():
		if node is MeshInstance3D and node.mesh==mesh and node.is_visible_in_tree():count+=1
	return count
func follows_pointer(p:Vector2) -> bool:
	var world=app.presenter.preview.transform*app.presenter.preview_source_anchor
	var screen=app.view.get_global_rect().position+app.camera.unproject_position(world)
	var normal=app.camera.global_basis.z
	var origin=app.Rules.vector(app.interaction.drag_source.origin_slot.anchor_m)
	return screen.distance_to(p)<0.75 and absf(normal.dot(world-origin))<0.00001
func finish() -> void:
	var n=0
	while app.session.is_busy() and n<300:await process_frame;n+=1
	check(not app.session.is_busy(),"original installation finished within finite budget")
func capture() -> void:
	if OS.get_cmdline_user_args().is_empty():return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("single_pointer_preview.png"))==OK,"save single pointer preview evidence")
func run() -> void:
	root.size=Vector2i(1400,900);app=load("res://scenes/workshop.tscn").instantiate();root.add_child(app);await frames(12)
	app.presenter.duration_scale=0.4
	app._choose(0);await frames();await mouse(app.tray.get_global_rect().get_center(),true);await move(slot(0));await settle_pose()
	var mesh=app.presenter.meshes.Beam_Front_01.mesh
	var p0:Transform3D=saved_pose("slot_01")
	check(app.presenter.preview.mesh==mesh and source_preview_count(mesh)==1,"exactly one visible locked source preview")
	check(app.presenter.preview_source_anchor.is_equal_approx(mesh.get_aabb().get_center()),"world-baked source rotates around its actual geometry centre")
	check(angle(app.presenter.preview.basis,p0.basis)<0.001,"original-facing source uses certified orientation")
	check(follows_pointer(slot(0)) and not app.presenter.hoist.visible,"held source follows pointer plane with no overhead rendering")
	var before:Basis=app.presenter.preview.basis
	await move(slot(9))
	check(app.presenter.preview.mesh==mesh and angle(before,app.presenter.preview.basis)<2.8,"opposite target eases rotation without switching mesh")
	check(follows_pointer(slot(9)),"rotation immediately preserves pointer position")
	await settle_pose()
	var opposite:Transform3D=saved_pose("slot_10")
	check(angle(p0.basis,opposite.basis)>3.1 and opposite.basis.determinant()>0.999,"opposite end target uses certified proper half turn")
	check(angle(app.presenter.preview.basis,opposite.basis)<0.001,"single source reaches target direction")
	check(source_preview_count(mesh)==1 and follows_pointer(slot(9)),"settled target pose never moves source to high entry or adds a duplicate")
	await capture()
	var source_origin=app.interaction.selection.origin_slot.duplicate(true)
	var radius=(app.camera.unproject_position(app.Rules.vector(app.data.steps[9].slot.anchor_m)+app.camera.global_basis.x*0.036)-app.camera.unproject_position(app.Rules.vector(app.data.steps[9].slot.anchor_m))).length()
	var edge=slot(9)+Vector2(radius*1.08,0)
	await move(edge);await settle_pose()
	check(app.interaction.hover_target.id=="slot_10" and app.presenter.preview_target_slot=="slot_10","candidate exit band retains target orientation")
	check(follows_pointer(edge),"hysteresis never pulls preview position away from pointer")
	await move(slot(1));await settle_pose()
	check(app.presenter.preview.mesh==mesh and app.presenter.preview.basis.is_equal_approx(Basis.IDENTITY),"incompatible target restores pickup direction without replacing source")
	check(follows_pointer(slot(1)) and source_preview_count(mesh)==1 and app.presenter.mapped_source_pose("slot_02").is_empty(),"incompatible target retains one pointer-following preview")
	check(app.interaction.selection.origin_slot==source_origin,"target changes preserve origin identity")
	var outside=app.view.get_global_rect().position+Vector2(1170,85)
	await move(outside);await settle_pose()
	check(app.presenter.preview.basis.is_equal_approx(Basis.IDENTITY) and follows_pointer(outside),"leaving targets returns direction but remains on pointer plane")
	await move(slot(4));await settle_pose()
	check(app.interaction.hover_slot_id=="slot_05" and angle(app.presenter.preview.basis,saved_pose("slot_05").basis)<0.001 and follows_pointer(slot(4)),"another opposite target changes orientation only")
	var tracking=true
	for t in [0.0,0.25,0.5,0.75,1.0]:
		var point=slot(4).lerp(slot(9),t);await move(point)
		tracking=tracking and follows_pointer(point) and source_preview_count(mesh)==1 and not app.presenter.hoist.visible
	check(tracking,"continuous sweep stays on pointer plane and never renders high-entry duplicate")
	await move(slot(9));await settle_pose()
	var release_basis=app.presenter.preview.basis
	await mouse(slot(9),false)
	check(app.presenter.preview.mesh==mesh and angle(release_basis,app.presenter.preview.basis)<0.001,"legal release retains source and final direction")
	var offset=app.presenter.preview.position-opposite.origin
	check(offset.y>0.30 and offset.y<=0.35001 and app.interaction.drag_source.is_empty(),"only after release original high-entry installation starts")
	check(app.session.availability("beam_end").remaining==4 and app.session.is_busy(),"inventory remains unchanged during original install animation")
	var ticks=0;var direction_stable=true;var path_stable=true
	while app.session.is_busy() and ticks<300:
		direction_stable=direction_stable and angle(app.presenter.preview.basis,opposite.basis)<0.001
		offset=app.presenter.preview.position-opposite.origin
		path_stable=path_stable and absf(offset.x)<0.00001 and absf(offset.z)<0.00001 and offset.y>=-0.00001 and offset.y<=0.35001
		await process_frame;ticks+=1
	check(direction_stable and path_stable,"released source follows original full validated path and direction")
	check(app.session.placements.get("slot_10")=="beam_end" and app.session.availability("beam_end").remaining==3,"legal completion consumes exactly one unit")
	check(not app.presenter.preview.visible and source_preview_count(mesh)==0,"commit clears transient preview")
	app._choose(0);await frames();await mouse(app.tray.get_global_rect().get_center(),true);await move(slot(0));await settle_pose();await move(slot(4))
	check(follows_pointer(slot(4)),"early-release setup is still on pointer plane while turning")
	await mouse(slot(4),false)
	check(app.presenter.active.has("source_pose") and app.presenter.preview.mesh==mesh and app.session.availability("beam_end").remaining==3,"early release enters original install only after validation without changing inventory identity")
	await finish();check(app.session.placements.get("slot_05")=="beam_end" and app.session.availability("beam_end").remaining==2,"early release commits once through original animation")
	app._choose(0);await frames();await mouse(app.tray.get_global_rect().get_center(),true);await move(slot(9));await settle_pose()
	check(app.presenter.preview.mesh==mesh and follows_pointer(slot(9)) and app.presenter.preview_target_slot.is_empty(),"occupied target never changes source or starts high preview")
	await mouse(slot(9),false);check(not app.session.is_busy() and app.session.placements.size()==2 and app.session.availability("beam_end").remaining==2,"occupied release cannot start installation or consume stock")
	app.reset_workshop();await frames()
	check(not app.presenter.preview.visible and not app.presenter.hoist.visible and app.interaction.drag_source.is_empty(),"reset clears preview and target state")
	check(not app.presenter.has_method("final_approach"),"temporary shortened-path experiment is absent from delivered logic")
	if not failed:print("POSE_PREVIEW_ALL_PASS checks=",checks,"; input=Godot-events; physical_mouse=untested; touch=untested")
	quit(1 if failed else 0)
