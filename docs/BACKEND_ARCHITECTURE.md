# MaatriWatch backend architecture

Python 3.11+ / Flask backend for MaatriWatch. Hardware is intentionally out of scope: the service accepts already-produced sensor measurements over HTTP. MQTT brokers may forward normalized measurements to the same ingestion service later.

## Storage decision

This MVP uses the requested **hybrid** model:

- **Postgres** is the durable system of record for hospitals, users, device ownership, complete readings, alerts, screenings, notes, and audit events. It supports hospital boundaries, reporting, transactions, retention, and clinical auditability.
- **Firebase Realtime Database** is a live projection containing only the current reading/status per patient. Its low-latency fan-out fits the Flutter dashboard without making Postgres the client-facing real-time channel.

RTDB-only is not appropriate here: clinician↔hospital membership is many-to-many, audit trails and screening history need relational integrity, and long-term analytics need queryable historical data.

## Hackathon prototype mode

For the submission flow, see [local demo guide](../DEMO.md). `DEMO_MODE` preserves the
normal Firebase Auth and Postgres implementation while exposing a role
picker. `DEMO_IN_MEMORY` is an explicitly isolated fallback for a machine that
cannot reach Supabase; it still routes simulated telemetry through the Phase 2
threshold evaluator, but it is not a production datastore or Firebase-write
substitute.

For the current feature inventory, limits, and root-relative setup commands, see the [project README](../README.md). This guide preserves the backend contract details from the earlier README.

## Local start (from backend/)

For teammate handoff, Firebase configuration, managed-Postgres deployment,
outbox-worker setup, and release checks, see [backend/DEPLOYMENT.md](../backend/DEPLOYMENT.md).

1. Create a Python 3.11 virtual environment and install `pip install -r requirements.txt`.
2. Copy `.env.example` to `.env`, supply Postgres and Firebase values, then apply the SQL migrations in lexical order (`001_initial_schema.sql`, `002_ingestion_alerting.sql`, then all remaining migrations through `009_clinical_followup_and_validation.sql`).
3. Run `flask --app app run --debug`.

For deployment, run the app behind Gunicorn as defined in `Procfile`; set all environment variables in the host configuration rather than committing a service-account file.

## HTTP API (initial)

- `GET /healthz` — no authentication.
- `POST /api/v1/ingest/vitals` (also `/api/v1/ingest/telemetry`) — device API-key authenticated; records an idempotent telemetry event, evaluates alert rules, writes an audit entry for each created alert, and queues Firebase projections.
- `GET /api/v1/me` — Firebase bearer-token authenticated; returns the application user and active hospital memberships.
- Clinician dashboard APIs (all Firebase bearer-token authenticated and scoped by the hospital path):
  - `GET /api/v1/hospitals/{hospitalId}/patients?sort=risk|recent|name`
  - `GET /api/v1/hospitals/{hospitalId}/patients/{patientId}`
  - `GET /api/v1/hospitals/{hospitalId}/patients/{patientId}/vitals?from=&to=&resolution=raw|5m|1h`
  - `GET /api/v1/hospitals/{hospitalId}/alerts?status=active|open|acknowledged|escalated|resolved|all`
  - `PATCH /api/v1/hospitals/{hospitalId}/alerts/{alertId}` with `{ "action": "acknowledge" | "resolve" | "escalate", "note": "..." }`
  - `GET` / `POST /api/v1/hospitals/{hospitalId}/patients/{patientId}/clinical-notes`

Patient companion APIs are identity-scoped: the mobile/web client never sends a
patient ID. After Firebase authentication, the backend resolves the one active
patient profile linked to the signed-in account:

- `GET /api/v1/patient/home` — current vital/device state, active alerts,
  open care-plan tasks, and urgent-warning-sign education.
- `POST /api/v1/patient/sos` — creates or updates a critical SOS episode and
  writes an audit event. It is a care-team notification, not a replacement for
  emergency services.
- `POST /api/v1/patient/symptoms` — records a patient symptom report for
  review; urgent selections are flagged for clinical workflow.
- `GET` / `PUT /api/v1/patient/consents[/{consentType}]` — patient-controlled
  monitoring, care-team, emergency-contact, and SOS-location sharing choices.
- `PATCH /api/v1/patient/care-plan/{taskId}` — completes or skips an assigned
  follow-up task.

Apply `004_patient_safety_workflows.sql` after the earlier migrations before
enabling these endpoints.

Only an active `clinician` membership at the requested hospital may use the clinical APIs. Every alert action locks the episode, writes an audit event with actor/request/IP context, updates the RTDB alert projection through the durable outbox after commit, and requires a note for resolve/escalate. The API never accepts a user, role, patient, or hospital authority from a browser request body.

The device endpoint requires `X-Device-Id` and `X-Device-Key`. Device keys must be high-entropy random values and only an Argon2 hash is stored in `devices.api_key_hash`. Every device upload must include a stable `event_id`, generated once by the device or simulator. Retrying the exact event returns the original reading instead of duplicating readings or alerts; reusing an ID for changed data returns HTTP 409.

