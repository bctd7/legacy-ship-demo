"""No-key, no-socket upstream error fixtures. Never touch the running service."""
import io
import json
import socket
import ssl
import unittest
from email.message import Message
from unittest.mock import patch
import urllib.error
import urllib.request

import server
from test_server import payload


class FakeResponse:
    def __init__(self, raw, status=200, headers=None):
        self.status, self.headers, self.raw = status, headers or {}, io.BytesIO(raw)
    def __enter__(self): return self
    def __exit__(self, *_args): self.raw.close()
    def read(self, limit): return self.raw.read(limit)


class FakeOpener:
    def __init__(self, outcome): self.outcome, self.calls = outcome, 0
    def open(self, _request, timeout):
        self.calls += 1
        if isinstance(self.outcome, Exception): raise self.outcome
        return self.outcome


def http_error(status=401, raw=None, headers=None):
    response_headers = Message()
    for name, value in (headers or {}).items(): response_headers[name] = value
    body = raw if raw is not None else json.dumps({"request_id": "test-request-001", "error": {
        "code": "AuthenticationError", "message": "DO_NOT_LEAK_BODY_MESSAGE"},
        "headers": {"Authorization": "DO_NOT_LEAK_AUTH"}}).encode()
    return urllib.error.HTTPError(server.OFFICIAL_URL, status, "DO_NOT_LEAK_REASON", response_headers, io.BytesIO(body))


