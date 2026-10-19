"""Private bounded 2xx-body retention and offline-only image recovery. No network."""
import json
import os
from pathlib import Path
import re
import secrets
import tempfile

from response_codec import MAX_RESPONSE, safe_response_fields


class RecoveryStore:
    def __init__(self, directory=None, announce=False):
        self.directory = Path(directory) if directory is not None else None
        self.announce = announce
        self.last_capture = {}

    def save(self, raw, metadata):
        if not isinstance(raw, bytes) or len(raw) > MAX_RESPONSE: return {'recovery_saved': False}
        capture_id = secrets.token_hex(16)
        try:
            if self.directory is None:
                self.directory = Path(tempfile.mkdtemp(prefix='image-generation-recovery-'))
            self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
            folder = self.directory / capture_id
            folder.mkdir(mode=0o700)
            # Only the response body and whitelisted response metadata. No request,
            # headers, input image, prompt, API key, session or raw exception.
            _write(folder / 'response.bin', raw)
            _write(folder / 'metadata.json', json.dumps(safe_response_fields(metadata), indent=2).encode())
            self.last_capture = {'recovery_saved': True, 'recovery_id': capture_id}
            if self.announce:
                print(json.dumps({'event': 'response_retained', 'recovery_directory': str(self.directory), 'recovery_id': capture_id}), flush=True)
            return dict(self.last_capture)
        except OSError:
            self.last_capture = {'recovery_saved': False}
            return dict(self.last_capture)

    def save_image(self, capture, image):
        if self.directory is None or not capture.get('recovery_saved'): return
        try: _write(self.directory / capture['recovery_id'] / 'image.png', image)
        except OSError: pass  # The already-retained response remains recoverable.


def _write(path, raw):
    # Exclusive, bounded writes into a random operator-owned directory. On Windows
    # inherited account ACLs apply; chmod does not promise a new Windows ACL.
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, 'wb') as stream: stream.write(raw)


def recover(directory, capture_id):
    from response_codec import decode_document
    from server import png_bytes, safe_diagnostic
    if not isinstance(capture_id, str) or not re.fullmatch('[0-9a-f]{32}', capture_id): raise ValueError('invalid_recovery_id')
    root = Path(directory).resolve(strict=True)
    folder = (root / capture_id).resolve(strict=True)
    if folder.parent != root: raise ValueError('invalid_recovery_path')
    body = folder / 'response.bin'
    metadata = folder / 'metadata.json'
    if body.is_symlink() or metadata.is_symlink() or body.stat().st_size > MAX_RESPONSE or metadata.stat().st_size > 8192:
        raise ValueError('invalid_recovery_file')
    raw = body.read_bytes()
    data, info = decode_document(raw, safe_diagnostic(json.loads(metadata.read_text(encoding='utf-8'))))
    if not isinstance(data, dict) or 'error' in data or not isinstance(data.get('data'), list) or len(data['data']) != 1 or not isinstance(data['data'][0], dict) or 'error' in data['data'][0]:
        raise ValueError('response_schema')
    image = png_bytes(data['data'][0].get('b64_json'))
    output = folder / 'image.png'
    if output.is_symlink(): raise ValueError('invalid_recovery_file')
    if output.exists():
        if output.stat().st_size > 8 * 1024 * 1024 or output.read_bytes() != image: raise ValueError('recovery_output_conflict')
    else: _write(output, image)
    return output, info


def main():
    import argparse
    from response_codec import DecodeFailure
    parser = argparse.ArgumentParser(description='Decode one retained response locally; never contacts an API or reads credentials.')
    parser.add_argument('--directory', required=True)
    parser.add_argument('--capture-id', required=True)
    args = parser.parse_args()
    try:
        output, _ = recover(args.directory, args.capture_id)
        print(json.dumps({'recovered': True, 'output_file': str(output), 'new_generation_requests': 0}))
    except (OSError, ValueError, DecodeFailure) as error:
        diagnostic = error.info if isinstance(error, DecodeFailure) else {}
        print(json.dumps({'recovered': False, 'diagnostic': diagnostic, 'new_generation_requests': 0}))
        return 1
    return 0


if __name__ == '__main__': raise SystemExit(main())
