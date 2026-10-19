extends "res://levels/stage.gd"

func enter_stage(config: Dictionary, context: Dictionary) -> String:
	var error := super.enter_stage(config, context)
	if not error.is_empty(): return error
	var label := Label.new()
	label.add_theme_color_override("font_color", Color("263c44"))
	label.add_theme_font_size_override("font_size", 22)
	label.text = str(config.get("message", "Component pending integration."))
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	center.add_child(label)
	report("pending_integration", {}, label.text)
	return ""
