extends RefCounted
const Registry = preload("res://levels/model_registry.gd")
const DEMO_GENERATION_PROMPT = "以输入的完整画布为构图参考，创作精美、柔和、富有诗意的国风绘本插画。尽可能美化环境和用户笔迹，把简笔山形、岸线、水纹等自然转译为有层次、有细节的景物，不要机械描摹粗糙线条。已经绘制的插画主体是定稿造型：保留其轮廓、朝向、跨度、主要结构及两端完整支撑，不大幅改造、不换成另一种设计，不裁断或遮没关键部分。尊重主体的位置、比例与前后关系，让环境围绕它自然生长；将空白融入连贯的水面、岸景、远山、植被与空气感，近景清晰、远景轻淡，形成柔和空间纵深。统一暖雅配色、水彩晕染、细腻笔触和光影，使插画主体与手绘内容融合为完整艺术画面。画面优美、有呼吸感，避免写实3D塑料感、工程平面图和贴纸拼贴感；不要文字、水印和标注。"
## Stage order, asset references and artwork policy; never interaction rules.
static func first_level() -> Dictionary:
	return {
		"id": "level_01", "title": "第一关 · 桥 → 船 → 白纸绘画",
		"stages": [
			{"id": "bridge", "title": "鲁班桥", "component": "bridge",
				"scene": "res://scenes/workshop.tscn"},
			{"id": "ship", "title": "船（未接入）", "component": "pending",
				"integration_status": "pending_integration",
				"message": "船组件尚未接入；此处为占位，不能完成或跳过。"},
			{"id": "drawing", "title": "白纸绘画", "component": "drawing",
				"surface_script": "res://drawing/drawing_surface.gd",
				"config_script": "res://drawing/drawing_config.gd",
				"paper_size": Vector2i(960, 640), "materials": [
					{"id": "bridge", "label": "桥", "texture_path": "", "result_stage": "bridge", "layer": 10,
						"target_position": Vector2(0.28, 0.60), "display_size": Vector2(0.40, 0.40),
						"allowed_drop_rect": Rect2(0.05, 0.30, 0.45, 0.55), "lock_on_place": true},
					{"id": "ship", "label": "船", "texture_path": "", "result_stage": "ship", "layer": 20,
						"target_position": Vector2(0.73, 0.60), "display_size": Vector2(0.40, 0.40),
						"allowed_drop_rect": Rect2(0.50, 0.30, 0.45, 0.55), "lock_on_place": true}
				]}
		]
	}

static func validation_error(config: Dictionary) -> String:
	if str(config.get("id", "")).is_empty(): return "Level id is required."
	if not config.get("stages") is Array or config.stages.is_empty(): return "Level needs stages."
	var ids := {}
	for item in config.stages:
		if not item is Dictionary: return "Each stage must be a Dictionary."
		var id := str(item.get("id", ""))
		if id.is_empty() or ids.has(id): return "Stage ids must be nonempty and unique."
		if str(item.get("component", "")).is_empty(): return "Stage %s needs a component." % id
		if item.component == "model":
			if not item.get("model") is Dictionary: return "Stage %s needs a model descriptor." % id
			var error := Registry.validation_error(item.model)
			if not error.is_empty(): return "Stage %s: %s" % [id, error]
		ids[id] = true
	return ""

