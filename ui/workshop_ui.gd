extends CanvasLayer
## Exhibition layout, thumbnail cards and menu intents. No assembly state mutation.
signal step_selected(index: int)
signal observe_requested
signal reset_requested
signal view_reset_requested
signal modal_changed(active: bool)
signal withdraw_requested
const INK = Color("443a30")
const MUTED = Color("8e8173")
const PAPER = Color("fbf8f2")
const LINE = Color("ded7cb")
var data: Dictionary
var root_control: Control
var view: SubViewportContainer
var viewport: SubViewport
var step_card: PanelContainer
var count_label: Label
var step_title: Label
var action_label: Label
var condition_label: Label
var feedback: Label
var target_label: Label
var progress: ProgressBar
var tray_scroll: ScrollContainer
var cards: Array = []
var pictures: Array = []
var captions: Array = []
var more_button: MenuButton
var reset_dialog: Control
var reset_cancel: Button
var reset_confirm: Button
var hint_panel: PanelContainer
var _feedback_state: Dictionary = {}
var withdraw_button: Button
var withdraw_note: Label
var reveal_serial: int = 0

func set_feedback(text: String, error: bool) -> bool:
	var state := {"text": text, "error": error}
	if _feedback_state == state: return false
	_feedback_state = state
	feedback.text = text
	feedback.add_theme_color_override("font_color", Color("9a5140") if error else Color("627455"))
	return true

func label(text: String, size: int = 16, color: Color = INK) -> Label:
	var node = Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func style(color: Color, border: Color = LINE, radius: int = 14, padding: int = 16) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.content_margin_left = padding
	box.content_margin_right = padding
	box.content_margin_top = padding
	box.content_margin_bottom = padding
	return box

func decorate_button(node: Button) -> void:
	node.custom_minimum_size = Vector2(96,48)
	node.add_theme_stylebox_override("normal",style(PAPER,LINE,12,12))
	node.add_theme_stylebox_override("hover",style(Color("f3ede2"),Color("c8b795"),12,12))
	node.add_theme_stylebox_override("pressed",style(Color("e9dfcf"),Color("b79865"),12,12))
	node.add_theme_stylebox_override("focus",style(Color(0,0,0,0),Color("b79865"),12,12))
	node.add_theme_color_override("font_color",INK)
	node.add_theme_color_override("font_hover_color",INK)
	node.add_theme_color_override("font_pressed_color",INK)
	node.add_theme_font_size_override("font_size",15)

func button(text: String, callback: Callable) -> Button:
	var node = Button.new()
	node.text = text
	decorate_button(node)
	node.pressed.connect(callback)
	return node

