# Signed-in Android testing with persistent data

The current phone-testing build uses the public HTTPS API at **https://maatriwatch-api.onrender.com/api/v1**, Firebase email/password authentication, Supabase PostgreSQL, and server-side OpenAI. Video is disabled. USB is needed only to install an updated APK; the installed public build works over Wi-Fi or mobile data.

## Current Render deployment — 24 October 2026

- Render service `maatriwatch-api` is on the **Free** plan in Singapore. Its Docker image supervises Gunicorn, the realtime outbox worker, and the companion/SOS worker. Runtime releases come from `codex/kochi-hackathon-baseline`; automatic redeploys are disabled. Render's deploy history records the exact running commit.
- Public `/healthz`, `/readyz`, and `/activate` returned 200; `/readyz` confirmed Supabase and Firebase readiness. Unauthenticated `/api/v1/account/access` returned 401. Firebase authorized the new hostname while retaining existing domains. Laptop API/workers were stopped after cloud readiness succeeded.
- Production flags are enabled; all demo flags and the email-verification bypass are false. Private credentials are platform environment secrets and remain excluded from Git and the Docker image. The existing Supabase database and accounts were retained.
- `patient_app/firebase-config.local.json` now selects the public API. Its previous USB configuration is backed up in ignored `output/phone-firebase-config-before-render.json`. The HTTPS APK must be installed on **both** phones, one at a time with the single cable, before testing without USB.
- Render Free sleeps after 15 minutes without inbound traffic, and waking can take about a minute. Sleeping also stops the workers, so reminders and SOS do **not** have guaranteed continuous delivery. The app allows up to 75 seconds for account lookup during wake-up. Use funded always-on hosting before relying on continuous notifications. See [Render's documented limits](https://render.com/docs/free).
- The Neysa event quickstart supplies model inference endpoints, not an API/worker deployment environment. This deployment continues to use the configured OpenAI integration.

Symptom-save recovery: readiness now waits for a connection checkout without calling the pool's startup wait, which permanently closes the pool if initialization times out. A transient health-check timeout returns 503 and leaves connection retries active. API checkouts return a readable JSON 503 when unavailable, and rollback failures release their checkout. The backend suite passes 99 tests. An isolated Supabase check with mocked Firebase verification confirmed that a Malayalam audio-mode concern saves, appears in history, and persists on a fresh connection after a simulated readiness timeout. The synthetic fixture was removed; existing records were retained. This is a server update compatible with the installed HTTPS app.

The sections below describe the preserved **local USB fallback**. Running its helper restarts laptop services; the current HTTPS phone build will continue to use Render unless its API configuration is deliberately switched back.

## Configured services

- Supabase PostgreSQL uses its IPv4-compatible **Session pooler**, port `5432`, with TLS required. The working URI is stored only in ignored `backend/.env` and `backend/.env.supabase`. Migrations through `014` are applied. Firebase remains the identity provider; no Supabase Auth migration or client database key is needed.
- All 33 app tables have row-level security enabled, with table and owned-sequence access revoked from public client roles. The backend database owner retains access; Firebase identities and patient/hospital authorization are enforced by the API. Future tables must receive equivalent restrictions before storing data.
- The Firebase Android app matches package `org.maatriwatch.patient`. Public client settings are in ignored `patient_app/firebase-config.local.json`; Firebase Admin credentials and OpenAI remain only in ignored `backend/.env`.
- `DEMO_MODE`, `DEMO_IN_MEMORY`, and `ALLOW_UNVERIFIED_PATIENT_DEMO` are false. The normal backend requires verified Firebase identity and an active linked PostgreSQL patient record. `DAILY_API_KEY` is empty.
- The API runs on loopback port `8000`. The reminder and realtime outbox workers run separately. Local process IDs/logs are kept under ignored `output/`.
- Each process reserves one database session, with a maximum of four connections per pool, to fit the small Session pooler's connection budget.
- Existing Firebase Auth accounts and deployed RTDB rules were preserved. The deployed rules already include scoped patient/clinician access and the optional direct-device transport rules.

The cloud database was backed up before migration in ignored `output/supabase-before-migrations-*.dump`. Its existing records were preserved. The dedicated synthetic phone-test accounts, patient profile, and feature records were copied into their own hospital, retaining their Firebase links and IDs.

The earlier local Docker database remains available as a fallback: container `maatriwatch-phone-db`, volume `maatriwatch-phone-pgdata`, loopback port `5433`. Its working configuration is preserved in ignored `backend/.env.local-before-supabase`. Switching back requires restoring that local `DATABASE_URL` and restarting the services; changes made in Supabase are not automatically copied back. Docker is unnecessary for normal Supabase testing.

## Start or resume testing

Connect/unlock the Android phone, allow USB debugging, and run from the repository root:

```powershell
pwsh -File backend/scripts/start_phone_testing.ps1
```

The helper starts the API and workers, restores USB forwarding for connected authorized phones, and checks readiness with an actual database query. A small background USB helper restores forwarding automatically within a few seconds whenever either test phone reconnects. Keep both phones connected for simultaneous SOS testing. It reuses recorded service processes instead of starting duplicates. Add `-Restart` after changing backend configuration to reload the services. Docker is started only when the configuration selects the local fallback database.

Install and run the normal app from `patient_app/`:

```powershell
flutter run --debug -t lib/main.dart -d DEVICE_ID --dart-define-from-file=firebase-config.local.json --no-pub
```

Use `flutter devices` to find `DEVICE_ID`. The compiled debug APK is also available locally under `patient_app/build/app/outputs/flutter-apk/app-debug.apk`. Re-running the startup helper after reconnecting restores the USB route; keep the laptop, services, and internet connection running during testing. The database switch needs no change to the phone's API URL.

If opening the app shows **Let’s reconnect**, keep its USB cable connected, confirm USB debugging is authorized, and tap **Try again**. Returning to the app also retries a failed account lookup. The local test server must still be running; Supabase hosts the database, not the API. Account opening allows up to 75 seconds for a hosted server to wake, then shows a readable connection message instead of raw socket details. Authentication and access restrictions remain enforced.

## Test sign-in

Private generated sign-in details are in `output/PHONE_TEST_SIGNIN.md`. They are deliberately excluded from Git. The dedicated patient and clinician accounts use reserved `.test` email addresses and an isolated synthetic hospital/profile. Only these newly created synthetic accounts were pre-verified by the administrator for integration testing; real-account email verification remains enforced. Existing real/admin/device identities were not changed.

The fixture includes synthetic concerns, a confirmed report, companion memory/messages, reminder inbox entries, and a booking. Previous weekly-plan records are retained as history; complete the new preference questionnaire and request AI food ideas in Nourish. It contains no real medical history. Open these features from the patient's care/help screens. Memory and sharing controls remain available.

To use a real email instead, provision/link that Firebase user through the normal hospital onboarding flow and complete email verification. An unlinked Firebase account is intentionally denied access. The complete production invitation flow also needs the configured activation page described in [backend deployment](../backend/DEPLOYMENT.md).

## Verification and remaining checks

On 23 October 2026:

- All twelve migrations applied to local PostgreSQL 17 successfully.
- Real PostgreSQL API checks saved/read companion memory and chat, concerns, reports, nutrition plans, clinician slots, and a patient booking. The Firebase token verifier was mocked only inside that isolated test process; database access, user linkage, tenant checks, and storage were real.
- Saved record IDs survived a Docker database restart. The reminder worker created persistent inbox notifications and completed its one-pass check.
- Firebase Admin authenticated successfully, email/password sign-in was enabled, the Android app was registered, and the configured normal Android APK built successfully.
- The backend suite passed 83 tests. Final password sign-in on the physical phone and native push delivery still need device verification.

On 24 October 2026, Supabase Session pooler connectivity was verified, migrations `010`–`013` applied, and the synthetic phone-test profiles/data copied without changing existing cloud records. Public API role access was denied in database checks. The API and both workers were switched to Supabase, and cloud-backed API read/write/persistence checks passed with Firebase token verification mocked only inside an isolated test process. The backend suite still passes 83 tests. Physical-phone password sign-in and native push delivery remain pending until the phone is reconnected.

## Patient feedback update — 24 October 2026

The normal app was installed and the user exercised patient mode. The updated build separates recorded audio with an editable transcript from manual symptom fields, removes the redundant symptom-report button and audio-file upload, and presents short monthly sections for experiences, severity, patterns and major insights. Keep `MAX_CONTENT_LENGTH=4000000` for recordings/report uploads; telemetry retains its independent 16 KB cap.

Event reminders capture the event name/date/time and advance notice. Nourish requires the new preference questionnaire and explicit AI consent, then returns suggested foods and explanations of items to limit or avoid using the selected confirmed report. No built-in weekly plan substitutes for an unavailable model.

For SOS, open **Help → My SOS guardians**, enter the guardian's email, and create a private code. On another Android phone, install the same app, choose **Guardian sign-in / setup**, sign in or create an account, verify that email, enter the code and enable SOS notifications. Codes are email-bound, single-use and valid for 24 hours; reissuing invalidates older codes for that recipient. Up to three guardians can be linked. Removing a guardian stops new notifications and inbox access. Guardians receive no reports or chat access.

The companion worker handles durable SOS delivery and retries, with generic high-priority push text and a persistent guardian inbox. Duplicate notifications within one minute are suppressed. Pending pushes expire after 15 minutes; missed requests remain in the inbox while the link is active. Background/foreground delivery still needs a two-phone device check. Notifications remain best-effort; keep a direct emergency contact plan.

Migration `014` was applied locally and to the backed-up cloud database. Isolated synthetic checks passed linking, ownership, revocation, SOS delivery/idempotency, event storage, live OpenAI food advice, brief monthly reports, and transcription beyond the old cap. Firebase verification and FCM sends were mocked only inside that isolated process; no external guardian was notified. The current suite passes 92 backend, 17 patient-app and four dashboard tests, with clean analysis for both Flutter apps.
