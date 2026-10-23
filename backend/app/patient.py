"""Patient-owned companion APIs. These never accept a patient ID from the client."""

from __future__ import annotations

import json
import hashlib
from uuid import uuid4

from flask import Blueprint, abort, current_app, g, jsonify, request

from .auth import require_firebase_user
from .db import get_db
from .device_health import device_health
from .firebase import sync_patient_live_vitals_access
from .guardian_notifications import send_guardian_support_request
from .measurements import public_vital
from .patient_workflows import (
    extract_supported_values,
    activity_entry_input,
    care_message_input,
    clinical_profile_input,
    lab_result_input,
    wellbeing_checkin_input,
)

patient_bp = Blueprint("patient", __name__)
_CONSENT_TYPES = {"monitoring", "care_team_sharing", "emergency_contact", "location"}
_DOCUMENT_MEDIA_TYPES = {"application/pdf", "image/jpeg", "image/png"}
_DOCUMENT_MAGIC = {
    "application/pdf": b"%PDF-",
    "image/jpeg": b"\xff\xd8\xff",
    "image/png": b"\x89PNG\r\n\x1a\n",
}
_DANGER_SIGNS = [
    {"id": "heavy_bleeding", "title": "Heavy bleeding", "action": "Get emergency care now if you soak a pad in an hour or pass large clots."},
    {"id": "breathing", "title": "Trouble breathing or chest pain", "action": "Call emergency services or go to the nearest emergency department now."},
    {"id": "headache", "title": "Severe headache or vision change", "action": "Seek urgent medical assessment today."},
    {"id": "fever", "title": "Fever or feeling very unwell", "action": "Contact your care team urgently."},
    {"id": "mental_health", "title": "Thoughts of harming yourself or your baby", "action": "Get emergency help now. Do not stay alone."},
]


def _row(row):
    return dict(row) if row else None


def _public_document(row):
    """Never place a report blob in a home or list response."""
    value = _row(row)
    if value:
        value.pop("content", None)
    return value


def _document_upload(file, declared_media_type: str | None = None):
    if not file or not file.filename:
        abort(400, description="document is required")
    media_type = (declared_media_type or file.mimetype or "").lower().strip()
    if media_type not in _DOCUMENT_MEDIA_TYPES:
        abort(400, description="Only PDF, JPEG, and PNG reports are supported")
    content = file.read(current_app.config["REPORT_UPLOAD_MAX_BYTES"] + 1)
    if not content:
        abort(400, description="The report file is empty")
    if len(content) > current_app.config["REPORT_UPLOAD_MAX_BYTES"]:
        abort(413, description="The report file exceeds the configured upload limit")
    if not content.startswith(_DOCUMENT_MAGIC[media_type]):
        abort(400, description="The report file does not match its declared type")
    filename = str(file.filename).replace("\\", "/").split("/")[-1].strip()
    if not filename or len(filename) > 180:
        abort(400, description="The report filename is invalid")
    return {
        "filename": filename,
        "media_type": media_type,
        "content": content,
        "sha256": hashlib.sha256(content).hexdigest(),
    }


def _patient_for_actor(cursor):
    if (
        not g.firebase_claims.get("demo")
        and g.firebase_claims.get("email_verified") is not True
        and not current_app.config.get("ALLOW_UNVERIFIED_PATIENT_DEMO")
    ):
        abort(403, description="Verify the email address for this patient account before accessing care information")
    cursor.execute(
        """SELECT p.*, h.name AS hospital_name FROM patients p JOIN hospitals h ON h.id = p.hospital_id
           WHERE p.user_id = %s AND p.is_active = true""",
        (g.actor["id"],),
    )
    patient = cursor.fetchone()
    if not patient:
        abort(403, description="This account is not linked to an active patient profile")
    return patient


def _mark_invitation_activated(cursor, patient) -> None:
    """Record successful verified access without persisting reset-link secrets."""
    cursor.execute(
        """UPDATE patient_invitations
              SET status = 'expired'
            WHERE patient_id = %s AND status = 'issued' AND expires_at < now()""",
        (patient["id"],),
    )
    cursor.execute(
        """UPDATE patient_invitations
              SET status = 'activated', activated_at = COALESCE(activated_at, now())
            WHERE patient_id = %s AND status = 'issued' AND expires_at >= now()""",
        (patient["id"],),
    )


