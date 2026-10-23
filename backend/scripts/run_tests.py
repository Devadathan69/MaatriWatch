"""Credential-isolated unit/API tests. Run from backend: python scripts/run_tests.py."""
import logging
import os
from pathlib import Path
import sys
import unittest
import dotenv

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
sys.path.insert(0, str(ROOT))
dotenv.load_dotenv = lambda *args, **kwargs: False
for key in ('DATABASE_URL', 'FIREBASE_PROJECT_ID', 'FIREBASE_DATABASE_URL', 'FIREBASE_SERVICE_ACCOUNT_JSON',
            'OPENAI_API_KEY', 'TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'DAILY_API_KEY'):
    os.environ.pop(key, None)
os.environ.update(APP_ENV='development', FLASK_ENV='development', DEMO_MODE='false', DEMO_IN_MEMORY='false', ALLOW_UNVERIFIED_PATIENT_DEMO='false')
logging.disable(logging.WARNING)
result = unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.discover('tests'))
raise SystemExit(not result.wasSuccessful())
