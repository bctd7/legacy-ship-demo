extends RefCounted
## item_id is a tray stock type or auxiliary action, never a target mesh ID.
## origin_slot/gesture/candidates are copied once at press; hover_target is separate.
static func capture(selection: Dictionary,gesture: Dictionary,candidates: Array,eligible: bool,revision: int,grab_id: String) -> Dictionary:
	return {"item_id":str(selection.item_id),"origin_slot":selection.origin_slot.duplicate(true),"gesture":gesture.duplicate(true),"candidates":candidates.duplicate(true),"eligible":eligible,"revision":revision,"grab_id":grab_id}

static func placement(source: Dictionary,target_slot_id: String,point: Vector3) -> Dictionary:
	return {"inventory_type_id":source.item_id,"slot_id":target_slot_id,"release_m":[point.x,point.y,point.z],"expected_revision":source.revision}

static func withdrawal(source: Dictionary,down: float,lateral: float) -> Dictionary:
	return {"action_id":source.item_id,"slot_id":source.origin_slot.id,"gesture_kind":"pull","grab_id":source.grab_id,"axis_distance_m":down,"lateral_distance_m":lateral,"expected_revision":source.revision}