@patient_bp.get("/patient/home")
@require_firebase_user
def home():
    connection = get_db()
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        _mark_invitation_activated(cursor, patient)
        cursor.execute(
            """SELECT captured_at, observed_at, received_at, heart_rate_bpm, spo2_percent,
                      heart_rate_source, spo2_source,
                      temperature_c, temperature_source, systolic_bp, diastolic_bp,
                      blood_pressure_source, battery_percent, contact_detected,
                      signal_quality, sensor_status, motion
               FROM vital_readings
               WHERE patient_id = %s
               ORDER BY observed_at DESC, id DESC
               LIMIT 1""",
            (patient["id"],),
        )
        latest_vital = cursor.fetchone()
        cursor.execute("""SELECT id, severity, status, alert_type, message, triggered_at, last_seen_at
                          FROM alerts WHERE patient_id = %s AND status IN ('open', 'acknowledged', 'escalated')
                          ORDER BY triggered_at DESC LIMIT 10""", (patient["id"],))
        alerts = cursor.fetchall()
        cursor.execute("""SELECT id, title, detail, due_at, status FROM care_plan_tasks
                          WHERE patient_id = %s AND status = 'open' ORDER BY due_at NULLS LAST, created_at DESC LIMIT 6""", (patient["id"],))
        tasks = cursor.fetchall()
        cursor.execute("""SELECT serial_number, firmware_version, last_seen_at, status, last_observed_at,
                                 last_battery_percent, last_sensor_status, last_contact_detected, last_signal_quality
                          FROM devices
                          WHERE assigned_patient_id = %s AND status = 'assigned' ORDER BY last_seen_at DESC NULLS LAST LIMIT 1""", (patient["id"],))
        device = cursor.fetchone()
        cursor.execute(
            """SELECT id, category, test_type, result_values, result_units, reported_on,
                      trimester, review_status, reference_status, submitted_at, reviewed_at
                 FROM patient_lab_results
                WHERE patient_id = %s
                ORDER BY submitted_at DESC LIMIT 6""",
            (patient["id"],),
        )
        lab_results = cursor.fetchall()
        cursor.execute(
            """SELECT id, checkin_type, immediate_safety_concern,
                      guardian_notification_status, clinician_review_status, submitted_at
                 FROM wellbeing_checkins
                WHERE patient_id = %s
                ORDER BY submitted_at DESC LIMIT 1""",
            (patient["id"],),
        )
        wellbeing = cursor.fetchone()
        cursor.execute(
            """SELECT count(*) AS completed_this_week
                 FROM wellbeing_checkins
                WHERE patient_id = %s
                  AND submitted_at >= date_trunc('week', now())""",
            (patient["id"],),
        )
        completed_checkins = cursor.fetchone()
        cursor.execute(
            """SELECT pregnancy_stage, patient_reported_history, clinician_confirmed_history,
                      current_medications, activity_clearance, last_patient_update_at, reviewed_at
                 FROM patient_clinical_profiles WHERE patient_id = %s""",
            (patient["id"],),
        )
        profile = cursor.fetchone()
        cursor.execute(
            """SELECT id, document_type, original_filename, media_type, byte_size, sha256,
                      extraction_status, review_status, uploaded_at, reviewed_at
                 FROM patient_report_documents WHERE patient_id = %s
                 ORDER BY uploaded_at DESC LIMIT 6""",
            (patient["id"],),
        )
        documents = cursor.fetchall()
        cursor.execute(
            """SELECT id, category, title, body, created_at
                 FROM patient_guidance WHERE patient_id = %s AND status = 'active'
                 ORDER BY created_at DESC LIMIT 8""",
            (patient["id"],),
        )
        guidance = cursor.fetchall()
        cursor.execute(
            """SELECT COALESCE(sum(minutes) FILTER (WHERE recorded_at >= date_trunc('day', now())), 0) AS today_minutes,
                      COALESCE(sum(minutes) FILTER (WHERE recorded_at >= date_trunc('week', now())), 0) AS week_minutes,
                      count(*) FILTER (WHERE recorded_at >= date_trunc('day', now())) AS today_sessions
                 FROM patient_activity_entries WHERE patient_id = %s""",
            (patient["id"],),
        )
        activity = cursor.fetchone()
        cursor.execute(
            """SELECT count(*) AS unread FROM care_messages
                 WHERE patient_id = %s AND sender_role = 'clinician' AND read_at IS NULL""",
            (patient["id"],),
        )
        unread_messages = cursor.fetchone()
    connection.commit()
    # Grant only this authenticated patient the RTDB live-vitals node that
    # matches the hospital/patient relationship verified above.
    sync_patient_live_vitals_access(
        g.actor["firebase_uid"], str(patient["hospital_id"]), str(patient["id"])
    )
    return jsonify(
        {
            "patient": _row(patient),
            "latest_vital": public_vital(latest_vital),
            "active_alerts": [_row(x) for x in alerts],
            "care_plan": [_row(x) for x in tasks],
            "device": _row(device),
            "device_health": device_health(
                device,
                offline_after_minutes=current_app.config["DEVICE_OFFLINE_AFTER_MINUTES"],
            ),
            "lab_onboarding_pending": patient.get("lab_onboarding_seen_at") is None,
            "lab_results": [_row(x) for x in lab_results],
            "report_documents": [_public_document(x) for x in documents],
            "clinical_profile": _row(profile) or {
                "pregnancy_stage": "not_recorded", "patient_reported_history": {},
                "clinician_confirmed_history": {}, "current_medications": [],
                "activity_clearance": "not_recorded",
            },
            "guidance": [_row(x) for x in guidance],
            "activity": {
                "today_minutes": int(activity["today_minutes"]),
                "week_minutes": int(activity["week_minutes"]),
                "today_sessions": int(activity["today_sessions"]),
                "automatic_tracking": "not_available_until_validated_wearable_classifier",
            },
            "messages": {"unread_from_care_team": int(unread_messages["unread"])},
            "wellbeing": {
                "recommended_checkins_per_week": 2,
                "completed_this_week": int(completed_checkins["completed_this_week"]),
                "latest": _row(wellbeing),
                "note": "This support check-in is not a diagnosis or a replacement for a validated clinical screen.",
            },
            "danger_signs": _DANGER_SIGNS,
        }
    )


