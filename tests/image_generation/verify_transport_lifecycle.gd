extends SceneTree
const Service = preload("res://image_generation/service.gd")
const Request = preload("res://image_generation/request.gd")
const Proxy = preload("res://image_generation/proxy_provider.gd")
var checks := 0
var failures := 0

class CancelCallbackTransport extends Node:
	var callback: Callable
	var reply: Dictionary
	var cancel_calls := 0
	var cancel_again: Callable
	func start(_wire: Dictionary, target: Callable) -> int:
		callback = target
		return OK
	func deliver() -> void:
		callback.call(reply)
	func cancel() -> void:
		cancel_calls += 1
		# Bound the adversarial fixture so the unfixed service fails without overflowing.
		if cancel_calls == 1:
			callback.call(reply)
			if cancel_again.is_valid(): cancel_again.call()

class MissingStartTransport extends Node:
	var cancel_calls := 0
	func cancel() -> void:
		cancel_calls += 1

class MissingCancelTransport extends Node:
	var start_calls := 0
	func start(_wire: Dictionary, _target: Callable) -> int:
		start_calls += 1
		return OK

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("TRANSPORT_LIFECYCLE_PASS: " if ok else "TRANSPORT_LIFECYCLE_FAIL: ") + label)

func wait_job(job: RefCounted):
	if job.done: return job.result
	return await job.finished

func assert_cleanup_before_signal(service: Node, transport: Node, signal_count: Array) -> void:
	signal_count[0] += 1
	var cleaned: bool = transport.is_queued_for_deletion() and transport.cancel_calls == 1
	for child in service.get_children():
		if child is Timer: cleaned = cleaned and child.is_stopped() and child.is_queued_for_deletion()
	check(cleaned, "finished is emitted after transport and deadline cleanup")

func run() -> void:
	var source := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	source.fill(Color.BLUE)
	var request := Request.new(source, "synthetic lifecycle test")
	var service := Service.new()
	var provider := Proxy.new()
	provider.endpoint = "https://offline.invalid/lifecycle"
	service.provider = provider
	root.add_child(service)
	var fixture := {"schema_version": 1, "image": {"mime_type": "image/png", "base64": Marshalls.raw_to_base64(source.save_png_to_buffer())}}
	var reply := {"status": 200, "body": JSON.stringify(fixture).to_utf8_buffer()}

	# Explicit cancellation must win even if cancel() returns a synchronous success.
	var transport := CancelCallbackTransport.new()
	transport.reply = reply
	service.transport_factory = func(): return transport
	var job = service.generate(request)
	await process_frame
	var signal_count := [0]
	transport.cancel_again = job.cancel
	job.finished.connect(func(_r): assert_cleanup_before_signal(service, transport, signal_count))
	job.cancel()
	check(job.done and not job.result.ok and job.result.error.code == "cancelled", "synchronous cancel callback cannot replace cancellation with success")
	check(signal_count[0] == 1 and transport.cancel_calls == 1, "reentrant cancel completes and cancels transport exactly once")
	transport.deliver()
	check(job.result.error.get("code") == "cancelled" and signal_count[0] == 1, "late success callback cannot replace completed cancellation")
	await process_frame

	# The same reentrancy can occur during success cleanup.
	transport = CancelCallbackTransport.new()
	transport.reply = reply
	service.transport_factory = func(): return transport
	job = service.generate(request)
	await process_frame
	signal_count = [0]
	job.finished.connect(func(_r): assert_cleanup_before_signal(service, transport, signal_count))
	transport.deliver()
	check(job.result.ok and signal_count[0] == 1 and transport.cancel_calls == 1, "success cleanup tolerates synchronous callbacks from cancel")
	await process_frame

	# A timeout remains a timeout when cancel() reports a generated image.
	transport = CancelCallbackTransport.new()
	transport.reply = reply
	service.transport_factory = func(): return transport
	request.timeout_seconds = 0.02
	job = service.generate(request)
	var result = await wait_job(job)
	check(not result.ok and result.error.get("code") == "timeout" and transport.cancel_calls == 1, "timeout survives synchronous success during cleanup")
	await process_frame
	request.timeout_seconds = 1.0

	# Unparented Node ownership transfers from factory to service, even if invalid.
	var missing_start := MissingStartTransport.new()
	var invalid_ref: WeakRef = weakref(missing_start)
	service.transport_factory = func(): return missing_start
	result = await wait_job(service.generate(request))
	check(result.error.get("code") == "configuration" and missing_start.cancel_calls == 0, "invalid unparented transport rejected without invoking its hooks")
	await process_frame
	check(invalid_ref.get_ref() == null, "factory-owned Node missing start is released")
	if invalid_ref.get_ref() != null: invalid_ref.get_ref().free()

	var missing_cancel := MissingCancelTransport.new()
	invalid_ref = weakref(missing_cancel)
	service.transport_factory = func(): return missing_cancel
	result = await wait_job(service.generate(request))
	check(result.error.get("code") == "configuration" and missing_cancel.start_calls == 0, "Node missing cancel is rejected before start")
	await process_frame
	check(invalid_ref.get_ref() == null, "factory-owned Node missing cancel is released")
	if invalid_ref.get_ref() != null: invalid_ref.get_ref().free()

	# A parented Node stays with its external owner, including its children.
	var external_owner := Node.new()
	root.add_child(external_owner)
	var external := MissingStartTransport.new()
	var child := Node.new()
	external.add_child(child)
	external_owner.add_child(external)
	service.transport_factory = func(): return external
	result = await wait_job(service.generate(request))
	await process_frame
	check(result.error.get("code") == "configuration" and is_instance_valid(external) and not external.is_queued_for_deletion() and external.get_parent() == external_owner and external.cancel_calls == 0 and is_instance_valid(child), "parented external Node and its children remain untouched")
	external_owner.queue_free()
	service.queue_free()
	await process_frame
	print("TRANSPORT_LIFECYCLE_CHECKS: %d passed / %d total; offline only" % [checks - failures, checks])
	quit(1 if failures else 0)