It accepts an already-normalized telemetry payload such as:

```json
{
  "event_id": "simulator-20260814:000042",
  "source_sequence": 42,
  "captured_at": "2026-08-14T10:12:00Z",
  "heart_rate_bpm": 78,
  "spo2_percent": 98,
  "temperature_c": 36.8,
  "blood_pressure_source": "validated_cuff",
  "systolic_bp": 112,
  "diastolic_bp": 72,
  "battery_percent": 84,
  "motion": {
    "fall_detected": false,
    "impact_g": 0.2,
    "orientation_change_degrees": 3,
    "post_impact_immobile_seconds": 0
  }
}
```

The HTTP simulator defaults to five-second uploads; the integrated XIAO firmware defaults to fifteen seconds. The endpoint accepts out-of-order uploads safely; RTDB keeps the newest event by capture time/event ID and the full, ordered history remains in Postgres.

To exercise the HTTP contract without firmware, run the simulator after provisioning a device in Postgres:

```text
python scripts/simulate_device.py --device-id <UUID> --device-key <secret> --scenario fall --count 3
```

It supports `normal`, `hypertension`, and `fall` scenarios and defaults to a five-second interval. It is an HTTP client only; it does not write embedded firmware.

## Alerting policy

The baseline policy is in `backend/app/alerting.py` and stores its version with every alert. It generates **risk signals for clinician review, not automated diagnoses or treatment advice**:

- elevated/severely elevated blood pressure → postpartum hypertensive-risk signal; it does not diagnose preeclampsia, which needs clinical context beyond wearable BP;
- possible fall → an explicit device fall event, or a complete impact + orientation change + post-impact immobility pattern.

| Signal | Baseline trigger | Output |
| --- | --- | --- |
| Postpartum hypertension risk | SBP ≥140 or DBP ≥90; escalates at SBP ≥160 or DBP ≥110 | Warning / critical risk signal; not a diagnosis of preeclampsia |
| Possible fall | Device `fall_detected: true`, or impact ≥2.5g plus orientation change ≥60° plus immobility ≥30 s | Critical risk signal |

The project did not include the referenced clinical abstract, so the baseline values are intentionally centralized and must receive local clinical governance approval before production deployment. PPH monitoring is intentionally outside this wearable MVP because immediate post-delivery care belongs in the clinical setting. BP logic is a risk prompt rather than a preeclampsia diagnosis, because diagnosis requires more than a high BP reading ([ACOG](https://www.acog.org/community/districts-and-sections/district-iv/whats-new/countdown-to-intern-year-week-3-hypertensive-disorders)).

Repeated five-second breaches update one unresolved alert episode (`occurrence_count`, `last_seen_at`) rather than creating alert storms. A normal reading never resolves an alert—only a clinician workflow may do that.

## Firebase delivery and worker

Readings, alert episodes, alert audit entries, and RTDB outbox records commit in one Postgres transaction. The high-rate vital-reading table is the durable telemetry record; the audit log is reserved for meaningful alert transitions to avoid duplicating every 5-second upload. After commit, the API makes a fast delivery attempt; failures remain retryable in `realtime_outbox` and return `"realtime": "pending"` without losing clinical data.

Run a separate worker process in production:

```text
python -m app.realtime_worker
```

For one-shot operation, use `flask --app app drain-realtime-outbox`. Firebase projections include `live_vitals/{hospitalId}/{patientId}` and a clinician-only `live_alerts/{hospitalId}/{alertId}` queue. They are live views, not the source of record.

## RBAC boundary

Firebase Auth proves who the human is; Postgres `app_users` and `hospital_memberships` decide which MaatriWatch role(s) they hold and which hospitals they can access. Never accept a hospital ID or role from the client as authorization. A clinician can have one membership row per hospital.

Firebase custom claims may be used only as an optional UI hint; the backend always evaluates membership in Postgres. The browser dashboard lives in [dashboard/README.md](../dashboard/README.md). It uses Firebase email/password for clinicians and carries the Firebase ID token to this API. Set `CORS_ALLOWED_ORIGINS` to the exact Firebase Hosting origin(s); wildcard CORS is intentionally unsupported and all `/api/v1` responses are `Cache-Control: no-store`.

Firebase Auth verification and RTDB live sync have separate readiness states. A transient RTDB problem can leave dashboard REST workflows available; queued projections retry via the outbox instead of losing data.

## Live RTDB shape

See [RTDB shape](../backend/firebase/rtdb-shape.json) and [database rules](../backend/firebase/database.rules.json). Client read access relies on server-maintained `access/{firebaseUid}/{hospitalId}` and patient-leaf `patient_access/{firebaseUid}/{hospitalId}/{patientId}` entitlement projections. Full hospital live-vitals and alert-queue reads are reserved for explicitly entitled clinician/admin accounts; patient clients may read only their own leaf. Write access is server-only; clients must never write readings or alert state directly.