@patient_bp.post("/patient/lab-onboarding/acknowledge")
@require_firebase_user
def acknowledge_lab_onboarding():
    connection = get_db()
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute(
            """UPDATE patients SET lab_onboarding_seen_at = COALESCE(lab_onboarding_seen_at, now()), updated_at = now()
                 WHERE id = %s RETURNING lab_onboarding_seen_at""",
            (patient["id"],),
        )
        value = cursor.fetchone()
    connection.commit()
    return jsonify({"lab_onboarding_seen_at": value["lab_onboarding_seen_at"]})


@patient_bp.post("/patient/lab-results/extract")
@require_firebase_user
def extract_lab_result():
    body = request.get_json(silent=True) or {}
    # Confirm account access before returning even a transient parsed result.
    with get_db().cursor() as cursor:
        _patient_for_actor(cursor)
    return jsonify(extract_supported_values(body.get("category"), body.get("report_text", "")))


@patient_bp.route("/patient/report-documents", methods=["GET", "POST"])
@require_firebase_user
def report_documents():
    connection = get_db()
    if request.method == "GET":
        with connection.cursor() as cursor:
            patient = _patient_for_actor(cursor)
            cursor.execute(
                """SELECT id, document_type, original_filename, media_type, byte_size, sha256,
                          extraction_status, review_status, uploaded_at, reviewed_at
                     FROM patient_report_documents WHERE patient_id = %s
                     ORDER BY uploaded_at DESC LIMIT 30""",
                (patient["id"],),
            )
            values = cursor.fetchall()
        return jsonify({"items": [_public_document(value) for value in values]})

    document_type = request.form.get("document_type", "medical_report")
    if document_type not in {"lab_report", "medical_report"}:
        abort(400, description="document_type must be lab_report or medical_report")
    upload = _document_upload(request.files.get("document"), request.form.get("media_type"))
    confirmed_text = str(request.form.get("report_text", "")).strip()
    if len(confirmed_text) > 5000:
        abort(400, description="report_text must not exceed 5000 characters")
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute(
            """INSERT INTO patient_report_documents
                   (hospital_id, patient_id, uploaded_by, document_type, original_filename,
                    media_type, byte_size, sha256, content, patient_confirmed_text, extraction_status)
                 VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
                 RETURNING id, document_type, original_filename, media_type, byte_size, sha256,
                           extraction_status, review_status, uploaded_at""",
            (
                patient["hospital_id"], patient["id"], g.actor["id"], document_type,
                upload["filename"], upload["media_type"], len(upload["content"]), upload["sha256"],
                upload["content"], confirmed_text or None,
                "patient_text_submitted" if confirmed_text else "not_requested",
            ),
        )
        saved = cursor.fetchone()
        cursor.execute(
            """INSERT INTO audit_log (actor_user_id, hospital_id, action, entity_type, entity_id,
                                         request_id, metadata, ip_address)
                 VALUES (%s, %s, 'patient.report_document_uploaded', 'patient_report_document', %s,
                         %s, %s::jsonb, %s)""",
            (g.actor["id"], patient["hospital_id"], str(saved["id"]), uuid4(),
             json.dumps({"document_type": document_type, "media_type": upload["media_type"], "byte_size": len(upload["content"])}),
             request.remote_addr),
        )
    connection.commit()
    return jsonify({
        "document": _public_document(saved),
        "message": "Your report was stored for clinician review. Any extracted values must still be confirmed before they are saved.",
    }), 201


