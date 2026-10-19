extends VBoxContainer
## Drawing host presentation: existing public component operations, no document rules.
const Palette = preload("res://levels/presentation/level_theme.gd")
const Toolbar = preload("res://drawing/drawing_toolbar.gd")
var surface: Control
var toolbar: HFlowContainer

func build(for_surface: Control, config: Dictionary) -> void:
	surface = for_surface
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_constant_override("separation", 8)
	var tools_panel := PanelContainer.new()
	tools_panel.add_theme_stylebox_override("panel", Palette.panel())
	add_child(tools_panel)
	toolbar = Toolbar.new()
	tools_panel.add_child(toolbar)
	toolbar.configure(surface, {"eraser_label": "橡皮", "color_width": 54, "show_width_label": false})
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "清空纸面笔画？素材会保留，可撤销。"
	dialog.confirmed.connect(func(): surface.cancel_gesture(); surface.document.clear_strokes(true))
	add_child(dialog)
	toolbar.clear_requested.connect(func(): dialog.popup_centered())
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(surface)
	var note := Label.new()
	note.text = str(config.get("composition_note", "将配置的 2D 图片拖入固定区域后自由绘画。"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Palette.MUTED)
	add_child(note)
