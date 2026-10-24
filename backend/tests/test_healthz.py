import unittest
from threading import Event
from unittest.mock import MagicMock, patch

from psycopg import OperationalError
from psycopg_pool import ConnectionPool, PoolTimeout

from app import create_app


class HealthEndpointTest(unittest.TestCase):
    def test_slow_initial_connection_does_not_poison_the_pool(self):
        app = create_app({"TESTING": True, "DATABASE_URL": None, "FIREBASE_AUTH_READY": True})
        release = Event()
        pool = ConnectionPool("postgresql://unused", min_size=1, max_size=1, open=False)
        app.extensions["db_pool"] = pool
        app.config["DATABASE_URL"] = "postgresql://unused"
        ready_connection = MagicMock()
        ready_connection.__enter__.return_value.cursor.return_value.__enter__.return_value.fetchone.return_value = {"value": 1}

        def delayed_connect(*_args, **_kwargs):
            release.wait(5)
            raise OperationalError("synthetic startup delay")

        original_wait = pool.wait
        try:
            with patch.object(pool, "_connect", side_effect=delayed_connect), \
                 patch.object(pool, "wait", side_effect=lambda timeout: original_wait(min(timeout, 0.03))), \
                 patch.object(pool, "connection", side_effect=[PoolTimeout("synthetic startup delay"), ready_connection]):
                first = app.test_client().get("/readyz")
                self.assertEqual(first.status_code, 503)
                self.assertFalse(pool.closed)
                self.assertEqual(app.test_client().get("/readyz").status_code, 200)
        finally:
            release.set()
            pool.close(timeout=2)

    def test_database_checkout_timeout_returns_json_and_next_request_recovers(self):
        from app.db import get_db
        app = create_app({"TESTING": True, "DATABASE_URL": None})
        pool = MagicMock()
        pool.getconn.side_effect = [PoolTimeout("private connection details"), MagicMock()]
        app.extensions["db_pool"] = pool

        @app.get("/test-database")
        def test_database():
            get_db()
            return {"ok": True}

        first = app.test_client().get("/test-database")
        self.assertEqual(first.status_code, 503)
        self.assertEqual(first.json["error"], "service_unavailable")
        self.assertNotIn("private connection details", first.get_data(as_text=True))
        self.assertEqual(app.test_client().get("/test-database").status_code, 200)

    def test_socket_loss_during_cleanup_returns_the_connection_to_the_pool(self):
        from app.db import get_db
        app = create_app({"TESTING": True, "DATABASE_URL": None})
        pool = MagicMock()
        connection = pool.getconn.return_value
        connection.autocommit = False
        connection.rollback.side_effect = OperationalError("synthetic disconnect")
        app.extensions["db_pool"] = pool
        with app.test_request_context():
            get_db()
        connection.close.assert_called_once()
        pool.putconn.assert_called_once_with(connection)

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
