import unittest

from app.config import Config


class ProductionConfigTest(unittest.TestCase):
    def test_production_configuration_rejects_email_verification_bypass(self):
        errors = Config.production_configuration_errors({
            "IS_PRODUCTION": True,
            "ALLOW_UNVERIFIED_PATIENT_DEMO": True,
        })
        self.assertIn("ALLOW_UNVERIFIED_PATIENT_DEMO must be false", errors)

    def test_production_configuration_rejects_development_secret(self):
        original = {
            "IS_PRODUCTION": Config.IS_PRODUCTION,
            "DATABASE_URL": Config.DATABASE_URL,
            "FIREBASE_PROJECT_ID": Config.FIREBASE_PROJECT_ID,
            "FIREBASE_SERVICE_ACCOUNT_JSON": Config.FIREBASE_SERVICE_ACCOUNT_JSON,
            "FIREBASE_DATABASE_URL": Config.FIREBASE_DATABASE_URL,
            "FIREBASE_AUTH_ACTION_URL": Config.FIREBASE_AUTH_ACTION_URL,
            "SECRET_KEY": Config.SECRET_KEY,
            "CORS_ALLOWED_ORIGINS": Config.CORS_ALLOWED_ORIGINS,
            "DEMO_MODE": Config.DEMO_MODE,
            "DEMO_IN_MEMORY": Config.DEMO_IN_MEMORY,
        }
        try:
            Config.IS_PRODUCTION = True
            Config.DATABASE_URL = "postgresql://configured"
            Config.FIREBASE_PROJECT_ID = "project"
            Config.FIREBASE_SERVICE_ACCOUNT_JSON = '{"private_key":"test"}'
            Config.FIREBASE_DATABASE_URL = "https://project.firebaseio.com"
            Config.FIREBASE_AUTH_ACTION_URL = "https://activate.maatriwatch.test/activate"
            Config.SECRET_KEY = "development-only-change-me"
            Config.CORS_ALLOWED_ORIGINS = ("https://dashboard.maatriwatch.test",)
            Config.DEMO_MODE = False
            Config.DEMO_IN_MEMORY = False
            self.assertIn("SECRET_KEY", Config.production_configuration_errors())
        finally:
            for name, value in original.items():
                setattr(Config, name, value)

    def test_production_configuration_rejects_local_and_placeholder_values(self):
        values = {
            "IS_PRODUCTION": True,
            "DATABASE_URL": "postgresql://user:change-me@localhost:5432/db",
            "FIREBASE_PROJECT_ID": "your-project",
            "FIREBASE_SERVICE_ACCOUNT_JSON": '{"type":"service_account"}',
            "FIREBASE_DATABASE_URL": "http://localhost:9000",
            "FIREBASE_AUTH_ACTION_URL": "https://example.com/activate",
            "SECRET_KEY": "short",
            "CORS_ALLOWED_ORIGINS": ("http://localhost:3000",),
            "DEMO_MODE": False,
            "DEMO_IN_MEMORY": False,
        }
        errors = Config.production_configuration_errors(values)
        self.assertEqual(
            set(errors),
            {
                "DATABASE_URL",
                "FIREBASE_PROJECT_ID",
                "FIREBASE_SERVICE_ACCOUNT_JSON",
                "FIREBASE_DATABASE_URL",
                "SECRET_KEY",
                "CORS_ALLOWED_ORIGINS",
                "FIREBASE_AUTH_ACTION_URL",
            },
        )


if __name__ == "__main__":
    unittest.main()
