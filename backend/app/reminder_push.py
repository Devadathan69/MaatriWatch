"""Optional opt-in Firebase phone notifications with non-clinical lock-screen text."""

from datetime import datetime, timedelta, timezone
import hashlib
from firebase_admin import messaging
from flask import Blueprint, abort, current_app, jsonify, request
from .auth import require_firebase_user
from .care_records import actor_patient, demo_enabled
from .companion import body, text
from .db import get_db

push_bp = Blueprint("reminder_push", __name__)


def devices(patient):
    if demo_enabled():
        return [
            r
            for r in current_app.extensions.setdefault("push_demo_devices", {}).values()
            if r["patient_id"] == str(patient["id"])
            and r["hospital_id"] == str(patient["hospital_id"])
            and r["is_active"]
        ]
    with get_db().cursor() as cur:
        cur.execute(
            "SELECT token,token_hash FROM patient_push_devices WHERE hospital_id=%s AND patient_id=%s AND is_active=true",
            (patient["hospital_id"], patient["id"]),
        )
        return cur.fetchall()


@push_bp.route("/patient/companion/push-device", methods=["POST", "DELETE"])
@require_firebase_user
def registration():
    patient = actor_patient()
    value = body()
    token = text(value.get("token"), "device token", 4096)
    if len(token) < 20:
        abort(400, description="Invalid device token")
    digest = hashlib.sha256(token.encode()).hexdigest()
    if request.method == "POST" and not current_app.config.get("FIREBASE_AUTH_READY"):
        abort(
            503,
            description="Phone reminders require the hospital’s Firebase server configuration",
        )
    if (
        request.method == "POST"
        and len(devices(patient)) >= 5
        and not any(r["token_hash"] == digest for r in devices(patient))
    ):
        abort(
            409,
            description="Five devices are already registered. Contact your care team to remove an older device.",
        )
    if demo_enabled():
        store = current_app.extensions.setdefault("push_demo_devices", {})
        if request.method == "DELETE":
            if digest in store and store[digest]["patient_id"] == str(patient["id"]):
                store[digest]["is_active"] = False
        else:
            store[digest] = {
                "patient_id": str(patient["id"]),
                "hospital_id": str(patient["hospital_id"]),
                "token": token,
                "token_hash": digest,
                "is_active": True,
            }
    else:
        with get_db().cursor() as cur:
            if request.method == "DELETE":
                cur.execute(
                    "UPDATE patient_push_devices SET is_active=false WHERE hospital_id=%s AND patient_id=%s AND token_hash=%s",
                    (patient["hospital_id"], patient["id"], digest),
                )
            else:
                cur.execute(
                    """INSERT INTO patient_push_devices(hospital_id,patient_id,token,token_hash) VALUES (%s,%s,%s,%s)
                ON CONFLICT(token_hash) DO UPDATE SET hospital_id=EXCLUDED.hospital_id,patient_id=EXCLUDED.patient_id,
                    token=EXCLUDED.token,is_active=true,updated_at=now()""",
                    (patient["hospital_id"], patient["id"], token, digest),
                )
        get_db().commit()
    return jsonify({"enabled": request.method == "POST"})


def send_pending(repo, now=None):
    now = now or datetime.now(timezone.utc)
    if not current_app.config.get("FIREBASE_AUTH_READY"):
        return
    if demo_enabled() and not current_app.config.get("TESTING"):
        return
    targets = devices(repo.patient)
    for row in repo.list("notification", 100):
        data = row["data"]
        if data.get("push_status") != "pending":
            continue
        if (
            data.get("push_next_attempt_at")
            and datetime.fromisoformat(data["push_next_attempt_at"]) > now
        ):
            continue
        sent = set(data.get("delivered_devices", []))
        attempt = data.get("push_attempts", 0) + 1
        for device in targets:
            if device["token_hash"] in sent:
                continue
            message = messaging.Message(
                token=device["token"],
                notification=messaging.Notification(
                    title="A gentle MaatriCare reminder",
                    body="Open MaatriWatch to see your reminder.",
                ),
                data={"notification_id": row["id"], "screen": "companion_reminders"},
            )
            try:
                messaging.send(message)
                sent.add(device["token_hash"])
            except Exception:
                # Do not log SDK exceptions: some transports include token/request details.
                pass
        complete = all(d["token_hash"] in sent for d in targets)
        data.update(
            delivered_devices=sorted(sent),
            push_attempts=attempt,
            push_status="not_enabled"
            if not targets
            else "sent"
            if complete
            else "failed"
            if attempt >= 5
            else "pending",
            push_next_attempt_at=(now + timedelta(seconds=30 * 2**attempt)).isoformat(),
        )
        repo.put("notification", data, row["id"])
