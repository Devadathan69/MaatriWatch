"""MaatriWatch Flask application factory."""

from __future__ import annotations

import os

import click

from flask import Flask, abort, jsonify, request

from .ai_chat import ai_chat_bp
from .auth import auth_bp
from .clinician import clinician_bp
from .config import Config
from .db import close_db, init_db, database_ready
from .firebase import init_firebase
from .ingestion import ingestion_bp
from .patient import patient_bp
from .devices import devices_bp
from .provisioning import provisioning_bp
from .companion import companion_bp
from .concerns import concerns_bp
from .reports import reports_bp
from .nutrition import nutrition_bp
from .consultations import consultations_bp
from .reminder_push import push_bp
from .outbox import deliver_pending_outbox


def create_app(test_config: dict | None = None) -> Flask:
    app = Flask(__name__)
    app.config.from_object(Config)
    if test_config:
        app.config.update(test_config)
    if app.config.get("IS_PRODUCTION"):
        errors = Config.production_configuration_errors(app.config)
        if errors:
            raise RuntimeError("Production configuration is incomplete: " + ", ".join(errors))

    init_db(app)
    init_firebase(app)
    app.teardown_appcontext(close_db)
    app.register_blueprint(auth_bp, url_prefix="/api/v1")
    app.register_blueprint(ai_chat_bp, url_prefix="/api/v1")
    app.register_blueprint(clinician_bp, url_prefix="/api/v1")
    app.register_blueprint(ingestion_bp, url_prefix="/api/v1")
    app.register_blueprint(patient_bp, url_prefix="/api/v1")
    app.register_blueprint(devices_bp, url_prefix="/api/v1")
    app.register_blueprint(provisioning_bp, url_prefix="/api/v1")
    app.register_blueprint(companion_bp, url_prefix="/api/v1")
    app.register_blueprint(concerns_bp, url_prefix="/api/v1")
    app.register_blueprint(reports_bp, url_prefix="/api/v1")
    app.register_blueprint(nutrition_bp, url_prefix="/api/v1")
    app.register_blueprint(consultations_bp, url_prefix="/api/v1")
    app.register_blueprint(push_bp, url_prefix="/api/v1")

    @app.before_request
    def protect_ingestion_payload_size():
        """A report upload must not silently expand the device attack surface."""
        if request.path in {"/api/v1/ingest/vitals", "/api/v1/ingest/telemetry"}:
            size = request.content_length
            if size is not None and size > app.config["TELEMETRY_MAX_CONTENT_LENGTH"]:
                abort(413, description="The telemetry payload is too large")

    @app.after_request
    def protect_api_responses(response):
        """Do not cache PHI, and permit only configured dashboard origins."""
        if request.path.startswith("/api/v1/"):
            response.headers["Cache-Control"] = "no-store, max-age=0"
            response.headers["X-Content-Type-Options"] = "nosniff"
            response.headers["Referrer-Policy"] = "no-referrer"
            response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
        origin = request.headers.get("Origin", "").rstrip("/")
        if origin and origin in app.config.get("CORS_ALLOWED_ORIGINS", ()):
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Access-Control-Allow-Methods"] = "GET, POST, PATCH, PUT, DELETE, OPTIONS"
            response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, X-Demo-Role"
            response.headers["Access-Control-Max-Age"] = "600"
            response.headers.add("Vary", "Origin")
        return response

    @app.get("/healthz")
    def healthz():
        return jsonify({"service": "maatriwatch-api", "status": "ok"})

    @app.get("/readyz")
    def readyz():
        missing = []
        if not app.config.get("DATABASE_URL") or not database_ready():
            missing.append("database")
        if not (app.config.get("FIREBASE_AUTH_READY") or app.config.get("DEMO_MODE")):
            missing.append("firebase_auth")
        if missing:
            return jsonify({"service": "maatriwatch-api", "status": "not_ready", "missing": missing}), 503
        return jsonify({"service": "maatriwatch-api", "status": "ready"})

    @app.errorhandler(400)
    def bad_request(error):
        return jsonify({"error": "bad_request", "message": str(error.description)}), 400

    @app.errorhandler(401)
    def unauthorised(error):
        return jsonify({"error": "unauthorised", "message": str(error.description)}), 401

    @app.errorhandler(403)
    def forbidden(error):
        return jsonify({"error": "forbidden", "message": str(error.description)}), 403

    @app.errorhandler(404)
    def not_found(_error):
        return jsonify({"error": "not_found"}), 404

    @app.errorhandler(409)
    def conflict(error):
        return jsonify({"error": "conflict", "message": str(error.description)}), 409

    @app.errorhandler(413)
    def payload_too_large(_error):
        return jsonify({"error": "payload_too_large", "message": "The telemetry payload is too large"}), 413

    @app.errorhandler(429)
    def rate_limited(error):
        return jsonify({"error": "rate_limited", "message": str(error.description)}), 429

    @app.errorhandler(503)
    def service_unavailable(error):
        return jsonify({"error": "service_unavailable", "message": str(error.description)}), 503

    @app.cli.command("drain-realtime-outbox")
    @click.option("--limit", default=100, show_default=True, type=click.IntRange(1, 1000))
    def drain_realtime_outbox(limit):
        """Deliver queued Firebase projections; run this as a separate worker process."""
        result = deliver_pending_outbox(limit)
        click.echo(f"delivered={result['delivered']} pending={result['pending']}")

    if not app.config.get("FIREBASE_AUTH_READY") and not app.config.get("DEMO_MODE"):
        app.logger.warning("Firebase Auth verification is unavailable; authenticated endpoints will reject requests.")
    if not app.config.get("FIREBASE_RTDB_READY") and not app.config.get("DEMO_MODE"):
        app.logger.warning("Firebase RTDB live sync is unavailable; durable API actions remain available when Auth is configured.")
    if not app.config.get("DATABASE_URL"):
        app.logger.warning("DATABASE_URL is not configured; database-backed endpoints will reject requests.")
    return app


# Required by `flask --app app run` and gunicorn's application factory expression.
app = create_app() if os.environ.get("FLASK_EAGER_APP") == "1" else None
