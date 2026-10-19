extends SceneTree
## Offline asset bake only. Uses the accepted final meshes/materials unchanged.
## Run with a rendering driver; never part of assembly or painting interaction.
const Presenter = preload("res://content/luban_bridge/bridge_presenter.gd")
const OUTPUT = "res://levels/assets/bridge_render.png"

func _init() -> void:
	call_deferred("bake")

func bake() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Bridge asset baking requires a rendering driver, not headless.")
		quit(1)
		return
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/luban_bridge/content.json"))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2048, 1536)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var model := Presenter.new()
	viewport.add_child(model)
	model.setup(config)
	model.show_complete(true)
	var bounds := AABB()
	var first := true
	for mesh in model.final_model.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = part if first else bounds.merge(part)
		first = false
	if first:
		push_error("Final bridge model contains no mesh bounds.")
		quit(1)
		return
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.48
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.9
	world_environment.environment = environment
	viewport.add_child(world_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-62, -32, 0)
	key.light_energy = 0.8
	key.light_color = Color(1, 0.99, 0.97)
	key.shadow_enabled = true
	key.shadow_bias = 0.025
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35, 145, 0)
	fill.light_energy = 0.28
	viewport.add_child(fill)
	var camera := Camera3D.new()
	camera.fov = 36.0
	camera.near = 0.01
	camera.far = 20.0
	camera.current = true
	viewport.add_child(camera)
	# Lower three-quarter perspective keeps the arch legible and reveals deck depth.
	var yaw := 0.45
	var pitch := 0.34
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var distance := bounds.size.length() * 0.75
	var center := bounds.get_center()
	for attempt in range(100):
		camera.position = center + direction * distance
		camera.look_at(center)
		var fits := true
		for corner in range(8):
			var point := camera.unproject_position(bounds.get_endpoint(corner))
			if not Rect2(96, 96, 1856, 1344).has_point(point): fits = false
		if fits: break
		distance *= 1.04
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	var used := image.get_used_rect()
	if used.size.x < 500 or image.get_pixel(0, 0).a != 0.0:
		push_error("Bridge bake did not produce a high resolution transparent image.")
		quit(1)
		return
	var crop := used.grow(24).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var output := image.get_region(crop)
	if output.save_png(OUTPUT) != OK:
		push_error("Bridge bake output could not be saved.")
		quit(1)
		return
	var manifest := {"source_model": config.final_scene, "source_sha256": FileAccess.get_sha256(config.final_scene),
		"materials": "accepted bridge_presenter wood_material, unchanged", "placeholder": false,
		"render_size": [2048,1536], "output_size": [output.get_width(),output.get_height()],
		"projection": "perspective", "fov_degrees": camera.fov, "yaw_radians": yaw, "pitch_radians": pitch,
		"distance": distance, "focus": str(center), "alpha": "transparent background; no floor or UI",
		"crop": [crop.position.x,crop.position.y,crop.size.x,crop.size.y], "padding_pixels": 24,
		"engine": Engine.get_version_info().string, "generator": "res://levels/tools/bake_bridge_image.gd"}
	var file := FileAccess.open("res://levels/assets/bridge_render.metadata.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t")); file.close()
	print("BRIDGE_BAKE_OK: ", output.get_size())
	quit()
