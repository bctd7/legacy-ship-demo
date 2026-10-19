"""Injectable desktop controller. Startup never submits an image generation."""
import base64
import ctypes
from ctypes import wintypes
import http.client
import json
import os
from pathlib import Path
import re
import secrets
import threading

from private_config import PrivateConfig
from recovery import RecoveryStore
from server import CLIENT_HEADER, Engine, LocalServer, MAX_RESPONSE, RequestError, png_bytes, safe_diagnostic


class LauncherError(Exception): pass


class LocalClient:
    def __init__(self, port=8769): self.port, self.session = port, None

    def request(self, method, path, data=None, timeout=3, handshake=False):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=timeout)
        headers = {'X-Image-Client': CLIENT_HEADER}
        if not handshake: headers['X-Local-Session'] = self.session or ''
        raw = json.dumps(data).encode() if data is not None else None
        if raw is not None: headers['Content-Type'] = 'application/json'
        try:
            connection.request(method, path, raw, headers)
            response = connection.getresponse()
            body = response.read(MAX_RESPONSE + 1)
            if len(body) > MAX_RESPONSE: raise LauncherError('local_response_too_large')
            return response.status, json.loads(body)
        finally:
            headers.clear()
            connection.close()

    def connect(self):
        status, data = self.request('GET', '/v1/session', handshake=True)
        if status != 200 or data.get('mode') != 'official' or not isinstance(data.get('session'), str):
            raise LauncherError('existing_service_incompatible')
        self.session = data['session']
        status, audit = self.request('GET', '/v1/status')
        if status != 200 or audit.get('protocol_revision') != 2 or audit.get('model_profile') != 'flash' or audit.get('max_calls') is not None:
            self.session = None
            raise LauncherError('existing_service_incompatible')
        return audit


class Controller:
    def __init__(self, directory, config=None, port=8769, client=None, engine_factory=Engine, server_factory=LocalServer):
        self.directory = Path(directory)
        self.config = config if config is not None else PrivateConfig(self.directory / 'api_key.local.json')
        self.port, self.client = port, client if client is not None else LocalClient(port)
        self.engine_factory, self.server_factory = engine_factory, server_factory
        self.engine, self.server, self.thread = None, None, None

    def start(self):
        if self.server is not None: return self.engine.audit()
        try: return self.client.connect()  # Reuse a compatible service before touching the vault.
        except ConnectionRefusedError: pass
        except (LauncherError, OSError, ValueError): raise LauncherError('existing_service_incompatible') from None
        secret = self.config.read_key()
        try:
            engine = self.engine_factory(mode='official', api_key=secret, unit_price_fen=12, max_calls=None, model_profile='flash')
        finally: secret = None
        engine.recovery_store = RecoveryStore(self.directory / 'results', announce=False)
        try: local_server = self.server_factory(self.port, engine)
        except OSError:
            engine.close()
            raise LauncherError('port_in_use') from None
        self.engine, self.server = engine, local_server
        self.thread = threading.Thread(target=local_server.serve_forever, kwargs={'poll_interval': 0.1}, daemon=True)
        self.thread.start()
        self.client.port = local_server.server_port
        self.client.session = engine.session
        return engine.audit()

    def status(self):
        status, data = self.client.request('GET', '/v1/status')
        if status != 200: raise LauncherError('local_service_unavailable')
        return data

    def operations(self):
        status, data = self.client.request('GET', '/v1/operations')
        if status != 200 or not isinstance(data.get('operations'), list): raise LauncherError('local_service_unavailable')
        return data['operations']

    def retry(self, operation_id, confirmed=False):
        if confirmed is not True: raise LauncherError('explicit_retry_confirmation_required')
        # Called only by the dedicated user retry button. A fresh retry operation
        # ID deduplicates double delivery; server still enforces one inflight job.
        return self.client.request('POST', '/v1/images/retry', {'request_id': operation_id,
            'retry_request_id': 'manual-' + secrets.token_hex(16), 'confirm_new_charge': True}, timeout=150)

    def save_result(self, operation_id):
        if not isinstance(operation_id, str) or not re.fullmatch('[A-Za-z0-9_-]{1,64}', operation_id): raise LauncherError('invalid_operation')
        status, data = self.client.request('GET', '/v1/results/' + operation_id)
        if status != 200: raise LauncherError('result_not_available')
        image = png_bytes(data.get('image', {}).get('base64'))
        folder = self.directory / 'viewed_results'
        folder.mkdir(mode=0o700, parents=True, exist_ok=True)
        output = folder / (operation_id + '.png')
        if output.is_symlink(): raise LauncherError('invalid_operation')
        if output.exists() and output.read_bytes() != image: raise LauncherError('result_conflict')
        if not output.exists(): output.write_bytes(image)
        return output

    def stop(self):
        if self.server is None: return
        if self.engine.audit()['inflight']: raise LauncherError('request_in_progress')
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.engine.close()
        self.server, self.engine, self.thread = None, None, None
        self.client.session = None


class SingleInstance:
    NAME = 'Local\\AncientJoinery.ImageGeneration.Desktop.v1'
    def __init__(self, api=None):
        self.api = api if api is not None else ctypes.WinDLL('kernel32', use_last_error=True)
        self.api.CreateMutexW.argtypes = [ctypes.c_void_p, wintypes.BOOL, wintypes.LPCWSTR]
        self.api.CreateMutexW.restype = wintypes.HANDLE
        self.api.CloseHandle.argtypes = [wintypes.HANDLE]
        self.api.CloseHandle.restype = wintypes.BOOL
        self.handle = None

    def acquire(self):
        self.handle = self.api.CreateMutexW(None, False, self.NAME)
        if not self.handle: raise LauncherError('launcher_lock_failed')
        if ctypes.get_last_error() == 183:
            self.close()
            return False
        return True

    def close(self):
        if self.handle:
            self.api.CloseHandle(self.handle)
            self.handle = None
