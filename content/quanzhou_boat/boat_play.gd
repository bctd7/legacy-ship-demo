extends Control
## Boat-owned presenter and rules, using the accepted generic pointer module.
signal completed(snapshot: Dictionary)
const Drag = preload("res://content/quanzhou_boat/boat_drag.gd")
const Style = preload("res://content/quanzhou_boat/visual_polish/bridge_style.gd")
const Surface = preload("res://content/quanzhou_boat/visual_polish/bridge_surface.gd")
const Orbit = preload("res://content/quanzhou_boat/boat_camera.gd")
const DropZone = preload("res://content/quanzhou_boat/drop_zone.gd")
const ContextWood = preload("res://content/quanzhou_boat/wood_context.gdshader")
var groups: Array = []
var cameras: Dictionary
var placed: Array[String] = []
var history: Array[String] = []
var revision := 0
var selected := ""
var mode := "overview"
var joint_index := 0
var cards: Dictionary = {}
var group_nodes: Dictionary = {}
var bounds: Dictionary = {}
var slots: Dictionary = {}
var view: SubViewportContainer
var viewport: SubViewport
var world: Node3D
var boat: Node3D
var joint: Node3D
var moving: Node3D
var moving_home: Vector3
var camera: Camera3D
var orbit
var drag
var panel: BoxContainer
var message: Label
var disclosure: Label
var progress: Label
var preview: MeshInstance3D
var target: MeshInstance3D
var joint_slider: HSlider
var split_button: Button
var returning_camera: Dictionary = {}
var frame_samples: Array[float] = []
var wood_materials: Dictionary = {}
var card_captions: Dictionary = {}
var card_pictures: Dictionary = {}
var mesh_lookup: Dictionary = {}
var step_card: PanelContainer
var connection_label: Label
var source_label: Label
var skip_button: Button
var return_button: Button
var cut_button: Button
var replay_button: Button
var preview_group: Node3D
var preview_goal := Vector3.ZERO
var preview_anchor := Vector3.ZERO
var preview_initialized := false
var lesson_id := ""
var pending_id := ""
var lesson_phase := ""
var lesson_tween: Tween
var lesson_homes: Dictionary = {}
var lesson_materials: Array[ShaderMaterial] = []
var lesson_nails: Node3D
var lesson_trace: Array = []
var lesson_generation := 0
var cutaway := false
var last_lesson_id := ""
var fixed_guide: Node3D
var guide_label: Label
var guide_id := ""
var preview_grab_center := Vector3.ZERO
var guide_outline: MeshInstance3D
var lesson_return_timer: Timer
var lesson_is_install := false
var drop_rules: Dictionary
var selected_drop_slot: Dictionary = {}
var drop_zone: Control
var zoom_bar: HBoxContainer
var thumbnail_grab_maps: Dictionary = {}
var preview_grab_point := Vector3.ZERO
var lesson_stage := ""
var lesson_detail := false
var lesson_user_inspecting := false
var lesson_focus := Vector3.ZERO
var lesson_standoff := Vector3.ZERO
var lesson_camera_goal: Dictionary = {}
var lesson_context_materials: Array[ShaderMaterial] = []
var lesson_hidden_nails: Dictionary = {}
var nail_trace: Array = []
var lesson_context_opacity := 1.0

func _ready() -> void:
	var assembly: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/quanzhou_boat/config/assembly.json"))
	groups = assembly.groups
	drop_rules = assembly.get("drop_tolerance",{"min_radius_px":56.0,"max_radius_px":96.0})
	cameras = JSON.parse_string(FileAccess.get_file_as_string("res://content/quanzhou_boat/config/cameras.json"))
	_build_ui()
	_build_world()
	drag = Drag.new()
	drag.camera = camera
	drag.view = view
	drag.tray = panel
	drag.presenter = self
	drag.orbit = orbit
	drag.card_lookup = _card_at
	drag.pointer_blocked = _pointer_blocked
	drag.part_picked.connect(_select)
	drag.install_requested.connect(_install)
	drag.drag_changed.connect(_drag_status)
	drag.cancel_requested.connect(_escape)
	drag.view_action_started.connect(_view_action_started)
	add_child(drag)
	lesson_return_timer = Timer.new()
	lesson_return_timer.one_shot = true
	lesson_return_timer.wait_time = 0.9
	lesson_return_timer.timeout.connect(_automatic_lesson_return)
	add_child(lesson_return_timer)
	set_mode("assembly")
	_bake_thumbnails.call_deferred()

func _process(delta: float) -> void:
	if frame_samples.size() < 600 and delta > 0: frame_samples.append(delta)
	if preview_group and preview_group.visible and preview_initialized:
		preview_group.position = preview_group.position.lerp(preview_goal,1.0-exp(-delta*36.0))
	if guide_label and guide_label.visible and not guide_id.is_empty():
		var anchor := Drag.vector(slots[guide_id].anchor_m)
		guide_label.position = view.global_position+camera.unproject_position(anchor)+Vector2(-170,-62)
	orbit.zoom_focus_enabled = mode == "assembly" and not guide_id.is_empty()
	_update_drop_zone()

func _input(_event: InputEvent) -> void:
	pass # Mapping is owned by the shared adapter; retained as a test tracing hook.

func _view_action_started(_action: String) -> void:
	if mode=="lesson" and drag.camera_enabled:
		lesson_return_timer.stop()
		lesson_user_inspecting = true
		message.text = "已暂停自动返回；可继续观察，或直接拖下一张亮色构件。"