@patient_bp.route("/patient/lab-results", methods=["GET", "POST"])
@require_firebase_user
def lab_results():
    connection = get_db()
    if request.method == "GET":
        with connection.cursor() as cursor:
            patient = _patient_for_actor(cursor)
            cursor.execute(
                """SELECT id, category, test_type, result_values, result_units, reported_on,
                      trimester, review_status, reference_status, submitted_at, reviewed_at
                     FROM patient_lab_results WHERE patient_id = %s
                     ORDER BY submitted_at DESC LIMIT 30""",
                (patient["id"],),
            )
            values = cursor.fetchall()
        return jsonify({"items": [_row(value) for value in values]})

    result = lab_result_input(request.get_json(silent=True) or {})
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute(
            """INSERT INTO patient_lab_results
                  (hospital_id, patient_id, category, test_type, result_values, result_units,
                   reported_on, trimester, extraction_method, review_status, reference_status)
                 VALUES (%s, %s, %s, %s, %s::jsonb, %s::jsonb, %s, %s, %s,
                         'pending_clinician_review', 'not_interpreted')
                 RETURNING id, category, test_type, result_values, result_units, reported_on,
                           trimester, review_status, reference_status, submitted_at""",
            (
                patient["hospital_id"], patient["id"], result["category"], result["test_type"],
                json.dumps(result["values"]), json.dumps(result["units"]), result["reported_on"],
                result["trimester"], result["extraction_method"],
            ),
        )
        saved = cursor.fetchone()
        cursor.execute(
            """INSERT INTO audit_log (actor_user_id, hospital_id, action, entity_type, entity_id,
                                        request_id, metadata, ip_address)
                 VALUES (%s, %s, 'patient.lab_result_submitted', 'patient_lab_result', %s, %s, %s::jsonb, %s)""",
            (g.actor["id"], patient["hospital_id"], str(saved["id"]), uuid4(),
             json.dumps({"category": result["category"], "test_type": result["test_type"]}), request.remote_addr),
        )
    connection.commit()
    return jsonify({
        "result": _row(saved),
        "message": "Your result was saved for clinician review. Do not change medicines or diet based only on this app.",
    }), 201


