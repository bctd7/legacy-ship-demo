extends SceneTree
var checks: Array = []
var results: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, name: String) -> void:
	checks.append({"name":name,"passed":condition})
	print("PASS " if condition else "FAIL ",name)

func _run() -> void:
	var adapter: Control = load("res://content/quanzhou_boat/stage_adapter.gd").new()
	root.add_child(adapter)
	adapter.stage_result.connect(func(_id: String,result: Dictionary): results.append(result))
	check(adapter.enter_stage({"id":"exit_probe"},{"mock_mode":false}).is_empty(),"stage enters existing lifecycle")
	var play: Control = adapter.play
	play._install({"inventory_type_id":"keel_center","slot_id":"keel_center","release_m":play.slots.keel_center.anchor_m,"expected_revision":play.revision})
	for i in 3: await process_frame
	check(play.mode=="lesson" and play.pending_id=="keel_center","accepted placement owns live pending camera animation")
	adapter.exit_stage()
	await create_timer(1.2).timeout
	check(play.pending_id.is_empty() and play.placed.is_empty(),"stage exit cancels pending placement")
	check(not play.drag.is_processing_input() and not play.drag.enabled,"stage exit disables input")
	check(results.is_empty(),"no late completed result after exit")
	adapter.queue_free()
	var passed := true
	for item in checks: if not item.passed: passed = false
	var file := FileAccess.open("res://content/quanzhou_boat/evidence/review_after/stage_exit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"checks":checks},"\t"))
	quit(0 if passed else 1)