func _label(text: String, parent: Node, font_size := 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(text: String, parent: Node, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 48
	Style.button(b)
	b.pressed.connect(action)
	parent.add_child(b)
	return b

func _build_ui() -> void:
	self.theme = Style.theme()
	var bg := ColorRect.new()
	bg.color = Color("eae6df")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var title := _label("泉州宋船",self,30)
	title.position = Vector2(34,18)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size = Vector2(155,48)
	var subtitle := _label("木作装配  /  观察 · 拿起 · 连接",self,14)
	subtitle.position = Vector2(195,36)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_OFF
	subtitle.size = Vector2(300,28)
	Style.label(subtitle,"caption",true)
	var bar := HBoxContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	bar.offset_left = -705
	bar.offset_right = -28
	bar.offset_top = 20
	bar.offset_bottom = 68
	bar.add_theme_constant_override("separation",10)
	add_child(bar)
	_button("整船查看",bar,func(): set_mode("overview"))
	_button("分组装配",bar,func(): set_mode("assembly"))
	_button("撤回一步",bar,undo)
	_button("重置装配",bar,reset_assembly)
	_button("视角复位",bar,reset_camera)
	return_button = _button("返回整船",bar,leave_joint)
	view = SubViewportContainer.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.offset_top = 84
	view.offset_bottom = -220
	view.stretch = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1400,596)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.add_child(viewport)
	drop_zone = DropZone.new()
	drop_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drop_zone.clip_contents = true
	add_child(drop_zone)
	zoom_bar = HBoxContainer.new()
	zoom_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	zoom_bar.offset_left = -232; zoom_bar.offset_right = -26
	zoom_bar.offset_top = 96; zoom_bar.offset_bottom = 142
	add_child(zoom_bar)
	_button("＋ 放大",zoom_bar,func(): _zoom_camera(0.75))
	_button("－ 缩小",zoom_bar,func(): _zoom_camera(1.333333))
	step_card = PanelContainer.new()
	step_card.position = Vector2(34,106)
	step_card.custom_minimum_size.x = 264
	step_card.add_theme_stylebox_override("panel",Style.panel(Style.PAPER,20,16,true))
	add_child(step_card)
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 228
	info.add_theme_constant_override("separation",10)
	step_card.add_child(info)
	progress = _label("",info,14)
	Style.label(progress,"caption",true)
	connection_label = _label("观察整船",info,21)
	_label("左拖木件 / 空白旋转 · 右键旋转
中键平移 · 滚轮缩放
拖动下方木件，松手连接",info,14)
	source_label = _label("",info,13)
	Style.label(source_label,"caption",true)
	skip_button = _button("跳过镜头，继续装配",info,skip_lesson)
	replay_button = _button("重播上一步连接",info,replay_lesson)
	cut_button = _button("剖切 / 完整",info,toggle_cutaway)
	var options := OptionButton.new()
	Style.button(options)
	for c in cameras.joints: options.add_item(c.label)
	info.add_child(options)
	_button("单独观察所选接头",info,func(): show_joint(options.selected))
	split_button = _button("分离 / 合拢接触面",info,func(): joint_slider.value = 1.0 if joint_slider.value < 0.5 else 0.0)
	joint_slider = HSlider.new()
	joint_slider.min_value = 0
	joint_slider.max_value = 1
	joint_slider.step = 0.01
	joint_slider.value_changed.connect(_separate_joint)
	info.add_child(joint_slider)
	message = _label("",self,15)
	message.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	message.offset_left = 34
	message.offset_right = -34
	message.offset_top = -214
	message.offset_bottom = -184
	var tray := PanelContainer.new()
	tray.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tray.offset_left = 24
	tray.offset_right = -24
	tray.offset_top = -180
	tray.offset_bottom = -30
	tray.add_theme_stylebox_override("panel",Style.panel(Style.PAPER,12,18))
	add_child(tray)
	var tray_column := VBoxContainer.new()
	tray.add_child(tray_column)
	Style.label(_label("完整装配组 · 卡片、携带与安装同形；按住拖动，变绿后松手",tray_column,13),"caption",true)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tray_column.add_child(scroll)
	panel = HBoxContainer.new()
	panel.add_theme_constant_override("separation",8)
	scroll.add_child(panel)
	for g in groups:
		var b := _button("",panel,func(): _select(str(g.id)))
		b.custom_minimum_size = Vector2(138,94)
		b.mouse_filter = Control.MOUSE_FILTER_PASS
		var card := VBoxContainer.new()
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.offset_left = 8; card.offset_right = -8
		card.offset_top = 4; card.offset_bottom = -4
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(card)
		var pic := TextureRect.new()
		pic.custom_minimum_size = Vector2(120,52)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(pic)
		var caption := _label(g.label,card,13)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cards[g.id] = b
		card_captions[g.id] = caption
		card_pictures[g.id] = pic
	disclosure = _label("",self,12)
	Style.label(disclosure,"footnote",true)
	disclosure.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	disclosure.offset_left = 34
	disclosure.offset_right = -34
	disclosure.offset_top = -25
	disclosure.offset_bottom = -3
	resized.connect(func(): if viewport: viewport.size = Vector2i(maxi(1,int(view.size.x)),maxi(1,int(view.size.y))))

func _pointer_blocked(p: Vector2) -> bool:
	return not view.get_global_rect().has_point(p) or step_card.get_global_rect().has_point(p) or zoom_bar.get_global_rect().has_point(p)

func _build_world() -> void:
	world = Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("eae6df")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.48
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	environment.environment = env
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-62,-32,0)
	light.light_energy = 0.8
	light.light_color = Color(1,0.99,0.97)
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 12.0
	light.shadow_bias = 0.025
	world.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35,145,0)
	fill.light_energy = 0.28
	fill.shadow_enabled = false
	world.add_child(fill)
	Surface.lighting(env,light,fill,12.0)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	ground.mesh = plane
	ground.position.y = -0.035
	ground.material_override = Surface.ground_material()
	world.add_child(ground)
	camera = Camera3D.new()
	camera.fov = 42
	camera.near = 0.01
	camera.far = 100
	world.add_child(camera)
	orbit = Orbit.new(camera,_camera_settings(cameras.overview))
	boat = _load_model("res://content/quanzhou_boat/assets/quanzhou_complete.glb")
	world.add_child(boat)
	_restore_wood(boat,0.1)
	for mesh in _meshes(boat): mesh_lookup[str(mesh.name)] = mesh
	_seat_source_nails()
	for g in groups:
		var nodes: Array = []
		var box := AABB()
		var first := true
		for root_name in g.roots:
			var n := boat.find_child(str(root_name), true, false) as Node3D
			if n == null: push_error("Missing boat root: " + str(root_name)); continue
			nodes.append(n)
		for mesh_name in g.get("mesh_members",[]):
			if not mesh_lookup.has(mesh_name): push_error("Missing boat member: " + str(mesh_name)); continue
			nodes.append(mesh_lookup[mesh_name])
		for n in nodes:
			for mesh in _meshes(n):
				var b: AABB = mesh.global_transform * mesh.get_aabb()
				box = b if first else box.merge(b)
				first = false
		group_nodes[g.id] = nodes
		bounds[g.id] = box
		var center: Vector3 = Drag.vector(g.anchor_m)
		if g.get("drop_anchor","") == "mesh_center": center = box.get_center()
		slots[g.id] = {"id":g.id,"anchor_m":[center.x,center.y,center.z],"radius_m":float(g.radius_m),"allowed":true}
		if g.get("drop_trigger_axis","") == "x":
			var points: Array = []
			for index in 5:
				points.append([lerpf(box.position.x,box.end.x,0.15+0.175*index),center.y,center.z])
			slots[g.id]["trigger_points_m"] = points
	preview = _marker(Color(1,0.72,0.3,0.65),0.01)
	preview_group = Node3D.new()
	world.add_child(preview_group)
	preview_group.visible = false
	target = _marker(Color(0.72,0.52,0.25,0.22),0.035)
	fixed_guide = Node3D.new()
	world.add_child(fixed_guide)
	guide_label = _label("",self,14)
	guide_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	guide_label.size = Vector2(340,46)
	guide_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	guide_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide_label.add_theme_color_override("font_color",Color("8a6a38"))
	reset_camera()

func _seat_source_nails() -> void:
	# Offline actual-triangle fit; only runtime node translations change.
	# Preserve head+shaft scale and axis, keep heads visible, never hide a nail set.
	var seating: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/quanzhou_boat/config/nail_seating.json"))
	for pair in seating.pairs:
		var delta := Drag.vector(pair.delta_world_m)
		for name_value in [pair.shank,pair.head]:
			var node: MeshInstance3D = mesh_lookup.get(name_value)
			if node==null or node.has_meta("nail_raw_transform"): continue
			node.set_meta("nail_raw_transform",node.global_transform)
			node.set_meta("nail_seating_delta",delta)
			node.position += node.get_parent_node_3d().global_basis.inverse()*delta

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D: result.append(node)
	for child in node.get_children(): result.append_array(_meshes(child))
	return result

func _load_model(path: String) -> Node3D:
	# Runtime glTF parsing makes the standalone launcher work before editor import.
	# It does not scan/reimport any other content package or shared directory.
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(path,state)
	if error != OK:
		push_error("Cannot open source model %s: %s" % [path,error_string(error)])
		return Node3D.new()
	return document.generate_scene(state)

