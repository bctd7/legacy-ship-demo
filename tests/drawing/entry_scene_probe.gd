extends Node
## Normal scene boot: no SceneTree replacement, root sizing or manual demo instantiation.
var checks := 0
var failed := false
var app: Control

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("ENTRY_PASS: ", label)
	else:
		failed = true
		push_error("ENTRY_FAILED: " + label)

func frames(count: int = 2) -> void:
	for i in range(count): await get_tree().process_frame

func mouse(local: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = get_tree().root.get_final_transform() * app.surface.get_global_transform_with_canvas() * local
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
	await frames()

func move(local: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = get_tree().root.get_final_transform() * app.surface.get_global_transform_with_canvas() * local
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await frames()

func click_button(button: Button) -> void:
	var local: Vector2 = app.surface.get_global_transform_with_canvas().affine_inverse() * button.get_global_rect().get_center()
	await mouse(local, true)
	await mouse(local, false)

func run() -> void:
	app = get_parent()
	await frames(5)
	check(app.size.x >= 1000 and app.size.y >= 700, "ordinary scene root receives project viewport size")
	check(app.surface.is_visible_in_tree() and app.surface.size.x > 420 and app.surface.size.y > 300, "paper surface receives visible container layout")
	check(app.undo_button.is_visible_in_tree() and app.redo_button.is_visible_in_tree(), "toolbar renders on ordinary scene startup")
	var surface: Control = app.surface
	var source: Vector2 = surface.tray_rect(0).get_center()
	var target: Vector2 = surface.paper_to_local(Vector2(0.32, 0.60) * Vector2(surface.document.paper_size))
	await mouse(source, true)
	await mouse(source, false)
	check(surface.document.placements.is_empty(), "ordinary scene tray click does not place")
	await mouse(source, true)
	await move(target)
	await mouse(target, false)
	check(surface.document.placements.get("placeholder_a", {}).get("locked", false), "ordinary scene receives drag and locks material")
	var start: Vector2 = surface.paper_to_local(Vector2(120, 120))
	var end: Vector2 = surface.paper_to_local(Vector2(280, 160))
	await mouse(start, true)
	await move(end)
	await mouse(end, false)
	check(surface.document.strokes.size() == 1, "ordinary scene receives paper drawing input")
	await click_button(app.undo_button)
	check(surface.document.strokes.is_empty(), "ordinary toolbar undo receives pointer click")
	await click_button(app.redo_button)
	check(surface.document.strokes.size() == 1, "ordinary toolbar redo receives pointer click")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var screen := get_tree().root.get_texture().get_image()
		var sample: Vector2 = surface.get_global_transform_with_canvas() * surface.paper_to_local(Vector2(50, 50))
		check(screen.get_pixelv(Vector2i(sample)) == Color.WHITE, "real rendered viewport contains white paper")
		check(screen.save_png(args[0]) == OK, "ordinary-layout interaction screenshot saved")
	if not failed: print("ENTRY_ALL_PASS checks=", checks, "; startup=scene; input=Godot-events; physical_input=untested")
	get_tree().quit(1 if failed else 0)