static func bridge_demo(output_directory: String, options: Dictionary = {}) -> Dictionary:
	var level := first_level()
	level.id = "integrated_demo"
	level.title = "第一关演示 · 桥拼装 → 白纸绘画"
	level["demonstration"] = true
	level["notice"] = "桥使用完整国风插画；船拼装本轮禁用"
	level.stages[0] = {"id": "assembly", "title": "桥拼装", "component": "model", "model": {
		"id": "luban_bridge", "adapter_script": "res://levels/bridge_stage_adapter.gd",
		"scene": "res://scenes/workshop.tscn", "drawing_asset": {"kind": "image_2d",
			"texture_path": "res://levels/assets/bridge_illustration_v2.png", "transparent_background": true,
			"preview_texture_path": "res://levels/assets/bridge_illustration_v2.png",
			"placed_texture_path": "res://levels/assets/bridge_illustration_v2.png", "placeholder": false}}}
	level.stages[2].title = "绘画（国风桥插画；可选船仍为占位）"
	level.stages[2]["show_tools"] = true
	level.stages[2]["require_materials"] = true
	level.stages[2]["export_size"] = Vector2i(1920, 1280)
	level.stages[2].materials[0].texture_path = ""
	level.stages[2].materials[0].result_stage = "assembly"
	level.stages[2].materials[0].label = "鲁班桥 · 国风绘本插画"
	level.stages[2].materials[1].label = "船 · 占位示意"
	level.stages[2].materials[1].texture_path = "res://levels/assets/ship_placeholder.svg"
	level.stages[2].materials[1]["optional"] = true
	# Distant bridge, nearer/larger ship; the 2D ship's bow points up-right toward the bridge.
	level.stages[2].materials[0].target_position = Vector2(0.65, 0.26)
	level.stages[2].materials[0].display_size = Vector2(0.40, 0.30)
	level.stages[2].materials[0].allowed_drop_rect = Rect2(0.42, 0.08, 0.45, 0.34)
	level.stages[2].materials[1].target_position = Vector2(0.28, 0.74)
	level.stages[2].materials[1].display_size = Vector2(0.46, 0.39)
	level.stages[2].materials[1].allowed_drop_rect = Rect2(0.03, 0.51, 0.48, 0.46)
	for material in level.stages[2].materials:
		material["placeholder"] = bool(material.get("optional", false))
		material["preview_texture_path"] = material.texture_path
		material["placed_texture_path"] = material.texture_path
		material["placement_transition"] = {"kind": "reserved", "duration_seconds": 0.0}
	level.stages[2]["composition_note"] = "桥使用风格化插画候选，非精确模型复原；可选船仍为占位。保留环境与自由绘画留白。"
	var include_optional := bool(options.get("include_optional_materials", false))
	level.stages[2].materials = level.stages[2].materials.filter(func(item: Dictionary): return include_optional or not bool(item.get("optional", false)))
	if not include_optional:
		level.notice = "完整国风桥插画 · 白纸自由绘画"
		level.stages[2].title = "绘画（模型单素材）"
		level.stages[2].composition_note = "将完整桥插画拖入纸面，再自由绘画；导出包含插画与全部笔迹的完整画布。"
	level.stages[2]["export_path"] = output_directory.path_join("drawing.png")
	level["disabled_stages"] = [{"id": "future_assembly", "component": "model", "enabled": false,
		"model": {"id": "vessel_pending", "scene": "", "drawing_asset": {"kind": "image_2d",
			"texture_path": "res://levels/assets/ship_placeholder.svg", "placeholder": true}}}]
	level["optional_generation"] = {"id": "generation", "title": "可选离线 MOCK 演示", "component": "generation",
		"input_stage": "drawing", "prompt": DEMO_GENERATION_PROMPT, "output_path": output_directory.path_join("mock_result.png")}
	level.stages = [level.stages[0], level.stages[2]]
	return level

## The runnable integration uses the same model factory for every registered package.
## bridge_only retains the accepted earlier regression entry, including optional art fixtures.
static func integrated_demo(output_directory: String, options: Dictionary = {}) -> Dictionary:
	if options.get("profile", "") == "bridge_only": return bridge_demo(output_directory, options)
	var level := bridge_demo(output_directory, {"include_optional_materials": true})
	level.title = "第一关 · 桥 → 船 → 白纸绘画"
	level.notice = "完成两项拼装后，将已完成模型的插画拖入画纸并自由绘画。"
	level.disabled_stages = []
	level["auto_advance"] = {"enabled":bool(options.get("auto_advance", true)), "delay_seconds":2.0}
	var drawing: Dictionary = level.stages[-1]
	drawing.title = "白纸绘画"
	drawing["compact_header"] = true
	drawing["entry_label"] = "进入绘画"
	drawing.composition_note = "船在近处，完整鲁班桥在远处，船头朝向桥；两张透明国风插画与笔迹共同导出。"
	for material in drawing.materials:
		material.texture_path = ""
		material.preview_texture_path = ""
		material.placed_texture_path = ""
		material.placeholder = false
		material.optional = false
	drawing.materials[1].label = "泉州古船 · 国风插画"
	drawing.materials[1].result_stage = "ship"
	# Use actual image aspect ratios: the taller foreground artwork needs more height.
	drawing.materials[0].display_size = Vector2(0.36, 0.28)
	drawing.materials[1].target_position = Vector2(0.29, 0.65)
	drawing.materials[1].display_size = Vector2(0.54, 0.64)
	drawing.materials[1].allowed_drop_rect = Rect2(0.03, 0.33, 0.55, 0.64)
	var registry := Registry.defaults()
	registry.merge(options.get("models", {}), true)
	var sequence: Array = options.get("model_stages", [
		{"id": "assembly", "title": "鲁班桥拼装", "model_key": "luban_bridge", "completion_text": "鲁班桥已完成"},
		{"id": "ship", "title": "泉州古船拼装", "model_key": "quanzhou_boat", "compact_header": true, "entry_label": "继续搭建古船", "completion_text": "古船已完成"}])
	if options.has("drawing_materials"): drawing.materials = options.drawing_materials.duplicate(true)
	return with_registered_models(level, sequence, registry, drawing)

## Pure configuration assembly: any number and identity of models use this seam.
static func with_registered_models(base: Dictionary, sequence: Array, registry: Dictionary, drawing: Dictionary) -> Dictionary:
	var level := base.duplicate(true)
	var stages: Array = []
	for spec in sequence:
		var item: Dictionary = spec.duplicate(true)
		item["component"] = "model"
		item["model"] = Registry.resolve(str(item.get("model_key", "")), registry)
		stages.append(item)
	stages.append(drawing.duplicate(true))
	level.stages = stages
	return level