func _restore_wood(root: Node, model_scale := 1.0) -> void:
	var palette: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/quanzhou_boat/config/materials.json"))
	for mesh in _meshes(root):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(surface)
			if source == null: continue
			if not palette.has(source.resource_name):
				if source is StandardMaterial3D and (source.resource_name.contains("linen") or source.resource_name.contains("rope") or source.resource_name.contains("cord")):
					var woven: StandardMaterial3D = source.duplicate()
					woven.albedo_color = Color("cfc0a2").srgb_to_linear() if source.resource_name.contains("linen") else Color("97805d").srgb_to_linear()
					woven.roughness = 0.94
					mesh.set_surface_override_material(surface,woven)
				continue
			var dimensions := mesh.get_aabb().size
			var axis := Vector3.RIGHT
			if dimensions.y > dimensions.x and dimensions.y > dimensions.z: axis = Vector3.UP
			elif dimensions.z > dimensions.x: axis = Vector3.BACK
			var key: String = source.resource_name + str(model_scale) + str(axis)
			if not wood_materials.has(key):
				var material := ShaderMaterial.new()
				material.shader = load("res://content/quanzhou_boat/wood.gdshader")
				material.set_shader_parameter("model_scale",model_scale)
				Surface.wood_parameters(material,key,axis)
				wood_materials[key] = material
			mesh.set_surface_override_material(surface,wood_materials[key])

func _marker(color: Color, radius: float) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	n.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	n.material_override = mat
	world.add_child(n)
	n.visible = false
	return n

func _group(id: String) -> Dictionary:
	for g in groups:
		if g.id == id: return g
	return {}

func _can_assemble(id: String) -> bool:
	if id in placed or not pending_id.is_empty(): return false
	for required in _group(id).get("requires", []):
		if required not in placed: return false
	return true

func _allowed(id: String) -> bool:
	return mode == "assembly" and _can_assemble(id)

func _card_at(point: Vector2) -> String:
	for id in cards:
		if not cards[id].get_global_rect().has_point(point) or not panel.get_parent().get_global_rect().has_point(point): continue
		# The generic pointer calls this before checking enabled. Returning from a
		# finished view here lets the very same press start the next real gesture.
		if mode == "lesson" and pending_id.is_empty() and _can_assemble(id): _leave_lesson(false,false,true)
		elif mode == "overview" and _can_assemble(id): set_mode("assembly")
		elif mode == "joint" and _can_assemble(id):
			leave_joint()
			if mode != "assembly": set_mode("assembly")
		if mode == "lesson":
			message.text = "正在连接，完成后自动继续；也可点击「跳过镜头」。"
			return ""
		return id if mode == "assembly" else ""
	return ""

func pointer_part_at(point: Vector2) -> Dictionary:
	var id := _card_at(point)
	if not id.is_empty(): return {"id":id,"operable":_allowed(id),"source":"card"}
	if _pointer_blocked(point) or mode!="assembly": return {}
	var local := point-view.global_position
	return _pick_operable_part(camera.project_ray_origin(local),camera.project_ray_normal(local))

func _pick_operable_part(origin: Vector3, direction: Vector3) -> Dictionary:
	if mode!="assembly" or guide_id.is_empty() or not _allowed(guide_id): return {}
	var nearest := INF
	var grab := Vector3.ZERO
	var found := false
	for mesh in _part_meshes(guide_id):
		var world_box: AABB = mesh.global_transform*mesh.get_aabb()
		if not _line_intersects_box(origin,origin+direction*100.0,world_box): continue
		var inverse := mesh.global_transform.affine_inverse()
		var local_origin := inverse*origin
		var local_direction := (inverse.basis*direction).normalized()
		var faces := mesh.mesh.get_faces()
		for index in range(0,faces.size(),3):
			var hit = Geometry3D.ray_intersects_triangle(local_origin,local_direction,faces[index],faces[index+1],faces[index+2])
			if hit==null: continue
			var world_hit: Vector3 = mesh.global_transform*hit
			var distance := origin.distance_squared_to(world_hit)
			if distance<nearest:
				nearest = distance
				grab = world_hit
				found = true
	return {"id":guide_id,"operable":true,"source":"scene","grab_world":grab} if found else {}

func _part_meshes(id: String) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for root in group_nodes[id]: result.append_array(_meshes(root))
	return result

func _drop_slot_for_camera(id: String) -> Dictionary:
	var slot: Dictionary = slots[id].duplicate(true)
	slot.trigger_points_m = [slot.anchor_m]
	var anchor := Drag.vector(slot.anchor_m)
	var pixels_per_metre := maxf((camera.unproject_position(anchor+camera.global_basis.x)-camera.unproject_position(anchor)).length(),1.0)
	var radius_pixels := clampf(float(slot.radius_m)*pixels_per_metre,float(drop_rules.min_radius_px),float(drop_rules.max_radius_px))
	slot.radius_m = radius_pixels/pixels_per_metre
	return slot

func _update_drop_zone() -> void:
	if not drop_zone: return
	drop_zone.visible = mode == "assembly" and not guide_id.is_empty() and fixed_guide.visible
	if not drop_zone.visible: return
	drop_zone.position = view.position
	drop_zone.size = view.size
	var slot := selected_drop_slot if drag and drag.held and not selected_drop_slot.is_empty() else _drop_slot_for_camera(guide_id)
	var points: Array[Vector2] = []
	var radii: Array[float] = []
	for value in slot.get("trigger_points_m",[slot.anchor_m]):
		var point := Drag.vector(value)
		if camera.is_position_behind(point): continue
		var screen := camera.unproject_position(point)
		points.append(screen)
		radii.append((camera.unproject_position(point+camera.global_basis.x*float(slot.radius_m))-screen).length())
	drop_zone.show_regions(points,radii,drag!=null and drag.dragging and drag.hover_slot_id==guide_id)

func _zoom_camera(amount: float) -> void:
	if drag.held or drag.gestures.owner in ["rotate","pan"]: return
	if not drag.camera_enabled:
		message.text = "镜头正在定位，稍后可放大；也可跳过镜头。"
		return
	if mode == "lesson":
		lesson_return_timer.stop()
		lesson_user_inspecting = true
	orbit.zoom(amount)

func connection_screen_point(pointer: Vector2) -> Vector2:
	var local := pointer-view.global_position
	var plane := Plane(camera.global_basis.z,camera.global_basis.z.dot(preview_grab_point))
	var hit = plane.intersects_ray(camera.project_ray_origin(local),camera.project_ray_normal(local))
	if hit == null: return pointer
	var moved_anchor: Vector3 = preview_anchor+hit-preview_grab_point
	return view.global_position+camera.unproject_position(moved_anchor)

func _select(id: String) -> void:
	if mode != "assembly": return
	selected = id
	var g := _group(id)
	var slot: Dictionary = _drop_slot_for_camera(id)
	slot.allowed = _allowed(id)
	selected_drop_slot = slot.duplicate(true)
	drag.choose(id,slot,slot.allowed,revision,{"mode":"place"},[slot])
	var requires: Array[String] = []
	for req in g.requires:
		if req not in placed: requires.append(_group(req).label)
	message.text = ("先完成：" + "、".join(requires)) if not requires.is_empty() else ("已安装，可撤回" if id in placed else "已选择 %s；将整组对齐金色轮廓，变绿后松手。%s" % [g.label,"板材按原位建造演示，不是整片刚体穿入。" if g.mode == "build" else "释放后归位，不演示未经验证的插入路径。"])

