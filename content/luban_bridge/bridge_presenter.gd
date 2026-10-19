extends Node3D
## Content-specific animation/presentation. Physical geometry is unchanged.
signal animation_done(ticket: int)
const Rules = preload("res://content/luban_bridge/bridge_rules.gd")
var data: Dictionary
var assembly: Node3D
var final_model: Node3D
var meshes: Dictionary = {}
var active: Dictionary = {}
var elapsed: float = 0
var duration_scale: float = 1.0
var preview: MeshInstance3D
var marker: MeshInstance3D
var hoist: MeshInstance3D
var selection_id: String = ""
var highlight_material: ShaderMaterial
var wood_materials: Dictionary = {}
var pull_preview: Node3D
var target_markers: Node3D
var preview_source_id: String=""
var preview_source_anchor: Vector3
var preview_type_id: String=""
var preview_target_slot: String=""
var preview_goal: Transform3D
var preview_from: Transform3D
var preview_progress: float=1.0
var preview_initialized: bool=false
var common_preview_meshes: Dictionary={}

func common_preview_mesh(id: String) -> Mesh:
	for family in data.get("inventory_families",[]):
		if family.id!=id or not family.has("common_preview"):continue
		if not common_preview_meshes.has(id):
			var panel=BoxMesh.new()
			panel.size=Rules.vector(family.common_preview.size_m)
			common_preview_meshes[id]=panel
		return common_preview_meshes[id]
	return null

func setup(config: Dictionary) -> void:
	data = config
	assembly = load(data.assembly_scene).instantiate()
	add_child(assembly)
	for player in assembly.find_children("*", "AnimationPlayer", true, false):
		player.stop()
		player.active = false
	for node in assembly.find_children("*", "MeshInstance3D", true, false):
		meshes[str(node.name)] = node
		if data.parts.has(str(node.name)):
			wood_materials[str(node.name)] = wood_material(str(node.name))
			node.material_override = wood_materials[str(node.name)]
	final_model = load(data.final_scene).instantiate()
	add_child(final_model)
	for node in final_model.find_children("*", "MeshInstance3D", true, false):
		if wood_materials.has(str(node.name)):
			node.material_override = wood_materials[str(node.name)]
	final_model.visible = false
	preview = MeshInstance3D.new()
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)
	preview.visible = false
	marker = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.022
	sphere.height = 0.044
	marker.mesh = sphere
	marker.material_override = ghost_material(Color(0.12, 0.75, 1.0, 0.25))
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	hoist = MeshInstance3D.new()
	var cable = CylinderMesh.new()
	cable.top_radius = 0.00065
	cable.bottom_radius = 0.00065
	cable.height = 1
	hoist.mesh = cable
	var cable_mat = StandardMaterial3D.new()
	cable_mat.albedo_color = Color(0.96, 0.67, 0.16)
	cable_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hoist.material_override = cable_mat
	add_child(hoist)
	hoist.visible = false
	highlight_material = ShaderMaterial.new()
	highlight_material.shader = preload("res://content/luban_bridge/materials/selection_outline.gdshader")
	pull_preview = Node3D.new()
	add_child(pull_preview)
	for id in data.fixtures:
		var copy = MeshInstance3D.new()
		copy.mesh = meshes[id].mesh
		copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pull_preview.add_child(copy)
	pull_preview.visible = false
	target_markers=Node3D.new()
	add_child(target_markers)
	for step in data.steps:
		if step.action_kind!="install":continue
		for point in step.slot.get("marker_points_m",[step.slot.anchor_m]):
			var hint=MeshInstance3D.new()
			var dot=SphereMesh.new()
			dot.radius=0.010;dot.height=0.020
			hint.mesh=dot
			hint.position=Rules.vector(point)
			hint.set_meta("slot_id",step.slot.id)
			hint.material_override=ghost_material(Color(0.77,0.62,0.36,0.25))
			hint.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			target_markers.add_child(hint)
	target_markers.visible=false
	sync([])

func wood_material(part_id: String) -> ShaderMaterial:
	var material = ShaderMaterial.new()
	material.shader = preload("res://content/luban_bridge/materials/redwood.gdshader")
	var axis = Vector3(0, 0, 1)
	if part_id.begins_with("Beam_") or part_id.begins_with("Deck_"):
		var number = int(part_id.right(2))
		var angle = deg_to_rad(60.0 - number * 20.0)
		axis = Vector3(cos(angle), sin(angle), 0)
	material.set_shader_parameter("grain_axis", axis)
	material.set_shader_parameter("variation", float(abs(part_id.hash()) % 100) / 100.0)
	return material

