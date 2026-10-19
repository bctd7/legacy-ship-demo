extends "res://levels/stage.gd"
## Explicit test replacement; never records a production completion.
func enter_stage(config: Dictionary, context: Dictionary) -> String:
	var error := super.enter_stage(config, context)
	if not error.is_empty(): return error
	if not bool(context.get("mock_mode", false)): return "Mock stages require explicit mock_mode."
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	center.add_child(column)
	var label := Label.new()
	label.add_theme_color_override("font_color", Color("263c44"))
	label.add_theme_font_size_override("font_size", 22)
	label.text = "测试占位 · %s\n仅验证流程，不代表组件可玩或正式完成。" % config.get("title", stage_id)
	column.add_child(label)
	var button := Button.new()
	button.text = "模拟本阶段完成"
	button.pressed.connect(func(): complete(); button.disabled = true)
	column.add_child(button)
	return ""

func complete(payload: Dictionary = {}) -> void:
	var data := payload.duplicate(true)
	data["mock_stage"] = stage_id
	report("completed", data)