func _install(request: Dictionary) -> void:
	var id := str(request.get("inventory_type_id", ""))
	if int(request.get("expected_revision",-1)) != revision or not _allowed(id): return
	if request.get("slot_id", "") != id:
		message.text = "范围外释放，未安装；请把卡片拖入圆标。"
		return
	var release := Drag.vector(request.release_m)
	var legal := false
	if selected_drop_slot.get("id","") != id: return
	for point in selected_drop_slot.get("trigger_points_m",[selected_drop_slot.anchor_m]):
		if release.distance_to(Drag.vector(point)) <= float(selected_drop_slot.radius_m)+0.0001: legal = true
	if not legal:
		message.text = "还没进入金色装配轮廓，已退回托盘；变绿后松手。"
		return
	pending_id = id
	revision += 1
	drag.enabled = false
	message.text = "有效释放，正在对准连接处……"
	preview_group.visible = true
	_start_lesson.call_deferred(id,true,revision)

func set_mode(next: String) -> void:
	if mode == "lesson": _leave_lesson(true,false)
	if mode == "joint": leave_joint()
	mode = next
	if drag: drag.cancel(); drag.enabled = next == "assembly"
	selected = ""
	_refresh()
	disclosure.text = "展示复原包含假设性的甲板、帆索与舵装；不代表全部考古原貌。板材接缝需紧固与密封，并非全部自锁。"
	message.text = "完整模型查看：左键空白或右键旋转，中键平移，滚轮缩放。" if next == "overview" else "把亮色构件拖到固定金色轮廓；变绿后松手，单击不会安装。"

func _refresh() -> void:
	for g in groups:
		if mode != "lesson":
			for n in group_nodes.get(g.id,[]): n.visible = mode == "overview" or g.id in placed
		var available := _can_assemble(g.id) and (mode in ["assembly","overview","joint"] or (mode == "lesson" and pending_id.is_empty()))
		var state := "✓ " if g.id in placed else ("○ " if available else "· ")
		card_captions[g.id].text = state + str(g.label)
		cards[g.id].modulate = Color.WHITE
		Style.card(cards[g.id],"installed" if g.id in placed else ("selected" if g.id == selected else ("available" if available else "locked")))
		card_captions[g.id].add_theme_color_override("font_color",Style.INK if available else Style.MUTED)
		card_pictures[g.id].modulate = Color.WHITE if available else Color(0.8,0.73,0.66)
	progress.text = "整船展示 · %d 操作组 / 1286 网格" % groups.size() if mode == "overview" else "装配进度  %d / %d" % [placed.size(),groups.size()]
	preview.visible = false
	target.visible = false
	joint_slider.visible = mode == "joint"
	split_button.visible = mode == "joint"
	skip_button.visible = mode == "lesson"
	return_button.visible = mode in ["joint","lesson"]
	cut_button.visible = mode in ["joint","lesson"]
	cut_button.text = "遮挡渐隐 / 完整" if mode=="lesson" else "剖切 / 完整"
	replay_button.visible = mode == "assembly" and last_lesson_id in placed
	if mode not in ["joint","lesson"]:
		connection_label.text = "观察整船" if mode == "overview" else "拿起木件，连接船体"
		source_label.text = "按住下方构件拖到船上目标，松手后观察连接过程。"
	_sync_guide()

func undo() -> void:
	if mode == "lesson":
		var was_pending := not pending_id.is_empty()
		_leave_lesson(false,false)
		if was_pending:
			message.text = "已撤回本次连接，动画与镜头已停止。"
			return
	if mode == "joint": leave_joint()
	if history.is_empty(): message.text = "尚无可撤回的装配。"; return
	if drag: drag.cancel()
	var id: String = history.pop_back()
	placed.erase(id)
	revision += 1
	mode = "assembly"
	drag.enabled = true
	_refresh()
	message.text = "已撤回：" + str(_group(id).label)

func reset_assembly() -> void:
	if mode == "lesson": _leave_lesson(false,false)
	if mode == "joint": leave_joint()
	if drag: drag.cancel()
	pending_id = ""
	placed.clear()
	history.clear()
	revision += 1
	set_mode("assembly")
	reset_camera()

func _camera_settings(c: Dictionary, local_joint := false) -> Dictionary:
	return {"focus":_joint_center() if local_joint else Drag.vector(c.focus),"yaw":float(c.yaw),"pitch":float(c.pitch),"distance":float(c.distance),"distance_limits":Vector2(0.12,5.0) if local_joint else Vector2(float(c.min),float(c.max)),"pan_limit":float(cameras.navigation.joint_pan_limit_m if local_joint else cameras.navigation.pan_limit_m),"pitch_limits":Vector2(float(cameras.navigation.pitch_min_rad),float(cameras.navigation.pitch_max_rad))}

func reset_camera() -> void:
	if mode == "lesson":
		if not drag.camera_enabled: return
		_apply_step_camera(_group(lesson_id).lesson)
		lesson_user_inspecting = true
		lesson_return_timer.stop()
		return
	var c: Dictionary = cameras.joints[joint_index] if mode == "joint" else cameras.overview
	orbit = Orbit.new(camera,_camera_settings(c,mode=="joint"))
	orbit.reset_view()
	if drag: drag.orbit = orbit

func show_joint(index: int) -> void:
	if drag and drag.held: return
	if mode == "lesson": _leave_lesson(true,false)
	if mode != "joint":
		returning_camera = _camera_snapshot()
	if drag: drag.cancel(); drag.enabled = false
	if joint: joint.queue_free(); joint = null
	mode = "joint"
	joint_index = index
	boat.visible = false
	joint = _load_model(cameras.joints[index].path)
	world.add_child(joint)
	_restore_wood(joint)
	cutaway = false
	_set_section(false)
	moving = joint.find_child("Moving",true,false)
	if moving: moving_home = moving.position
	joint_slider.set_value_no_signal(0.65)
	_separate_joint(0.65)
	_refresh()
	disclosure.text = str(cameras.joints[index].note)
	message.text = "拖动滑杆分离接触面，右键旋转观察；点击「返回整船」恢复原视角与进度。"
	progress.text = str(cameras.joints[index].label) + (" · 互动扩展" if cameras.joints[index].extension else " · 原模型裁切")
	connection_label.text = str(cameras.joints[index].label)
	source_label.text = str(cameras.joints[index].note)
	reset_camera()

func _joint_center() -> Vector3:
	var box := AABB()
	var first := true
	for mesh in _meshes(joint):
		var b: AABB = mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.get_center()

func _separate_joint(value: float) -> void:
	if mode == "lesson" and pending_id.is_empty() and lesson_return_timer: lesson_return_timer.stop()
	if moving: moving.position = moving_home + Drag.vector(cameras.joints[joint_index].separation) * value

func leave_joint() -> void:
	if mode == "lesson":
		_leave_lesson(true)
		return
	if mode != "joint": return
	if joint: joint.queue_free(); joint = null; moving = null
	boat.visible = true
	cutaway = false
	_set_section(false)
	mode = returning_camera.get("mode","overview")
	orbit = Orbit.new(camera,_camera_settings(cameras.overview))
	drag.orbit = orbit
	orbit.focus = returning_camera.focus
	orbit.yaw = returning_camera.yaw
	orbit.pitch = returning_camera.pitch
	orbit.distance = returning_camera.distance
	orbit.min_distance = float(cameras.overview.min)
	orbit.max_distance = float(cameras.overview.max)
	orbit.update_view()
	drag.enabled = mode == "assembly"
	_refresh()
	disclosure.text = "板材按原位建造分组呈现；展示复原中含假设构件。桅脚直榫和柱梁方榫为互动扩展。"
	message.text = "已返回整船，原视角与装配进度保留。"

func _escape() -> void:
	if mode in ["joint","lesson"]: leave_joint()
	else: message.text = "已取消拖动。"

