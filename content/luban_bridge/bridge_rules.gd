extends RefCounted
## Bridge-owned stock compatibility, target-slot dependencies and withdrawal policy.
var data: Dictionary
func _init(config: Dictionary) -> void: data=config
func step_for_part(id: String) -> Dictionary:
	for step in data.steps:
		if step.part_id==id:return step
	return {}
func step_for_slot(id: String) -> Dictionary:
	for step in data.steps:
		if step.action_kind=="install" and step.slot.id==id:return step
	return {}
func type_for(id: String) -> Dictionary:
	for item in data.inventory_types:
		if item.id==id:return item
	return {}
func stock_members(id: String) -> Array:
	if not type_for(id).is_empty():return [id]
	for family in data.get("inventory_families",[]):
		if family.id==id:return family.member_type_ids
	return []
func display_item_for_type(id: String) -> String:
	for family in data.get("inventory_families",[]):
		if family.member_type_ids.has(id):return family.id
	return id
func completed_part_ids(state: Dictionary) -> Array:
	var ids: Array=[]
	for step in data.steps:
		if step.action_kind=="install" and state.placements.has(step.slot.id):ids.append(step.part_id)
	ids.append_array(state.completed_actions)
	return ids
func remaining(id: String,state: Dictionary) -> int:
	var item=type_for(id)
	if item.is_empty():
		var count: int=0
		for member in stock_members(id):count+=remaining(member,state)
		return count
	var used: int=0
	for value in state.placements.values():
		if value==id:used+=1
	return int(item.quantity)-used
func dependency_reason(step: Dictionary,state: Dictionary) -> String:
	var done=completed_part_ids(state)
	var names: Array[String]=[]
	var count: int=0
	for id in step.requires:
		if not done.has(id):
			count+=1
			if names.size()<2:names.append(str(step_for_part(id).label))
	if count==0:return ""
	return str(step.dependency_reason)+" 还缺："+"、".join(names)+("等%d件。"%count if count>2 else "。")
func availability(id: String,state: Dictionary) -> Dictionary:
	if id==data.withdraw_action_id:
		if state.completed_actions.has(id):return {"allowed":false,"reason":"辅助支撑已经撤除。","remaining":0}
		var reason=dependency_reason(step_for_part(id),state)
		return {"allowed":reason.is_empty(),"reason":reason if not reason.is_empty() else "可轻拖或点击快捷按钮撤除。","remaining":1}
	var members=stock_members(id)
	if members.is_empty():return {"allowed":false,"reason":"未知库存类型。","remaining":0}
	var count=remaining(id,state)
	if count<=0:return {"allowed":false,"reason":"该规格库存已用完。","remaining":0}
	var reason: String="没有兼容的空闲槽位。"
	for step in data.steps:
		if step.action_kind!="install" or not members.has(data.slot_type_map[step.slot.id]) or state.placements.has(step.slot.id):continue
		if remaining(data.slot_type_map[step.slot.id],state)<=0:continue
		var missing=dependency_reason(step,state)
		if missing.is_empty():return {"allowed":true,"reason":"可拖到任意亮起的兼容空位。","remaining":count}
		reason=missing
	return {"allowed":false,"reason":reason,"remaining":count}
func target_options(id: String,state: Dictionary) -> Array:
	var options: Array=[]
	for step in data.steps:
		if step.action_kind!="install":continue
		var required_type: String=data.slot_type_map[step.slot.id]
		var compatible: bool=stock_members(id).has(required_type)
		var vacant: bool=not state.placements.has(step.slot.id)
		var reason=dependency_reason(step,state)
		var allowed: bool=compatible and vacant and reason.is_empty() and remaining(required_type,state)>0
		if not compatible:reason="该槽位需要："+str(type_for(data.slot_type_map[step.slot.id]).label)
		elif not vacant:reason="这个槽位已占用，请选其他兼容空位。"
		elif allowed:reason=str(step.get("trigger_note",""))
		var option: Dictionary=step.slot.duplicate(true)
		option.merge({"part_id":step.part_id,"compatible":compatible,"allowed":allowed,"reason":reason,"label":step.label},true)
		options.append(option)
	return options
func describe_state(state: Dictionary) -> Dictionary:
	var statuses: Dictionary={}
	var available: Array=[]
	var units: int=0
	for entry in data.tray_entries:
		var status=availability(entry.id,state)
		statuses[entry.id]=status
		if status.allowed:
			available.append(entry.id)
			if entry.kind=="stock":units+=int(status.remaining)
	return {"installed_count":state.placements.size(),"install_total":data.installable_part_ids.size(),"available_ids":available,"available_units":units,"statuses":statuses,"completed_ids":completed_part_ids(state),"placements":state.placements.duplicate(true),"finished":state.completed_actions.has(data.withdraw_action_id),"recommended_id":available[0] if not available.is_empty() else "","withdraw_ready":availability(data.withdraw_action_id,state).allowed}
