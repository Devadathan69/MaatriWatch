# Deploying the four companion phases

The source code is implemented. This document separates the local synthetic demo from enabling persistent/provider-backed features. Clinical validation and operational care processes remain separate requirements.

For the configured Supabase database, normal Firebase sign-in build, and repeatable laptop/USB service startup, see [signed-in phone testing](PHONE_TESTING.md). The credential-free fixture below remains a separate option.

## Local synthetic demonstration

From the repository root:

```powershell
.\.venv\Scripts\python.exe backend/scripts/run_local_demo.py
```

In a second terminal:

```powershell
Set-Location patient_app
flutter pub get
flutter run -t lib/companion_demo.dart -d chrome --web-hostname localhost --web-port 3001 --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1
```

The banner identifies synthetic data. By default the fixture server never loads `.env`, real database/provider credentials, or patient data. Companion storage is process-local in this mode and resets on restart. It seeds a report, concern, food preferences, availability, and a booking. Food guidance requires explicit OpenAI opt-in. Unconfigured AI/video calls produce explicit errors.

To test real AI replies, concern extraction/transcription, and report extraction against synthetic data, explicitly enable OpenAI:

```powershell
.\.venv\Scripts\python.exe backend/scripts/run_local_demo.py --with-openai
```

This option reads only allowlisted OpenAI settings from `backend/.env` or the process environment. It never enables database, Firebase, Daily, or Twilio credentials. Requests use the configured OpenAI account and incur its API usage. Existing per-feature processing consent and memory controls still apply. `--check-config` reports only enablement booleans and exits without contacting providers.

For a USB-connected Android phone, use `adb reverse tcp:8000 tcp:8000`, then run `flutter run -t lib/companion_demo.dart -d DEVICE_ID --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1` from `patient_app/`. USB debugging authorization is required. Keep the laptop/backend running and USB connected. This test build bypasses Firebase sign-in; use the normal `lib/main.dart` build with Firebase client settings for authenticated account and push testing.

Video may remain disabled while booking/cancellation/rescheduling are tested. A different video provider requires an explicit integration; a free public meeting URL is not a replacement for appointment-bound authorization.

## Database and service setup

Install the updated `backend/requirements.txt`. Use a Flutter SDK with Dart 3.10 or newer; Flutter 3.44.2/Dart 3.12.2 were used for local checks. The connected application needs the existing hospital/user/Firebase provisioning described in [backend deployment](../backend/DEPLOYMENT.md).

With a backed-up, approved development/staging database configured, run from `backend/`:

```powershell
..\.venv\Scripts\python.exe scripts/apply_migrations.py
```

The helper applies missing migrations through `014` and reasserts idempotent `013`: `010` adds companion records, `011` adds slots/bookings, `012` adds private FCM device registrations, and `013` restricts the original 29 app tables and their owned sequences. Migration `014` adds four private guardian tables with the same server-only restrictions. Pending migrations commit together or roll back on error. Backend access uses the database owner; Firebase and API authorization remain required. Future application tables need equivalent restrictions before storing data.

On 24 October 2026, the existing Supabase database was backed up and upgraded through `013` using its TLS Session pooler. Existing cloud records were preserved and isolated synthetic phone-test profiles/data added. The API and workers use this cloud database, while the previous local database/configuration remain available as a fallback. Booking uses row locks and a unique active-slot index. Normal booking/storage were exercised against PostgreSQL; simultaneous-booking unit tests still use the memory adapter.

Run three processes in the hosted environment:

```text
gunicorn app:create_app()
python -m app.realtime_worker
python -m app.companion_worker
```

The companion worker checks every 30 seconds, creates reminder inbox entries, sends opted-in phone notifications, prepares previous-month concern summaries, reconciles appointment reminders, and retries video revocations after cancellation. It must be supervised/restarted by the host. An always-available HTTP API/worker is not a continuously thinking model or a staffed emergency service.

## OpenAI

