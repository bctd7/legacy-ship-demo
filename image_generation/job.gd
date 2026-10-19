extends RefCounted
signal finished(result)
signal cancel_requested
var done := false
var result: RefCounted

func cancel() -> void:
	if not done: cancel_requested.emit()

func complete(value: RefCounted) -> void:
	if done: return
	done = true
	result = value
	# Release the cancellation closure's job/state cycle before notifying callers.
	for connection in cancel_requested.get_connections():
		cancel_requested.disconnect(connection.callable)
	finished.emit(value)
