"""Finite native HTTP tests. All images synthetic, all engines explicitly stub."""
import base64
import concurrent.futures
import http.client
import json
import struct
import threading
import time
import unittest
import zlib

from server import CLIENT_HEADER, MAX_BODY, Engine, LocalServer


def synthetic_bridge_png():
    width, height = 64, 48
    pixels = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            bridge = (8 <= x < 57 and 25 <= y < 29) or (x in range(15, 19) or x in range(44, 48)) and 29 <= y < 40
            drawing = 5 <= x <= 58 and y == 10 + x // 16
            row.extend((110, 65, 30) if bridge else (30, 90, 170) if drawing else (245, 240, 225))
        pixels.append(row)
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(b"".join(pixels))) + chunk(b"IEND", b"")


def payload(prompt="synthetic bridge drawing", request_id="test-1"):
    return {"schema_version": 1, "request_id": request_id, "prompt": prompt,
            "image": {"mime_type": "image/png", "base64": base64.b64encode(synthetic_bridge_png()).decode("ascii")}}


class LocalHTTPTests(unittest.TestCase):
    def setUp(self):
        self.engine = Engine(mode="stub", max_calls=16)
        self.server = LocalServer(0, self.engine)
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.engine.close()

    def request(self, method, path, data=None, headers=None, raw=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=2)
        fields = {"X-Image-Client": CLIENT_HEADER, "X-Local-Session": self.engine.session}
        if data is not None or raw is not None:
            fields["Content-Type"] = "application/json"
        fields.update(headers or {})
        encoded = json.dumps(data).encode() if data is not None else raw
        connection.request(method, path, encoded, fields)
        response = connection.getresponse()
        status, body = response.status, json.loads(response.read())
        connection.close()
        return status, body

    def test_loopback_binding_and_memory_session_handshake(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        status, body = self.request("GET", "/v1/session", headers={"X-Local-Session": ""})
        self.assertEqual(status, 200)
        self.assertTrue(body["mode"] == "stub" and len(body["session"]) >= 32)

    def test_actual_http_stub_is_explicit_and_never_calls_upstream(self):
        self.engine._official = lambda *_: self.fail("Stub must not call an external model")
        status, body = self.request("POST", "/v1/images/generate", payload())
        self.assertEqual(status, 200)
        self.assertTrue(body["mode"] == "stub" and body["source"] == "local_stub")
        self.assertTrue(body["image"]["base64"] == payload()["image"]["base64"])
        self.assertTrue(self.engine.audit()["real_calls"] == 0 and self.engine.audit()["reserved_fen"] == 0)

    def test_identical_content_is_cached_without_another_dispatch(self):
        self.request("POST", "/v1/images/generate", payload())
        status, _ = self.request("POST", "/v1/images/generate", payload(request_id="different-click-id"))
        self.assertEqual(status, 200)
        self.assertTrue(self.engine.audit()["stub_calls"] == 1 and self.engine.audit()["cache_hits"] == 1)

    def test_inflight_repeated_click_is_rejected(self):
        self.engine.delay = 0.25
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            first = pool.submit(self.request, "POST", "/v1/images/generate", payload())
            deadline = time.monotonic() + 1
            while not self.engine.audit()["inflight"] and time.monotonic() < deadline:
                time.sleep(0.005)
            status, body = self.request("POST", "/v1/images/generate", payload(request_id="second-click"))
            self.assertTrue(status == 409 and body["error"]["code"] == "in_progress")
            self.assertEqual(first.result()[0], 200)
        self.assertEqual(self.engine.audit()["stub_calls"], 1)

    def test_request_id_cannot_be_reused_for_other_content(self):
        self.request("POST", "/v1/images/generate", payload())
        status, body = self.request("POST", "/v1/images/generate", payload(prompt="other drawing"))
        self.assertTrue(status == 409 and body["error"]["code"] == "request_id_conflict")

    def test_origin_referer_host_and_missing_session_are_rejected(self):
        for headers, expected in [({"Origin": "https://example.invalid"}, 403), ({"Referer": "https://example.invalid"}, 403),
                                  ({"Host": "localhost:%d" % self.server.server_port}, 403), ({"X-Local-Session": ""}, 401),
                                  ({"X-Image-Client": ""}, 403)]:
            with self.subTest(expected=expected):
                self.assertEqual(self.request("POST", "/v1/images/generate", payload(), headers)[0], expected)
        self.assertEqual(self.engine.audit()["stub_calls"], 0)

    def test_invalid_bodies_are_rejected_without_dispatch(self):
        malformed = [None, [], {}, dict(payload(), prompt=" "), dict(payload(), image={"mime_type": "image/png", "base64": "not png"}),
                     dict(payload(), endpoint="https://third-party.invalid")]
        for data in malformed:
            raw = json.dumps(data).encode()
            self.assertEqual(self.request("POST", "/v1/images/generate", raw=raw)[0], 400)
        self.assertEqual(self.request("POST", "/v1/images/generate", raw=b"{")[0], 400)
        self.assertEqual(self.engine.audit()["stub_calls"], 0)

    def test_content_type_and_oversized_length_are_rejected(self):
        self.assertEqual(self.request("POST", "/v1/images/generate", payload(), {"Content-Type": "text/plain"})[0], 415)
        self.assertEqual(self.request("POST", "/v1/images/generate", raw=b"", headers={"Content-Length": str(MAX_BODY + 1)})[0], 413)

    def test_session_limit_stops_new_dispatch_but_preserves_cache(self):
        self.engine.max_calls = 1
        self.request("POST", "/v1/images/generate", payload())
        self.assertEqual(self.request("POST", "/v1/images/generate", payload(prompt="next", request_id="next"))[0], 429)
        self.assertEqual(self.request("POST", "/v1/images/generate", payload())[0], 200)

    def test_cancelled_http_wait_does_not_clear_receipt(self):
        self.engine.delay = 0.15
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=2)
        connection.request("POST", "/v1/images/generate", json.dumps(payload()),
                           {"Content-Type": "application/json", "X-Image-Client": CLIENT_HEADER, "X-Local-Session": self.engine.session})
        deadline = time.monotonic() + 1
        while not self.engine.audit()["inflight"] and time.monotonic() < deadline:
            time.sleep(0.005)
        connection.close()
        time.sleep(0.2)
        self.assertEqual(self.request("POST", "/v1/images/generate", payload())[0], 200)
        self.assertEqual(self.engine.audit()["stub_calls"], 1)

    def test_official_mode_without_safe_credential_or_known_price_is_unavailable(self):
        with self.assertRaises(ValueError):
            Engine(mode="official")


if __name__ == "__main__":
    unittest.main(verbosity=2)
