extends RefCounted
## Opt-in presentation only. Values come from the accepted bridge workshop.
## Does not connect signals, change disabled state, or mutate assembly state.
const INK = Color("443a30")
const MUTED = Color("8e8173")
const PAPER = Color("fbf8f2")
const LINE = Color("ded7cb")
const BACKGROUND = Color("eae6df")
const ACCENT = Color("a48352")
const SUCCESS = Color("627455")
const ERROR = Color("9a5140")
const TARGET = Color("687e5e")
const FONT_NAMES = ["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"]
const TYPE_SIZES = {"title":30, "section":21, "body":15, "button":15, "caption":13, "footnote":12}

static func panel(color: Color = PAPER, padding: int = 16, radius: int = 14, shadow: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = LINE
	s.set_border_width_all(1)
	s.set_corner_radius_all(radius)
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = padding
	s.content_margin_bottom = padding
	if shadow:
		s.shadow_color = Color(0.25, 0.20, 0.15, 0.07)
		s.shadow_size = 12
		s.shadow_offset = Vector2(0, 4)
	return s

static func _border(color: Color, border: Color, padding: int = 12, radius: int = 12) -> StyleBoxFlat:
	var s := panel(color, padding, radius)
	s.border_color = border
	return s

static func _button_styles() -> Dictionary:
	return {
		"normal": _border(PAPER, LINE),
		"hover": _border(Color("f3ede2"), Color("c8b795")),
		"pressed": _border(Color("e9dfcf"), Color("b79865")),
		"hover_pressed": _border(Color("e9dfcf"), Color("b79865")),
		"focus": _border(Color.TRANSPARENT, Color("b79865")),
		"disabled": _border(Color("f6f2e9"), Color("e8e1d5"))
	}

static func button(b: BaseButton) -> void:
	# Compatible with the integrator's current Style.button(b) call sites.
	var styles := _button_styles()
	for key in styles:
		b.add_theme_stylebox_override(key, styles[key])
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, INK)
	b.add_theme_color_override("font_disabled_color", MUTED)
	b.add_theme_font_size_override("font_size", 15)

static func label(node: Label, role: String = "body", muted: bool = false) -> void:
	node.add_theme_font_size_override("font_size", TYPE_SIZES.get(role, 15))
	node.add_theme_color_override("font_color", MUTED if muted else INK)
	# Use this instead of modulating an already brown text color.
	node.modulate = Color.WHITE

static func feedback(node: Label, state: String = "neutral") -> void:
	var colors := {"neutral": INK, "success": SUCCESS, "error": ERROR, "target": TARGET}
	node.add_theme_color_override("font_color", colors.get(state, INK))
	node.modulate = Color.WHITE

static func card(node: BaseButton, state: String = "available") -> void:
	# State is supplied by the owner. Never changes node.disabled or mouse_filter.
	button(node)
	var bg := Color("eee4d2") if state in ["available", "selected"] else Color("f6f2e9")
	var line := Color("b69a6c") if state == "selected" else LINE
	node.add_theme_stylebox_override("normal", _border(bg, line, 5, 10))
	node.add_theme_stylebox_override("disabled", _border(bg, line, 5, 10))
	node.add_theme_stylebox_override("hover", _border(Color("f3ede2"), Color("c8b795"), 5, 10))
	node.add_theme_stylebox_override("pressed", _border(Color("e9dfcf"), Color("b79865"), 5, 10))
	# Deliberately avoid dimming the parent: it would dim captions and thumbnails twice.

static func theme() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	t.default_font = font
	t.default_font_size = 16
	t.set_color("font_color", "Label", INK)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_constant("separation", "HBoxContainer", 8)
	t.set_constant("separation", "VBoxContainer", 9)
	for type in ["Button", "OptionButton", "MenuButton"]:
		var styles := _button_styles()
		for key in styles:
			t.set_stylebox(key, type, styles[key])
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			t.set_color(key, type, INK)
		t.set_color("font_disabled_color", type, MUTED)
		t.set_font_size("font_size", type, 15)
	t.set_stylebox("panel", "PopupMenu", panel(PAPER, 12, 12, true))
	t.set_stylebox("hover", "PopupMenu", _border(Color("f3ede2"), LINE, 8, 6))
	t.set_stylebox("separator", "PopupMenu", _border(LINE, LINE, 0, 0))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_disabled_color", "PopupMenu", MUTED)
	t.set_font_size("font_size", "PopupMenu", 15)
	t.set_constant("v_separation", "PopupMenu", 12)
	t.set_stylebox("background", "ProgressBar", _border(Color("e9e2d7"), Color("e9e2d7"), 0, 2))
	t.set_stylebox("fill", "ProgressBar", _border(ACCENT, ACCENT, 0, 2))
	for type in ["HScrollBar", "VScrollBar"]:
		t.set_stylebox("scroll", type, panel(Color("e9e2d7"), 4, 4))
		t.set_stylebox("grabber", type, _border(Color("c8b795"), Color("c8b795"), 4, 4))
		t.set_stylebox("grabber_highlight", type, _border(ACCENT, ACCENT, 4, 4))
		t.set_stylebox("grabber_pressed", type, _border(Color("b79865"), Color("b79865"), 4, 4))
	t.set_stylebox("slider", "HSlider", _border(Color("e9e2d7"), LINE, 2, 2))
	t.set_stylebox("grabber_area", "HSlider", _border(ACCENT, ACCENT, 2, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", _border(Color("b79865"), Color("b79865"), 2, 2))
	t.set_icon("grabber", "HSlider", _slider_knob(ACCENT))
	t.set_icon("grabber_highlight", "HSlider", _slider_knob(Color("b79865")))
	t.set_icon("grabber_disabled", "HSlider", _slider_knob(LINE))
	return t

static func _slider_knob(color: Color) -> ImageTexture:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	for y in range(14):
		for x in range(14):
			var coverage := clampf(6.5 - Vector2(x - 6.5, y - 6.5).length(), 0.0, 1.0)
			img.set_pixel(x, y, Color(color.r, color.g, color.b, coverage))
	return ImageTexture.create_from_image(img)
