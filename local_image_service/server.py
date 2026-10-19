"""Loopback-only image bridge. Standard library; no environment credential reads."""
import argparse
import base64
import binascii
import getpass
import hashlib
import hmac
import http.client
import json
import re
import secrets
import socket
import ssl
import struct
import sys
import threading
import time
import urllib.error
import urllib.request
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from response_codec import CATEGORIES, DecodeFailure, decode_document, response_metadata, safe_response_fields
from recovery import RecoveryStore

OFFICIAL_URL = "https://ark.cn-beijing.volces.com/api/v3/images/generations"
MODEL_ID = "doubao-seedream-5-0-flash-260915"
MODEL_PROFILES = {
    "flash": {"model_id": MODEL_ID, "unit_price_fen": 12},
    "pro": {"model_id": "doubao-seedream-5-0-pro-260628", "unit_price_fen": 60},
}
CLIENT_HEADER = "godot-loopback-v1"
MAX_IMAGE = 8 * 1024 * 1024
MAX_BODY = 12 * 1024 * 1024
MAX_RESPONSE = 24 * 1024 * 1024
MAX_ERROR_BODY = 16 * 1024
ERROR_CATEGORIES = frozenset({"upstream_http", "network_timeout", "network_tls", "network_dns",
                             "network_connection", "network_transport", "request_encoding",
                             "response_json", "response_schema", "response_image", "response_too_large", "unexpected"}) | CATEGORIES


def safe_diagnostic(data):
    """Only fixed categories/status and bounded identifier tokens, never messages."""
    if not isinstance(data, dict):
        return {}
    safe = safe_response_fields(data)
    category = data.get("category")
    if isinstance(category, str) and category in ERROR_CATEGORIES:
        safe["category"] = category
    status = data.get("upstream_http_status")
    if type(status) is int and 100 <= status <= 599:
        safe["upstream_http_status"] = status
    for field, limit in (("vendor_code", 96), ("upstream_request_id", 128)):
        value = data.get(field)
        if isinstance(value, str) and 1 <= len(value) <= limit and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.:-]*", value) and not value.lower().startswith(("bearer", "sk-", "authorization", "api_key", "api-key")):
            safe[field] = value
    return safe


def error_identifiers(data=None, headers=None):
    """Read only named identifier fields/header values; never emit a raw message."""
    result = {}
    if isinstance(data, dict):
        error = data.get("error", {})
        if not isinstance(error, dict): error = {}
        result["vendor_code"] = error.get("code")
        result["upstream_request_id"] = data.get("request_id") or data.get("RequestId") or error.get("request_id")
        # Official docs also place Request ID in error.message. Extract the token
        # only, with an explicit delimiter; no other message content is retained.
        message = error.get("message")
        if not result["upstream_request_id"] and isinstance(message, str) and len(message) <= MAX_ERROR_BODY:
            match = re.search(r"\bRequest\s*ID\s*:\s*([A-Za-z0-9][A-Za-z0-9_.:-]{0,127})(?=\s|$)", message, re.IGNORECASE)
            if match: result["upstream_request_id"] = match.group(1).rstrip(".:")
    if headers is not None and not safe_diagnostic(result).get("upstream_request_id"):
        # Never iterate or serialize response headers. These are correlation IDs.
        result["upstream_request_id"] = headers.get("x-request-id") or headers.get("x-tt-logid")
    return safe_diagnostic(result)


class UpstreamFailure(Exception):
    def __init__(self, category, **fields):
        self.diagnostic = safe_diagnostic(dict(fields, category=category))
        super().__init__(category)  # Fixed category only, never raw exception text.


def classify_exception(error):
    reason = error.reason if isinstance(error, urllib.error.URLError) else error
    if isinstance(error, urllib.error.HTTPError):
        return safe_diagnostic({"category": "upstream_http", "upstream_http_status": error.code})
    if isinstance(reason, UnicodeError): category = "request_encoding"
    elif isinstance(reason, (TimeoutError, socket.timeout)): category = "network_timeout"
    elif isinstance(reason, ssl.SSLError): category = "network_tls"
    elif isinstance(reason, socket.gaierror): category = "network_dns"
    elif isinstance(reason, ConnectionError): category = "network_connection"
    elif isinstance(error, urllib.error.URLError) or isinstance(reason, OSError): category = "network_transport"
    else: category = "unexpected"
    return {"category": category}