func build(config: Dictionary) -> void:
	data = config
	root_control = Control.new()
	root_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC"])
	theme.default_font = font
	theme.default_font_size = 16
	root_control.theme = theme
	add_child(root_control)
	var background = ColorRect.new()
	background.color = Color("eae6df")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(background)
	var title = label("鲁班桥",30)
	title.position = Vector2(34,18)
	root_control.add_child(title)
	var subtitle = label("木作装配  /  观察 · 拿起 · 契合",14,MUTED)
	subtitle.position = Vector2(158,34)
	root_control.add_child(subtitle)
	var tools = HBoxContainer.new()
	tools.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tools.offset_left = -480
	tools.offset_right = -28
	tools.offset_top = 20
	tools.offset_bottom = 68
	tools.add_theme_constant_override("separation",10)
	root_control.add_child(tools)
	tools.add_child(label("空白拖动旋转",14,MUTED))
	tools.add_child(button("↺  视角复位",func(): view_reset_requested.emit()))
	tools.add_child(button("?  提示",func(): hint_panel.visible = not hint_panel.visible))
	more_button = MenuButton.new()
	more_button.text = "更多  ···"
	decorate_button(more_button)
	more_button.get_popup().add_item("观察完整模型",0)
	more_button.get_popup().add_separator()
	more_button.get_popup().add_item("重置装配…",1)
	more_button.get_popup().id_pressed.connect(_menu_action)
	tools.add_child(more_button)
	view = SubViewportContainer.new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.offset_top = 84
	view.offset_bottom = -198
	view.stretch = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(view)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1400,618)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.add_child(viewport)
	step_card = PanelContainer.new()
	step_card.position = Vector2(34,110)
	step_card.size = Vector2(268,204)
	var card_style = style(PAPER,Color("e0d9cf"),16,20)
	card_style.shadow_color = Color(0.25,0.20,0.15,0.07)
	card_style.shadow_size = 12
	card_style.shadow_offset = Vector2(0,4)
	step_card.add_theme_stylebox_override("panel",card_style)
	root_control.add_child(step_card)
	var step_info = VBoxContainer.new()
	step_info.add_theme_constant_override("separation",9)
	step_card.add_child(step_info)
	count_label = label("",13,MUTED)
	step_info.add_child(count_label)
	step_title = label("",21)
	step_info.add_child(step_title)
	action_label = label("",15)
	action_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_label.custom_minimum_size.x = 228
	step_info.add_child(action_label)
	condition_label = label("",13,MUTED)
	condition_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	step_info.add_child(condition_label)
	progress = ProgressBar.new()
	progress.max_value = data.installable_part_ids.size()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 4
	progress.add_theme_stylebox_override("background",style(Color("e9e2d7"),Color("e9e2d7"),2,0))
	progress.add_theme_stylebox_override("fill",style(Color("a48352"),Color("a48352"),2,0))
	step_info.add_child(progress)
	withdraw_button=button("撤除辅助支撑",func(): withdraw_requested.emit())
	step_info.add_child(withdraw_button)
	withdraw_note=label("",12,MUTED)
	withdraw_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	step_info.add_child(withdraw_note)
	hint_panel = PanelContainer.new()
	hint_panel.position = Vector2(34,334)
	hint_panel.size = Vector2(268,140)
	hint_panel.add_theme_stylebox_override("panel",style(PAPER,LINE,14,16))
	hint_panel.visible = false
	root_control.add_child(hint_panel)
	var help = label("左键命中零件：拖动零件。\n左键空白或右键：旋转。\n中键拖动：小范围平移。\n滚轮缩放，视角复位还原。",14,MUTED)
	hint_panel.add_child(help)
	target_label = label("",16,Color("687e5e"))
	target_label.add_theme_color_override("font_shadow_color",PAPER)
	target_label.add_theme_constant_override("shadow_offset_x",1)
	target_label.add_theme_constant_override("shadow_offset_y",1)
	root_control.add_child(target_label)
	feedback = label("",15)
	feedback.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	feedback.offset_left = 36
	feedback.offset_right = -36
	feedback.offset_top = -195
	feedback.offset_bottom = -170
	root_control.add_child(feedback)
	var tray_panel = PanelContainer.new()
	tray_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	tray_panel.offset_left = 24
	tray_panel.offset_right = -24
	tray_panel.offset_top = -158
	tray_panel.offset_bottom = -27
	tray_panel.add_theme_stylebox_override("panel",style(PAPER,Color("e1dacd"),18,12))
	root_control.add_child(tray_panel)
	var tray_stack = VBoxContainer.new()
	tray_stack.add_theme_constant_override("separation",5)
	tray_panel.add_child(tray_stack)
	var tray_heading = label("构件托盘   ·   亮色木件均可装，按住拖动；单击只选中",12,MUTED)
	tray_stack.add_child(tray_heading)
	tray_scroll = ScrollContainer.new()
	tray_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tray_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tray_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tray_stack.add_child(tray_scroll)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	tray_scroll.add_child(row)
	for i in range(data.tray_entries.size()):
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(128,86)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.set_meta("part_id",data.tray_entries[i].id)
		card.add_theme_stylebox_override("panel",style(Color("f6f2e9"),Color("e8e1d5"),10,5))
		var stack = VBoxContainer.new()
		stack.add_theme_constant_override("separation",0)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(stack)
		var picture = TextureRect.new()
		picture.custom_minimum_size = Vector2(118,54)
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(picture)
		var short_name: String = data.tray_entries[i].label
		var caption = label(short_name,12)
		caption.set_meta("short_name",short_name)
		captions.append(caption)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(caption)
		cards.append(card)
		pictures.append(picture)
		row.add_child(card)
	var limit = label("受控装配演示 · 临时蓝色支撑在最后一步撤出 · 不作承载模拟",11,MUTED)
	limit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	limit.offset_left = 36
	limit.offset_top = -22
	limit.offset_bottom = -3
	root_control.add_child(limit)
	reset_dialog = Control.new()
	reset_dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(reset_dialog)
	var scrim = ColorRect.new()
	scrim.color = Color(0.16,0.13,0.10,0.22)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reset_dialog.add_child(scrim)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	reset_dialog.add_child(center)
	var confirmation = PanelContainer.new()
	confirmation.custom_minimum_size = Vector2(430,210)
	confirmation.add_theme_stylebox_override("panel",style(PAPER,LINE,18,28))
	center.add_child(confirmation)
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation",18)
	confirmation.add_child(stack)
	stack.add_child(label("重新开始装配？",23))
	stack.add_child(label("本轮进度将清空，木件会回到托盘。",15,MUTED))
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation",14)
	stack.add_child(actions)
	reset_cancel = button("继续装配",func(): reset_dialog.hide())
	reset_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(reset_cancel)
	reset_confirm = button("确认重置",func(): reset_dialog.hide(); reset_requested.emit())
	reset_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(reset_confirm)
	reset_dialog.hide()
	reset_dialog.visibility_changed.connect(func(): modal_changed.emit(reset_dialog.visible))