func ghost_material(color: Color) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func sync(done: Array) -> void:
	active.clear()
	preview.visible = false
	target_markers.visible=false
	pull_preview.visible = false
	marker.visible = false
	hoist.visible = false
	for id in meshes:
		var node: MeshInstance3D = meshes[id]
		node.material_override = wood_materials.get(id, null)
		node.material_overlay = null
		node.visible = false
		if data.target_pose.has(id):
			node.transform = Transform3D.IDENTITY
	for id in data.base_parts:
		meshes[id].visible = true
	for id in data.fixtures:
		meshes[id].visible = not done.has(data.withdraw_action_id)
	for step in data.steps:
		if step.action_kind=="install" and done.has(step.part_id):
			for id in step.moving:meshes[id].visible = true
	set_highlight("" if done.has(data.withdraw_action_id) else selection_id)

func show_complete(enabled: bool) -> void:
	assembly.visible = not enabled
	final_model.visible = enabled
	marker.visible = not enabled
	preview.visible = false
	pull_preview.visible = false
	target_markers.visible=false

func set_compatible_targets(options: Array,enabled: bool) -> void:
	target_markers.visible=enabled
	for node in target_markers.get_children():
		node.visible=false
		for option in options:
			if option.id==node.get_meta("slot_id"):
				node.visible=option.allowed
				break

func set_highlight(part_id: String) -> void:
	selection_id = part_id
	for id in meshes:
		var selected: bool = not part_id.is_empty() and (id == part_id or data.get("pick_aliases",{}).get(id,"") == part_id)
		meshes[id].material_overlay = highlight_material if selected else null

func set_target(slot: Dictionary, enabled: bool = true, gesture: Dictionary = {"mode":"place"}) -> void:
	marker.position = Rules.vector(slot.get("marker_points_m",[slot.anchor_m])[0])
	marker.visible = enabled and gesture.mode == "place"
	marker.scale = Vector3.ONE * (float(slot.radius_m) / 0.022)
	marker.material_override = ghost_material(Color(0.75,0.56,0.25,0.16))

func begin_preview(part_id: String) -> void:
	preview_source_id=""
	preview_type_id=part_id;preview_target_slot="";preview_initialized=false
	preview.transform=Transform3D.IDENTITY;preview_goal=Transform3D.IDENTITY;preview_progress=1
	var common=common_preview_mesh(part_id)
	if common!=null:
		preview_source_id=part_id
		preview_source_anchor=common.get_aabb().get_center()
		preview.mesh=common
		return
	var mesh_id = data.fixtures[0] if part_id == data.withdraw_action_id else part_id
	for item in data.inventory_types:
		if item.id==part_id:
			mesh_id=item.representative_part_id
			break
	if not meshes.has(mesh_id):
		return
	preview_source_id=mesh_id
	preview_source_anchor=meshes[mesh_id].mesh.get_aabb().get_center()
	preview.mesh = meshes[mesh_id].mesh

func mapped_source_pose(slot_id: String) -> Dictionary:
	for step in data.steps:
		if step.action_kind!="install" or step.slot.id!=slot_id:continue
		for family in data.get("inventory_families",[]):
			if family.id!=preview_type_id or not family.has("common_preview") or not family.member_type_ids.has(data.slot_type_map[slot_id]):continue
			var rows: Array=step.slot.common_preview_rotation_rows
			return {"pose":Transform3D(Basis(Rules.vector(rows[0]),Rules.vector(rows[1]),Rules.vector(rows[2])).transposed(),Vector3.ZERO),"step":step}
		if data.slot_type_map[slot_id]!=preview_type_id:return {}
		for item in data.inventory_types:
			if item.id!=preview_type_id:continue
			if step.part_id==item.representative_part_id:return {"pose":Transform3D.IDENTITY,"step":step}
			var mapping: Dictionary=item.get("to_slot_pose",{}).get(step.part_id,{})
			if mapping.is_empty():return {}
			var rows: Array=mapping.rotation_rows
			var rotation=Basis(Rules.vector(rows[0]),Rules.vector(rows[1]),Rules.vector(rows[2])).transposed()
			return {"pose":Transform3D(rotation,Rules.vector(mapping.translation_m)),"step":step}
	return {}

func _preview_goal(pose: Transform3D) -> void:
	var pivot=pose*preview_source_anchor
	if not preview_initialized:
		preview.transform=Transform3D(Basis.IDENTITY,pivot-preview_source_anchor)
		preview_initialized=true
	if not preview_goal.basis.is_equal_approx(pose.basis):
		preview_from=preview.transform;preview_progress=0
	preview_goal=pose
	# Position follows the pointer immediately; only orientation is eased.
	preview.position=pivot-preview.basis*preview_source_anchor

func _blend_preview(delta: float) -> void:
	if not preview.visible or preview_progress>=1:return
	preview_progress=minf(1,preview_progress+delta/0.14)
	var t=smoothstep(0,1,preview_progress)
	var rotation=preview_from.basis.get_rotation_quaternion().slerp(preview_goal.basis.get_rotation_quaternion(),t)
	var pivot=preview_goal*preview_source_anchor
	preview.transform=Transform3D(Basis(rotation),pivot-Basis(rotation)*preview_source_anchor)
	if preview_progress>=1:preview.transform=preview_goal

