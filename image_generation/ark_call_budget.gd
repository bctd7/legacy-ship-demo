extends RefCounted
## Single-session conservative admission ledger; contains no image/prompt/key.
var generation_authorized := false # Account, safe credential setup and image approval required.
var budget_limit_fen := 1000 # Current user-authorized ceiling: CNY 10.
var unit_price_fen := 0 # Unknown price blocks all requests. Round an upper bound up.
var max_calls := 16 # Conservative session bound, independent of model price; first test uses one.
var _reserved_fen := 0
var _call_count := 0
var _entries: Array[Dictionary] = []

func reserve() -> int:
	if not generation_authorized or unit_price_fen <= 0 or budget_limit_fen <= 0 or budget_limit_fen > 1000:
		return 0
	if max_calls <= 0 or max_calls > 16 or _call_count >= max_calls: return 0
	if unit_price_fen > budget_limit_fen - _reserved_fen: return 0
	_reserved_fen += unit_price_fen
	_call_count += 1
	_entries.append({"unit_price_fen": unit_price_fen, "state": "reserved"})
	return _entries.size()

func mark_started(ticket: int) -> void:
	if ticket > 0 and ticket <= _entries.size() and _entries[ticket - 1].state == "reserved":
		_entries[ticket - 1].state = "started_or_outcome_unknown"

func release_unstarted(ticket: int) -> void:
	if ticket <= 0 or ticket > _entries.size() or _entries[ticket - 1].state != "reserved": return
	_reserved_fen -= int(_entries[ticket - 1].unit_price_fen)
	_call_count -= 1
	_entries[ticket - 1].state = "rejected_before_send"

func audit() -> Dictionary:
	return {"call_count": _call_count, "reserved_fen": _reserved_fen,
		"max_calls": max_calls,
		"budget_limit_fen": budget_limit_fen, "configured_unit_price_fen": unit_price_fen,
		"entries": _entries.duplicate(true)}