@patient_bp.post("/patient/wellbeing-checkins")
@require_firebase_user
def submit_wellbeing_checkin():
    checkin = wellbeing_checkin_input(request.get_json(silent=True) or {})
    connection = get_db()
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        notification_status = "not_requested"
        if checkin["immediate_safety_concern"] and checkin["guardian_notification_consent"]:
            notification_status = "not_configured"
        cursor.execute(
            """INSERT INTO wellbeing_checkins
                  (hospital_id, patient_id, responses, immediate_safety_concern,
                   guardian_notification_consent, guardian_notification_status)
                 VALUES (%s, %s, %s::jsonb, %s, %s, %s)
                 RETURNING id, immediate_safety_concern, guardian_notification_consent,
                           guardian_notification_status, clinician_review_status, submitted_at""",
            (patient["hospital_id"], patient["id"], json.dumps(checkin["answers"]),
             checkin["immediate_safety_concern"], checkin["guardian_notification_consent"], notification_status),
        )
        saved = cursor.fetchone()
        alert = None
        if checkin["immediate_safety_concern"]:
            cursor.execute(
                """INSERT INTO alerts (hospital_id, patient_id, severity, status, alert_type, message,
                          triggered_at, last_seen_at, occurrence_count, rule_id, rule_version, dedupe_key, evidence)
                     VALUES (%s, %s, 'critical', 'open', 'wellbeing_safety_concern',
                          'Patient selected an immediate safety concern in a wellbeing check-in. Contact immediately and follow the emergency protocol.',
                          now(), now(), 1, 'wellbeing_safety_concern', '2026-09-09', %s, %s::jsonb)
                     ON CONFLICT (hospital_id, patient_id, dedupe_key)
                        WHERE dedupe_key IS NOT NULL AND status IN ('open', 'acknowledged', 'escalated')
                     DO UPDATE SET last_seen_at = now(), occurrence_count = alerts.occurrence_count + 1,
                                   updated_at = now()
                     RETURNING id, status, triggered_at""",
                (patient["hospital_id"], patient["id"], f"wellbeing-safety:{patient['id']}",
                 json.dumps({"source": "patient_wellbeing_checkin"})),
            )
            alert = cursor.fetchone()
        cursor.execute(
            """INSERT INTO audit_log (actor_user_id, hospital_id, action, entity_type, entity_id,
                                        request_id, metadata, ip_address)
                 VALUES (%s, %s, 'patient.wellbeing_checkin_submitted', 'wellbeing_checkin', %s, %s, %s::jsonb, %s)""",
            (g.actor["id"], patient["hospital_id"], str(saved["id"]), uuid4(),
             json.dumps({"immediate_safety_concern": checkin["immediate_safety_concern"]}), request.remote_addr),
        )
    connection.commit()

    if checkin["immediate_safety_concern"] and checkin["guardian_notification_consent"]:
        notification_status = send_guardian_support_request(
            current_app.config,
            phone=patient.get("emergency_contact_phone"),
            patient_name=str(patient["full_name"]),
        )
        with connection.cursor() as cursor:
            cursor.execute(
                """UPDATE wellbeing_checkins SET guardian_notification_status = %s
                     WHERE id = %s RETURNING id, immediate_safety_concern,
                         guardian_notification_consent, guardian_notification_status,
                         clinician_review_status, submitted_at""",
                (notification_status, saved["id"]),
            )
            saved = cursor.fetchone()
        connection.commit()

    return jsonify({
        "checkin": _row(saved),
        "alert": _row(alert),
        "urgent": checkin["immediate_safety_concern"],
        "message": (
            "Your care team was alerted. Get emergency help now and do not stay alone."
            if checkin["immediate_safety_concern"]
            else "Your support check-in was saved. It is not a diagnosis; contact your care team if you are worried."
        ),
    }), 201