Keep `OPENAI_API_KEY` server-side. `OPENAI_CHAT_MODEL` defaults to `gpt-5-mini`; `OPENAI_TRANSCRIBE_MODEL` defaults to `gpt-transcribe`. Model availability must match the account. Recorded audio is bounded to 3 MB; report extraction accepts PDF/JPEG/PNG below 3.8 MB. Provider timeouts, unreadable values, refusals, and malformed outputs produce visible errors or require correction. No transcription/OCR accuracy guarantee is claimed.

Memory, sharing health context, and automatic month-end AI summaries have separate opt-ins. Individual audio/report processing also requires consent. Raw extraction files are not retained by the new extraction endpoints; confirmed data is stored. `store=false` is requested, which is not a guarantee of zero provider retention. The older report-document upload endpoint retains attachments separately.

## Android reminders

Firebase Admin credentials must have the intended project and Cloud Messaging access. Use the patient's public Firebase app options in the Android build. The user chooses **Enable phone reminders** and grants notification permission. Device registration tokens are stored server-side under patient/hospital scope, refreshed while the registration listener runs, and deregistered on sign-out where connectivity permits; the SDK token is also deleted locally. Re-enable reminders if registration changes after reinstall/rotation.

The worker sends only generic lock-screen text and an opaque inbox notification ID. It does not transmit symptoms, reminder titles, report values, or clinical notes in the notification payload. Delivery is best-effort with bounded retries/backoff; device settings, OS power controls, Firebase availability, and network connectivity affect delivery. Inbox entries remain available independently. No emergency delivery promise is made. Browser push is not configured; web uses the in-app inbox.

## Private video consultations

Set `DAILY_API_KEY` in the backend host. Clinicians publish their own availability from the dashboard schedule button. Patients book/cancel/reschedule through the patient care-plan consultation screen. Start/end timestamps include offsets; clients display device-local time.

Both the booked patient and assigned active clinician must pass backend authorization and explicitly confirm video-provider use. Join opens ten minutes before the start and ends at the scheduled end. The backend creates/verifies a private Daily room and issues room-bound, expiring role-specific tokens. Tokens are transient and are passed to the SDK in memory, not appended to app URLs, persisted, or logged. The room expires five minutes after scheduled end; tokens eject at expiry. Automatic recording/transcription are off.

Cancellation prevents new join requests and attempts to expire an already-issued room. Provider failures leave a durable revocation flag for the worker to retry; an already-connected call may persist until revocation/expiry during an outage. Rescheduling reserves the new slot and cancels the old booking transactionally. Patient API calls cannot publish clinician availability or join another patient's appointment.

The web call frame and Android WebView use pinned Daily JS `0.94.0`. Camera/microphone permissions are requested only on joining. HTTPS and compatible browser/WebView policies are required. Android and browser media behavior, actual call quality, and live provider permissions still require real-device testing. iOS/desktop native video is not implemented; use the web client there. The repository does not currently contain an iOS target.

## Verification and remaining limits

Run `python scripts/run_tests.py` from `backend/`, then `flutter analyze` and `flutter test` in each Flutter app. These tests use synthetic data and mocked providers. Actual database migrations/concurrent transactions, model extraction/transcription quality (especially Malayalam), native notification delivery, and a real two-party video call require staging verification. The report/nutrition policy is documented in [REPORT_POLICY.md](REPORT_POLICY.md).

On 23 October 2026, the four-tab Android demo was installed on a connected phone over USB. With explicit OpenAI opt-in, live synthetic API checks passed chat, symptom extraction, text/PDF report extraction, and English audio transcription. The backend suite now contains 83 passing tests, including default credential isolation, OpenAI-only opt-in, and database readiness checks. These small connection/format checks are not clinical or multilingual accuracy evaluations.

Before clinical use, obtain governance approval for comparisons/response ownership, validate models and hardware with representative data, review privacy/retention/access controls, and have a clinician/dietitian review personalised plans. No medical accuracy, nutrient adequacy, regulated-device status, or clinical outcome is established by software tests.

The 24 October patient-feedback update adds guardian app notifications, separate manual/audio concern paths, brief four-section monthly AI reports, event/advance reminders, and questionnaire-first AI food ideas. The current backend suite passes 92 tests. See [current phone-testing steps](PHONE_TESTING.md) for guardian linking, upload limits and remaining device checks.
