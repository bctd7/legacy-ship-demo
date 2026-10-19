extends SceneTree
const Provider = preload("res://image_generation/loopback_provider.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	var provider := Provider.new()
	var diagnostic := {"category": "upstream_http", "upstream_http_status": 401, "vendor_code": "AuthenticationError", "upstream_request_id": "fixture-request-1"}
	var result = decode(provider, diagnostic)
	check(result.error.code == "upstream_outcome_unknown" and result.error.diagnostic == diagnostic, "safe upstream status/code/id survive the unified result boundary")
	check(result.error.outcome_unknown and not result.error.automatic_retry and result.error.message.contains("upstream_http"), "failure stays ambiguous and non-retrying with a fixed category message")
	var extra := diagnostic.duplicate()
	extra.headers = {"Authorization": "DO_NOT_LEAK"}
	extra.body = "DO_NOT_LEAK"
	extra.message = "DO_NOT_LEAK"
	result = decode(provider, extra)
	check(result.error.diagnostic == diagnostic and not str(result.error).contains("DO_NOT_LEAK"), "unlisted body/message/header fields never propagate")
	result = decode(provider, {"category": "unknown category DO_NOT_LEAK", "upstream_http_status": 999, "vendor_code": "bad\nheader", "upstream_request_id": "Bearer DO_NOT_LEAK"})
	check(not result.error.has("diagnostic"), "invalid category/status/identifier values are discarded")
	result = decode(provider, {"category": "network_timeout"})
	check(result.error.diagnostic.category == "network_timeout" and result.error.outcome_unknown and not result.error.automatic_retry, "timeout classification never implies cancellation or a refund")
	result = decode(provider, ["DO_NOT_LEAK"])
	check(not result.error.has("diagnostic"), "non-object diagnostic rejected")
	result = decode(provider, {"vendor_code": "sk-DO_NOT_LEAK", "upstream_request_id": "x".repeat(129), "upstream_http_status": 200.5})
	check(not result.error.has("diagnostic"), "credential-like prefixes, oversized identifiers and fractional status rejected")
	result = decode(provider, {"vendor_code": "trailing-newline\n", "upstream_request_id": "trailing-cr\r"})
	check(not result.error.has("diagnostic"), "trailing control characters cannot bypass identifier filtering")
	result = provider.decode(502, JSON.stringify({"error": {"code": "upstream_outcome_unknown"}}).to_utf8_buffer())
	check(not result.ok and result.error.code == "upstream_outcome_unknown" and not result.error.has("diagnostic"), "old running service responses remain compatible")
	var framing := {"category": "response_truncated", "upstream_http_status": 200, "response_content_type": "application/json", "response_content_encoding": "gzip", "response_charset": "utf-8", "response_bom": "none", "response_body_kind": "json_candidate", "wire_bytes": 1024, "decoded_bytes": 2048, "declared_bytes": 4096, "parse_position": 5, "parse_line": 2, "parse_column": 3, "parse_failure": "length_mismatch", "read_incomplete": true, "recovery_saved": true, "recovery_id": "a".repeat(32)}
	result = decode(provider, framing)
	check(result.error.diagnostic == framing and result.error.outcome_unknown, "response framing metadata and recovery reference survive the unified boundary")
	result = decode(provider, {"category": "response_encoding", "response_content_encoding": "br", "recovery_saved": false})
	check(result.error.diagnostic.response_content_encoding == "br" and not result.error.diagnostic.recovery_saved, "unsupported compression is explicit and a save failure does not claim recovery")
	result = decode(provider, {"response_content_type": "DO_NOT_LEAK", "response_charset": "DO_NOT_LEAK", "response_body_kind": "DO_NOT_LEAK", "parse_failure": "DO_NOT_LEAK", "wire_bytes": true, "decoded_bytes": -1, "parse_position": 1.5, "parse_line": 1099511627777, "recovery_saved": "yes", "recovery_id": "../DO_NOT_LEAK"})
	check(not result.error.has("diagnostic"), "raw feature values, invalid positions and path-like recovery IDs cannot propagate")
	print("LOOPBACK_DIAGNOSTIC_CHECKS: %d passed / %d total; fixtures only, no HTTP" % [checks - failures, checks])
	quit(1 if failures else 0)

func decode(provider: RefCounted, diagnostic: Variant):
	return provider.decode(502, JSON.stringify({"schema_version": 1, "error": {"code": "upstream_outcome_unknown", "diagnostic": diagnostic}}).to_utf8_buffer())

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("LOOPBACK_DIAGNOSTIC_PASS: " if ok else "LOOPBACK_DIAGNOSTIC_FAIL: ") + label)