func move_preview(_part_id: String, point: Vector3, anchor: Vector3, near: bool,target: Dictionary={}) -> void:
	if preview_source_id.is_empty():return
	var goal=Transform3D(Basis.IDENTITY,point-preview_source_anchor)
	var mapped=mapped_source_pose(str(target.get("id",""))) if near or target.get("pose_active",false) else {}
	preview_target_slot=""
	if not mapped.is_empty():
		preview_target_slot=str(target.id)
		goal.basis=mapped.pose.basis
		goal.origin=point-goal.basis*preview_source_anchor
	_preview_goal(goal)
	marker.position=anchor
	marker.visible=true
	preview.material_override = ghost_material(Color(0.47,0.76,0.53,0.45) if near else Color(0.65,0.64,0.57,0.38))
	preview.visible = true
	marker.material_override = ghost_material(Color(0.47,0.76,0.53,0.3) if near else Color(0.75,0.56,0.25,0.16))

func move_pull_preview(axis: Vector3, distance: float, ready: bool) -> void:
	pull_preview.position = axis*minf(distance,0.035)
	var material = ghost_material(Color(0.47,0.76,0.53,0.42) if ready else Color(0.55,0.66,0.69,0.3))
	for child in pull_preview.get_children():
		child.material_override = material
	pull_preview.visible = true

func hide_preview() -> void:
	preview.visible=false;pull_preview.visible=false
	preview_source_id="";preview_target_slot="";preview_initialized=false

func animate_step(step: Dictionary, ticket: int) -> void:
	active = {"step": step, "ticket": ticket}
	elapsed = 0
	preview.visible = false
	pull_preview.visible = false
	marker.visible = false
	target_markers.visible=false
	if step.action_kind=="install":
		begin_preview(str(data.slot_type_map[step.slot.id]))
		var mapped=mapped_source_pose(step.slot.id)
		if not mapped.is_empty():
			active["source_pose"]=mapped.pose
			preview.transform=mapped.pose;preview.position+=Rules.vector(step.path.from_m)
			preview_goal=preview.transform;preview_initialized=true;preview_progress=1
			preview.visible=true;preview.material_override=wood_materials[preview_source_id]
			for id in step.moving:meshes[id].visible=false;meshes[id].position=Rules.vector(step.path.from_m)
			_update_hoist(step)
			return
	for id in step.moving:
		meshes[id].visible = true
		meshes[id].position = Rules.vector(step.path.from_m)
	_update_hoist(step)

func _process(delta: float) -> void:
	_blend_preview(delta)
	if active.is_empty():
		return
	var step: Dictionary = active.step
	elapsed += delta
	var u = clampf(elapsed / maxf(float(step.path.duration_s) * duration_scale, 0.001), 0, 1)
	var position_m = Rules.vector(step.path.from_m).lerp(Rules.vector(step.path.to_m), u)
	for id in step.moving:
		meshes[id].position = position_m
	if active.has("source_pose"):
		preview.transform=active.source_pose;preview.position+=position_m
	_update_hoist(step)
	if u >= 1:
		var ticket: int = active.ticket
		active.clear()
		preview.visible=false;preview_source_id=""
		hoist.visible = false
		animation_done.emit(ticket)

func _update_hoist(step: Dictionary) -> void:
	hoist.visible = step.action_kind == "install"
	if not hoist.visible:
		return
	var node: MeshInstance3D = meshes[step.moving[0]]
	var box: AABB = node.get_aabb()
	var point = node.position + box.get_center()
	point.y = node.position.y + box.end.y
	var top: float = maxf(0.62, point.y + 0.02)
	hoist.position = Vector3(point.x, (point.y + top) / 2, point.z)
	hoist.scale = Vector3(1, top - point.y, 1)

func pick(ray_origin: Vector3, ray_direction: Vector3) -> String:
	var best: String = ""
	var distance: float = INF
	var candidates: Array = data.parts+data.fixtures
	if selection_id == data.withdraw_action_id:
		candidates = data.fixtures
	for id in candidates:
		var mesh: MeshInstance3D = meshes[id]
		if not mesh.visible:
			continue
		var inverse = mesh.global_transform.affine_inverse()
		var box = mesh.get_aabb().grow(0.012) if data.fixtures.has(id) else mesh.get_aabb()
		var hit = box.intersects_ray(inverse * ray_origin, inverse.basis * ray_direction)
		if hit != null:
			var dist: float = ray_origin.distance_to(mesh.global_transform * hit)
			if dist < distance:
				distance = dist
				best = id
	return best
