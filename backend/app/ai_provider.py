"""Small server-only OpenAI transport. Never logs prompts, responses, or keys."""
import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from flask import abort, current_app


def output_text(result):
    return '\n'.join(part.get('text', '') for item in result.get('output', [])
                     if item.get('type') == 'message' for part in item.get('content', [])
                     if part.get('type') == 'output_text').strip()


def response(instructions, inputs, *, schema=None, max_tokens=1200):
    config = current_app.config
    key = config.get('OPENAI_API_KEY')
    if not key:
        abort(503, description='AI is not configured. Your saved information is still available.')
    body = {'model': config['OPENAI_CHAT_MODEL'], 'instructions': instructions,
            'input': inputs, 'max_output_tokens': max_tokens, 'store': False}
    if schema:
        body['text'] = {'format': {'type': 'json_schema', 'name': 'care_result', 'strict': True, 'schema': schema}}
    req = Request('https://api.openai.com/v1/responses', data=json.dumps(body).encode(),
                  headers={'Authorization': f'Bearer {key}', 'Content-Type': 'application/json'}, method='POST')
    try:
        with urlopen(req, timeout=config['OPENAI_CHAT_TIMEOUT_SECONDS']) as result:
            value = json.load(result)
        if value.get('status') not in (None, 'completed'):
            abort(502, description='AI did not finish. Please try again; nothing has been confirmed.')
        text = output_text(value)
        if not text:
            abort(502, description='AI could not prepare this response. Please contact your care team.')
        return json.loads(text) if schema else text[:6000]
    except (HTTPError, URLError, TimeoutError, ValueError, TypeError):
        abort(503, description='AI is temporarily unavailable. Please try again or contact your care team.')


def object_schema(properties):
    return {'type': 'object', 'properties': properties, 'required': list(properties), 'additionalProperties': False}
