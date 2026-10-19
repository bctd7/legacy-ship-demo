"""Bounded response decoding. Diagnostics describe structure, never body text."""
import codecs
import json
import re
import zlib
from email.message import Message

MAX_RESPONSE = 24 * 1024 * 1024
ENUMS = {
    'response_content_type': {'application/json', 'text/event-stream', 'text/html', 'text/plain', 'image/png', 'application/octet-stream', 'missing', 'other'},
    'response_content_encoding': {'identity', 'gzip', 'deflate', 'br', 'other'},
    'response_charset': {'unspecified', 'utf-8', 'utf-16', 'utf-32', 'other'},
    'response_bom': {'none', 'utf-8', 'utf-16-le', 'utf-16-be', 'utf-32-le', 'utf-32-be'},
    'response_body_kind': {'empty', 'json_candidate', 'sse', 'html', 'png', 'binary', 'other'},
    'parse_failure': {'syntax', 'extra_data', 'unicode', 'depth', 'compression', 'unsupported_encoding', 'unsupported_charset', 'length_mismatch', 'incomplete_read', 'unexpected_sse', 'unexpected_html', 'empty'},
}
NUMBERS = {'wire_bytes', 'decoded_bytes', 'declared_bytes', 'parse_position', 'parse_line', 'parse_column'}
BOOLEANS = {'read_incomplete', 'recovery_saved'}
CATEGORIES = {'response_encoding', 'response_charset', 'response_compression', 'response_truncated', 'response_stream', 'response_content_type', 'response_empty'}


def safe_response_fields(data):
    if not isinstance(data, dict): return {}
    out = {}
    for key, choices in ENUMS.items():
        value = data.get(key)
        if isinstance(value, str) and value in choices: out[key] = value
    for key in NUMBERS:
        value = data.get(key)
        if type(value) is int and 0 <= value <= 2**40: out[key] = value
    for key in BOOLEANS:
        if type(data.get(key)) is bool: out[key] = data[key]
    if isinstance(data.get('recovery_id'), str) and re.fullmatch('[0-9a-f]{32}', data['recovery_id']):
        out['recovery_id'] = data['recovery_id']
    return out


def response_metadata(headers):
    # Select only framing/type metadata. Never enumerate headers, copy values,
    # or inspect Authorization, cookies, credentials, URLs or arbitrary messages.
    content_type = headers.get('Content-Type', '')
    encoding = headers.get('Content-Encoding', '')
    length = headers.get('Content-Length', '')
    content_type = content_type if isinstance(content_type, str) and len(content_type) <= 256 else ''
    message = Message()
    message['Content-Type'] = content_type
    media = content_type.partition(';')[0].strip().lower() or 'missing'
    if media.endswith('+json') and re.fullmatch(r'application/[a-z0-9.+-]+', media): media = 'application/json'
    charset = message.get_content_charset() or 'unspecified'
    charset = {'utf8': 'utf-8', 'utf16': 'utf-16', 'utf32': 'utf-32'}.get(charset, charset)
    encoding = encoding.strip().lower() if isinstance(encoding, str) else 'other'
    info = {'response_content_type': media if media in ENUMS['response_content_type'] else 'other',
            'response_content_encoding': encoding if encoding in ENUMS['response_content_encoding'] else 'identity' if not encoding else 'other',
            'response_charset': charset if charset in ENUMS['response_charset'] else 'other'}
    if isinstance(length, str) and len(length) <= 13 and re.fullmatch('[0-9]+', length) and int(length) <= 2**40:
        info['declared_bytes'] = int(length)
    return info


class DecodeFailure(Exception):
    def __init__(self, category, info):
        self.category, self.info = category, safe_response_fields(info)
        super().__init__(category)


def fail(category, info, reason=None):
    if reason: info['parse_failure'] = reason
    raise DecodeFailure(category, info) from None


def _inflate(raw, window, limit, info):
    try:
        decoder = zlib.decompressobj(window)
        decoded = decoder.decompress(raw, limit + 1)
        if len(decoded) > limit or decoder.unconsumed_tail:
            fail('response_too_large', info)
        if not decoder.eof or decoder.unused_data:
            fail('response_compression', info, 'compression')
        return decoded
    except zlib.error:
        fail('response_compression', info, 'compression')


def decode_document(raw, metadata, limit=MAX_RESPONSE):
    info = safe_response_fields(metadata)
    info['wire_bytes'] = len(raw)
    if len(raw) > limit: fail('response_too_large', info)
    if info.get('read_incomplete'): fail('response_truncated', info, 'incomplete_read')
    if 'declared_bytes' in info and info['declared_bytes'] != len(raw):
        fail('response_truncated', info, 'length_mismatch')
    encoding = info.get('response_content_encoding', 'identity')
    if encoding == 'gzip': raw = _inflate(raw, zlib.MAX_WBITS | 16, limit, info)
    elif encoding == 'deflate':
        # Both zlib-wrapped and legacy raw DEFLATE occur in HTTP implementations.
        try: raw = _inflate(raw, zlib.MAX_WBITS, limit, info)
        except DecodeFailure as error:
            if error.category != 'response_compression': raise
            raw = _inflate(raw, -zlib.MAX_WBITS, limit, info)
    elif encoding != 'identity': fail('response_encoding', info, 'unsupported_encoding')
    info['decoded_bytes'] = len(raw)
    if not raw: info['response_body_kind'] = 'empty'; fail('response_empty', info, 'empty')
    bom, codec = 'none', 'utf-8-sig'
    for marker, name, decoder in [(codecs.BOM_UTF32_LE, 'utf-32-le', 'utf-32'), (codecs.BOM_UTF32_BE, 'utf-32-be', 'utf-32'),
                                   (codecs.BOM_UTF8, 'utf-8', 'utf-8-sig'), (codecs.BOM_UTF16_LE, 'utf-16-le', 'utf-16'), (codecs.BOM_UTF16_BE, 'utf-16-be', 'utf-16')]:
        if raw.startswith(marker): bom, codec = name, decoder; break
    info['response_bom'] = bom
    stripped = raw.lstrip()
    info['response_body_kind'] = 'png' if raw.startswith(b'\x89PNG\r\n\x1a\n') else 'binary' if b'\x00' in stripped[:128] and bom == 'none' else 'other'
    if info.get('response_charset') == 'other': fail('response_charset', info, 'unsupported_charset')
    if bom == 'none' and info.get('response_charset') in {'utf-16', 'utf-32'}:
        fail('response_charset', info, 'unsupported_charset')
    try: text = raw.decode(codec)
    except UnicodeError: fail('response_json', info, 'unicode')
    start = text.lstrip()
    if start.startswith(('{', '[')): info['response_body_kind'] = 'json_candidate'
    elif start.lower().startswith(('<!doctype html', '<html', '<head', '<body')): info['response_body_kind'] = 'html'
    elif start.startswith(('data:', 'event:', ':')): info['response_body_kind'] = 'sse'
    if info.get('response_content_type') == 'text/event-stream' or info['response_body_kind'] == 'sse':
        fail('response_stream', info, 'unexpected_sse')
    if info.get('response_content_type') == 'text/html' or info['response_body_kind'] == 'html':
        fail('response_content_type', info, 'unexpected_html')
    try: data = json.loads(text)
    except json.JSONDecodeError as error:
        info.update(parse_position=error.pos, parse_line=error.lineno, parse_column=error.colno)
        fail('response_json', info, 'extra_data' if error.msg == 'Extra data' else 'syntax')
    except RecursionError: fail('response_json', info, 'depth')
    return data, info
