extends Node
## Explicit loopback exception. The generic HTTPS transport remains unchanged.
const Codec = preload("res://image_generation/codec.gd")
var _http: HTTPRequest
var _callback: Callable
var _wire: Dictionary = {}
var _phase := ""
var _base := ""
var _session := "" # Process memory only; never logged or stored in Resource/files.

func start(wire: Dictionary, callback: Callable) -> int:
	var pattern := RegEx.new()
	pattern.compile("^http://127[.]0[.]0[.]1:([1-9][0-9]{0,4})/v1/images/generate$")
	var match_url := pattern.search(str(wire.get("url", "")))
	if match_url == null or int(match_url.get_string(1)) > 65535 or wire.get("local_mode") not in ["stub", "official"]:
		return ERR_UNAUTHORIZED
	_base = "http://127.0.0.1:" + match_url.get_string(1)
	_wire = wire
	_callback = callback
	_http = HTTPRequest.new()
	_http.max_redirects = 0
	_http.accept_gzip = false
	_http.body_size_limit = 2048
	add_child(_http)
	_http.request_completed.connect(_completed)
	_phase = "session"
	return _http.request(_base + "/v1/session", PackedStringArray(["X-Image-Client: godot-loopback-v1"]))

func cancel() -> void:
	_callback = Callable()
	_session = ""
	_wire = {}
	if is_instance_valid(_http): _http.cancel_request()

func _completed(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _callback.is_valid(): return
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish({"transport_error": true})
		return
	if _phase == "session":
		var data = JSON.parse_string(body.get_string_from_utf8())
		if status != 200 or not data is Dictionary or data.get("mode") != _wire.local_mode or not data.get("session") is String:
			_finish({"transport_error": true})
			return
		var token_pattern := RegEx.new()
		token_pattern.compile("^[A-Za-z0-9_-]{32,128}$")
		if token_pattern.search(data.session) == null:
			_finish({"transport_error": true})
			return
		_session = data.session
		_phase = "generation"
		_http.body_size_limit = Codec.MAX_BODY_BYTES
		var headers := PackedStringArray(["Content-Type: application/json", "X-Image-Client: godot-loopback-v1", "X-Local-Session: " + _session])
		var error := _http.request_raw(_wire.url, headers, HTTPClient.METHOD_POST, _wire.body)
		_session = ""
		_wire = {}
		if error != OK: _finish({"transport_error": true})
		return
	_finish({"status": status, "body": body})

func _finish(reply: Dictionary) -> void:
	var callback := _callback
	_callback = Callable()
	_session = ""
	_wire = {}
	callback.call(reply)