func _menu_action(id: int) -> void:
	if id == 0:
		observe_requested.emit()
	elif id == 1:
		reset_dialog.show()

func world_input_blocked(point: Vector2) -> bool:
	if reset_dialog.visible: return true
	return (step_card.visible and step_card.get_global_rect().has_point(point)) or (hint_panel.visible and hint_panel.get_global_rect().has_point(point))

func card_at(point: Vector2) -> String:
	if not tray_scroll.get_global_rect().has_point(point):
		return ""
	for card in cards:
		if card.get_global_rect().has_point(point):
			return card.get_meta("part_id")
	return ""

func images_ready(images: Array) -> void:
	for i in range(mini(images.size(),pictures.size())):
		pictures[i].texture = images[i]

func set_state(selected: int,state: Dictionary,busy: bool,observing: bool,cancel_withdraw: bool=false) -> void:
	count_label.text="已装 %02d / %02d · 可用 %d 件"%[state.installed_count,state.install_total,state.available_units]
	progress.value=state.installed_count
	more_button.disabled=busy
	more_button.get_popup().set_item_text(0,"返回装配" if observing else "观察完整模型")
	withdraw_button.text="取消撤除" if cancel_withdraw else ("辅助已撤除" if state.finished else "撤除辅助支撑")
	withdraw_button.disabled=not cancel_withdraw and (not state.withdraw_ready or busy or observing)
	withdraw_note.text="可点取消，或按 Esc；进度不会提前提交。" if cancel_withdraw else ("正式件已齐，可直接点击撤除。" if state.withdraw_ready else ("已完成收尾。" if state.finished else "正式件装齐后可用，还缺 %d 件。"%(state.install_total-state.installed_count)))
	if state.finished:
		step_title.text="装配完成"
		action_label.text="全部正式桥件已就位。"
		condition_label.text="辅助支撑、吊索和提示均已清理。"
	else:
		var entry: Dictionary=data.tray_entries[selected]
		var status: Dictionary=state.statuses[entry.id]
		step_title.text=entry.label
		action_label.text="可轻轻斜向下拖，也可点撤除按钮。" if entry.kind=="withdraw" else entry.get("action_hint","拿起该规格，可放任意亮起的兼容空位。")
		condition_label.text=status.reason
	for i in range(cards.size()):
		var entry: Dictionary=data.tray_entries[i]
		var status: Dictionary=state.statuses[entry.id]
		cards[i].visible=not(state.finished and entry.kind=="withdraw")
		cards[i].modulate=Color(1,1,1,1 if status.allowed else 0.52)
		cards[i].add_theme_stylebox_override("panel",style(Color("eee4d2") if status.allowed else Color("f6f2e9"),Color("b69a6c") if i==selected else LINE,10,5))
		captions[i].text=str(captions[i].get_meta("short_name"))+(" ×%d"%status.remaining if entry.kind=="stock" else "")
	if not busy and not state.finished:reveal_selected(selected)

func reveal_selected(index: int) -> void:
	# A restored support card may have just become visible; wait for container layout.
	reveal_serial+=1
	var ticket = reveal_serial
	await get_tree().process_frame
	if ticket==reveal_serial and is_instance_valid(cards[index]) and cards[index].visible:
		tray_scroll.ensure_control_visible(cards[index])