func validate_state(state: Dictionary) -> Dictionary:
	if not state.get("placements") is Dictionary or not state.get("completed_actions") is Array:return fail("快照必须包含槽位库存映射与已完成动作。")
	for slot in state.placements:
		var step=step_for_slot(str(slot))
		var type_id=str(state.placements[slot])
		if step.is_empty() or type_for(type_id).is_empty():return fail("快照包含未知槽位或库存类型。")
		if data.slot_type_map[slot]!=type_id:return fail("快照把不兼容库存放入了槽位。")
		if not dependency_reason(step,state).is_empty():return fail("快照缺少目标槽位的必要依赖。")
	for item in data.inventory_types:
		if remaining(item.id,state)<0:return fail("快照超额消耗了库存。")
	var seen: Dictionary={}
	for id in state.completed_actions:
		if id!=data.withdraw_action_id or seen.has(id):return fail("快照包含未知或重复动作。")
		seen[id]=true
		if not dependency_reason(step_for_part(id),state).is_empty():return fail("正式件未齐，快照不能提前撤支撑。")
	return {"ok":true}
func normalize_snapshot_state(state: Dictionary,from_ruleset: String) -> Dictionary:
	if not state.get("placements") is Dictionary or not state.get("completed_actions") is Array:return fail("快照必须包含槽位库存映射与已完成动作。")
	var normalized: Dictionary=state.duplicate(true)
	if from_ruleset!=data.ruleset_version:
		var migration: Dictionary=data.get("legacy_inventory_migrations",{}).get(from_ruleset,{})
		if migration.is_empty():return fail("快照规则版本不匹配。")
		for slot_id in normalized.placements:
			var type_id=str(normalized.placements[slot_id])
			var restricted: Array=migration.get("slot_restrictions",{}).get(type_id,[])
			if not restricted.is_empty() and not restricted.has(slot_id):return fail("旧快照的库存类型与原槽位不符。")
			normalized.placements[slot_id]=migration.get("type_aliases",{}).get(type_id,type_id)
	return {"ok":true,"state":normalized}
func migrate_ids(ids: Array) -> Dictionary:
	var state={"placements":{},"completed_actions":[]}
	var seen: Dictionary={}
	for id in ids:
		var step=step_for_part(str(id))
		if step.is_empty() or seen.has(id):return fail("旧快照包含未知或重复ID。")
		seen[id]=true
		if step.action_kind=="withdraw":state.completed_actions.append(id)
		else:state.placements[step.slot.id]=data.slot_type_map[step.slot.id]
	var result=validate_state(state)
	if result.ok:result.state=state
	return result
func validate(request: Dictionary,state: Dictionary) -> Dictionary:
	var action_id=str(request.get("action_id",request.get("part_id","")))
	if action_id==data.withdraw_action_id:
		var status=availability(action_id,state)
		if not status.allowed:return fail(status.reason)
		var step=step_for_part(action_id)
		if request.get("source","")!="shortcut":
			var gesture: Dictionary=step.interaction
			if request.get("gesture_kind","")!="pull" or not gesture.grab_ids.has(request.get("grab_id","")):return fail("请选中蓝色支撑后轻轻向下拖，或使用撤除按钮。")
			var down=request.get("axis_distance_m",null)
			var lateral=request.get("lateral_distance_m",null)
			if not numeric(down) or not numeric(lateral):return fail("拖动距离无效。")
			if float(down)<float(gesture.min_distance_m):return fail("请轻轻向下或斜向下拖一点，再松手。")
			if float(down)>float(gesture.max_distance_m) or absf(float(lateral))>float(gesture.max_lateral_m):return fail("拖动偏离过多；也可以点击撤除辅助支撑。")
		return {"ok":true,"step":step,"commit":{"kind":"action","action_id":action_id}}
	if request.has("action_id"):return fail("快捷动作不能用于安装木件。")
	var id=str(request.get("inventory_type_id",request.get("part_id","")))
	var members=stock_members(id)
	if members.is_empty():return fail("未知库存类型。")
	var slot_id=str(request.get("slot_id",""))
	var step=step_for_slot(slot_id)
	if step.is_empty():return fail("没有进入明确的连接槽位，请拖到亮起的位置。")
	if state.placements.has(slot_id):return fail("这个槽位已占用，库存未消耗。")
	var actual_type: String=data.slot_type_map[slot_id]
	if not members.has(actual_type):return fail("规格不兼容：该槽位需要"+str(type_for(actual_type).label)+"。")
	var status=availability(actual_type,state)
	if not status.allowed:return fail(status.reason)
	var missing=dependency_reason(step,state)
	if not missing.is_empty():return fail(missing)
	var point=request.get("release_m",[])
	if not point is Array or point.size()!=3:return fail("放置位置无效。")
	for value in point:
		if not numeric(value):return fail("放置位置无效。")
	var inside: bool=false
	for trigger in step.slot.get("trigger_points_m",[step.slot.anchor_m]):
		if vector(point).distance_to(vector(trigger))<=float(step.slot.radius_m):inside=true;break
	if not inside:return fail("还没进入槽位吸附范围，库存未消耗。")
	# UI families resolve only after the target is fixed; snapshots retain real stock IDs.
	return {"ok":true,"step":step,"commit":{"kind":"placement","slot_id":slot_id,"type_id":actual_type}}
static func numeric(value) -> bool:
	return (value is float or value is int) and is_finite(float(value))
static func vector(v: Array) -> Vector3:return Vector3(float(v[0]),float(v[1]),float(v[2]))
static func fail(message: String) -> Dictionary:return {"ok":false,"message":message}
