extends Node
## Composition root: content + local session + generic interaction + exhibition UI.
const Rules = preload("res://content/luban_bridge/bridge_rules.gd")
const Session = preload("res://session/local_session.gd")
const Presenter = preload("res://content/luban_bridge/bridge_presenter.gd")
const Orbit = preload("res://interaction/orbit_camera.gd")
const Drag = preload("res://interaction/drag_interaction.gd")
const Stage = preload("res://app/workshop_stage.gd")
var data: Dictionary
var session
var presenter
var orbit
var interaction
var ui
var camera: Camera3D
var viewport: SubViewport
var view: SubViewportContainer
var tray: Control
var feedback: Label
var target_label: Label
var selected: int = 0
var observing: bool = false
var modal: bool = false
var state_info: Dictionary = {}

func _ready() -> void:
	DisplayServer.window_set_title("鲁班桥 · 木作展台")
	data = JSON.parse_string(FileAccess.get_file_as_string("res://content/luban_bridge/content.json"))
	session = Session.new(data,Rules.new(data))
	ui = preload("res://ui/workshop_ui.gd").new()
	add_child(ui)
	ui.build(data)
	view = ui.view
	viewport = ui.viewport
	feedback = ui.feedback
	target_label = ui.target_label
	presenter=Presenter.new()
	camera=Stage.build(viewport,presenter)
	presenter.setup(data)
	orbit = Orbit.new(camera)
	interaction = Drag.new()
	interaction.camera = camera
	interaction.view = view
	interaction.presenter = presenter
	interaction.orbit = orbit
	interaction.card_lookup = ui.card_at
	interaction.pick_id_lookup = _resolve_pick
	interaction.pointer_blocked = ui.world_input_blocked
	interaction.install_requested.connect(_install)
	interaction.part_picked.connect(_pick_part)
	interaction.drag_changed.connect(_drag_feedback)
	interaction.target_changed.connect(_target_changed)
	interaction.cancel_requested.connect(_cancel_operation)
	add_child(interaction)
	ui.step_selected.connect(_choose)
	ui.observe_requested.connect(_toggle_observe)
	ui.reset_requested.connect(reset_workshop)
	ui.view_reset_requested.connect(func(): interaction.cancel(); orbit.reset_view())
	ui.modal_changed.connect(_modal_changed)
	ui.withdraw_requested.connect(_withdraw_shortcut)
	session.changed.connect(_state_changed)
	session.rejected.connect(func(message): _message(message,true))
	session.animation_requested.connect(presenter.animate_step)
	presenter.animation_done.connect(func(ticket): session.finish_animation(ticket))
	_state_changed(session.snapshot())
	_message("按住下方木件缩略图，拖到连接位置。",false)
	var thumbnails = preload("res://content/luban_bridge/thumbnail_baker.gd").new()
	add_child(thumbnails)
	thumbnails.ready_images.connect(ui.images_ready)
	thumbnails.bake(presenter,data.tray_entries)

func _choose(index: int) -> void:
	if interaction!=null and interaction.held:return
	if index<0 or index>=data.tray_entries.size():return
	selected=index
	var entry: Dictionary=data.tray_entries[index]
	var status: Dictionary=session.availability(entry.id)
	var options: Array=[]
	var slot: Dictionary={}
	var gesture={"mode":"place"}
	if entry.kind=="withdraw":
		var step: Dictionary=session.rules.step_for_part(data.withdraw_action_id)
		slot=step.slot.duplicate(true);gesture=step.interaction
	else:
		options=session.target_options(entry.id)
		for target in options:
			if target.compatible and (slot.is_empty() or target.allowed):
				slot=target
				if target.allowed:break
	interaction.choose(entry.id,slot,status.allowed,session.revision,gesture,options)
	tray=ui.cards[index];interaction.tray=tray
	ui.set_state(selected,_summary(),session.is_busy(),observing,_withdraw_busy())
	target_label.text="↓  轻拖支撑，或点撤除按钮" if entry.kind=="withdraw" else "拖到任一亮起的兼容空位"

func _resolve_pick(id: String) -> String:
	if data.get("pick_aliases",{}).has(id):return data.withdraw_action_id
	var step: Dictionary=session.rules.step_for_part(id)
	if step.is_empty() or step.action_kind!="install":return ""
	return session.rules.display_item_for_type(data.slot_type_map[step.slot.id])

func _pick_part(id: String) -> void:
	for i in range(data.tray_entries.size()):
		if data.tray_entries[i].id==id:
			_choose(i);return
	var resolved=_resolve_pick(id)
	for i in range(data.tray_entries.size()):
		if data.tray_entries[i].id==resolved:_choose(i);return

