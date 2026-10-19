extends SceneTree
const Demo = preload("res://drawing/drawing_demo.gd")
const Surface = preload("res://drawing/drawing_surface.gd")
const Document = preload("res://drawing/drawing_document.gd")
var surface: Control
var checks := 0
var failed := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("DRAWING_PASS: ", label)
	else:
		failed = true
		push_error("DRAWING_FAILED: " + label)

func frames(count: int = 2) -> void:
	for i in range(count): await process_frame

func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_final_transform() * surface.get_global_transform_with_canvas() * point
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
	await frames()

func move(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_final_transform() * surface.get_global_transform_with_canvas() * point
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await frames()

func escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await frames()

func stroke(doc: RefCounted, a: Vector2, b: Vector2, erase: bool = false) -> void:
	doc.begin_stroke(a, Color.RED, 24, erase)
	doc.append_stroke(b)
	doc.end_stroke()

func run() -> void:
	root.size = Vector2i(1400, 900)
	surface = Surface.new()
	surface.position = Vector2(35, 20)
	surface.size = Vector2(1050, 820)
	root.add_child(surface)
	check(surface.configure(Demo.demo_config()).is_empty(), "valid transparent placeholder configuration")
	await frames()
	var tray: Vector2 = surface.tray_rect(0).get_center()
	var target: Vector2 = surface.paper_to_local(Vector2(0.32, 0.60) * Vector2(surface.document.paper_size))
	await mouse(tray, true)
	await mouse(tray, false)
	check(surface.document.placements.is_empty(), "clicking tray does not place material")
	await mouse(tray, true)
	await move(target)
	check(surface.document.placements.is_empty(), "hovering legal target does not commit before release")
	await escape()
	await mouse(target, false)
	check(surface.document.placements.is_empty(), "Escape cancels; late release cannot commit")
	await mouse(tray, true)
	await move(surface.paper_to_local(Vector2(0.9, 0.1) * Vector2(surface.document.paper_size)))
	await mouse(surface.paper_to_local(Vector2(0.9, 0.1) * Vector2(surface.document.paper_size)), false)
	check(surface.document.placements.is_empty(), "release inside paper but outside allowed rect returns to tray")
	await mouse(tray, true)
	await move(Vector2(1090, 300))
	await mouse(Vector2(1090, 300), false)
	check(surface.document.placements.is_empty(), "release outside control cancels drag")
	await mouse(tray, true)
	await move(target + Vector2(20, 15))
	await mouse(target + Vector2(20, 15), false)
	check(surface.document.placements.has("placeholder_a"), "real pointer drag and release places material")
	check(surface.document.placements.placeholder_a.position == Vector2(0.32, 0.60) and surface.document.placements.placeholder_a.locked, "drop snaps exactly to configured target and locks")
	check(not surface.document.place_material("placeholder_a", Vector2(0.3, 0.6)), "locked material rejects further placement")
	var doc: RefCounted = surface.document
	var center := Vector2(0.32, 0.60) * Vector2(doc.paper_size)
	var base: Image = doc.compose()
	var original := base.get_pixelv(Vector2i(center))
	check(original != Color.WHITE, "transparent material composites onto white paper")
	stroke(doc, center - Vector2(30, 0), center + Vector2(30, 0))
	check(doc.compose().get_pixelv(Vector2i(center)).r > 0.95, "stroke layer renders above locked material")
	stroke(doc, center - Vector2(30, 0), center + Vector2(30, 0), true)
	check(doc.compose().get_pixelv(Vector2i(center)).is_equal_approx(original), "eraser restores material, not white paint")
	doc.undo()
	check(doc.compose().get_pixelv(Vector2i(center)).r > 0.95, "undo eraser restores ink")
	doc.undo()
	check(doc.compose().get_pixelv(Vector2i(center)).is_equal_approx(original), "undo pen restores unmodified material")
	doc.redo()
	check(doc.can_undo() and doc.can_redo(), "redo reapplies pen and retains next redo")
	check(not doc.clear_strokes() and doc.can_redo(), "clear requires explicit confirmation and leaves history unchanged")
	doc.clear_strokes(true)
	check(doc.compose().get_pixelv(Vector2i(center)).is_equal_approx(original) and doc.placements.size() == 1, "confirmed clear retains paper and material")
	doc.undo()
	check(doc.compose().get_pixelv(Vector2i(center)).r > 0.95, "clear is one undoable command")
	doc.redo()
	doc.begin_stroke(Vector2(100, 100), Color.BLUE, 12)
	doc.cancel_stroke()
	check(doc.ink_image().get_pixel(100, 100).a == 0, "canceling draft leaves no ink or history")
	stroke(doc, Vector2(100, 100), Vector2(140, 100))
	check(not doc.can_redo(), "new committed stroke invalidates redo")
	var paper: Rect2 = surface.paper_rect()
	check(is_equal_approx(paper.size.x / paper.size.y, 1.5), "paper fits window without aspect distortion")
	var logical := Vector2(344, 217)
	check(surface.local_to_paper(surface.paper_to_local(logical)).distance_to(logical) < 0.001, "screen and logical coordinate roundtrip")
	var history_before_resize: int = doc.strokes.size()
	surface.size = Vector2(750, 540)
	await frames()
	check(surface.local_to_paper(surface.paper_to_local(logical)).distance_to(logical) < 0.001 and doc.strokes.size() == history_before_resize, "window resize preserves logical artwork and history")
	var large: Image = doc.compose(Vector2i(1920, 1280))
	check(large != null and large.get_size() == Vector2i(1920, 1280), "export can rerasterize at double paper resolution")
	check(large.get_pixel(240, 200).r > 0.95 and large.get_pixel(240, 200).g < 0.1, "export scales stroke positions and widths")
	check(doc.compose(Vector2i(1000, 1000)) == null, "distorted output dimensions rejected")
	check(large.get_pixel(0, 0) == Color.WHITE and large.get_pixel(1919, 1279) == Color.WHITE, "export bounds are opaque white paper only")
	check(large.get_pixel(230, 520) == Color.WHITE, "unfilled target guide does not enter exported image")
	var path := OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://drawing_test.png"
	check(doc.export_png(path, Vector2i(1920, 1280)) == OK, "PNG writes successfully")
	var loaded := Image.load_from_file(path)
	check(loaded != null and loaded.get_size() == Vector2i(1920, 1280) and loaded.get_pixel(0, 0) == Color.WHITE, "saved PNG reopens with correct layers and dimensions")
	var bad_config: Resource = Demo.demo_config()
	bad_config.materials[0].target_position = Vector2(-1, 0)
	check(not doc.configure(bad_config).is_empty() and doc.placements.size() == 1, "invalid config rejects atomically and preserves current work")
	var initial: Resource = Demo.demo_config()
	initial.materials[1].initially_locked = true
	var second := Document.new()
	second.configure(initial)
	check(second.placements.has("placeholder_b") and not second.can_move("placeholder_b"), "initially locked flag preplaces supplied art")
	initial.materials[0].lock_on_place = false
	second.configure(initial)
	check(second.place_material("placeholder_a", Vector2(0.3, 0.6)) and second.can_move("placeholder_a"), "lock_on_place=false retains move permission")
	var fitted: Vector2 = second.material_size(initial.materials[1], Vector2(second.paper_size))
	check(is_equal_approx(fitted.x / fitted.y, 1.5), "material fits configured bounds without distorting source aspect")
	tray = surface.tray_rect(1).get_center()
	await mouse(tray, true)
	await move(surface.paper_to_local(Vector2(700, 330)))
	surface.notification(Control.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	await mouse(surface.paper_to_local(Vector2(700, 330)), false)
	check(not doc.placements.has("placeholder_b"), "window focus loss cancels pending material drag")
	var touch := InputEventScreenTouch.new()
	touch.index = 2
	touch.position = root.get_final_transform() * surface.get_global_transform_with_canvas() * tray
	touch.pressed = true
	Input.parse_input_event(touch)
	await frames()
	var touch_motion := InputEventScreenDrag.new()
	touch_motion.index = 2
	touch_motion.position = root.get_final_transform() * surface.get_global_transform_with_canvas() * surface.paper_to_local(Vector2(700, 330))
	Input.parse_input_event(touch_motion)
	await frames()
	touch.index = 3
	touch.pressed = false
	touch.position = touch_motion.position
	Input.parse_input_event(touch)
	await frames()
	check(not doc.placements.has("placeholder_b"), "secondary touch cannot release captured drag")
	touch.index = 2
	touch.canceled = true
	Input.parse_input_event(touch)
	await frames()
	check(not doc.placements.has("placeholder_b") and surface._pointer == -2, "canceled owner touch returns material to tray")
	# Canvas input clips at border and does not draw while moving back across outside.
	var before: int = doc.strokes.size()
	await mouse(surface.paper_to_local(Vector2(850, 80)), true)
	await move(surface.paper_rect().end + Vector2(60, -200))
	await move(surface.paper_to_local(Vector2(100, 400)))
	await mouse(surface.paper_to_local(Vector2(100, 400)), false)
	check(doc.strokes.size() == before + 1 and doc.ink_image().get_pixel(100, 400).a == 0, "stroke exits at border and re-entry does not bridge outside excursion")
	var demo: Control = load("res://drawing/drawing_demo.tscn").instantiate()
	root.add_child(demo)
	surface.hide()
	await frames()
	stroke(demo.surface.document, Vector2(90, 90), Vector2(130, 90))
	demo._request_clear()
	check(demo.clear_dialog.visible and demo.surface.document.ink_image().get_pixel(100, 90).a > 0, "clear UI opens explicit confirmation without erasing")
	demo.clear_dialog.canceled.emit()
	demo.clear_dialog.hide()
	check(demo.surface.document.ink_image().get_pixel(100, 90).a > 0, "canceling clear confirmation preserves ink")
	demo.clear_dialog.confirmed.emit()
	check(demo.surface.document.ink_image().get_pixel(100, 90).a == 0, "confirming clear dialog erases ink")
	if OS.get_cmdline_user_args().size() > 1 and DisplayServer.get_name() != "headless":
		demo.surface.document.place_material("placeholder_a", Vector2(0.32, 0.60))
		stroke(demo.surface.document, Vector2(120, 110), Vector2(360, 200))
		await frames(4)
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[1]) == OK, "rendered standalone demo screenshot saved")
	if not failed: print("DRAWING_ALL_PASS checks=", checks, "; input=Godot-events; physical_mouse=untested; touch_hardware=untested")
	quit(1 if failed else 0)