def parse_official_response(raw, metadata):
    """Pure bounded decoding, shared by live delivery and offline recovery."""
    try:
        data, info = decode_document(raw, metadata, limit=MAX_RESPONSE)
    except DecodeFailure as error:
        raise UpstreamFailure(error.category, **dict(metadata, **error.info)) from None
    fields = dict(metadata, **info)
    if not isinstance(data, dict):
        raise UpstreamFailure("response_schema", **fields)
    fields.update(error_identifiers(data))
    rows = data.get("data")
    if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0], dict) or "error" in data:
        raise UpstreamFailure("response_schema", **fields)
    if "error" in rows[0]:
        fields.update(error_identifiers(rows[0]))
        raise UpstreamFailure("response_schema", **fields)
    encoded = rows[0].get("b64_json")
    try: png_bytes(encoded)
    except RequestError:
        raise UpstreamFailure("response_image", **fields) from None
    return {"mime_type": "image/png", "base64": encoded}


def fetch_official_image(request, opener, recovery_store=None):
    """Injectable transport. No retries; retain bounded 2xx bodies before parsing."""
    fields, raw = {}, b""
    try:
        with opener.open(request, timeout=120) as response:
            fields = dict(response_metadata(response.headers), **error_identifiers(headers=response.headers), upstream_http_status=response.status)
            chunks, size = [], 0
            try:
                while size <= MAX_RESPONSE:
                    chunk = response.read(min(65536, MAX_RESPONSE + 1 - size))
                    if not chunk: break
                    chunks.append(chunk)
                    size += len(chunk)
            except http.client.IncompleteRead as error:
                chunks.append(error.partial[:max(0, MAX_RESPONSE + 1 - size)])
                fields["read_incomplete"] = True
            except Exception:
                # Preserve chunks received before a read/TLS/socket failure. Never
                # emit exception text or discard already received image bytes.
                fields["read_incomplete"] = True
            raw = b"".join(chunks)
            fields['wire_bytes'] = len(raw)
    except urllib.error.HTTPError as error:
        identifiers = error_identifiers(headers=error.headers)
        try:
            raw_error = error.read(MAX_ERROR_BODY + 1)
            if len(raw_error) <= MAX_ERROR_BODY:
                identifiers.update(error_identifiers(json.loads(raw_error), error.headers))
        except Exception: pass
        finally: error.close()
        raise UpstreamFailure("upstream_http", upstream_http_status=error.code, **identifiers) from None
    except Exception as error:
        details = classify_exception(error)
        category = details.pop("category")
        raise UpstreamFailure(category, **details) from None
    capture = {}
    if recovery_store is not None and 200 <= fields['upstream_http_status'] < 300:
        capture = recovery_store.save(raw, fields)
    try:
        output = parse_official_response(raw, fields)
    except UpstreamFailure as error:
        raise UpstreamFailure(error.diagnostic['category'], **{k: v for k, v in dict(error.diagnostic, **capture).items() if k != 'category'}) from None
    if recovery_store is not None:
        recovery_store.save_image(capture, png_bytes(output['base64']))
    return output


class RequestError(Exception):
    def __init__(self, status, code, diagnostic=None):
        self.status, self.code = status, code
        self.diagnostic = safe_diagnostic(diagnostic)
        super().__init__(code)