func _withdraw_busy() -> bool:
	return session.is_action_pending(data.withdraw_action_id)

func _withdraw_shortcut() -> void:
	if _withdraw_busy():
		_cancel_operation();return
	var result: Dictionary=session.request_install({"action_id":data.withdraw_action_id,"source":"shortcut","expected_revision":session.revision})
	if result.ok:_message("正在受控撤除；可点取消或按 Esc。",false)

func _cancel_operation() -> void:
	if _withdraw_busy():
		session.cancel_pending()
		_message("已取消撤除，支撑仍保持在位。",false)
	else:_message("已取消拖动，库存与槽位不变。",false)

func _install(request: Dictionary) -> void:
	var result: Dictionary = session.request_install(request)
	if result.ok:
		_message("支撑正在沿原验证路径向下撤出。" if data.tray_entries[selected].kind=="withdraw" else "木件正在沿验证路径贴合。",false)

func _summary() -> Dictionary:
	return session.view_state()

func _recommended_index() -> int:
	var id: String = _summary().recommended_id
	for i in range(data.tray_entries.size()):
		if data.tray_entries[i].id==id:return i
	return selected

func _state_changed(state: Dictionary) -> void:
	state_info = _summary()
	_refresh_interaction()
	if not state.busy:
		presenter.sync(state_info.completed_ids)
		if not state_info.finished:
			if not session.availability(data.tray_entries[selected].id).allowed:
				selected = _recommended_index()
			_choose(selected)
			if state_info.installed_count==state_info.install_total:
				_message("正式木件已齐：选中蓝色支撑，向下拖至绿色后松手。",false)
			else:
				_message("已装 %d 件，当前 %d 件可装；同组木件可任选先后。" % [state_info.installed_count,state_info.available_units],false)
		else:
			_message("装配完成。支撑与操作辅助已撤除。",false)
	ui.set_state(selected,state_info,state.busy,observing,_withdraw_busy())

func _toggle_observe() -> void:
	if session.is_busy():
		return
	interaction.cancel()
	observing = not observing
	presenter.show_complete(observing)
	_refresh_interaction()
	if not observing:
		presenter.sync(state_info.completed_ids)
		if not _summary().finished:
			_choose(selected)
	ui.set_state(selected,_summary(),false,observing,false)
	_message("完整模型观察 · 左键空白或右键旋转，中键平移，滚轮缩放。" if observing else ("装配完成，所有操作辅助已撤除。" if _summary().finished else "已返回装配，当前进度保留。"),false)

func reset_workshop() -> void:
	interaction.cancel()
	observing = false
	presenter.show_complete(false)
	session.reset()
	_message("已重新开始，先拿起第一个木件。",false)

func _modal_changed(active: bool) -> void:
	modal = active
	interaction.cancel()
	_refresh_interaction()

func _refresh_interaction() -> void:
	interaction.camera_enabled=not modal
	interaction.enabled=not session.is_busy() and not observing and not modal and not _summary().finished

func _drag_feedback(active: bool, near: bool) -> void:
	if active:
		if data.tray_entries[selected].kind=="withdraw":
			_message("已到撤除阈值，松手完成受控撤除。" if near else "沿向下箭头拉动支撑，变绿后松手。",false)
		else:
			_message("位置正确，松手贴合。" if near else "将木件移至当前连接位置。",false)

func _target_changed(target: Dictionary,near: bool) -> void:
	target_label.text="目标："+str(target.get("label","未进入槽位"))+(" · 松手装入" if near else "")
	if not interaction.hover_slot_id.is_empty() and not target.get("reason","").is_empty():_message(target.reason,not target.get("allowed",false))

func _message(text: String,error: bool) -> void:
	if ui.set_feedback(text,error): print("WORKSHOP: ",text)

func _process(_delta: float) -> void:
	if camera==null or data.is_empty():
		return
	target_label.visible = not observing and not session.is_busy() and not state_info.finished and session.availability(data.tray_entries[selected].id).allowed
	if target_label.visible:
		var slot: Dictionary=interaction.hover_target if not interaction.hover_target.is_empty() else interaction.selection.origin_slot
		var anchor = Rules.vector(slot.get("trigger_point_m",slot.get("marker_points_m",[slot.anchor_m])[0]))
		var rect = view.get_global_rect()
		target_label.position = rect.position+camera.unproject_position(anchor)+Vector2(14,-32)
		target_label.position.x = clampf(target_label.position.x,rect.position.x+320,rect.end.x-245)
		target_label.position.y = clampf(target_label.position.y,rect.position.y+20,rect.end.y-40)