# Same source/hover protocol as the accepted bridge; stable actual mesh orientation.
func set_target(slot: Dictionary, allowed: bool, _behavior: Dictionary) -> void:
	if allowed: _show_guide(str(slot.id))
	else: _sync_guide()
func set_highlight(id: String) -> void:
	if not id.is_empty():
		connection_label.text = str(_group(id).lesson.title)
		source_label.text = str(_group(id).lesson.source_note)
func set_compatible_targets(_candidates: Array, _allowed_value: bool) -> void: pass
func begin_preview(id: String) -> void:
	for child in preview_group.get_children(): child.queue_free()
	preview_anchor = Drag.vector(slots[id].anchor_m)
	var carry_box := AABB()
	var first := true
	for source in _part_meshes(id):
		var source_box: AABB = source.global_transform*source.get_aabb()
		carry_box = source_box if first else carry_box.merge(source_box)
		first = false
		var copy := MeshInstance3D.new()
		copy.mesh = source.mesh
		copy.set_meta("source_mesh_name",str(source.name))
		copy.transform = source.global_transform
		for surface in source.mesh.get_surface_count(): copy.set_surface_override_material(surface,source.get_active_material(surface))
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		preview_group.add_child(copy)
	preview_group.position = Vector3.ZERO
	preview_grab_center = carry_box.get_center()
	preview_grab_point = preview_grab_center
	if thumbnail_grab_maps.has(id):
		var map: Dictionary = thumbnail_grab_maps[id]
		var rect: Rect2 = card_pictures[id].get_global_rect()
		var image_size := Vector2(224,120)*minf(rect.size.x/224.0,rect.size.y/120.0)
		var image_rect := Rect2(rect.get_center()-image_size*0.5,image_size)
		if image_rect.has_point(drag.press_position):
			var uv: Vector2 = (drag.press_position-image_rect.position)/image_rect.size-Vector2(0.5,0.5)
			preview_grab_point += map.basis.x*uv.x*float(map.size)*224.0/120.0-map.basis.y*uv.y*float(map.size)
	if drag.world_grab is Vector3: preview_grab_point = drag.world_grab
	preview_initialized = false
	preview_group.visible = false # A press only selects; the threshold's first move reveals it.
func hide_preview() -> void:
	preview.visible = false
	if preview_group: preview_group.visible = false
	_sync_guide()
func pick(origin: Vector3, direction: Vector3) -> String:
	return str(_pick_operable_part(origin,direction).get("id",""))
func move_preview(id: String, point: Vector3, anchor: Vector3, near: bool, _visual_target: Dictionary) -> void:
	preview_goal = Vector3.ZERO if near else point-preview_anchor
	if not preview_initialized:
		preview_group.position = preview_goal
		preview_initialized = true
	preview_group.visible = true
	target.material_override.albedo_color = Color(0.25,0.55,0.32,0.3) if near else Color(0.72,0.52,0.25,0.22)
func _drag_status(active: bool, near: bool) -> void:
	if active:
		message.text = "整组已对齐，松手后贴合并演示固定。" if near else "让零件连接处靠近金色目标；判定跟随零件，范围外松手不会安装。"
		Style.feedback(message,"target" if near else "neutral")
		if guide_outline:
			guide_outline.material_override.albedo_color = Color(0.32,0.51,0.31,0.85) if near else Color(0.65,0.46,0.23,0.6)
		if not guide_id.is_empty(): guide_label.text = ("已对齐 · " if near else "固定装配位 · ")+str(_group(guide_id).label)+("\n松手后入位" if near else "\n拖入金色轮廓，变绿后松手")

func _sync_guide() -> void:
	if fixed_guide == null: return
	if mode != "assembly" or not pending_id.is_empty():
		fixed_guide.visible = false
		guide_label.visible = false
		target.visible = false
		return
	var id := selected if not selected.is_empty() and _allowed(selected) else ""
	if id.is_empty():
		for group in groups:
			if _allowed(group.id): id = group.id; break
	if id.is_empty():
		fixed_guide.visible = false
		guide_label.visible = false
		return
	_show_guide(id)

func _show_guide(id: String) -> void:
	orbit.zoom_focus = Drag.vector(slots[id].anchor_m)
	fixed_guide.visible = true
	guide_label.visible = true
	target.position = Drag.vector(slots[id].anchor_m)
	target.visible = true
	target.material_override.albedo_color = Color(0.72,0.52,0.25,0.22)
	guide_label.text = "固定装配位 · "+str(_group(id).label)+"\n拖入金色轮廓，变绿后松手"
	if guide_id == id:
		if guide_outline: guide_outline.material_override.albedo_color = Color(0.65,0.46,0.23,0.6)
		return
	guide_id = id
	for child in fixed_guide.get_children():
		child.visible = false
		child.queue_free()
	var box := AABB()
	var first := true
	for source in _part_meshes(id):
		var copy := MeshInstance3D.new()
		copy.mesh = source.mesh
		fixed_guide.add_child(copy)
		copy.global_transform = source.global_transform
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.73,0.55,0.3,0.11)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		copy.material_override = material
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var b: AABB = source.global_transform*source.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var corners: Array[Vector3] = []
	for x in [box.position.x,box.end.x]:
		for y in [box.position.y,box.end.y]:
			for z in [box.position.z,box.end.z]: corners.append(Vector3(x,y,z))
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for edge in [[0,1],[0,2],[0,4],[1,3],[1,5],[2,3],[2,6],[3,7],[4,5],[4,6],[5,7],[6,7]]:
		var a: Vector3 = corners[edge[0]]
		var b: Vector3 = corners[edge[1]]
		var segments := 10 if a.distance_to(b)>0.2 else 1
		for i in segments:
			lines.surface_add_vertex(a.lerp(b,float(i)/segments))
			lines.surface_add_vertex(a.lerp(b,(float(i)+0.6)/segments))
	lines.surface_end()
	guide_outline = MeshInstance3D.new()
	guide_outline.mesh = lines
	var line_material := StandardMaterial3D.new()
	line_material.albedo_color = Color(0.65,0.46,0.23,0.6)
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.no_depth_test = true
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	guide_outline.material_override = line_material
	guide_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fixed_guide.add_child(guide_outline)

func snapshot() -> Dictionary:
	return {"schema":1,"placed_groups":placed.duplicate(),"complete":placed.size()==groups.size(),"revision":revision,"operation_groups":groups.size(),"source_assembly_groups":59,"source_meshes":1286}

func deactivate() -> void:
	if mode == "lesson": _leave_lesson(false,false)
	if drag: drag.enabled = false; drag.camera_enabled = false; drag.cancel(); drag.set_process_input(false)
	set_process(false)

func _camera_snapshot() -> Dictionary:
	return {"mode":mode,"focus":orbit.focus,"yaw":orbit.yaw,"pitch":orbit.pitch,"distance":orbit.distance,"min":orbit.min_distance,"max":orbit.max_distance}

func _director() -> Dictionary:
	return cameras.assembly_director

func _detail_camera_goal(start: Dictionary) -> Dictionary:
	var goal := start.duplicate()
	goal.focus = lesson_focus
	goal.distance = minf(float(start.distance),clampf(float(start.distance)*float(_director().detail_distance_ratio),float(_director().detail_min_distance_m),float(_director().detail_max_distance_m)))
	return goal # Keep the user's yaw and pitch: the same interface stays in the same world.

