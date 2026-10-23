"""The demo must never inherit production services, including after AI opt-in."""
import json
import os
from pathlib import Path
import subprocess
import sys
import unittest


class LocalDemoIsolationTest(unittest.TestCase):
    def configuration(self, *flags):
        environment = {
            **os.environ,
            'OPENAI_API_KEY': 'synthetic-test-value-never-send',
            'DATABASE_URL': 'synthetic-database-secret',
            'FIREBASE_PROJECT_ID': 'synthetic-firebase-project',
            'FIREBASE_SERVICE_ACCOUNT_JSON': 'synthetic-admin-secret',
            'DAILY_API_KEY': 'synthetic-video-secret',
            'TWILIO_AUTH_TOKEN': 'synthetic-whatsapp-secret',
            'APP_ENV': 'production',
        }
        script = Path(__file__).resolve().parents[1] / 'scripts' / 'run_local_demo.py'
        result = subprocess.run(
            [sys.executable, str(script), '--check-config', *flags],
            env=environment, capture_output=True, text=True, timeout=15, check=True,
        )
        self.assertNotIn('synthetic-test-value', result.stdout + result.stderr)
        self.assertNotIn('synthetic-admin-secret', result.stdout + result.stderr)
        return json.loads(result.stdout)

    def test_default_demo_disables_all_provider_credentials(self):
        result = self.configuration()
        self.assertTrue(result.pop('synthetic_demo'))
        self.assertFalse(any(result.values()))

    def test_explicit_openai_opt_in_keeps_other_services_isolated(self):
        result = self.configuration('--with-openai')
        self.assertTrue(result.pop('synthetic_demo'))
        self.assertTrue(result.pop('openai_enabled'))
        self.assertFalse(any(result.values()))
