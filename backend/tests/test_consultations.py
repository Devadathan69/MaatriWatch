from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from threading import RLock
import unittest
from unittest.mock import patch
from werkzeug.exceptions import HTTPException, Conflict

from app import create_app
from app.consultation_store import MemorySchedule
from app.demo_store import DEMO_HOSPITAL_ID
from app.video_provider import create_join


class ConsultationTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app(
            {
                "TESTING": True,
                "DEMO_MODE": True,
                "DEMO_IN_MEMORY": True,
                "DATABASE_URL": None,
            }
        )
        self.client = self.app.test_client()
        self.patient = {"X-Demo-Role": "patient"}
        self.doctor = {"X-Demo-Role": "doctor"}
        self.start = datetime.now(timezone.utc) + timedelta(minutes=5)

    def publish(self, start=None):
        start = start or self.start
        result = self.client.post(
            f"/api/v1/hospitals/{DEMO_HOSPITAL_ID}/consultation-slots",
            json={
                "start_at": start.isoformat(),
                "end_at": (start + timedelta(minutes=30)).isoformat(),
            },
            headers=self.doctor,
        )
        self.assertEqual(result.status_code, 201)
        return result.json["slot"]

    def book(self, slot):
        result = self.client.post(
            "/api/v1/patient/consultations",
            json={
                "slot_id": slot["id"],
                "reason": "Discuss my monthly concern summary",
            },
            headers=self.patient,
        )
        self.assertEqual(result.status_code, 201)
        return result.json["appointment"]

    def test_booking_cancellation_and_reminder(self):
        slot = self.publish()
        visit = self.book(slot)
        duplicate = self.client.post(
            "/api/v1/patient/consultations",
            json={"slot_id": slot["id"]},
            headers=self.patient,
        )
        self.assertEqual(duplicate.status_code, 409)
        reminders = self.client.get(
            "/api/v1/patient/companion", headers=self.patient
        ).json["reminders"]
        self.assertEqual(reminders[0]["data"]["appointment_id"], visit["id"])
        self.assertEqual(
            self.client.patch(
                "/api/v1/patient/consultations/" + visit["id"],
                json={"action": "cancel"},
                headers=self.patient,
            ).status_code,
            200,
        )
        available = self.client.get(
            "/api/v1/patient/consultations/slots", headers=self.patient
        ).json["items"]
        self.assertEqual(available[0]["id"], slot["id"])
        self.assertEqual(
            self.client.get("/api/v1/patient/companion", headers=self.patient).json[
                "reminders"
            ][0]["data"]["status"],
            "cancelled",
        )

    def test_publish_overlaps_reschedule_and_authorization(self):
        a = self.publish()
        visit = self.book(a)
        conflict = self.client.post(
            f"/api/v1/hospitals/{DEMO_HOSPITAL_ID}/consultation-slots",
            json={
                "start_at": self.start.isoformat(),
                "end_at": (self.start + timedelta(minutes=20)).isoformat(),
            },
            headers=self.doctor,
        )
        self.assertEqual(conflict.status_code, 409)
        b = self.publish(self.start + timedelta(hours=1))
        result = self.client.patch(
            "/api/v1/patient/consultations/" + visit["id"],
            json={"action": "reschedule", "slot_id": b["id"]},
            headers=self.patient,
        )
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json["appointment"]["slot_id"], b["id"])
        self.assertEqual(
            self.client.get(
                f"/api/v1/hospitals/{DEMO_HOSPITAL_ID}/consultations",
                headers=self.patient,
            ).status_code,
            403,
        )
        other = self.client.post(
            f"/api/v1/hospitals/{DEMO_HOSPITAL_ID}/consultations/{result.json['appointment']['id']}/join",
            json={"video_consent": True},
            headers={"X-Demo-Role": "clinician"},
        )
        self.assertEqual(other.status_code, 404)

    def test_concurrent_bookings_reserve_only_one_patient(self):
        store = MemorySchedule({"slots": {}, "appointments": {}}, RLock())
        with self.app.app_context():
            slot = store.publish(
                "h", "clinician", self.start, self.start + timedelta(minutes=30)
            )

        def attempt(patient_id):
            with self.app.app_context():
                try:
                    return store.book(
                        {"id": patient_id, "hospital_id": "h"}, slot["id"], ""
                    )["id"]
                except HTTPException as error:
                    return error.code

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(attempt, ["a", "b"]))
        self.assertEqual(sum(isinstance(v, str) for v in results), 1)
        self.assertIn(409, results)
        self.assertEqual(store.appointments("h", patient="other"), [])

    def test_video_unconfigured_keeps_booking_and_requires_consent(self):
        visit = self.book(self.publish())
        path = "/api/v1/patient/consultations/" + visit["id"] + "/join"
        self.assertEqual(
            self.client.post(path, json={}, headers=self.patient).status_code, 400
        )
        self.assertEqual(
            self.client.post(
                path, json={"video_consent": True}, headers=self.patient
            ).status_code,
            503,
        )
        self.assertEqual(
            self.client.get("/api/v1/patient/consultations", headers=self.patient).json[
                "items"
            ][0]["status"],
            "booked",
        )

    @patch("app.video_provider.daily")
    def test_tokens_are_private_appointment_scoped_and_expiring(self, provider):
        appointment = {
            "id": "00000000-0000-0000-0000-000000000001",
            "start_at": self.start.isoformat(),
            "end_at": (self.start + timedelta(minutes=30)).isoformat(),
            "status": "booked",
        }
        name = "mw-" + appointment["id"].replace("-", "")
        provider.side_effect = [
            None,
            {
                "name": name,
                "privacy": "private",
                "url": "https://test.daily.co/" + name,
            },
            {"token": "unit-test-meeting-token"},
        ]
        with self.app.app_context():
            result = create_join(appointment, "patient-id")
        token = provider.call_args_list[-1].args[2]["properties"]
        self.assertEqual(token["room_name"], name)
        self.assertFalse(token["is_owner"])
        self.assertTrue(token["eject_at_token_exp"])
        self.assertFalse(token["start_cloud_recording"])
        self.assertGreater(token["exp"], token["nbf"])
        self.assertNotIn("token", result["room_url"])
        with self.app.app_context():
            with self.assertRaises(Conflict):
                create_join(
                    appointment, "patient-id", now=self.start - timedelta(hours=1)
                )
        self.assertEqual(provider.call_count, 3)
