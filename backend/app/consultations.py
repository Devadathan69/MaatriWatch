"""Hospital availability, patient booking, cancellation, and private video access."""

from datetime import datetime, timedelta, timezone
from flask import Blueprint, abort, current_app, g, jsonify, request
from werkzeug.exceptions import HTTPException

from .auth import require_firebase_user, require_hospital_role
from .care_records import actor_patient, records, demo_enabled
from .companion import body, aware_time, text
from .consultation_store import schedule, identifier
from . import video_provider
from .db import get_db

consultations_bp = Blueprint("consultations", __name__)


def optional_text(value, field="reason"):
    if value is None or value == "":
        return ""
    return text(value, field, 1000)


def appointment_reminder(patient, appointment):
    repo = records(patient)
    stable = "appointment:" + appointment["id"]
    prior = next(
        (r for r in repo.list("reminder", 10000) if r["stable_key"] == stable), None
    )
    if prior:
        if appointment["status"] != "booked" and prior["data"]["status"] == "active":
            repo.put("reminder", {**prior["data"], "status": "cancelled"}, prior["id"])
        return
    if appointment["status"] == "booked":
        due = datetime.fromisoformat(
            appointment["start_at"].replace("Z", "+00:00")
        ) - timedelta(minutes=30)
        repo.put(
            "reminder",
            {
                "title": "Your scheduled video visit is coming up",
                "due_at": due.isoformat(),
                "recurrence": "none",
                "timezone": "UTC",
                "status": "active",
                "appointment_id": appointment["id"],
            },
            stable_key=stable,
        )


@consultations_bp.get("/patient/consultations/slots")
@require_firebase_user
def available_slots():
    patient = actor_patient()
    return jsonify({"items": schedule().slots(str(patient["hospital_id"]))})


@consultations_bp.route("/patient/consultations", methods=["GET", "POST"])
@require_firebase_user
def patient_consultations():
    patient = actor_patient()
    store = schedule()
    if request.method == "GET":
        return jsonify(
            {
                "items": store.appointments(
                    str(patient["hospital_id"]), patient=str(patient["id"])
                ),
                "video_configured": bool(current_app.config.get("DAILY_API_KEY")),
            }
        )
    values = body()
    row = store.book(
        patient, identifier(values.get("slot_id")), optional_text(values.get("reason"))
    )
    reminder_pending = False
    try:
        appointment_reminder(patient, row)
    except Exception:
        # Booking is durable. The worker reconciles missing reminders without losing the reservation.
        reminder_pending = True
    return jsonify({"appointment": row, "reminder_pending": reminder_pending}), 201


def _revoke(row):
    if not row.get("video_revocation_pending"):
        return
    if not current_app.config.get("DAILY_API_KEY"):
        return
    try:
        video_provider.revoke(row)
        if demo_enabled():
            schedule().data["appointments"][row["id"]]["video_revocation_pending"] = (
                False
            )
        else:
            with get_db().cursor() as cur:
                cur.execute(
                    "UPDATE consultations SET video_revocation_pending=false WHERE id=%s AND hospital_id=%s",
                    (row["id"], row["hospital_id"]),
                )
            get_db().commit()
        row["video_revocation_pending"] = False
    except HTTPException:
        pass  # Durable flag is retried by companion_worker; never turn a cancellation into a failed booking action.


@consultations_bp.patch("/patient/consultations/<appointment_id>")
@require_firebase_user
def patient_change(appointment_id):
    patient = actor_patient()
    store = schedule()
    row = store.get(
        identifier(appointment_id),
        str(patient["hospital_id"]),
        patient=str(patient["id"]),
    )
    if not row:
        abort(404, description="Appointment not found")
    values = body()
    if values.get("action") == "reschedule":
        if values.get("slot_id") == row["slot_id"]:
            abort(400, description="Choose a different slot")
        new = store.book(
            patient,
            identifier(values.get("slot_id")),
            row["reason"],
            replace_id=row["id"],
        )
        old = store.get(
            row["id"], str(patient["hospital_id"]), patient=str(patient["id"])
        )
        appointment_reminder(patient, old)
        appointment_reminder(patient, new)
        _revoke(old)
        return jsonify({"appointment": new})
    if values.get("action") != "cancel":
        abort(400, description="Choose cancel or reschedule")
    row = store.change(row, "cancelled", optional_text(values.get("note"), "note"))
    appointment_reminder(patient, row)
    _revoke(row)
    return jsonify({"appointment": row})


