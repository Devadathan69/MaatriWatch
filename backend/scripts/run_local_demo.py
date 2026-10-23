"""Isolated synthetic demo, with explicitly optional server-side OpenAI access."""

import argparse
import json
import os
from pathlib import Path
import sys
import dotenv

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
sys.path.insert(0, str(ROOT))
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    '--with-openai', action='store_true',
    help='Enable real OpenAI requests using only OpenAI settings from backend/.env or the environment.',
)
parser.add_argument('--check-config', action='store_true', help='Print credential-free configuration status and exit.')
args = parser.parse_args()
ai_names = ('OPENAI_API_KEY', 'OPENAI_CHAT_MODEL', 'OPENAI_TRANSCRIBE_MODEL',
            'OPENAI_CHAT_TIMEOUT_SECONDS', 'OPENAI_CHAT_MAX_REQUESTS', 'OPENAI_CHAT_WINDOW_SECONDS')
ai_settings = {}
if args.with_openai:
    local_values = dotenv.dotenv_values(ROOT / '.env')
    ai_settings = {name: os.environ.get(name) or local_values.get(name) for name in ai_names}
    ai_settings = {name: value for name, value in ai_settings.items() if value}
    key = ai_settings.get('OPENAI_API_KEY', '').strip()
    if not key or any(value in key.lower() for value in ('your-key', 'replace-with', 'placeholder', 'change-me')):
        parser.error('--with-openai requires a configured OPENAI_API_KEY in backend/.env or the environment')

# Never load database, Firebase, Twilio, or video credentials in either mode.
# Read only the allowlisted OpenAI settings, and only after the explicit flag.
dotenv.load_dotenv = lambda *a, **k: False
for key in (
    "DATABASE_URL",
    "FIREBASE_PROJECT_ID",
    "FIREBASE_DATABASE_URL",
    "FIREBASE_SERVICE_ACCOUNT_JSON",
    "OPENAI_API_KEY",
    "TWILIO_ACCOUNT_SID",
    "TWILIO_AUTH_TOKEN",
    "DAILY_API_KEY",
) + ai_names:
    os.environ.pop(key, None)
os.environ.update(
    APP_ENV="development",
    FLASK_ENV="development",
    DEMO_MODE="true",
    DEMO_IN_MEMORY="true",
    CORS_ALLOWED_ORIGINS="http://localhost:3001,http://127.0.0.1:3001",
)
os.environ.update(ai_settings)
if args.check_config:
    print(json.dumps({
        'synthetic_demo': True,
        'openai_enabled': bool(os.environ.get('OPENAI_API_KEY')),
        'database_enabled': bool(os.environ.get('DATABASE_URL')),
        'firebase_enabled': bool(os.environ.get('FIREBASE_SERVICE_ACCOUNT_JSON') or os.environ.get('FIREBASE_PROJECT_ID')),
        'video_enabled': bool(os.environ.get('DAILY_API_KEY')),
        'whatsapp_enabled': bool(os.environ.get('TWILIO_AUTH_TOKEN')),
    }))
    raise SystemExit(0)

from app import create_app
from app.demo_store import DEMO_HOSPITAL_ID
from datetime import datetime, timedelta, timezone

app = create_app()
client = app.test_client()
headers = {"X-Demo-Role": "patient"}
report = client.post(
    "/api/v1/patient/reports/analyses",
    headers=headers,
    json={
        "title": "DEMO • synthetic report",
        "confirmed": True,
        "context": {
            "stage": "pregnant",
            "trimester": 2,
            "protocol": "75g_ogtt_fasting",
        },
        "readings": [
            {
                "analyte": "ogtt_fasting",
                "name": "Fasting glucose (synthetic)",
                "value": 95,
                "unit": "mg/dL",
            }
        ],
    },
).json["report"]
client.put(
    "/api/v1/patient/nutrition",
    headers=headers,
    json={
        "diet": "vegetarian",
        "allergens": [],
        "dislikes": [],
        "allergies_confirmed": True,
    },
)
client.post(
    "/api/v1/patient/nutrition", headers=headers, json={"report_id": report["id"]}
)
client.post(
    "/api/v1/patient/concerns",
    headers=headers,
    json={
        "original_text": "A mild headache yesterday afternoon (synthetic example).",
        "language": "en",
        "confirmed": True,
        "share_with_care_team": True,
        "symptoms": [
            {
                "symptom_key": "headache",
                "name": "Headache",
                "severity": "mild",
                "onset": "yesterday afternoon",
                "frequency": "once",
                "details": "Synthetic presentation entry",
                "source_quote": "headache",
            }
        ],
    },
)
for offset in (30, 120):
    start = datetime.now(timezone.utc) + timedelta(minutes=offset)
    slot = client.post(
        f"/api/v1/hospitals/{DEMO_HOSPITAL_ID}/consultation-slots",
        headers={"X-Demo-Role": "doctor"},
        json={
            "start_at": start.isoformat(),
            "end_at": (start + timedelta(minutes=30)).isoformat(),
        },
    ).json["slot"]
    if offset == 30:
        client.post(
            "/api/v1/patient/consultations",
            headers=headers,
            json={"slot_id": slot["id"], "reason": "DEMO • monthly follow-up"},
        )
if __name__ == "__main__":
    print('Synthetic demo: live OpenAI ' + ('enabled; requests use the configured API account.' if args.with_openai else 'disabled.'))
    app.run(host="127.0.0.1", port=8000, use_reloader=False)