@patient_bp.post("/patient/sos")
@require_firebase_user
def sos():
    from .guardians import queue_guardian_sos
    body = request.get_json(silent=True) or {}
    note = str(body.get("note", "")).strip()[:500]
    connection = get_db()
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute('SELECT id FROM patients WHERE id=%s FOR UPDATE', (patient['id'],))
        cursor.execute("""INSERT INTO alerts (hospital_id, patient_id, severity, status, alert_type, message, triggered_at,
                          last_seen_at, occurrence_count, rule_id, rule_version, dedupe_key, evidence)
                          VALUES (%s, %s, 'critical', 'open', 'sos_help_request', %s, now(), now(), 1, 'patient_sos', '2026-1', %s, %s)
                          ON CONFLICT (hospital_id, patient_id, dedupe_key) WHERE dedupe_key IS NOT NULL AND status IN ('open','acknowledged','escalated')
                          DO UPDATE SET last_seen_at = now(), occurrence_count = alerts.occurrence_count + 1, updated_at = now()
                          RETURNING id, status, triggered_at""",
                       (patient["hospital_id"], patient["id"], "Patient requested urgent help." + (f" Note: {note}" if note else ""), f"patient-sos:{patient['id']}", '{"source":"patient_app"}'))
        alert = cursor.fetchone()
        guardian_count = queue_guardian_sos(cursor, patient, alert['id'])
        cursor.execute("""INSERT INTO audit_log (actor_user_id, hospital_id, action, entity_type, entity_id, request_id, metadata, ip_address)
                          VALUES (%s, %s, 'patient.sos_requested', 'alert', %s, %s, %s, %s)""",
                       (g.actor["id"], patient["hospital_id"], str(alert["id"]), uuid4(), '{"source":"patient_app"}', request.remote_addr))
    connection.commit()
    return jsonify({"alert": _row(alert), "guardian_notifications_queued": guardian_count,
        "message": "Urgent help request saved. Guardian notifications are queued when a guardian is linked. For immediate danger, call emergency services."}), 201


@patient_bp.post("/patient/symptoms")
@require_firebase_user
def symptoms():
    body = request.get_json(silent=True) or {}
    symptom_ids = body.get("symptoms", [])
    if not isinstance(symptom_ids, list) or not all(isinstance(x, str) and len(x) <= 64 for x in symptom_ids):
        abort(400, description="symptoms must be a list of valid symptom IDs")
    notes = str(body.get("notes", "")).strip()[:1000]
    urgent = bool(set(symptom_ids) & {"heavy_bleeding", "breathing", "headache", "mental_health"})
    connection = get_db()
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        import json
        cursor.execute("""INSERT INTO symptom_reports (hospital_id, patient_id, symptoms, notes, severity)
                          VALUES (%s, %s, %s::jsonb, %s, %s) RETURNING id, severity, submitted_at""",
                       (patient["hospital_id"], patient["id"], json.dumps(symptom_ids), notes or None, "urgent" if urgent else "routine"))
        report = cursor.fetchone()
    connection.commit()
    return jsonify({"report": _row(report), "urgent": urgent}), 201


@patient_bp.route("/patient/clinical-profile", methods=["GET", "PUT"])
@require_firebase_user
def clinical_profile():
    connection = get_db()
    if request.method == "GET":
        with connection.cursor() as cursor:
            patient = _patient_for_actor(cursor)
            cursor.execute(
                """SELECT pregnancy_stage, patient_reported_history, clinician_confirmed_history,
                          current_medications, activity_clearance, last_patient_update_at, reviewed_at
                     FROM patient_clinical_profiles WHERE patient_id = %s""",
                (patient["id"],),
            )
            profile = cursor.fetchone()
        return jsonify({"profile": _row(profile) or {
            "pregnancy_stage": "not_recorded", "patient_reported_history": {},
            "clinician_confirmed_history": {}, "current_medications": [],
            "activity_clearance": "not_recorded",
        }})

    profile = clinical_profile_input(request.get_json(silent=True) or {})
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute(
            """INSERT INTO patient_clinical_profiles
                   (patient_id, hospital_id, pregnancy_stage, patient_reported_history,
                    current_medications, last_patient_update_at)
                 VALUES (%s, %s, %s, %s::jsonb, %s::jsonb, now())
                 ON CONFLICT (patient_id) DO UPDATE SET
                   pregnancy_stage = EXCLUDED.pregnancy_stage,
                   patient_reported_history = EXCLUDED.patient_reported_history,
                   current_medications = EXCLUDED.current_medications,
                   last_patient_update_at = now(), updated_at = now()
                 RETURNING pregnancy_stage, patient_reported_history, clinician_confirmed_history,
                           current_medications, activity_clearance, last_patient_update_at, reviewed_at""",
            (patient["id"], patient["hospital_id"], profile["pregnancy_stage"],
             json.dumps(profile["history"]), json.dumps(profile["current_medications"])),
        )
        saved = cursor.fetchone()
        cursor.execute(
            """INSERT INTO audit_log (actor_user_id, hospital_id, action, entity_type, entity_id,
                                         request_id, metadata, ip_address)
                 VALUES (%s, %s, 'patient.clinical_profile_updated', 'patient_clinical_profile', %s,
                         %s, %s::jsonb, %s)""",
            (g.actor["id"], patient["hospital_id"], str(patient["id"]), uuid4(),
             json.dumps({"pregnancy_stage": profile["pregnancy_stage"]}), request.remote_addr),
        )
    connection.commit()
    return jsonify({
        "profile": _row(saved),
        "message": "Your updates were shared for care-team review. Only clinician-confirmed information is used to personalise clinical workflows.",
    })