def _join(row, clinician=False):
    if body().get("video_consent") is not True:
        abort(
            400,
            description="Confirm the video provider and camera/microphone use before joining",
        )
    result = video_provider.create_join(row, g.actor["id"], clinician)
    if not schedule().issued(row):
        abort(
            409,
            description="The appointment was cancelled while joining. Access was not issued.",
        )
    return jsonify({"join": result})


@consultations_bp.post("/patient/consultations/<appointment_id>/join")
@require_firebase_user
def patient_join(appointment_id):
    patient = actor_patient()
    row = schedule().get(
        identifier(appointment_id),
        str(patient["hospital_id"]),
        patient=str(patient["id"]),
    )
    if not row:
        abort(404, description="Appointment not found")
    return _join(row)


@consultations_bp.route(
    "/hospitals/<hospital_id>/consultation-slots", methods=["GET", "POST"]
)
@require_hospital_role("clinician")
def clinician_slots(hospital_id):
    store = schedule()
    if request.method == "GET":
        return jsonify(
            {
                "items": [
                    r
                    for r in store.slots(hospital_id)
                    if str(r["clinician_user_id"]) == str(g.actor["id"])
                ]
            }
        )
    values = body()
    start = aware_time(values.get("start_at"))
    end = aware_time(values.get("end_at"))
    now = datetime.now(timezone.utc)
    if not now < start < now + timedelta(days=90) or not timedelta(
        minutes=10
    ) <= end - start <= timedelta(minutes=60):
        abort(
            400,
            description="Publish a future 10–60 minute slot within the next 90 days",
        )
    return jsonify(
        {"slot": store.publish(hospital_id, str(g.actor["id"]), start, end)}
    ), 201


@consultations_bp.delete("/hospitals/<hospital_id>/consultation-slots/<slot_id>")
@require_hospital_role("clinician")
def close_slot(hospital_id, slot_id):
    schedule().close(identifier(slot_id), hospital_id, str(g.actor["id"]))
    return jsonify({"closed": True})


@consultations_bp.get("/hospitals/<hospital_id>/consultations")
@require_hospital_role("clinician")
def clinician_consultations(hospital_id):
    return jsonify(
        {
            "items": schedule().appointments(hospital_id, clinician=str(g.actor["id"])),
            "video_configured": bool(current_app.config.get("DAILY_API_KEY")),
        }
    )


@consultations_bp.patch("/hospitals/<hospital_id>/consultations/<appointment_id>")
@require_hospital_role("clinician")
def clinician_change(hospital_id, appointment_id):
    row = schedule().get(
        identifier(appointment_id), hospital_id, clinician=str(g.actor["id"])
    )
    if not row:
        abort(404, description="Appointment not found")
    values = body()
    action = values.get("action")
    if action not in ("cancel", "complete"):
        abort(400, description="Choose cancel or complete")
    if action == "complete" and datetime.now(timezone.utc) < aware_time(
        row["start_at"]
    ):
        abort(409, description="The visit has not started yet")
    row = schedule().change(
        row,
        "cancelled" if action == "cancel" else "completed",
        optional_text(values.get("note"), "note"),
    )
    appointment_reminder({"id": row["patient_id"], "hospital_id": hospital_id}, row)
    _revoke(row)
    return jsonify({"appointment": row})


@consultations_bp.post("/hospitals/<hospital_id>/consultations/<appointment_id>/join")
@require_hospital_role("clinician")
def clinician_join(hospital_id, appointment_id):
    row = schedule().get(
        identifier(appointment_id), hospital_id, clinician=str(g.actor["id"])
    )
    if not row:
        abort(404, description="Appointment not found")
    return _join(row, True)


def reconcile_appointments():
    if demo_enabled():
        return 0
    with get_db().cursor() as cur:
        cur.execute("""SELECT a.*,s.start_at,s.end_at FROM consultations a JOIN consultation_slots s ON s.id=a.slot_id
            WHERE (a.status='booked' AND s.end_at>now()) OR a.video_revocation_pending=true
            OR EXISTS(SELECT 1 FROM companion_records r WHERE r.patient_id=a.patient_id AND r.kind='reminder'
                AND r.stable_key='appointment:'||a.id::text AND r.data->>'status'='active' AND a.status<>'booked')""")
        rows = cur.fetchall()
    from .care_records import wire

    for row in wire(rows):
        appointment_reminder(
            {"id": row["patient_id"], "hospital_id": row["hospital_id"]}, row
        )
        _revoke(row)
    return len(rows)
