extends Resource
## All positions and sizes are normalized to the paper. Texture alpha is preserved.
## Target rect tests the dragged asset CENTER; its entire snapped bounds must fit paper.
@export var paper_size := Vector2i(960, 640)
@export var materials: Array[Dictionary] = []
# Each material: id:String, label:String, texture:Texture2D, target_position:Vector2,
# display_size:Vector2, allowed_drop_rect:Rect2, lock_on_place:bool=true,
# initially_locked:bool=false. initially_locked means already placed at its target.

func validation_error() -> String:
	if paper_size.x < 16 or paper_size.y < 16 or paper_size.x > 4096 or paper_size.y > 4096:
		return "Paper dimensions must be between 16 and 4096."
	var ids: Dictionary = {}
	for item in materials:
		var id := str(item.get("id", ""))
		if id.is_empty() or ids.has(id):
			return "Material ids must be nonempty and unique."
		ids[id] = true
		if not item.get("texture") is Texture2D:
			return "Material %s needs a Texture2D." % id
		if not item.get("target_position") is Vector2 or not item.get("display_size") is Vector2 or not item.get("allowed_drop_rect") is Rect2:
			return "Material %s needs normalized target, size and drop rect." % id
		var target: Vector2 = item.target_position
		var extent: Vector2 = item.display_size
		var allowed: Rect2 = item.allowed_drop_rect
		var unit := Rect2(Vector2.ZERO, Vector2.ONE)
		if extent.x <= 0 or extent.y <= 0 or not unit.encloses(Rect2(target - extent / 2, extent)):
			return "Material %s must fit fully inside paper at its target." % id
		if not allowed.has_area() or not unit.encloses(allowed) or not allowed.has_point(target):
			return "Material %s needs an in-paper allowed rect containing its target." % id
	return ""
