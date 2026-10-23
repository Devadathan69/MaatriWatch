# Signed-in Android testing with persistent data

The phone-testing environment uses the normal patient application, Firebase email/password authentication, Supabase PostgreSQL, and server-side OpenAI. Video is disabled. The database is hosted in Supabase; the API and workers still run on the laptop.

## Configured services

- Supabase PostgreSQL uses its IPv4-compatible **Session pooler**, port `5432`, with TLS required. The working URI is stored only in ignored `backend/.env` and `backend/.env.supabase`. Migrations through `013` are applied. Firebase remains the identity provider; no Supabase Auth migration or client database key is needed.
- All 29 app tables have row-level security enabled, with table and owned-sequence access revoked from public client roles. The backend database owner retains access; Firebase identities and patient/hospital authorization are enforced by the API. Future tables must receive equivalent restrictions before storing data.
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

The helper starts the API and workers, restores USB forwarding for connected authorized phones, and checks readiness with an actual database query. It reuses recorded service processes instead of starting duplicate workers. Add `-Restart` after changing backend configuration to reload all three services. Docker is started only when the configuration selects the local fallback database.

Install and run the normal app from `patient_app/`:

```powershell
flutter run --debug -t lib/main.dart -d DEVICE_ID --dart-define-from-file=firebase-config.local.json --no-pub
```

Use `flutter devices` to find `DEVICE_ID`. The compiled debug APK is also available locally under `patient_app/build/app/outputs/flutter-apk/app-debug.apk`. Re-running the startup helper after reconnecting restores the USB route; keep the laptop, services, and internet connection running during testing. The database switch needs no change to the phone's API URL.

## Test sign-in

Private generated sign-in details are in `output/PHONE_TEST_SIGNIN.md`. They are deliberately excluded from Git. The dedicated patient and clinician accounts use reserved `.test` email addresses and an isolated synthetic hospital/profile. Only these newly created synthetic accounts were pre-verified by the administrator for integration testing; real-account email verification remains enforced. Existing real/admin/device identities were not changed.

The fixture includes a synthetic concern, confirmed report comparison, meal-plan draft, companion memory/messages, reminder inbox entries, and a booking. It contains no real medical history. Open the companion, concern history, Nourish planner, and consultations from the patient's care/help screens. Memory and sharing controls remain available to inspect or change.

To use a real email instead, provision/link that Firebase user through the normal hospital onboarding flow and complete email verification. An unlinked Firebase account is intentionally denied access. The complete production invitation flow also needs the configured activation page described in [backend deployment](../backend/DEPLOYMENT.md).

## Verification and remaining checks

On 23 October 2026:

- All twelve migrations applied to local PostgreSQL 17 successfully.
- Real PostgreSQL API checks saved/read companion memory and chat, concerns, reports, nutrition plans, clinician slots, and a patient booking. The Firebase token verifier was mocked only inside that isolated test process; database access, user linkage, tenant checks, and storage were real.
- Saved record IDs survived a Docker database restart. The reminder worker created persistent inbox notifications and completed its one-pass check.
- Firebase Admin authenticated successfully, email/password sign-in was enabled, the Android app was registered, and the configured normal Android APK built successfully.
- The backend suite passed 83 tests. Final password sign-in on the physical phone and native push delivery still need device verification.

On 24 October 2026, Supabase Session pooler connectivity was verified, migrations `010`–`013` applied, and the synthetic phone-test profiles/data copied without changing existing cloud records. Public API role access was denied in database checks. The API and both workers were switched to Supabase, and cloud-backed API read/write/persistence checks passed with Firebase token verification mocked only inside an isolated test process. The backend suite still passes 83 tests. Physical-phone password sign-in and native push delivery remain pending until the phone is reconnected.
