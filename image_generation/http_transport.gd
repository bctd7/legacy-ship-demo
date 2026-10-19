extends Node
## Opt-in only. No environment reads, key storage, retries, redirects or logging.
const Codec = preload("res://image_generation/codec.gd")
var enabled := false
var allowed_urls := PackedStringArray() # Exact endpoint allowlist from trusted setup.
var transient_headers: Callable # Optional session header supplier; never a Resource/export.
var _http: HTTPRequest
var _callback: Callable

func start(wire: Dictionary, callback: Callable) -> int:
	var url: String = wire.get("url", "")
	if not enabled or not allowed_urls.has(url) or not url.begins_with("https://") or url.contains("@") or url.contains("?") or url.contains("#"):
		return ERR_UNAUTHORIZED
	_http = HTTPRequest.new()
	_http.max_redirects = 0
	_http.body_size_limit = Codec.MAX_BODY_BYTES
	_http.accept_gzip = false
	_http.timeout = 0.0 # Service owns the total deadline.
	add_child(_http)
	_callback = callback
	_http.request_completed.connect(_completed)
	var headers := PackedStringArray(wire.headers)
	if transient_headers.is_valid():
		var extra: PackedStringArray = transient_headers.call()
		for header in extra:
			if header.contains("\r") or header.contains("\n"): return ERR_INVALID_PARAMETER
		headers.append_array(extra)
	return _http.request_raw(url, headers, HTTPClient.METHOD_POST, wire.body)

func cancel() -> void:
	_callback = Callable()
	if is_instance_valid(_http): _http.cancel_request()

func _completed(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _callback.is_valid():
		var callback := _callback
		_callback = Callable()
		callback.call({"transport_error": result != HTTPRequest.RESULT_SUCCESS, "status": status, "body": body})
