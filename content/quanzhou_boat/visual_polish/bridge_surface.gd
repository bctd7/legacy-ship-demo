extends RefCounted
## Parameters from app/workshop_stage.gd and luban_bridge/materials/redwood.gdshader.
## Pure, explicit helpers: no scene search, input handling, geometry or camera edits.
const WOOD_DARK = Vector3(0.25, 0.085, 0.043)
const WOOD_LIGHT = Vector3(0.43, 0.185, 0.095)

static func lighting(env: Environment, key: DirectionalLight3D, fill: DirectionalLight3D, shadow_distance_m: float = 3.0) -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("eae6df")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.48
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	key.rotation_degrees = Vector3(-62, -32, 0)
	key.light_energy = 0.8
	key.light_color = Color(1, 0.99, 0.97)
	key.light_angular_distance = 1.1
	key.shadow_enabled = true
	key.shadow_bias = 0.025
	key.shadow_blur = 1.5
	key.directional_shadow_max_distance = shadow_distance_m
	fill.rotation_degrees = Vector3(-35, 145, 0)
	fill.light_energy = 0.28
	fill.light_color = Color.WHITE
	fill.shadow_enabled = false

static func ground_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("b9b8b6").srgb_to_linear()
	mat.roughness = 0.93
	return mat

static func wood_parameters(material: ShaderMaterial, part_id: String, grain_axis: Vector3 = Vector3.RIGHT) -> void:
	# Keeps the integrator's clipping/reveal shader and all its animation uniforms.
	# Supports the bridge shader and the current boat shader with shared color uniforms.
	if material.shader == null:
		return
	var uniforms: Dictionary = {}
	for item in material.shader.get_shader_uniform_list():
		uniforms[str(item.name)] = true
	var parameters := {
		"wood_dark": WOOD_DARK,
		"wood_light": WOOD_LIGHT,
		"grain_axis": grain_axis.normalized() if not grain_axis.is_zero_approx() else Vector3.RIGHT,
		"variation": float(posmod(part_id.hash(), 100)) / 100.0
	}
	for name in parameters:
		if uniforms.has(name):
			material.set_shader_parameter(name, parameters[name])
