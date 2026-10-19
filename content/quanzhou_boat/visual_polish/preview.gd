extends SceneTree
## Standalone resource check and optional offscreen UI swatch. No boat code is loaded.
## Run from this directory: Godot --headless --path . --script preview.gd
## For an independent hidden-window render: Godot --path . --script preview.gd -- --render
var style: Script
var surface: Script

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var base := (get_script() as Script).resource_path.get_base_dir()
	style = load(base.path_join("bridge_style.gd"))
	surface = load(base.path_join("bridge_surface.gd"))
	assert(style != null and surface != null)
	var theme: Theme = style.theme()
	assert(theme.default_font_size == 16)
	assert(theme.get_color("font_color", "Label") == Color("443a30"))
	assert(theme.get_stylebox("normal", "Button").bg_color == Color("fbf8f2"))
	assert(theme.get_stylebox("hover", "Button").border_color == Color("c8b795"))
	assert(theme.get_stylebox("pressed", "Button").border_color == Color("b79865"))
	assert(theme.get_icon("grabber", "HSlider").get_width() == 14)
	var test_button := Button.new()
	test_button.disabled = true
	style.card(test_button, "locked")
	assert(test_button.disabled)
	test_button.free()
	var env := Environment.new()
	var key := DirectionalLight3D.new()
	var fill := DirectionalLight3D.new()
	surface.lighting(env, key, fill, 12.0)
	assert(is_equal_approx(env.ambient_light_energy, 0.48))
	assert(is_equal_approx(key.light_energy, 0.8))
	assert(is_equal_approx(key.directional_shadow_max_distance, 12.0))
	assert(is_equal_approx(fill.light_energy, 0.28))
	key.free()
	fill.free()
	# Prove wood tuning leaves animation uniforms intact; the shader is only a fixture.
	var shader := Shader.new()
	shader.code = "shader_type spatial; uniform vec3 wood_dark; uniform vec3 wood_light; uniform vec3 grain_axis; uniform float variation; uniform bool section_enabled; uniform float reveal_limit; void fragment() { ALBEDO = wood_light; }"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("section_enabled", true)
	mat.set_shader_parameter("reveal_limit", 0.37)
	surface.wood_parameters(mat, "preview")
	assert(mat.get_shader_parameter("section_enabled") == true)
	assert(is_equal_approx(mat.get_shader_parameter("reveal_limit"), 0.37))
	assert(mat.get_shader_parameter("wood_dark") == surface.WOOD_DARK)
	print("VISUAL_POLISH_CHECK_OK: bridge palette, control states, lighting, clipping/reveal preserved")
	if "--render" not in OS.get_cmdline_user_args():
		quit(0)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Use a rendering display driver for --render; headless is resource validation only.")
		quit(1)
		return
	# The launcher uses WindowStyle Hidden. Do not minimize: that suspends GPU
	# draws on Windows. This independent swatch window must never take focus.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1400, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var bg := ColorRect.new()
	bg.color = style.BACKGROUND
	bg.size = viewport.size
	bg.theme = theme
	viewport.add_child(bg)
	_add_label(bg, "泉州宋船", Vector2(34, 18), "title")
	_add_label(bg, "木作装配  /  观察 · 拿起 · 契合", Vector2(204, 34), "caption", true)
	var tools := HBoxContainer.new()
	tools.position = Vector2(820, 20)
	tools.add_theme_constant_override("separation", 10)
	bg.add_child(tools)
	for text in ["整船查看", "分组装配", "视角复位", "更多 ···"]:
		var b := Button.new()
		b.text = text
		b.custom_minimum_size = Vector2(120, 48)
		tools.add_child(b)
	var paper := _card(bg, Vector2(34, 110), Vector2(310, 465), 20)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	paper.add_child(column)
	for item in [["已装 03 / 12 · 可用 4 件", "caption"], ["船板平接", "section"], ["先观察接触面，再拖动木件。", "body"], ["木板接缝需紧固与密封。", "caption"]]:
		var label := Label.new()
		label.text = item[0]
		style.label(label, item[1], item[1] == "caption")
		column.add_child(label)
	var progress := ProgressBar.new()
	progress.value = 25
	progress.show_percentage = false
	progress.custom_minimum_size.y = 4
	column.add_child(progress)
	for text in ["重播装配", "分离 / 合拢接触面"]:
		var b := Button.new()
		b.text = text
		b.custom_minimum_size.y = 48
		column.add_child(b)
	var options := OptionButton.new()
	options.add_item("船板平接")
	options.add_item("龙骨短斜接")
	options.custom_minimum_size.y = 48
	column.add_child(options)
	var slider := HSlider.new()
	slider.value = 55
	slider.custom_minimum_size.y = 30
	column.add_child(slider)
	var disabled := Button.new()
	disabled.text = "接头演示完成"
	disabled.disabled = true
	disabled.custom_minimum_size.y = 48
	column.add_child(disabled)
	_add_label(bg, "样式校样 · 此处不加载船、不包含装配交互", Vector2(460, 300), "section")
	_add_label(bg, "模型、镜头与动画由集成场景提供。", Vector2(460, 347), "body", true)
	var feedback := _add_label(bg, "位置正确，可以契合。", Vector2(36, 705), "body")
	style.feedback(feedback, "success")
	var tray := _card(bg, Vector2(24, 742), Vector2(1352, 131), 12)
	var stack := VBoxContainer.new()
	tray.add_child(stack)
	var heading := Label.new()
	heading.text = "构件托盘 · 亮色木件可装，按住拖动，单击只选中"
	style.label(heading, "footnote", true)
	stack.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	stack.add_child(row)
	var captions := {"available":"可装配", "selected":"已选中", "installed":"已安装", "locked":"待前序完成"}
	for state in captions:
		var b := Button.new()
		b.text = captions[state]
		b.custom_minimum_size = Vector2(180, 74)
		style.card(b, state)
		b.disabled = state in ["installed", "locked"]
		row.add_child(b)
	_add_label(bg, "资源校样，不代表考古复原或力学模拟。", Vector2(36, 876), "footnote", true)
	await process_frame
	await process_frame
	# Hidden/offscreen Windows windows can suspend automatic presentation.
	# Explicitly draw the independent SubViewport before reading its texture.
	RenderingServer.force_draw(false)
	var output := base.path_join("preview.png")
	var err := viewport.get_texture().get_image().save_png(output)
	assert(err == OK)
	print("VISUAL_POLISH_PREVIEW_OK: ", output)
	quit(0)

func _add_label(parent: Node, text: String, position: Vector2, role: String, muted: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = position
	style.label(label, role, muted)
	parent.add_child(label)
	return label

func _card(parent: Node, position: Vector2, size: Vector2, padding: int) -> PanelContainer:
	var node := PanelContainer.new()
	node.position = position
	node.size = size
	node.add_theme_stylebox_override("panel", style.panel(style.PAPER, padding, 16, true))
	parent.add_child(node)
	return node
