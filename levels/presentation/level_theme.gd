extends RefCounted
## Presentation only. No stage, model, input, or document decisions.
const BACKGROUND := Color("eae6df")
const PAPER := Color("fbf8f2")
const INK := Color("443a30")
const MUTED := Color("8a7d6c")
const LINE := Color("ded7cb")
const ACCENT := Color("806044")

static func panel(fill: Color = PAPER, border: Color = LINE, radius: int = 10, padding: int = 12) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

static func make() -> Theme:
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	font.font_weight = 400
	theme.default_font = font
	theme.default_font_size = 15
	for kind in ["Label", "CheckButton", "CheckBox"]:
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(key, kind, INK)
	for kind in ["Button", "OptionButton", "ColorPickerButton"]:
		theme.set_stylebox("normal", kind, panel())
		theme.set_stylebox("hover", kind, panel(Color("f3ede2"), Color("c8b795")))
		theme.set_stylebox("pressed", kind, panel(Color("e9dfcf"), Color("b79865")))
		theme.set_stylebox("disabled", kind, panel(Color("eee9e0"), Color("e2dbcf")))
		theme.set_stylebox("focus", kind, panel(Color(0, 0, 0, 0), Color("a78a60")))
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(key, kind, INK)
		theme.set_color("font_disabled_color", kind, Color("aca08f"))
	theme.set_stylebox("normal", "LineEdit", panel(Color.WHITE))
	theme.set_color("font_color", "LineEdit", INK)
	theme.set_color("font_uneditable_color", "LineEdit", MUTED)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	var track := panel(Color("d9d0c3"), Color("d9d0c3"), 3, 2)
	var filled := panel(Color("a68a64"), Color("a68a64"), 3, 2)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_constant("separation", "HBoxContainer", 10)
	theme.set_constant("h_separation", "HFlowContainer", 10)
	theme.set_constant("v_separation", "HFlowContainer", 8)
	var paper := panel(Color.WHITE, Color("d3c9ba"), 1, 0)
	paper.shadow_color = Color(0.24, 0.19, 0.13, 0.10)
	paper.shadow_size = 8
	paper.shadow_offset = Vector2(0, 4)
	theme.set_stylebox("paper", "DrawingSurface", paper)
	theme.set_stylebox("material_card", "DrawingSurface", panel(PAPER, LINE, 10, 0))
	theme.set_stylebox("material_card_placed", "DrawingSurface", panel(Color("f0ebe2"), Color("d9cebd"), 10, 0))
	theme.set_color("target_fill", "DrawingSurface", Color(0.65, 0.52, 0.33, 0.025))
	theme.set_color("target_fill_hot", "DrawingSurface", Color(0.65, 0.52, 0.33, 0.10))
	theme.set_color("target_border", "DrawingSurface", Color("c9bfaf"))
	theme.set_color("target_border_hot", "DrawingSurface", Color("a18252"))
	theme.set_color("material_label", "DrawingSurface", INK)
	theme.set_color("material_status", "DrawingSurface", MUTED)
	theme.set_constant("separate_material_status", "DrawingSurface", 1)
	theme.set_constant("locked_preview_opacity_percent", "DrawingSurface", 45)
	return theme

static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", panel(ACCENT, ACCENT))
	button.add_theme_stylebox_override("hover", panel(Color("6f5139"), Color("6f5139")))
	button.add_theme_stylebox_override("pressed", panel(Color("60452f"), Color("60452f")))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, Color("fffaf1"))