class UpstreamDiagnosticTests(unittest.TestCase):
    def failure(self, outcome):
        opener = FakeOpener(outcome)
        # No Authorization header, no API key, no real opener or network socket.
        request = urllib.request.Request(server.OFFICIAL_URL, data=b"{}")
        with self.assertRaises(server.UpstreamFailure) as caught:
            server.fetch_official_image(request, opener)
        self.assertEqual(opener.calls, 1)
        diagnostic = caught.exception.diagnostic
        self.assertTrue("DO_NOT_LEAK" not in json.dumps(diagnostic))
        self.assertTrue("DO_NOT_LEAK" not in str(caught.exception))
        return diagnostic

    def test_http_status_vendor_code_and_structured_request_id(self):
        diagnostic = self.failure(http_error())
        self.assertEqual(diagnostic, {"category": "upstream_http", "upstream_http_status": 401,
                                      "vendor_code": "AuthenticationError", "upstream_request_id": "test-request-001"})

    def test_http_errors_are_not_confused_with_network_errors(self):
        for status in (400, 403, 404, 429, 500, 503):
            with self.subTest(status=status):
                diagnostic = self.failure(http_error(status))
                self.assertTrue(diagnostic["category"] == "upstream_http" and diagnostic["upstream_http_status"] == status)

    def test_header_request_id_is_selected_without_copying_other_headers(self):
        diagnostic = self.failure(http_error(raw=b"not json", headers={"x-request-id": "header-request-02", "Authorization": "DO_NOT_LEAK_AUTH"}))
        self.assertTrue(diagnostic["upstream_request_id"] == "header-request-02" and "vendor_code" not in diagnostic)

    def test_request_id_token_in_official_message_is_extracted_without_message(self):
        body = json.dumps({"error": {"code": "ModelNotOpen", "message": "DO_NOT_LEAK_BODY_MESSAGE Request ID: model-request-003."}}).encode()
        diagnostic = self.failure(http_error(404, raw=body))
        self.assertTrue(diagnostic["vendor_code"] == "ModelNotOpen" and diagnostic["upstream_request_id"] == "model-request-003")

    def test_oversized_error_body_is_not_parsed(self):
        with patch.object(server, "MAX_ERROR_BODY", 8):
            diagnostic = self.failure(http_error(headers={"x-tt-logid": "header-log-004"}))
        self.assertTrue(diagnostic["upstream_request_id"] == "header-log-004" and "vendor_code" not in diagnostic)

    def test_invalid_identifier_values_and_unlisted_fields_are_dropped(self):
        diagnostic = server.safe_diagnostic({"category": "upstream_http", "upstream_http_status": 401,
            "vendor_code": "Bearer DO_NOT_LEAK_AUTH", "upstream_request_id": "bad\nheader", "body": "DO_NOT_LEAK_BODY_MESSAGE", "headers": {}, "api_key": "DO_NOT_LEAK_AUTH"})
        self.assertEqual(diagnostic, {"category": "upstream_http", "upstream_http_status": 401})
        self.assertEqual(server.safe_diagnostic({"category": [], "upstream_http_status": True}), {})

    def test_timeout_is_classified_without_raw_reason(self):
        diagnostic = self.failure(urllib.error.URLError(TimeoutError("DO_NOT_LEAK_REASON")))
        self.assertEqual(diagnostic, {"category": "network_timeout"})

    def test_tls_error_is_classified_without_certificate_or_reason(self):
        diagnostic = self.failure(urllib.error.URLError(ssl.SSLError("DO_NOT_LEAK_REASON")))
        self.assertEqual(diagnostic, {"category": "network_tls"})

    def test_dns_error_is_classified_without_hostname_or_reason(self):
        diagnostic = self.failure(urllib.error.URLError(socket.gaierror(-2, "DO_NOT_LEAK_REASON")))
        self.assertEqual(diagnostic, {"category": "network_dns"})

    def test_connection_error_is_classified_without_raw_reason(self):
        diagnostic = self.failure(urllib.error.URLError(ConnectionRefusedError("DO_NOT_LEAK_REASON")))
        self.assertEqual(diagnostic, {"category": "network_connection"})

    def test_opaque_url_error_does_not_copy_reason_string(self):
        diagnostic = self.failure(urllib.error.URLError("DO_NOT_LEAK_REASON"))
        self.assertEqual(diagnostic, {"category": "network_transport"})

    def test_request_header_encoding_error_is_classified_without_header_data(self):
        diagnostic = self.failure(UnicodeEncodeError("ascii", "\u00e9", 0, 1, "DO_NOT_LEAK_REASON"))
        self.assertEqual(diagnostic, {"category": "request_encoding"})

    def test_bad_response_json_is_distinct_from_network_failure(self):
        diagnostic = self.failure(FakeResponse(b"DO_NOT_LEAK_BODY_MESSAGE", headers={"x-request-id": "response-json-1"}))
        self.assertTrue(diagnostic["category"] == "response_json" and diagnostic["upstream_http_status"] == 200)

    def test_schema_error_preserves_safe_vendor_code_only(self):
        body = json.dumps({"error": {"code": "OutputImageSensitiveContentDetected", "message": "DO_NOT_LEAK_BODY_MESSAGE"}}).encode()
        diagnostic = self.failure(FakeResponse(body))
        self.assertTrue(diagnostic["category"] == "response_schema" and diagnostic["vendor_code"] == "OutputImageSensitiveContentDetected")

    def test_image_decode_boundary_is_reported_without_base64(self):
        body = json.dumps({"data": [{"b64_json": "DO_NOT_LEAK_BODY_MESSAGE"}]}).encode()
        diagnostic = self.failure(FakeResponse(body))
        self.assertEqual({k: diagnostic[k] for k in ("category", "upstream_http_status")}, {"category": "response_image", "upstream_http_status": 200})

    def test_oversized_response_classification(self):
        with patch.object(server, "MAX_RESPONSE", 8):
            diagnostic = self.failure(FakeResponse(b"DO_NOT_LEAK_BODY_MESSAGE"))
        self.assertEqual({k: diagnostic[k] for k in ("category", "upstream_http_status")}, {"category": "response_too_large", "upstream_http_status": 200})

    def test_unexpected_exception_is_opaque(self):
        self.assertEqual(self.failure(RuntimeError("DO_NOT_LEAK_REASON")), {"category": "unexpected"})

    def test_simulated_failure_keeps_reservation_and_deduplicates_without_retry(self):
        engine = server.Engine(mode="stub", max_calls=1)
        # Exercise the paid-path accounting with NO key or socket, using only a fake opener.
        engine.mode, engine.unit_price_fen = "official", 60
        opener = FakeOpener(http_error())
        engine._official = lambda *_args: server.fetch_official_image(urllib.request.Request(server.OFFICIAL_URL, data=b"{}"), opener)
        try:
            with self.assertRaises(server.RequestError) as first:
                engine.generate(payload())
            self.assertTrue(first.exception.status == 502 and first.exception.diagnostic["upstream_http_status"] == 401)
            with self.assertRaises(server.RequestError) as repeat:
                engine.generate(payload())
            self.assertTrue(repeat.exception.code == "outcome_unknown" and repeat.exception.diagnostic == first.exception.diagnostic)
            audit = engine.audit()
            self.assertTrue(audit["real_calls"] == 1 and audit["reserved_fen"] == 60 and not audit["inflight"])
            self.assertTrue(audit["last_failure"] == first.exception.diagnostic and opener.calls == 1)
        finally:
            engine.close()

    def test_simulated_timeout_keeps_reservation_without_a_second_attempt(self):
        engine = server.Engine(mode="stub", max_calls=1)
        engine.mode, engine.unit_price_fen = "official", 60
        opener = FakeOpener(urllib.error.URLError(TimeoutError("DO_NOT_LEAK_REASON")))
        engine._official = lambda *_args: server.fetch_official_image(urllib.request.Request(server.OFFICIAL_URL, data=b"{}"), opener)
        try:
            with self.assertRaises(server.RequestError) as first:
                engine.generate(payload())
            with self.assertRaises(server.RequestError) as repeated:
                engine.generate(payload())
            audit = engine.audit()
            self.assertTrue(first.exception.diagnostic == {"category": "network_timeout"})
            self.assertTrue(repeated.exception.code == "outcome_unknown" and audit["reserved_fen"] == 60 and audit["real_calls"] == 1 and opener.calls == 1)
        finally:
            engine.close()

    def test_http_error_envelope_contains_only_safe_diagnostic_fields(self):
        diagnostic = {"category": "upstream_http", "upstream_http_status": 403, "vendor_code": "OperationDenied.ServiceNotOpen",
                      "upstream_request_id": "fixture-request-5", "body": "DO_NOT_LEAK_BODY_MESSAGE", "Authorization": "DO_NOT_LEAK_AUTH"}
        error = server.RequestError(502, "upstream_outcome_unknown", diagnostic)
        handler = object.__new__(server.Handler)
        handler.headers = {}
        captured = {}
        handler._send = lambda status, body: captured.update(status=status, body=body)
        handler._error(error)
        details = captured["body"]["error"]
        self.assertTrue(captured["status"] == 502 and details["outcome_unknown"] and not details["automatic_retry"])
        self.assertTrue(details["diagnostic"]["vendor_code"] == "OperationDenied.ServiceNotOpen")
        self.assertTrue("DO_NOT_LEAK" not in json.dumps(captured) and "DO_NOT_LEAK" not in str(error))

    def test_user_explicit_prior_reservation_is_preserved_with_one_new_attempt(self):
        engine = server.Engine(mode="stub", max_calls=1, prior_reserved_fen=60)
        engine.mode, engine.unit_price_fen = "official", 60
        opener = FakeOpener(urllib.error.URLError(TimeoutError()))
        engine._official = lambda *_args: server.fetch_official_image(urllib.request.Request(server.OFFICIAL_URL, data=b"{}"), opener)
        try:
            before = engine.audit()
            self.assertTrue(before["real_calls"] == 0 and before["prior_reserved_fen"] == 60 and before["reserved_fen"] == 60 and before["max_calls"] == 1)
            with self.assertRaises(server.RequestError): engine.generate(payload())
            with self.assertRaises(server.RequestError) as limit: engine.generate(payload(prompt="another", request_id="another"))
            after = engine.audit()
            self.assertTrue(after["reserved_fen"] == 120 and after["session_reserved_fen"] == 60 and after["prior_reserved_fen"] == 60)
            self.assertTrue(limit.exception.code == "session_limit" and after["real_calls"] == 1 and opener.calls == 1)
        finally:
            engine.close()

    def test_prior_reservation_counts_against_total_ten_yuan_limit(self):
        engine = server.Engine(mode="stub", max_calls=1, prior_reserved_fen=960)
        engine.mode, engine.unit_price_fen = "official", 60
        try:
            with self.assertRaises(server.RequestError) as limit: engine.generate(payload())
            self.assertTrue(limit.exception.code == "session_limit" and engine.audit()["reserved_fen"] == 960 and engine.audit()["real_calls"] == 0)
        finally:
            engine.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
