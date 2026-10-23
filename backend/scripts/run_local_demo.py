"""Local synthetic feature demo; never loads workstation credentials or a database."""

import os
from pathlib import Path
import sys
import dotenv

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
sys.path.insert(0, str(ROOT))
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
):
    os.environ.pop(key, None)
os.environ.update(
    APP_ENV="development",
    FLASK_ENV="development",
    DEMO_MODE="true",
    DEMO_IN_MEMORY="true",
    CORS_ALLOWED_ORIGINS="http://localhost:3001,http://127.0.0.1:3001",
)
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
    app.run(host="127.0.0.1", port=8000, use_reloader=False)
