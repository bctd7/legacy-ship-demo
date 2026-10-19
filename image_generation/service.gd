extends Node
## Add to SceneTree. All operations run on the main thread. No autoload required.
const Request = preload("res://image_generation/request.gd")
const Result = preload("res://image_generation/result.gd")
const Job = preload("res://image_generation/job.gd")
const Codec = preload("res://image_generation/codec.gd")
var provider: RefCounted
var transport_factory: Callable # A fresh unparented Node transfers ownership, even if invalid.
var _active: Dictionary = {}

func generate(request: RefCounted) -> RefCounted:
	var job := Job.new()
	var state := {"job": job, "provider": provider, "factory": transport_factory,
		"transport": null, "timer": null, "sent": false, "finishing": false, "snapshot": {}}
	_active[job.get_instance_id()] = state
	job.cancel_requested.connect(func(): _finish(state, Result.failure("cancelled", "Generation cancelled locally.", 0, state.sent)))
	var error := _snapshot(request, state)
	call_deferred("_begin", state, error)
	return job

func _snapshot(request: RefCounted, state: Dictionary) -> String:
	if not request is Request: return "Expected an image generation Request."
	if request.prompt.strip_edges().is_empty() or request.prompt.length() > 32000: return "Prompt must contain 1 to 32000 characters."
	if not is_finite(request.timeout_seconds) or request.timeout_seconds < 0.01 or request.timeout_seconds > 600: return "Timeout must be between 0.01 and 600 seconds."
	if request.image == null or request.image.is_empty(): return "An input image is required."
	if not Codec.valid_extent(request.image.get_width(), request.image.get_height()): return "Input image dimensions exceed package limits."
	var copy: Image = request.image.duplicate()
	if copy.is_compressed() and copy.decompress() != OK: return "Input image could not be decompressed."
	copy.convert(Image.FORMAT_RGBA8)
	var bytes := copy.save_png_to_buffer()
	if bytes.is_empty() or bytes.size() > Codec.MAX_IMAGE_BYTES: return "Input PNG exceeds package limits."
	state.snapshot = {"png": bytes, "prompt": request.prompt}
	state.timeout = request.timeout_seconds
	return ""

func _begin(state: Dictionary, error: String) -> void:
	if state.job.done: return
	if not error.is_empty():
		_finish(state, Result.failure("invalid_input", error))
		return
	if not is_inside_tree() or state.provider == null or not state.factory.is_valid():
		_finish(state, Result.failure("configuration", "Service needs a SceneTree, provider and transport factory."))
		return
	var encoded: Dictionary = state.provider.encode(state.snapshot)
	state.snapshot.clear()
	if encoded.has("failure"):
		_finish(state, encoded.failure)
		return
	var transport = state.factory.call()
	if not transport is Node or transport.get_parent() != null or not transport.has_method("start") or not transport.has_method("cancel"):
		# Only an unparented Node was handed over; external owners retain theirs.
		if transport is Node and transport.get_parent() == null:
			transport.queue_free()
		_finish(state, Result.failure("configuration", "Transport factory must return a fresh transport Node."))
		return
	state.transport = transport
	add_child(transport)
	var timer := Timer.new()
	timer.one_shot = true
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(timer)
	state.timer = timer
	timer.timeout.connect(func(): _finish(state, Result.failure("timeout", "Generation timed out locally.", 0, state.sent)))
	timer.start(state.timeout)
	# Mark potentially sent before start: a transport may complete synchronously.
	state.sent = true
	var start_error: int = transport.start(encoded.wire, func(reply: Dictionary): _reply(state, reply))
	if start_error != OK and not state.job.done:
		state.sent = false
		_finish(state, Result.failure("transport_start", "Transport did not start."))

func _reply(state: Dictionary, reply: Dictionary) -> void:
	if state.job.done or state.finishing: return
	if reply.get("transport_error", false):
		_finish(state, Result.failure("network", "Generation transport failed; remote outcome may be unknown.", 0, true))
		return
	_finish(state, state.provider.decode(reply.get("status", 0), reply.get("body", PackedByteArray())))

func _finish(state: Dictionary, result: RefCounted) -> void:
	if state.job.done or state.finishing: return
	# cancel() is injected code and may synchronously call back or cancel again.
	state.finishing = true
	if is_instance_valid(state.timer):
		state.timer.stop()
		state.timer.queue_free()
	if is_instance_valid(state.transport):
		state.transport.cancel()
		state.transport.queue_free()
	state.snapshot.clear()
	_active.erase(state.job.get_instance_id())
	state.job.complete(result)

func _exit_tree() -> void:
	for state in _active.values():
		_finish(state, Result.failure("cancelled", "Generation service closed.", 0, state.sent))
