from datetime import datetime, timedelta, timezone
from unittest.mock import patch
import unittest
from app import create_app
from app.care_records import actor_patient, records
from app.companion import deliver_due


class ReminderPushTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app(
            {
                "TESTING": True,
                "DEMO_MODE": True,
                "DEMO_IN_MEMORY": True,
                "DATABASE_URL": None,
                "FIREBASE_AUTH_READY": True,
            }
        )
        self.client = self.app.test_client()
        self.headers = {"X-Demo-Role": "patient"}

    @patch("app.reminder_push.messaging.send", return_value="unit-message-id")
    def test_push_is_opt_in_generic_and_not_repeated(self, send):
        registered = self.client.post(
            "/api/v1/patient/companion/push-device",
            json={"token": "unit-test-device-token-for-messaging"},
            headers=self.headers,
        )
        self.assertEqual(registered.status_code, 200)
        with self.app.test_request_context():
            from flask import g

            g.demo_role = "patient"
            repo = records(actor_patient())
            now = datetime.now(timezone.utc)
            reminder = repo.put(
                "reminder",
                {
                    "title": "Sensitive personal reminder title",
                    "due_at": (now - timedelta(minutes=1)).isoformat(),
                    "status": "active",
                    "recurrence": "none",
                    "timezone": "UTC",
                },
            )
            deliver_due(repo, now)
            deliver_due(repo, now)
            self.assertEqual(send.call_count, 1)
            message = send.call_args.args[0]
            self.assertNotIn("Sensitive", message.notification.body)
            self.assertNotIn("Sensitive", message.notification.title)
            self.assertEqual(
                repo.list("notification")[0]["data"]["push_status"], "sent"
            )
        self.client.delete(
            "/api/v1/patient/companion/push-device",
            json={"token": "unit-test-device-token-for-messaging"},
            headers=self.headers,
        )
        self.assertEqual(registered.json, {"enabled": True})

    def test_cors_allows_patient_memory_deletion(self):
        self.app.config["CORS_ALLOWED_ORIGINS"] = ("https://patient.example",)
        result = self.client.options(
            "/api/v1/patient/companion/messages",
            headers={
                "Origin": "https://patient.example",
                "Access-Control-Request-Method": "DELETE",
            },
        )
        self.assertIn("DELETE", result.headers["Access-Control-Allow-Methods"])
