extends RefCounted
## Exhibition world construction only; no session, inventory or input decisions.
static func build(viewport: SubViewport,presenter: Node3D) -> Camera3D:
	var world = Node3D.new()
	viewport.add_child(world)
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("eae6df")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1,1,1)
	env.ambient_light_energy = 0.48
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	environment.environment = env
	world.add_child(environment)
	var key = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-62,-32,0)
	key.light_energy = 0.8
	key.light_color = Color(1,0.99,0.97)
	key.light_angular_distance = 1.1
	key.shadow_enabled = true
	key.shadow_bias = 0.025
	key.shadow_blur = 1.5
	key.directional_shadow_max_distance = 3
	world.add_child(key)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-35,145,0)
	fill.light_energy = 0.28
	world.add_child(fill)
	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(200,200)
	ground.mesh = plane
	ground.position.y = 0.0048 # Just below the original base bottom at 0.0054929 m.
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color("b9b8b6").srgb_to_linear()
	mat.roughness = 0.93
	ground.material_override = mat
	world.add_child(ground)
	world.add_child(presenter)
	var camera = Camera3D.new()
	camera.fov = 40
	camera.near = 0.01
	camera.far = 100
	world.add_child(camera)
	camera.current = true
	return camera
