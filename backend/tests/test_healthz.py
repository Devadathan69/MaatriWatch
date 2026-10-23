import unittest
from unittest.mock import MagicMock

from psycopg import OperationalError

from app import create_app


class HealthEndpointTest(unittest.TestCase):
    def test_healthz_is_available_without_external_services(self):
        app = create_app({"TESTING": True})
        response = app.test_client().get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {"service": "maatriwatch-api", "status": "ok"})

    def test_readyz_reports_missing_dependencies_without_secrets(self):
        app = create_app({"TESTING": True})
        response = app.test_client().get("/readyz")
        self.assertEqual(response.status_code, 503)
        self.assertIn("database", response.get_json()["missing"])

    def test_readyz_rejects_configured_but_unreachable_database(self):
        app = create_app({"TESTING": True, "DATABASE_URL": "postgresql://localhost/unused", "FIREBASE_AUTH_READY": True})
        pool = MagicMock()
        pool.open.side_effect = OperationalError("private-connection-details")
        app.extensions["db_pool"] = pool
        response = app.test_client().get("/readyz")
        self.assertEqual(response.status_code, 503)
        self.assertIn("database", response.get_json()["missing"])
        self.assertNotIn("private-connection-details", response.get_data(as_text=True))

    def test_readyz_accepts_usable_database_and_firebase_auth(self):
        app = create_app({"TESTING": True, "DATABASE_URL": "postgresql://localhost/unused", "FIREBASE_AUTH_READY": True})
        pool = MagicMock()
        pool.connection.return_value.__enter__.return_value.cursor.return_value.__enter__.return_value.fetchone.return_value = {"value": 1}
        app.extensions["db_pool"] = pool
        response = app.test_client().get("/readyz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json()["status"], "ready")


if __name__ == "__main__":
    unittest.main()