@patient_bp.route("/patient/messages", methods=["GET", "POST"])
@require_firebase_user
def messages():
    connection = get_db()
    if request.method == "GET":
        with connection.cursor() as cursor:
            patient = _patient_for_actor(cursor)
            cursor.execute(
                """SELECT m.id, m.sender_role, m.body, m.status, m.in_reply_to, m.created_at, m.read_at,
                          CASE WHEN m.sender_role = 'clinician' THEN u.display_name ELSE 'You' END AS sender_name
                     FROM care_messages m JOIN app_users u ON u.id = m.sender_user_id
                    WHERE m.patient_id = %s ORDER BY m.created_at ASC, m.id ASC LIMIT 100""",
                (patient["id"],),
            )
            values = cursor.fetchall()
            cursor.execute(
                """UPDATE care_messages SET read_at = now()
                     WHERE patient_id = %s AND sender_role = 'clinician' AND read_at IS NULL""",
                (patient["id"],),
            )
        connection.commit()
        return jsonify({"items": [_row(value) for value in values]})

    message = care_message_input(request.get_json(silent=True) or {})
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        if message["in_reply_to"]:
            cursor.execute(
                "SELECT id FROM care_messages WHERE id = %s AND patient_id = %s",
                (message["in_reply_to"], patient["id"]),
            )
            if not cursor.fetchone():
                abort(400, description="in_reply_to does not belong to this conversation")
        cursor.execute(
            """INSERT INTO care_messages
                   (hospital_id, patient_id, sender_user_id, sender_role, body, in_reply_to)
                 VALUES (%s, %s, %s, 'patient', %s, %s)
                 RETURNING id, sender_role, body, status, in_reply_to, created_at, read_at""",
            (patient["hospital_id"], patient["id"], g.actor["id"], message["body"], message["in_reply_to"]),
        )
        saved = cursor.fetchone()
        cursor.execute(
            """INSERT INTO audit_log (actor_user_id, hospital_id, action, entity_type, entity_id,
                                         request_id, metadata, ip_address)
                 VALUES (%s, %s, 'patient.care_message_sent', 'care_message', %s, %s, %s::jsonb, %s)""",
            (g.actor["id"], patient["hospital_id"], str(saved["id"]), uuid4(),
             json.dumps({"patient_id": str(patient["id"])}), request.remote_addr),
        )
    connection.commit()
    return jsonify({
        "message": _row(saved),
        "notice": "Messages are reviewed during care-team working hours and are not an emergency service. For urgent danger signs, use SOS or seek emergency care now.",
    }), 201


