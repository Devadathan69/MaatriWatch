"""Environment-backed Flask configuration."""

from __future__ import annotations

import os
from collections.abc import Mapping
from urllib.parse import urlparse

from dotenv import load_dotenv

# Gunicorn and the standalone outbox worker do not automatically load `.env`.
# Deployment environments still take precedence over this local-development file.
load_dotenv()


def _positive_int(name: str, default: int) -> int:
    raw = os.getenv(name, str(default)).strip()
    try:
        value = int(raw)
    except ValueError as error:
        raise RuntimeError(f"{name} must be a positive integer") from error
    if value <= 0:
        raise RuntimeError(f"{name} must be a positive integer")
    return value


def _looks_placeholder(value: object) -> bool:
    if not isinstance(value, str) or not value.strip():
        return True
    normalised = value.strip().lower()
    return any(token in normalised for token in (
        "change-me", "replace-with", "your-", "[your", "<your", "example", "placeholder",
    ))


def _is_https_public_url(value: object) -> bool:
    if _looks_placeholder(value):
        return False
    parsed = urlparse(str(value))
    return (
        parsed.scheme == "https"
        and bool(parsed.netloc)
        and parsed.hostname not in {"localhost", "127.0.0.1", "::1"}
    )


class Config:
    ENVIRONMENT = os.getenv("APP_ENV", os.getenv("FLASK_ENV", "development")).strip().lower()
    IS_PRODUCTION = ENVIRONMENT in {"production", "prod"}
    SECRET_KEY = os.getenv("SECRET_KEY", "development-only-change-me")
    DATABASE_URL = os.getenv("DATABASE_URL")
    FIREBASE_PROJECT_ID = os.getenv("FIREBASE_PROJECT_ID")
    FIREBASE_DATABASE_URL = os.getenv("FIREBASE_DATABASE_URL")
    FIREBASE_SERVICE_ACCOUNT_JSON = os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON")
    FIREBASE_AUTH_ACTION_URL = os.getenv("FIREBASE_AUTH_ACTION_URL")
    FIREBASE_READY = False
    FIREBASE_AUTH_READY = False
    FIREBASE_RTDB_READY = False
    CORS_ALLOWED_ORIGINS = tuple(
        origin.strip().rstrip("/")
        for origin in os.getenv("CORS_ALLOWED_ORIGINS", "").split(",")
        if origin.strip()
    )
    DEMO_MODE = os.getenv("DEMO_MODE", "false").strip().lower() in {"1", "true", "yes"}
    DEMO_IN_MEMORY = os.getenv("DEMO_IN_MEMORY", "false").strip().lower() in {"1", "true", "yes"}
    # Explicit, short-lived presentation escape hatch for a Firebase email
    # delivery outage. It only relaxes patient email verification; account,
    # active-patient, and Firebase-token checks still apply.
    ALLOW_UNVERIFIED_PATIENT_DEMO = os.getenv(
        "ALLOW_UNVERIFIED_PATIENT_DEMO", "false"
    ).strip().lower() in {"1", "true", "yes"}
    JSON_SORT_KEYS = False
    # The global limit admits a small patient report. Telemetry receives a
    # separate, much smaller route-level limit in the app factory.
    MAX_CONTENT_LENGTH = _positive_int("MAX_CONTENT_LENGTH", 4_000_000)
    REPORT_UPLOAD_MAX_BYTES = _positive_int("REPORT_UPLOAD_MAX_BYTES", 4_000_000)
    TELEMETRY_MAX_CONTENT_LENGTH = _positive_int("TELEMETRY_MAX_CONTENT_LENGTH", 16_384)
    REALTIME_OUTBOX_BATCH_SIZE = _positive_int("REALTIME_OUTBOX_BATCH_SIZE", 100)
    DEVICE_OFFLINE_AFTER_MINUTES = _positive_int("DEVICE_OFFLINE_AFTER_MINUTES", 30)
    # Optional. When unset, an urgent wellbeing disclosure remains visible to
    # the care team but WhatsApp delivery is reported as not configured.
    TWILIO_ACCOUNT_SID = os.getenv("TWILIO_ACCOUNT_SID")
    TWILIO_AUTH_TOKEN = os.getenv("TWILIO_AUTH_TOKEN")
    TWILIO_WHATSAPP_FROM = os.getenv("TWILIO_WHATSAPP_FROM")
    TWILIO_TIMEOUT_SECONDS = _positive_int("TWILIO_TIMEOUT_SECONDS", 10)
    # Optional server-only MaatriCare education assistant. Leave the key
    # unset to disable the endpoint without affecting patient care APIs.
    OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
    OPENAI_CHAT_MODEL = os.getenv("OPENAI_CHAT_MODEL", "gpt-5-mini").strip()
    OPENAI_TRANSCRIBE_MODEL = os.getenv('OPENAI_TRANSCRIBE_MODEL', 'gpt-transcribe').strip()
    OPENAI_CHAT_TIMEOUT_SECONDS = _positive_int("OPENAI_CHAT_TIMEOUT_SECONDS", 60)
    OPENAI_CHAT_MAX_REQUESTS = _positive_int("OPENAI_CHAT_MAX_REQUESTS", 12)
    OPENAI_CHAT_WINDOW_SECONDS = _positive_int("OPENAI_CHAT_WINDOW_SECONDS", 900)

    @classmethod
    def production_configuration_errors(cls, values: Mapping[str, object] | None = None) -> list[str]:
        """Return safe configuration names only; never echo configured values."""
        source = values or cls.__dict__

        def value(name: str):
            return source.get(name, getattr(cls, name, None))

        if not value("IS_PRODUCTION"):
            return []
        errors: list[str] = []
        database_url = value("DATABASE_URL")
        if _looks_placeholder(database_url) or "localhost" in str(database_url).lower():
            errors.append("DATABASE_URL")
        if _looks_placeholder(value("FIREBASE_PROJECT_ID")):
            errors.append("FIREBASE_PROJECT_ID")
        service_account = value("FIREBASE_SERVICE_ACCOUNT_JSON")
        if _looks_placeholder(service_account) or '"private_key"' not in str(service_account):
            errors.append("FIREBASE_SERVICE_ACCOUNT_JSON")
        if not _is_https_public_url(value("FIREBASE_DATABASE_URL")):
            errors.append("FIREBASE_DATABASE_URL")
        if _looks_placeholder(value("SECRET_KEY")) or len(str(value("SECRET_KEY"))) < 32:
            errors.append("SECRET_KEY")
        origins = value("CORS_ALLOWED_ORIGINS") or ()
        if not origins or "*" in origins or not all(_is_https_public_url(origin) for origin in origins):
            errors.append("CORS_ALLOWED_ORIGINS")
        if not _is_https_public_url(value("FIREBASE_AUTH_ACTION_URL")):
            errors.append("FIREBASE_AUTH_ACTION_URL")
        if value("DEMO_MODE") or value("DEMO_IN_MEMORY"):
            errors.append("DEMO_MODE/DEMO_IN_MEMORY must be false")
        return errors
