extends "res://levels/stage.gd"
## Hosts the drawing surface. Drawing data and brush behavior remain in drawing/.
const DrawingPanel = preload("res://levels/presentation/drawing_panel.gd")
var surface: Control
var toolbar: Control

func enter_stage(config: Dictionary, context: Dictionary) -> String:
	var error := super.enter_stage(config, context)
	if not error.is_empty(): return error
	for key in ["surface_script", "config_script"]:
		if not ResourceLoader.exists(str(config.get(key, ""))):
			return "Drawing component is missing: " + str(config.get(key, key))
	var config_script = load(config.config_script)
	var surface_script = load(config.surface_script)
	if not config_script is Script or not surface_script is Script: return "Drawing components must be scripts."
	var paper = config_script.new()
	paper.paper_size = config.get("paper_size", Vector2i(960, 640))
	var materials: Array = config.get("materials", []).duplicate(true)
	materials.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("layer", 0)) < int(b.get("layer", 0)))
	for material in materials:
		var item: Dictionary = material.duplicate(true)
		var path := str(item.get("texture_path", ""))
		if path.is_empty():
			var source: Dictionary = context.get("results", {}).get(str(item.get("result_stage", "")), {})
			var payload: Dictionary = source.get("payload", {})
			var asset: Dictionary = payload.get("drawing_asset", {})
			if not asset.is_empty() and asset.get("kind", "image_2d") != "image_2d": return "Drawing materials must be 2D images."
			path = str(asset.get("texture_path", payload.get("texture_path", "")))
			if asset.has("placeholder"): item["placeholder"] = bool(asset.placeholder)
			for key in ["preview_texture_path", "placed_texture_path"]:
				if str(item.get(key, "")).is_empty(): item[key] = str(asset.get(key, path))
		if path.is_empty() or not (ResourceLoader.exists(path) if path.begins_with("res://") else FileAccess.file_exists(path)):
			return "Material %s needs a supplied texture_path; assembly does not imply an image asset." % item.get("id", "?")
		var texture: Texture2D
		if path.begins_with("res://"):
			var imported = load(path)
			if imported is Texture2D: texture = imported
			elif imported is Image: texture = ImageTexture.create_from_image(imported)
			else: return "Material resource must be a 2D image: " + path
		else:
			var image := Image.load_from_file(path)
			if image == null or image.is_empty(): return "Material image cannot be loaded: " + path
			texture = ImageTexture.create_from_image(image)
		# The current drawing API shares one Texture2D between drag preview and placement.
		var preview := str(item.get("preview_texture_path", ""))
		var placed := str(item.get("placed_texture_path", ""))
		if preview.is_empty(): preview = path
		if placed.is_empty(): placed = path
		if preview != placed or placed != path: return "Distinct preview/placed images are reserved for a future adapter; use the same 2D image for now."
		item["preview_texture_path"] = preview
		item["placed_texture_path"] = placed
		item["texture"] = texture
		paper.materials.append(item)
	error = paper.validation_error()
	if not error.is_empty(): return error
	surface = surface_script.new()
	if not surface is Control or not surface.has_method("configure"):
		if surface is Node: surface.free()
		surface = null
		return "Drawing surface must expose configure(config)."
	if config.get("show_tools", false):
		var panel := DrawingPanel.new()
		add_child(panel)
		panel.build(surface, config)
		toolbar = panel.toolbar
	else:
		surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(surface)
	return surface.configure(paper)

func export_to(path: String) -> String:
	if not active or not is_instance_valid(surface): return "Drawing stage is not active."
	if _reported: return "Drawing result already submitted."
	if stage_config.get("require_materials", false):
		for item in surface.document.materials:
			if not surface.document.placements.has(item.id): return "请先将所有配置图片拖到纸面固定区域。"
	surface.cancel_gesture()
	var export_size: Vector2i = stage_config.get("export_size", Vector2i.ZERO)
	var error: Error = surface.document.export_png(path, export_size)
	if error != OK: return "PNG export failed (%s): %s" % [error_string(error), path]
	var placeholders := false
	for item in surface.document.materials: placeholders = placeholders or bool(item.get("placeholder", false))
	report("completed", {"texture_path": path, "paper_size": stage_config.get("paper_size", Vector2i(960, 640)),
		"export_size": surface.document.paper_size if export_size == Vector2i.ZERO else export_size,
		"contains_placeholder_assets": placeholders})
	surface.process_mode = Node.PROCESS_MODE_DISABLED
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_instance_valid(toolbar):
		toolbar.set_locked(true)
	return ""

func exit_stage() -> void:
	if is_instance_valid(surface): surface.cancel_gesture()
	super.exit_stage()
