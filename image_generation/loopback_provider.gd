extends "res://image_generation/provider.gd"
## Local protocol only. No provider secret, model selection or dependency on levels.
const Codec = preload("res://image_generation/codec.gd")
var port := 8769
var expected_mode := "stub" # Must be explicitly "official" for a configured real service.
var request_id := "" # Optional caller operation ID; server also deduplicates content.

func encode(snapshot: Dictionary) -> Dictionary:
	if port < 1 or port > 65535 or expected_mode not in ["stub", "official"]:
		return {"failure": Result.failure("configuration", "Invalid local service configuration.")}
	var operation_id := request_id
	if operation_id.is_empty(): operation_id = Crypto.new().generate_random_bytes(16).hex_encode()
	var payload := {"schema_version": 1, "request_id": operation_id, "prompt": snapshot.prompt,
		"image": {"mime_type": "image/png", "base64": Marshalls.raw_to_base64(snapshot.png)}}
	return {"wire": {"url": "http://127.0.0.1:%d/v1/images/generate" % port,
		"local_mode": expected_mode, "headers": PackedStringArray(["Content-Type: application/json"]),
		"body": JSON.stringify(payload).to_utf8_buffer()}}

func decode(status: int, body: PackedByteArray):
	if body.size() > Codec.MAX_BODY_BYTES:
		return Result.failure("response_too_large", "Local response exceeds package limits.", status, true)
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		return Result.failure("invalid_response", "Expected a local JSON response.", status, true)
	if status != 200:
		var code := "local_service_error"
		var upstream_error = data.get("error", {})
		if upstream_error is Dictionary and upstream_error.get("code") in ["in_progress", "outcome_unknown", "busy", "session_limit", "request_id_conflict", "upstream_outcome_unknown"]:
			code = upstream_error.code
		var diagnostic := _safe_diagnostic(upstream_error.get("diagnostic") if upstream_error is Dictionary else null)
		var message := "Local request failed; no automatic retry."
		if diagnostic.has("category"): message = "Local request failed (%s); no automatic retry." % diagnostic.category
		var failure = Result.failure(code, message, status, code in ["in_progress", "outcome_unknown", "upstream_outcome_unknown"] or status >= 500)
		if not diagnostic.is_empty(): failure.error.diagnostic = diagnostic
		return failure
	var source := "local_stub" if expected_mode == "stub" else "volcengine_official"
	var output = data.get("image")
	if data.get("schema_version") != 1 or data.get("mode") != expected_mode or data.get("source") != source or not output is Dictionary or output.get("mime_type") != "image/png":
		return Result.failure("mode_mismatch", "Local service mode/output did not match the selected mode.", status, true)
	return Codec.from_base64(output.get("base64"))

static func _safe_diagnostic(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	var safe := {}
	if value.get("category") in ["upstream_http", "network_timeout", "network_tls", "network_dns", "network_connection", "network_transport", "request_encoding", "response_json", "response_schema", "response_image", "response_too_large", "unexpected", "response_encoding", "response_charset", "response_compression", "response_truncated", "response_stream", "response_content_type", "response_empty"]:
		safe.category = value.category
	var status = value.get("upstream_http_status")
	if (status is int or status is float) and status >= 100 and status <= 599 and status == int(status):
		safe.upstream_http_status = int(status)
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9][A-Za-z0-9_.:-]*$")
	for field in ["vendor_code", "upstream_request_id"]:
		var token = value.get(field)
		var limit := 96 if field == "vendor_code" else 128
		if not token is String or token.is_empty() or token.length() > limit or token.contains("\r") or token.contains("\n") or pattern.search(token) == null: continue
		var rejected := false
		for prefix in ["bearer", "sk-", "authorization", "api_key", "api-key"]:
			if token.to_lower().begins_with(prefix): rejected = true
		if not rejected: safe[field] = token
	var enums := {
		"response_content_type": ["application/json", "text/event-stream", "text/html", "text/plain", "image/png", "application/octet-stream", "missing", "other"],
		"response_content_encoding": ["identity", "gzip", "deflate", "br", "other"],
		"response_charset": ["unspecified", "utf-8", "utf-16", "utf-32", "other"],
		"response_bom": ["none", "utf-8", "utf-16-le", "utf-16-be", "utf-32-le", "utf-32-be"],
		"response_body_kind": ["empty", "json_candidate", "sse", "html", "png", "binary", "other"],
		"parse_failure": ["syntax", "extra_data", "unicode", "depth", "compression", "unsupported_encoding", "unsupported_charset", "length_mismatch", "incomplete_read", "unexpected_sse", "unexpected_html", "empty"]}
	for key in enums:
		if value.get(key) is String and value[key] in enums[key]: safe[key] = value[key]
	for key in ["wire_bytes", "decoded_bytes", "declared_bytes", "parse_position", "parse_line", "parse_column"]:
		var number = value.get(key)
		if (number is int or number is float) and number >= 0 and number <= 1099511627776 and number == int(number): safe[key] = int(number)
	for key in ["read_incomplete", "recovery_saved"]:
		if value.get(key) is bool: safe[key] = value[key]
	var capture = value.get("recovery_id")
	var recovery_pattern := RegEx.new()
	recovery_pattern.compile("^[0-9a-f]{32}$")
	if capture is String and capture.length() == 32 and recovery_pattern.search(capture) != null: safe.recovery_id = capture
	return safe