func _blend_camera(t: float, start: Dictionary, goal: Dictionary) -> void:
	orbit.focus = (start.focus as Vector3).lerp(goal.focus,t)
	orbit.yaw = lerp_angle(float(start.yaw),float(goal.yaw),t)
	orbit.pitch = lerpf(float(start.pitch),float(goal.pitch),t)
	orbit.distance = lerpf(float(start.distance),float(goal.distance),t)
	orbit.update_view()

func _apply_step_camera(_c: Dictionary) -> void:
	var goal := _detail_camera_goal(returning_camera)
	_blend_camera(1.0,_camera_snapshot(),goal)

func _phase(text: String) -> void:
	lesson_phase = text
	Style.feedback(message,"success" if text.begins_with("固定完成") else "neutral")
	lesson_trace.append({"group":lesson_id,"phase":text,"stage":lesson_stage,"time_ms":Time.get_ticks_msec(),"pending":pending_id})
	message.text = text + " · " + str(_group(lesson_id).label)

func _start_lesson(id: String, installing := false, accepted_revision := -1) -> void:
	if drag.held or (installing and (pending_id != id or revision != accepted_revision)): return
	if mode == "lesson": _leave_lesson(false,false,true)
	returning_camera = _camera_snapshot()
	lesson_id = id
	lesson_is_install = installing
	lesson_user_inspecting = false
	lesson_return_timer.stop()
	last_lesson_id = id
	lesson_generation += 1
	lesson_stage = "holding"
	lesson_detail = not installing or id in _director().key_groups
	lesson_focus = Drag.vector(slots[id].anchor_m)
	lesson_standoff = Drag.vector(_group(id).approach_m).limit_length(float(_director().standoff_max_m))
	lesson_camera_goal = _detail_camera_goal(returning_camera) if lesson_detail else returning_camera.duplicate()
	mode = "lesson"
	drag.cancel()
	drag.enabled = false
	drag.camera_enabled = false
	if not installing: begin_preview(id)
	preview_initialized = false
	preview_group.visible = true
	for root in group_nodes[id]: root.visible = false
	var c: Dictionary = _group(id).lesson
	_refresh()
	connection_label.text = str(c.title)
	source_label.text = str(c.source_note)
	if c.has("joint_id"):
		connection_label.text = "原船接口贴合 · 扩展榫卯另看"
		source_label.text = "当前使用同一原船构件；v3榫卯扩展请主动选择单独观察，非考古原件复原。"
	if c.kind=="sheathing":
		source_label.text = "内部结构钉保留在覆盖层内；交付模型未单列外护轻钉，不用结构钉冒充。"
	disclosure.text = "原船同一接口连续观察；轻微近位与贴合为教学示意，未验证整船施工碰撞。"
	_phase("零件停在接口附近")
	if lesson_detail: _prepare_context_fade(lesson_camera_goal)
	lesson_tween = create_tween()
	lesson_tween.tween_property(preview_group,"position",lesson_standoff,0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	lesson_tween.tween_interval(0.12)
	if lesson_detail:
		lesson_tween.tween_callback(func(): lesson_stage = "approach"; _phase("沿当前观察方向靠近同一接口"))
		lesson_tween.tween_method(_blend_camera.bind(returning_camera,lesson_camera_goal),0.0,1.0,float(_director().approach_seconds)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		lesson_tween.parallel().tween_method(_set_context_opacity,1.0,float(_director().context_opacity),float(_director().approach_seconds))
	lesson_tween.tween_callback(_prepare_lesson_geometry)

func _point_box_distance(box: AABB, point: Vector3) -> float:
	return point.distance_to(point.clamp(box.position,box.end))

func _line_intersects_box(origin: Vector3, end: Vector3, box: AABB) -> bool:
	var direction := end-origin
	var low := 0.0
	var high := 1.0
	for axis in 3:
		if absf(direction[axis])<0.000001:
			if origin[axis]<box.position[axis] or origin[axis]>box.end[axis]: return false
		else:
			var a := (box.position[axis]-origin[axis])/direction[axis]
			var b := (box.end[axis]-origin[axis])/direction[axis]
			low = maxf(low,minf(a,b))
			high = minf(high,maxf(a,b))
			if low>high: return false
	return true

func _prepare_context_fade(goal: Dictionary) -> void:
	var bearing := Vector3(sin(float(goal.yaw))*cos(float(goal.pitch)),sin(float(goal.pitch)),cos(float(goal.yaw))*cos(float(goal.pitch)))
	var origin: Vector3 = lesson_focus+bearing*float(goal.distance)
	var keep: Array = _group(lesson_id).connection_meshes
	var own: Array[MeshInstance3D] = _part_meshes(lesson_id)
	for mesh in _meshes(boat):
		if mesh in own or not mesh.is_visible_in_tree(): continue
		if str(mesh.name) in keep: continue
		var box: AABB = mesh.global_transform*mesh.get_aabb()
		if _point_box_distance(box,lesson_focus)<0.025 or not _line_intersects_box(origin,lesson_focus,box): continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if not material is ShaderMaterial: continue
			var faded := ShaderMaterial.new()
			faded.shader = ContextWood
			for key in ["grain_axis","wood_dark","wood_light","variation","model_scale","section_enabled","section_center","section_half","cutaway_enabled","reveal_enabled","reveal_limit"]:
				var value = material.get_shader_parameter(key)
				if value!=null: faded.set_shader_parameter(key,value)
			mesh.set_meta("context_material_"+str(surface),material)
			mesh.set_surface_override_material(surface,faded)
			lesson_context_materials.append(faded)

func _set_context_opacity(value: float) -> void:
	lesson_context_opacity = value
	for material in lesson_context_materials: material.set_shader_parameter("context_opacity",value)

func _restore_context_materials() -> void:
	for mesh in _meshes(boat):
		for surface in mesh.mesh.get_surface_count():
			var key := "context_material_"+str(surface)
			if mesh.has_meta(key):
				mesh.set_surface_override_material(surface,mesh.get_meta(key))
				mesh.remove_meta(key)
	lesson_context_materials.clear()
	lesson_context_opacity = 1.0

func _set_section(enabled: bool, center := Vector3.ZERO, half := Vector3(100,100,100)) -> void:
	for material in wood_materials.values():
		material.set_shader_parameter("section_enabled",enabled)
		material.set_shader_parameter("section_center",center)
		material.set_shader_parameter("section_half",half)
		material.set_shader_parameter("cutaway_enabled",cutaway)

func _prepare_lesson_geometry() -> void:
	if mode != "lesson": return
	var c: Dictionary = _group(lesson_id).lesson
	# The swap is between identical original meshes at identical transforms,
	# never a different GLB, a crop, or a forced second camera pose.
	for root in group_nodes[lesson_id]:
		lesson_homes[root] = root.transform
		root.position += root.get_parent_node_3d().global_basis.inverse()*lesson_standoff
		root.visible = str(root.name)!=c.get("nail_side","") and c.kind!="partition_sequence"
	# The merged step hands off one local module at a time at the same pose.
	preview_group.visible = c.kind=="partition_sequence"
	cutaway = not lesson_context_materials.is_empty()
	lesson_stage = "settle"
	_phase("镜头停稳，观察原船接触面" if lesson_detail else "本地组件对齐")
	lesson_tween = create_tween()
	lesson_tween.tween_interval(float(_director().settle_seconds) if lesson_detail else 0.08)
	lesson_tween.tween_callback(_run_wood_phase)

func _run_wood_phase() -> void:
	if mode != "lesson": return
	var c: Dictionary = _group(lesson_id).lesson
	lesson_stage = "wood"
	drag.camera_enabled = true
	lesson_tween = create_tween()
	var text := "实际接触面沿原方向靠合"
	if c.kind in ["planking","sheathing"]: text = "板列近位贴合 · 建造示意，不演示整壳穿入"
	elif c.kind=="tenon": text = "原船连接处对准贴合 · 扩展榫卯可单独观察"
	elif c.kind=="partition": text = "当地隔舱与横梁对齐船壳"
	elif c.kind=="partition_sequence": text = "隔舱与梁整组确认 · 各道依次短落位"
	elif c.kind=="rigged_mast": text = "同桅总成就地定位，帆索保持相系 · 展示复原"
	elif c.kind=="rudder": text = "艉舵总成对齐导向位置 · 示意"
	_phase(text)
	if c.kind=="partition_sequence":
		for root_name in c.sequence_roots:
			var root: Node3D = boat.find_child(str(root_name),true,false)
			lesson_tween.tween_callback(_begin_partition_piece.bind(root))
			_queue_motion(lesson_tween,root,Vector3.ZERO,float(c.sequence_step_seconds))
		lesson_tween.tween_callback(func(): preview_group.visible = false)
		lesson_tween.tween_callback(_begin_fixed_phase)
		return
	var first := true
	var seconds := float(c.wood_seconds) if lesson_detail else float(_director().repeat_wood_seconds)
	for root in group_nodes[lesson_id]:
		_queue_motion(lesson_tween,root,Vector3.ZERO,seconds,not first)
		first = false
	lesson_tween.tween_callback(_begin_fixed_phase)

func _begin_partition_piece(root: Node3D) -> void:
	# Preview and source share the fitted original geometry and the same standoff.
	var names: Array[String] = []
	for mesh in _meshes(root): names.append(str(mesh.name))
	for copy in preview_group.get_children():
		if str(copy.get_meta("source_mesh_name","")) in names: copy.visible = false
	root.visible = true

func _queue_motion(tween: Tween, node: Node3D, world_offset: Vector3, duration: float, parallel := false) -> void:
	if not lesson_homes.has(node):
		lesson_homes[node] = node.transform
		node.position += node.get_parent_node_3d().global_basis.inverse()*world_offset
	var home: Vector3 = (lesson_homes[node] as Transform3D).origin
	var track: PropertyTweener
	if parallel: track = tween.parallel().tween_property(node,"position",home,duration)
	else: track = tween.tween_property(node,"position",home,duration)
	track.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _set_reveal(limit: float) -> void:
	for material in lesson_materials: material.set_shader_parameter("reveal_limit",limit)

func _begin_fixed_phase() -> void:
	if mode != "lesson": return
	var c: Dictionary = _group(lesson_id).lesson
	lesson_stage = "fixed"
	lesson_tween = create_tween()
	# Delivered F±1 are structural nails seated in the inner planking.
	# Outer-cover light fasteners are not separate assets; never fake them with F±1.
	if c.has("nail_side") and c.kind!="sheathing":
		_phase("钉头沿源轴钉入，木面正常遮挡钉身")
		_prepare_nails(str(c.nail_side),lesson_focus)
		var first := true
		for pair in lesson_nails.get_children():
			var track: PropertyTweener
			if first: track = lesson_tween.tween_property(pair,"position",Vector3.ZERO,float(c.fixed_seconds))
			else: track = lesson_tween.parallel().tween_property(pair,"position",Vector3.ZERO,float(c.fixed_seconds))
			track.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			first = false
		if first: lesson_tween.tween_interval(0.12) # No out-of-range nail is invented.
	else:
		if c.kind=="sheathing": _phase("外护板贴合 · 内部结构钉被覆盖，外护轻钉未单列")
		else: _phase("当地板壁接触就位 · L形铁件未建模" if c.kind=="partition" else "接触面固定就位")
		lesson_tween.tween_interval(0.22 if lesson_detail else 0.10)
	lesson_tween.tween_callback(_finish_lesson_install)

func _prepare_nails(side: String, focus: Vector3) -> void:
	lesson_nails = Node3D.new()
	world.add_child(lesson_nails)
	var source_root: Node = boat.find_child(side,true,false)
	var pairs: Array = []
	if source_root==null: return
	for shank in _meshes(source_root):
		if not str(shank.name).begins_with("Driven iron shank"): continue
		var suffix := str(shank.name).trim_prefix("Driven iron shank")
		var head: MeshInstance3D = mesh_lookup.get("Iron fastening head"+suffix)
		if head==null or not source_root.is_ancestor_of(head): continue
		var shank_center: Vector3 = (shank.global_transform*shank.get_aabb()).get_center()
		var head_center: Vector3 = (head.global_transform*head.get_aabb()).get_center()
		if head_center.distance_to(focus)>float(_director().nail_focus_radius_m): continue
		var length_m := head_center.distance_to(shank_center)*2.0
		if length_m<0.001: continue
		pairs.append({"shank":shank,"head":head,"head_center":head_center,"axis":(head_center-shank_center).normalized(),"length_m":length_m})
	pairs.sort_custom(func(a: Dictionary,b: Dictionary): return (a.head_center as Vector3).distance_squared_to(focus)<(b.head_center as Vector3).distance_squared_to(focus))
	var chosen: Array[Vector3] = []
	for item in pairs:
		if chosen.size()>=int(_director().nail_count): break
		var crowded := false
		for previous in chosen:
			if previous.distance_to(item.head_center)<0.012: crowded = true
		if crowded: continue
		chosen.append(item.head_center)
		var pair := Node3D.new()
		lesson_nails.add_child(pair)
		var stroke := float(item.length_m)*float(_director().nail_stroke_ratio)
		for source in [item.shank,item.head]:
			var copy := MeshInstance3D.new()
			copy.mesh = source.mesh
			copy.set_meta("source_mesh_name",str(source.name))
			pair.add_child(copy)
			copy.transform = source.global_transform
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for surface in source.mesh.get_surface_count():
				var material: Material = source.get_active_material(surface)
				if material is StandardMaterial3D:
					material = material.duplicate()
					material.no_depth_test = false
					material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				copy.set_surface_override_material(surface,material)
			lesson_hidden_nails[source] = source.visible
			source.visible = false
		pair.position = (item.axis as Vector3)*stroke
		nail_trace.append({"group":lesson_id,"phase":"prepared","shank":str(item.shank.name),"head":str(item.head.name),"head_world":str(item.head_center),"axis_out":str(item.axis),"length_m":item.length_m,"stroke_m":stroke,"scale_unchanged":true,"depth_test":true})

func _restore_nail_sources(completed := false) -> void:
	if lesson_nails:
		for pair in lesson_nails.get_children():
			for copy in pair.get_children():
				var source: MeshInstance3D = mesh_lookup.get(str(copy.get_meta("source_mesh_name","")))
				if source:
					nail_trace.append({"group":lesson_id,"phase":"fixed_final" if completed else "interrupted","source":str(source.name),"position_error_m":copy.global_position.distance_to(source.global_position),"basis_matches":copy.global_basis.is_equal_approx(source.global_basis)})
		lesson_nails.queue_free()
		lesson_nails = null
	for source in lesson_hidden_nails:
		if is_instance_valid(source): source.visible = lesson_hidden_nails[source]
	lesson_hidden_nails.clear()

func _commit_pending_lesson() -> void:
	if pending_id.is_empty(): return
	placed.append(pending_id)
	history.append(pending_id)
	pending_id = ""
	revision += 1
	if placed.size()==groups.size(): completed.emit(snapshot())

func _finish_lesson_install() -> void:
	if mode != "lesson": return
	_commit_pending_lesson()
	_restore_nail_sources(true)
	for root in group_nodes[lesson_id]: root.visible = true
	lesson_stage = "complete"
	_refresh()
	_phase("固定完成 · 可观察或直接拖下一件")
	if lesson_user_inspecting:
		message.text = "已保留当前观察；可返回原视角，或直接拖下一件。"
	elif lesson_is_install:
		lesson_return_timer.start(float(_director().complete_hold_seconds) if lesson_detail else float(_director().repeat_complete_hold_seconds))

func _automatic_lesson_return() -> void:
	if mode=="lesson" and pending_id.is_empty() and lesson_is_install and not drag.held and not drag.rotating:
		_leave_lesson(false,true)

func _restore_lesson_geometry(restore_context := true) -> void:
	if lesson_tween and lesson_tween.is_valid(): lesson_tween.kill()
	preview_group.visible = false
	_restore_nail_sources()
	for node in lesson_homes:
		if is_instance_valid(node): node.transform = lesson_homes[node]
	lesson_homes.clear()
	for mesh in _meshes(boat):
		mesh.visible = true
		for surface in mesh.mesh.get_surface_count():
			var key := "lesson_material_"+str(surface)
			if mesh.has_meta(key):
				mesh.set_surface_override_material(surface,mesh.get_meta(key))
				mesh.remove_meta(key)
	lesson_materials.clear()
	if joint: joint.queue_free(); joint = null; moving = null
	boat.visible = true
	cutaway = false
	_set_section(false)
	if restore_context: _restore_context_materials()

func _show_assembly_members() -> void:
	for g in groups:
		for root in group_nodes[g.id]: root.visible = g.id in placed or returning_camera.get("mode","assembly")=="overview"

func _finish_lesson_return(keep_current_camera := false) -> void:
	if mode!="lesson": return
	_restore_context_materials()
	mode = str(returning_camera.get("mode","assembly"))
	if not keep_current_camera:
		orbit.focus = returning_camera.focus
		orbit.yaw = returning_camera.yaw
		orbit.pitch = returning_camera.pitch
		orbit.distance = returning_camera.distance
	orbit.min_distance = minf(float(returning_camera.get("min",cameras.overview.min)),orbit.distance)
	orbit.max_distance = float(returning_camera.get("max",cameras.overview.max))
	orbit.update_view()
	drag.camera_enabled = true
	drag.enabled = mode=="assembly"
	lesson_phase = ""
	lesson_stage = ""
	lesson_is_install = false
	lesson_user_inspecting = false
	_refresh()
	disclosure.text = "桅脚直榫、柱梁方榫为互动扩展；上部结构含展示复原；板缝并非全部自锁。"
	message.text = "已保留当前视角，继续装配。" if keep_current_camera else "已返回原视角；连接进度保留。"

func _leave_lesson(commit: bool, smooth := true, keep_current_camera := false) -> void:
	if mode!="lesson": return
	if smooth and lesson_stage=="returning": return
	lesson_return_timer.stop()
	if commit: _commit_pending_lesson()
	else: pending_id = ""
	lesson_generation += 1
	_restore_lesson_geometry(not smooth)
	_show_assembly_members()
	if not smooth:
		_finish_lesson_return(keep_current_camera)
		return
	lesson_stage = "returning"
	drag.camera_enabled = false
	drag.enabled = false
	var start := _camera_snapshot()
	if (start.focus as Vector3).is_equal_approx(returning_camera.focus) and is_equal_approx(float(start.distance),float(returning_camera.distance)) and is_equal_approx(float(start.yaw),float(returning_camera.yaw)) and is_equal_approx(float(start.pitch),float(returning_camera.pitch)):
		_finish_lesson_return()
		return
	_phase("沿连续路径返回原观察位置")
	lesson_tween = create_tween()
	lesson_tween.tween_method(_blend_camera.bind(start,returning_camera),0.0,1.0,float(_director().return_seconds)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	lesson_tween.parallel().tween_method(_set_context_opacity,lesson_context_opacity,1.0,float(_director().return_seconds))
	lesson_tween.tween_callback(_finish_lesson_return)

func skip_lesson() -> void:
	_leave_lesson(true)

func replay_lesson() -> void:
	if mode == "assembly" and last_lesson_id in placed and not drag.held: _start_lesson(last_lesson_id)

func toggle_cutaway() -> void:
	if lesson_return_timer: lesson_return_timer.stop()
	if mode=="lesson":
		if not drag.camera_enabled: return
		if lesson_context_materials.is_empty():
			message.text = "当前没有需要渐隐的遮挡木件；可继续旋转、缩放观察。"
			return
		lesson_user_inspecting = true
		cutaway = not cutaway
		_set_context_opacity(float(_director().context_opacity) if cutaway else 1.0)
		message.text = "遮挡木件渐隐观察；钉身仍按真实深度遮挡。" if cutaway else "已恢复完整遮挡木件。"
		return
	cutaway = not cutaway
	var center := _joint_center() if mode == "joint" else Drag.vector(_group(lesson_id).lesson.focus_m)
	for material in wood_materials.values():
		material.set_shader_parameter("cutaway_enabled",cutaway)
		material.set_shader_parameter("section_center",center)
	# Cut the fixed member while keeping the entering tenon solid and legible.
	# Both are still the delivered mesh geometry; no replacement joint is built.
	if moving:
		for mesh in _meshes(moving):
			for surface in mesh.mesh.get_surface_count():
				var material := mesh.get_active_material(surface)
				if material is ShaderMaterial: material.set_shader_parameter("cutaway_enabled",false)
	message.text = "剖切观察：切去朝镜头一侧的局部表面，便于看入位关系。" if cutaway else "已恢复完整局部表面。"

func _bake_thumbnails() -> void:
	if DisplayServer.get_name() == "headless": return
	var views: Array = []
	for g in groups:
		var sources := _part_meshes(g.id)
		if sources.is_empty(): continue
		var thumb := SubViewport.new()
		thumb.size = Vector2i(224,120)
		thumb.own_world_3d = true
		thumb.transparent_bg = true
		thumb.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(thumb)
		var stage := Node3D.new()
		thumb.add_child(stage)
		var geometry := Node3D.new()
		stage.add_child(geometry)
		var box: AABB = bounds[g.id]
		for source in sources:
			var copy := MeshInstance3D.new()
			copy.mesh = source.mesh
			copy.transform = source.global_transform
			geometry.add_child(copy)
			for surface in source.mesh.get_surface_count(): copy.set_surface_override_material(surface,source.get_active_material(surface))
		geometry.position = -box.get_center()
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-48,-25,0)
		light.light_energy = 1.1
		stage.add_child(light)
		var env := WorldEnvironment.new()
		var environment := Environment.new()
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color.WHITE
		environment.ambient_light_energy = 0.7
		env.environment = environment
		stage.add_child(env)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = maxf(box.size.length()*0.82,0.04)
		cam.position = Vector3(0.6,0.9,1.7)*maxf(box.size.length(),0.1)
		stage.add_child(cam)
		cam.look_at(Vector3.ZERO)
		var source_names: Array[String] = []
		for source in sources: source_names.append(str(source.name))
		thumbnail_grab_maps[g.id] = {"basis":cam.global_basis,"size":cam.size,"mesh_count":sources.size(),"mesh_names":source_names}
		views.append({"id":g.id,"viewport":thumb})
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for item in views:
		card_pictures[item.id].texture = ImageTexture.create_from_image(item.viewport.get_texture().get_image())
		item.viewport.queue_free()
