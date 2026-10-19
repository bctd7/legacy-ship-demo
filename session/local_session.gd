extends RefCounted
## One authoritative state: slot->stock type, plus completed non-placement actions.
signal changed(snapshot: Dictionary)
signal rejected(message: String)
signal animation_requested(step: Dictionary,ticket: int)
var data: Dictionary
var rules
var placements: Dictionary={}
var completed_actions: Array=[]
var revision: int=0
var serial: int=0
var _pending: Dictionary={}
func _init(config: Dictionary,model_rules) -> void:data=config;rules=model_rules
func is_busy() -> bool:return not _pending.is_empty()
func is_action_pending(action_id: String) -> bool:return is_busy() and _pending.commit.kind=="action" and _pending.commit.action_id==action_id
func pending_ticket() -> int:return int(_pending.ticket) if is_busy() else -1
func _state() -> Dictionary:return {"placements":placements,"completed_actions":completed_actions}
func snapshot() -> Dictionary:
	return {"schema":3,"content_id":data.id,"content_version":data.version,"ruleset_version":data.ruleset_version,"placements":placements.duplicate(true),"completed_actions":completed_actions.duplicate(),"revision":revision,"busy":not _pending.is_empty()}
func view_state() -> Dictionary:return rules.describe_state(_state())
func availability(id: String) -> Dictionary:return rules.availability(id,_state())
func target_options(id: String) -> Array:return rules.target_options(id,_state())
func request_install(request: Dictionary) -> Dictionary:
	if not _pending.is_empty():return reject("当前动作尚未完成。")
	if int(request.get("expected_revision",-1))!=revision:return reject("状态已变化，请重新选择。")
	var result: Dictionary=rules.validate(request,_state())
	if not result.ok:return reject(result.message)
	serial+=1
	_pending={"ticket":serial,"commit":result.commit.duplicate(true)}
	changed.emit(snapshot())
	animation_requested.emit(result.step,serial)
	return {"ok":true,"ticket":serial}
func finish_animation(ticket: int) -> bool:
	if _pending.is_empty() or int(_pending.ticket)!=ticket:return false
	var commit: Dictionary=_pending.commit
	if commit.kind=="placement":placements[commit.slot_id]=commit.type_id
	else:completed_actions.append(commit.action_id)
	_pending.clear();revision+=1
	changed.emit(snapshot())
	return true
func cancel_pending() -> bool:
	if _pending.is_empty():return false
	serial+=1;_pending.clear();revision+=1
	changed.emit(snapshot())
	return true
func reset() -> void:
	serial+=1;_pending.clear();placements.clear();completed_actions.clear();revision+=1
	changed.emit(snapshot())
func restore(saved: Dictionary) -> Dictionary:
	if not _pending.is_empty():return reject("动作进行中不能恢复，请先取消或重置。")
	if saved.get("content_id")!=data.id or saved.get("content_version")!=data.version:return reject("快照与内容包不匹配。")
	var state: Dictionary={}
	if saved.get("schema")==3:
		var normalized: Dictionary=rules.normalize_snapshot_state({"placements":saved.get("placements",null),"completed_actions":saved.get("completed_actions",null)},str(saved.get("ruleset_version","")))
		if not normalized.ok:return reject(normalized.message)
		state=normalized.state
	elif saved.get("schema")==2:
		if not saved.get("completed_ids") is Array:return reject("旧快照无效。")
		var migrated: Dictionary=rules.migrate_ids(saved.completed_ids)
		if not migrated.ok:return reject(migrated.message)
		state=migrated.state
	elif saved.get("schema")==1:
		var ids: Array=[]
		var legacy=saved.get("completed_steps",null)
		if not legacy is Array or legacy.size()>data.steps.size():return reject("旧快照无效。")
		for i in range(legacy.size()):
			if legacy[i]!=data.steps[i].id:return reject("旧快照前缀无效。")
			ids.append(data.steps[i].part_id)
		var migrated: Dictionary=rules.migrate_ids(ids)
		if not migrated.ok:return reject(migrated.message)
		state=migrated.state
	else:return reject("未知快照格式。")
	var result: Dictionary=rules.validate_state(state)
	if not result.ok:return reject(result.message)
	placements=state.placements.duplicate(true);completed_actions=state.completed_actions.duplicate();revision+=1
	changed.emit(snapshot())
	return {"ok":true}
func reject(message: String) -> Dictionary:
	rejected.emit(message)
	return {"ok":false,"message":message}
