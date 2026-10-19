extends "res://content/quanzhou_boat/verify_tolerance.gd"
func _ready() -> void:
	super._ready()
	evidence = "res://content/quanzhou_boat/evidence/connected_groups"

func _run() -> void:
	await _frames(25)
	if "baseline" in OS.get_cmdline_user_args():
		await _baseline_click()
		return
	_check(groups.size()==28,"28 local connected operation units loaded")
	var ownership: Dictionary = {}
	for g in groups:
		var parts := _part_meshes(g.id)
		_check(parts.size()==int(g.source_mesh_count),"declared exact mesh count "+g.id)
		for mesh in parts:
			_check(not ownership.has(str(mesh.name)),"single group ownership "+str(mesh.name))
			ownership[str(mesh.name)] = g.id
	_check(ownership.size()==1286,"complete source coverage with no duplicated or missing meshes")
	_check(_part_meshes("keel_bow").size()==1 and _part_meshes("keel_stern").size()==1,"bow and stern have independent cards and source objects")
	_check("K0" in _group("keel_bow").roots and "K2" not in _group("keel_bow").roots,"bow card cannot install stern")
	_check(_group("deck_bow").source_bounds_m.max[0]<0.8 and _group("deck_stern").source_bounds_m.min[0]>1.9,"fore and aft support sets stay at their own deck")
	_check(_group("deck_walkway_port").source_bounds_m.min[2]>0 and _group("deck_walkway_starboard").source_bounds_m.max[2]<0,"hatch-separated walkway sides remain independent")
	await _click_threshold_check()
	await _capture("01_ready_28")
	for index in groups.size():
		var id: String = groups[index].id
		if index==14:
			get_window().size = Vector2i(1920,1080)
			await _frames(10)
			event_log.append({"kind":"window_resize_api","size":str(get_window().size),"transform":str(get_tree().root.get_final_transform())})
		if id=="keel_bow":
			var center := view.get_global_rect().get_center()
			for step in 4:
				await _mouse(center,true,MOUSE_BUTTON_WHEEL_UP)
				await _mouse(center,false,MOUSE_BUTTON_WHEEL_UP)
			_check(orbit.distance<3,"existing wheel zoom remains available before separated bow drag")
		await _drag_group(id)
		if index==6:
			await _button_click("撤回一步")
			_check(id not in placed and pending_id.is_empty() and mode=="assembly","undo during pending cancels only this local connection")
			await _drag_group(id)
		var route := "auto"
		if index%7==1:
			route = "return_pending"
			await _button_click("返回整船")
			await _wait_assembly("return_"+id)
		elif index%7==2:
			route = "skip_pending"
			await _button_click("跳过镜头，继续装配")
			await _wait_assembly("skip_"+id)
		else:
			await _wait_installed(id)
			if id=="shell_starboard":
				route = "inspect_then_direct"
				var center := view.get_global_rect().get_center()
				await _mouse(center,true,MOUSE_BUTTON_RIGHT)
				await _mouse(center,false,MOUSE_BUTTON_RIGHT)
				_check(mode=="lesson","finished local inspection waits for direct next-card input")
			else: await _wait_assembly("auto_"+id)
		_check(id in placed,"connected local group completes "+id)
		route_log.back()["completion_route"] = route
		route_log.back()["after_route"] = _input_state()
		if index<5 or id in ["bulkhead_12","mast_bed_fore","mast_bed_main","deck_bow","deck_stern","deck_walkway_port","deck_walkway_starboard","mast_rig_fore","mast_rig_main","rudder"]: await _capture("step_%02d_%s"%[index+1,id])
		if id=="keel_bow":
			_check("keel_stern" not in placed and not group_nodes.keel_stern[0].visible,"bow installation leaves separated stern hidden")
			await _button_click("视角复位")
	_check(placed.size()==28 and snapshot().complete and completion_count==1,"continuous complete 28-group flow reports completion once")
	var all_visible := true
	for mesh in _meshes(boat):
		if not mesh.is_visible_in_tree(): all_visible = false
	_check(all_visible,"all 1286 source meshes visible after complete flow")
	await _capture("02_complete_28")
	await _button_click("撤回一步")
	_check(placed.size()==27 and guide_id=="rudder" and "rudder" not in placed,"undo removes exactly the final connected rudder group")
	await _drag_group("rudder")
	await _wait_installed("rudder")
	await _wait_assembly("reinstalled_rudder")
	_check(placed.size()==28 and completion_count==2,"last connected group can be reinstalled through actual input")
	await _button_click("重置装配")
	_check(placed.is_empty() and history.is_empty() and guide_id=="keel_center","reset returns to first local group")
	await _button_click("＋ 放大")
	_check(orbit.distance<4.25,"zoom control still works after complete reset")
	await _capture("03_reset_ready")
	var passed := true
	for item in checks: if not item.passed: passed = false
	_write("connected_flow.json")
	var f := FileAccess.open(evidence.path_join("result.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify({"passed":passed,"checks":checks.size(),"failed":checks.filter(func(item): return not item.passed),"groups":groups.size(),"meshes":ownership.size(),"events":event_log.size(),"routes":route_log,"states":sequence_states,"limitations":"Godot input-event injection, not native human mouse acceptance; no target-machine performance claim."},"\t"))
	print("CONNECTED_FLOW groups=",groups.size()," checks=",checks.size()," passed=",passed," events=",event_log.size())
	get_tree().quit(0 if passed else 1)

func _mouse(point: Vector2, down: bool, button := MOUSE_BUTTON_LEFT) -> void:
	await super._mouse(point,down,button)
	if button==MOUSE_BUTTON_LEFT and down and drag.held and not drag.dragging:
		_check(not preview_group.visible and not preview_initialized,"held source remains hidden until actual drag threshold "+str(drag.drag_source.get("item_id","")))

func _click_threshold_check() -> void:
	var point: Vector2 = cards.keel_center.get_global_rect().get_center()
	for attempt in 2:
		await _hover_pointer(point)
		await _mouse(point,true)
		await _frames(4)
		_check(not preview_group.visible and placed.is_empty() and pending_id.is_empty(),"click-only press has no brown source flash "+str(attempt))
		await _move(point+Vector2(4,0))
		_check(not drag.dragging and not preview_group.visible,"subthreshold motion keeps carried object hidden")
		if attempt==0: await _capture("fixed_click_held_no_flash")
		await _mouse(point+Vector2(4,0),false)
	await _hover_pointer(point)
	await _mouse(point,true)
	await _move(point+Vector2(12,-1))
	_check(drag.dragging and preview_group.visible and preview_initialized,"threshold crossing immediately starts visible actual drag")
	_check(preview_group.position.is_equal_approx(preview_goal) and preview_group.position.length()>0.1,"first visible frame initializes at pointer-derived pose instead of world zero")
	await _capture("fixed_threshold_first_frame")
	await _mouse(point+Vector2(12,-1),false)
	_check(placed.is_empty() and pending_id.is_empty(),"outside threshold probe release does not install")

func _baseline_click() -> void:
	var point: Vector2 = cards.keel_center.get_global_rect().get_center()
	await _hover_pointer(point)
	await _mouse(point,true)
	_check(preview_group.visible and not drag.dragging,"REPRO press displays source at default transform before drag threshold")
	await _capture("baseline_press_flash")
	await _mouse(point,false)
	_check(not preview_group.visible and placed.is_empty(),"REPRO release hides the flash without installing")
	_write("baseline_click.json")
	get_tree().quit()