@patient_bp.route("/patient/activity", methods=["GET", "POST"])
@require_firebase_user
def activity():
    connection = get_db()
    if request.method == "GET":
        with connection.cursor() as cursor:
            patient = _patient_for_actor(cursor)
            cursor.execute(
                """SELECT activity_clearance FROM patient_clinical_profiles WHERE patient_id = %s""",
                (patient["id"],),
            )
            profile = cursor.fetchone() or {"activity_clearance": "not_recorded"}
            cursor.execute(
                """SELECT id, activity_type, session_part, minutes, source, classifier_confidence, recorded_at, note
                     FROM patient_activity_entries WHERE patient_id = %s
                     ORDER BY recorded_at DESC LIMIT 30""",
                (patient["id"],),
            )
            entries = cursor.fetchall()
        return jsonify({
            "activity_clearance": profile["activity_clearance"],
            "automatic_tracking": "not_available_until_validated_wearable_classifier",
            "items": [_row(entry) for entry in entries],
        })

    entry = activity_entry_input(request.get_json(silent=True) or {})
    with connection.cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute("SELECT activity_clearance FROM patient_clinical_profiles WHERE patient_id = %s", (patient["id"],))
        profile = cursor.fetchone()
        if not profile or profile["activity_clearance"] != "cleared_by_clinician":
            abort(403, description="Your care team must confirm that activity tracking is appropriate before you record walking tasks")
        cursor.execute(
            """INSERT INTO patient_activity_entries
                   (hospital_id, patient_id, activity_type, session_part, minutes, source, note)
                 VALUES (%s, %s, %s, %s, %s, 'patient_reported', %s)
                 RETURNING id, activity_type, session_part, minutes, source, classifier_confidence, recorded_at, note""",
            (patient["hospital_id"], patient["id"], entry["activity_type"], entry["session_part"], entry["minutes"], entry["note"]),
        )
        saved = cursor.fetchone()
    connection.commit()
    return jsonify({
        "entry": _row(saved),
        "message": "Activity was recorded as patient-reported. Stop activity and seek advice if you develop warning symptoms or have been told to restrict activity.",
    }), 201


@patient_bp.get("/patient/consents")
@require_firebase_user
def consents():
    with get_db().cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute("""SELECT DISTINCT ON (consent_type) consent_type, granted, policy_version, recorded_at, withdrawn_at
                          FROM patient_consents WHERE patient_id = %s ORDER BY consent_type, recorded_at DESC""", (patient["id"],))
        values = cursor.fetchall()
    return jsonify({"items": [_row(x) for x in values]})


@patient_bp.put("/patient/consents/<consent_type>")
@require_firebase_user
def set_consent(consent_type):
    if consent_type not in _CONSENT_TYPES:
        abort(404)
    body = request.get_json(silent=True) or {}
    if not isinstance(body.get("granted"), bool):
        abort(400, description="granted must be a boolean")
    with get_db().cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute("""INSERT INTO patient_consents (hospital_id, patient_id, consent_type, granted, policy_version, withdrawn_at)
                          VALUES (%s, %s, %s, %s, '2026-1', CASE WHEN %s THEN NULL ELSE now() END)
                          ON CONFLICT (patient_id, consent_type, policy_version) DO UPDATE SET granted = EXCLUDED.granted,
                            recorded_at = now(), withdrawn_at = EXCLUDED.withdrawn_at
                          RETURNING consent_type, granted, policy_version, recorded_at, withdrawn_at""",
                       (patient["hospital_id"], patient["id"], consent_type, body["granted"], body["granted"]))
        value = cursor.fetchone()
    get_db().commit()
    return jsonify({"consent": _row(value)})


@patient_bp.patch("/patient/care-plan/<task_id>")
@require_firebase_user
def complete_task(task_id):
    body = request.get_json(silent=True) or {}
    status = body.get("status")
    if status not in {"completed", "skipped"}:
        abort(400, description="status must be completed or skipped")
    with get_db().cursor() as cursor:
        patient = _patient_for_actor(cursor)
        cursor.execute("""UPDATE care_plan_tasks SET status = %s, completed_at = now() WHERE id = %s AND patient_id = %s
                          RETURNING id, title, status, completed_at""", (status, task_id, patient["id"]))
        task = cursor.fetchone()
    if not task:
        abort(404)
    get_db().commit()
    return jsonify({"task": _row(task)})
