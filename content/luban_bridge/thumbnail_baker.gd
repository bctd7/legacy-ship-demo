extends Node
## Actual content meshes rendered as tray thumbnails. No external image assets.
signal ready_images(images: Array)

func bake(presenter, steps: Array) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var views: Array = []
	for step in steps:
		var viewport = SubViewport.new()
		viewport.size = Vector2i(224,144)
		viewport.own_world_3d = true
		viewport.transparent_bg = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(viewport)
		var world = Node3D.new()
		viewport.add_child(world)
		var mesh_id: String = step.representative_part_id
		var source: MeshInstance3D = presenter.meshes[mesh_id]
		var mesh = MeshInstance3D.new()
		var common: Mesh=presenter.common_preview_mesh(step.id)
		mesh.mesh = common if common!=null else source.mesh
		mesh.material_override = presenter.wood_materials.get(mesh_id,source.material_override)
		if common!=null:
			mesh.material_override=mesh.material_override.duplicate()
			mesh.material_override.set_shader_parameter("grain_axis",Vector3.RIGHT)
		var box: AABB = mesh.mesh.get_aabb()
		mesh.position = -box.get_center()
		world.add_child(mesh)
		var env = WorldEnvironment.new()
		var environment = Environment.new()
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(1,0.93,0.83)
		environment.ambient_light_energy = 0.7
		env.environment = environment
		world.add_child(env)
		var light = DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-48,-25,0)
		light.light_energy = 0.75
		world.add_child(light)
		var camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(box.size.length()*0.95,0.04)
		camera.position = Vector3(0.7,0.9,1.7)*maxf(box.size.length(),0.1)
		world.add_child(camera)
		camera.look_at(Vector3.ZERO)
		views.append(viewport)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var images: Array = []
	for viewport in views:
		images.append(ImageTexture.create_from_image(viewport.get_texture().get_image()))
		viewport.queue_free()
	ready_images.emit(images)
	queue_free()
