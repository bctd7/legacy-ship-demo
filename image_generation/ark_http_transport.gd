extends "res://image_generation/http_transport.gd"
## Mainland official endpoint only; shared conservative budget across job factories.
const Provider = preload("res://image_generation/ark_seedream_provider.gd")
var budget: RefCounted

func start(wire: Dictionary, callback: Callable) -> int:
	if not enabled or wire.get("url", "") != Provider.ENDPOINT or not allowed_urls.has(Provider.ENDPOINT) or not transient_headers.is_valid() or budget == null:
		return ERR_UNAUTHORIZED
	var ticket: int = budget.reserve()
	if ticket == 0: return ERR_UNAUTHORIZED
	var error := super.start(wire, callback)
	if error == OK: budget.mark_started(ticket)
	else: budget.release_unstarted(ticket)
	return error