def png_bytes(encoded):
    if not isinstance(encoded, str) or len(encoded) > ((MAX_IMAGE + 2) // 3) * 4:
        raise RequestError(400, "invalid_image")
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        raise RequestError(400, "invalid_image") from None
    if not 33 <= len(raw) <= MAX_IMAGE or raw[:8] != b"\x89PNG\r\n\x1a\n" or raw[12:16] != b"IHDR":
        raise RequestError(400, "invalid_image")
    width, height = struct.unpack(">II", raw[16:24])
    if not (15 <= width <= 4096 and 15 <= height <= 4096 and width <= height * 16 and height <= width * 16):
        raise RequestError(400, "invalid_image")
    # Validate bounded chunk framing/CRC without decompressing untrusted pixels.
    offset, ended = 8, False
    while offset + 12 <= len(raw):
        size = struct.unpack(">I", raw[offset:offset + 4])[0]
        end = offset + 12 + size
        if end > len(raw):
            raise RequestError(400, "invalid_image")
        chunk = raw[offset + 4:offset + 8 + size]
        if zlib.crc32(chunk) & 0xFFFFFFFF != struct.unpack(">I", raw[offset + 8 + size:end])[0]:
            raise RequestError(400, "invalid_image")
        if chunk[:4] == b"IEND":
            ended = size == 0 and end == len(raw)
            break
        offset = end
    if not ended:
        raise RequestError(400, "invalid_image")
    return raw


def validate_request(data):
    if not isinstance(data, dict) or set(data) != {"schema_version", "request_id", "prompt", "image"} or type(data.get("schema_version")) is not int or data["schema_version"] != 1:
        raise RequestError(400, "invalid_request")
    request_id, prompt, image = data["request_id"], data["prompt"], data["image"]
    if not isinstance(request_id, str) or not 1 <= len(request_id) <= 64 or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for c in request_id):
        raise RequestError(400, "invalid_request_id")
    if not isinstance(prompt, str) or not prompt.strip() or len(prompt) > 32000:
        raise RequestError(400, "invalid_prompt")
    if not isinstance(image, dict) or set(image) != {"mime_type", "base64"} or image.get("mime_type") != "image/png":
        raise RequestError(400, "invalid_image")
    raw = png_bytes(image.get("base64"))
    fingerprint = hashlib.sha256(raw + b"\x00" + prompt.encode("utf-8")).hexdigest()
    return request_id, prompt, image, fingerprint


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Engine:
    def __init__(self, mode="stub", api_key=None, unit_price_fen=0, max_calls=None, delay=0.0, prior_reserved_fen=0, model_profile="flash"):
        if mode not in ("stub", "official") or (max_calls is not None and (type(max_calls) is not int or not 1 <= max_calls <= 16)) or not 0 <= delay <= 5 or type(prior_reserved_fen) is not int or not 0 <= prior_reserved_fen <= 1000:
            raise ValueError("Invalid service configuration")
        if not isinstance(model_profile, str) or model_profile not in MODEL_PROFILES:
            raise ValueError("Select a verified flash or pro model profile")
        self.model_profile = model_profile
        self.model_id = MODEL_PROFILES[model_profile]["model_id"]
        if mode == "official" and (not api_key or unit_price_fen != MODEL_PROFILES[model_profile]["unit_price_fen"]):
            raise ValueError("Official mode needs safe setup and the selected profile's confirmed price")
        self.mode, self._api_key = mode, api_key
        self.unit_price_fen, self.max_calls, self.delay = unit_price_fen, max_calls, delay
        self.session = secrets.token_urlsafe(32)  # Memory only; never printed or persisted.
        self.lock = threading.Lock()
        self.records, self.request_ids, self.operations = {}, {}, {}
        self.prior_reserved_fen = prior_reserved_fen
        self.calls, self.reserved_fen, self.cache_hits = 0, prior_reserved_fen, 0
        self.last_failure = {}
        self.recovery_store = RecoveryStore(announce=True)

    def audit(self):
        with self.lock:
            return {"protocol_revision": 2, "mode": self.mode, "model_profile": self.model_profile, "model_id": self.model_id, "source": "local_stub" if self.mode == "stub" else "volcengine_official",
                    "real_calls": self.calls if self.mode == "official" else 0,
                    "stub_calls": self.calls if self.mode == "stub" else 0,
                    "reserved_fen": self.reserved_fen, "unit_price_fen": self.unit_price_fen,
                    "prior_reserved_fen": self.prior_reserved_fen,
                    "session_reserved_fen": self.reserved_fen - self.prior_reserved_fen,
                    "max_calls": self.max_calls, "cache_hits": self.cache_hits,
                    "inflight": any(r["state"] == "inflight" for r in self.records.values()),
                    "last_failure": dict(self.last_failure), "last_response": safe_diagnostic(self.recovery_store.last_capture)}

    def list_operations(self):
        with self.lock:
            return [{"request_id": name, "state": operation["state"],
                     "retry_of": operation.get("retry_of"),
                     "diagnostic": safe_diagnostic(operation.get("diagnostic"))}
                    for name, operation in self.operations.items()]

    def result(self, request_id):
        with self.lock:
            operation = self.operations.get(request_id)
            if operation is None: raise RequestError(404, "result_not_available")
            if operation["state"] != "done":
                raise RequestError(409, "in_progress" if operation["state"] == "inflight" else "outcome_unknown", operation.get("diagnostic"))
            return operation["body"]

    def retry(self, data):
        if not isinstance(data, dict) or set(data) != {"request_id", "retry_request_id", "confirm_new_charge"} or data["confirm_new_charge"] is not True:
            raise RequestError(400, "explicit_retry_confirmation_required")
        previous, replacement = data["request_id"], data["retry_request_id"]
        if not isinstance(previous, str) or not isinstance(replacement, str) or previous == replacement:
            raise RequestError(400, "invalid_request_id")
        with self.lock:
            old = self.operations.get(previous)
            if old is None or old["state"] != "unknown": raise RequestError(409, "retry_not_available")
            payload = dict(old["data"], request_id=replacement)
        return self.generate(payload, _retry_of=previous)

    def generate(self, data, _retry_of=None):
        request_id, prompt, image, fingerprint = validate_request(data)
        with self.lock:
            if request_id in self.request_ids:
                if self.request_ids[request_id] != fingerprint: raise RequestError(409, "request_id_conflict")
                operation = self.operations[request_id]
                if operation["state"] == "done":
                    self.cache_hits += 1
                    return operation["body"]
                raise RequestError(409, "in_progress" if operation["state"] == "inflight" else "outcome_unknown", operation.get("diagnostic"))
            previous = self.operations.get(_retry_of) if _retry_of is not None else None
            if _retry_of is not None and (previous is None or previous["state"] != "unknown" or previous["fingerprint"] != fingerprint):
                raise RequestError(409, "retry_not_available")
            old = self.records.get(fingerprint)
            if old:
                if old["state"] == "done":
                    self.cache_hits += 1
                    return old["body"]
                if old["state"] == "inflight" or previous is None:
                    raise RequestError(409, "in_progress" if old["state"] == "inflight" else "outcome_unknown", old.get("diagnostic"))
            if any(r["state"] == "inflight" for r in self.records.values()): raise RequestError(409, "busy")
            if (self.max_calls is not None and self.calls >= self.max_calls) or (self.mode == "official" and self.reserved_fen + self.unit_price_fen > 1000):
                raise RequestError(429, "session_limit")
            self.calls += 1
            self.request_ids[request_id] = fingerprint
            self.reserved_fen += self.unit_price_fen if self.mode == "official" else 0
            operation = {"state": "inflight", "fingerprint": fingerprint,
                         "data": {"schema_version": 1, "request_id": request_id, "prompt": prompt, "image": dict(image)}, "retry_of": _retry_of}
            self.records[fingerprint] = self.operations[request_id] = operation
        try:
            if self.delay: time.sleep(self.delay)
            output = image if self.mode == "stub" else self._official(prompt, image)
            body = {"schema_version": 1, "mode": self.mode,
                    "source": "local_stub" if self.mode == "stub" else "volcengine_official", "image": output}
            with self.lock:
                operation.update(state="done", body=body)
            return body
        except Exception as error:
            diagnostic = safe_diagnostic(error.diagnostic if isinstance(error, UpstreamFailure) else classify_exception(error))
            with self.lock:
                operation.update(state="unknown", diagnostic=diagnostic)
                self.last_failure = diagnostic
            raise RequestError(502, "upstream_outcome_unknown", diagnostic) from None

    def _official(self, prompt, image):
        payload = {"model": self.model_id, "prompt": prompt, "image": "data:image/png;base64," + image["base64"],
                   "size": "2K", "output_format": "png", "response_format": "b64_json",
                   "layer_decomposition": False, "optimize_prompt_options": {"mode": "standard"}, "watermark": True}
        request = urllib.request.Request(OFFICIAL_URL, json.dumps(payload).encode("utf-8"),
                                         {"Content-Type": "application/json", "Accept": "application/json", "Accept-Encoding": "identity", "Authorization": "Bearer " + self._api_key})
        # Ignore ambient proxy configuration; no third-party redirect, SDK retry or fallback.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        return fetch_official_image(request, opener, self.recovery_store)

    def close(self):
        self._api_key = None
        self.session = ""
        self.records.clear()
        self.request_ids.clear()
        self.operations.clear()


class LocalServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False
    request_queue_size = 8

    def __init__(self, port, engine):
        self.engine = engine
        super().__init__(("127.0.0.1", port), Handler)

    def handle_error(self, request, client_address):
        pass  # Never dump requests, headers, keys or exceptions to logs.


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *_args):
        pass

    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def _guard(self, authenticated=True):
        if self.client_address[0] != "127.0.0.1" or self.headers.get("Host") != "127.0.0.1:%d" % self.server.server_port:
            raise RequestError(403, "loopback_only")
        if self.headers.get("Origin") is not None or self.headers.get("Referer") is not None or self.headers.get("X-Image-Client") != CLIENT_HEADER:
            raise RequestError(403, "native_client_required")
        incoming = self.headers.get("X-Local-Session", "")
        if authenticated and (not incoming.isascii() or not hmac.compare_digest(incoming, self.server.engine.session)):
            raise RequestError(401, "session_required")

    def _send(self, status, body):
        raw = json.dumps(body, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        try:
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass  # Local cancellation does not imply remote cancellation/refund.

    def _error(self, error):
        # Drain small rejected bodies before closing, avoiding a Windows TCP reset
        # racing the structured error response. Never parse or log discarded data.
        length = self.headers.get("Content-Length", "")
        if not getattr(self, "_body_consumed", False) and length.isascii() and length.isdigit() and len(length) <= 5 and int(length) <= 65536:
            try:
                self.rfile.read(int(length))
            except OSError:
                pass
        details = {"code": error.code, "message": "Local image request did not complete.", "automatic_retry": False,
                   "outcome_unknown": error.code in {"upstream_outcome_unknown", "outcome_unknown", "in_progress"}}
        if error.diagnostic: details["diagnostic"] = error.diagnostic
        self._send(error.status, {"schema_version": 1, "error": details})

    def do_GET(self):
        try:
            if self.path == "/v1/session":
                self._guard(False)
                self._send(200, {"schema_version": 1, "mode": self.server.engine.mode, "session": self.server.engine.session})
            elif self.path == "/v1/status":
                self._guard()
                self._send(200, self.server.engine.audit())
            elif self.path == "/v1/operations":
                self._guard()
                self._send(200, {"operations": self.server.engine.list_operations()})
            elif self.path.startswith("/v1/results/"):
                self._guard()
                self._send(200, self.server.engine.result(self.path[len("/v1/results/"):]))
            else:
                raise RequestError(404, "not_found")
        except RequestError as error:
            self._error(error)

    def do_POST(self):
        try:
            self._guard()
            if self.path not in {"/v1/images/generate", "/v1/images/retry"}:
                raise RequestError(404, "not_found")
            if self.headers.get("Content-Type") != "application/json" or self.headers.get("Transfer-Encoding") is not None:
                raise RequestError(415, "json_required")
            length_text = self.headers.get("Content-Length", "")
            if not length_text.isascii() or not length_text.isdigit() or not 1 <= len(length_text) <= 9:
                raise RequestError(411, "length_required")
            length = int(length_text)
            if not 1 <= length <= MAX_BODY:
                raise RequestError(413, "body_too_large")
            raw = self.rfile.read(length)
            self._body_consumed = True
            if len(raw) != length:
                raise RequestError(400, "incomplete_body")
            try:
                data = json.loads(raw.decode("utf-8"))
            except (ValueError, UnicodeError, RecursionError):
                raise RequestError(400, "invalid_json") from None
            self._send(200, self.server.engine.retry(data) if self.path == "/v1/images/retry" else self.server.engine.generate(data))
        except RequestError as error:
            self._error(error)
        except (OSError, socket.timeout):
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8769)
    parser.add_argument("--mode", choices=("stub", "official"), default="stub")
    parser.add_argument("--stub-delay", type=float, default=0.0)
    parser.add_argument("--max-calls", type=int, default=0, help="0: no per-start call cap; still one inflight request and bounded budget")
    parser.add_argument("--model-profile", choices=tuple(MODEL_PROFILES), default="flash")
    parser.add_argument("--confirmed-price-fen", type=int, default=0)
    parser.add_argument("--prior-reserved-fen", type=int, default=0)
    parser.add_argument("--confirm-account-and-upload", action="store_true")
    args = parser.parse_args()
    if not 0 <= args.port <= 65535 or not 0 <= args.max_calls <= 16 or not 0 <= args.stub_delay <= 5 or not 0 <= args.prior_reserved_fen <= 1000:
        parser.error("Port, request cap or stub delay is out of range")
    key = None
    if args.mode == "official":
        expected_price = MODEL_PROFILES[args.model_profile]["unit_price_fen"]
        if not args.confirm_account_and_upload or args.confirmed_price_fen != expected_price or args.stub_delay:
            parser.error("Confirm account, upload permission and selected profile price before official mode")
        if args.prior_reserved_fen + expected_price > 1000:
            parser.error("Previous reservation leaves insufficient budget; no credential requested")
        if not sys.stdin.isatty():
            parser.error("Official credential setup requires an interactive terminal, never redirected input")
        key = getpass.getpass("Ark API key (memory only, input hidden): ")
        if not key.strip() or "\r" in key or "\n" in key:
            parser.error("No usable credential supplied")
    engine = Engine(args.mode, key, args.confirmed_price_fen, args.max_calls or None, args.stub_delay, args.prior_reserved_fen, args.model_profile)
    key = None
    server = LocalServer(args.port, engine)
    print(json.dumps({"event": "ready", "host": "127.0.0.1", "port": server.server_port, "mode": engine.mode,
                      "real_calls": 0, "model_profile": engine.model_profile, "model_id": engine.model_id,
                      "unit_price_fen": engine.unit_price_fen, "prior_reserved_fen": engine.prior_reserved_fen,
                      "reserved_fen": engine.reserved_fen, "max_calls": engine.max_calls}), flush=True)
    try:
        server.serve_forever(poll_interval=0.1)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        engine.close()


if __name__ == "__main__":
    main()
