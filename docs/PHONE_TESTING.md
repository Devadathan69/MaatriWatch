# Signed-in Android testing with persistent data

The local phone-testing environment uses the normal patient application, Firebase email/password authentication, PostgreSQL, and server-side OpenAI. Video is disabled. This is a local development setup; it is not a cloud deployment.

## Configured services

- PostgreSQL runs in Docker container `maatriwatch-phone-db`, bound only to `127.0.0.1:5433`. Its data lives in the named volume `maatriwatch-phone-pgdata`, independently of the API process. All migrations through `012` have been applied locally.
- The Firebase Android app matches package `org.maatriwatch.patient`. Public client settings are in ignored `patient_app/firebase-config.local.json`; Firebase Admin credentials and OpenAI remain only in ignored `backend/.env`.
- `DEMO_MODE`, `DEMO_IN_MEMORY`, and `ALLOW_UNVERIFIED_PATIENT_DEMO` are false. The normal backend requires verified Firebase identity and an active linked PostgreSQL patient record. `DAILY_API_KEY` is empty.
- The API runs on loopback port `8000`. The reminder and realtime outbox workers run separately. Local process IDs/logs are kept under ignored `output/`.
- Existing Firebase Auth accounts and deployed RTDB rules were preserved. The deployed rules already include scoped patient/clinician access and the optional direct-device transport rules.

The earlier Supabase endpoint rejected the saved host/project username. Its settings were preserved in ignored `backend/.env.supabase-before-phone`. The local database provides persistent phone testing while access to the correct cloud project is pending; it does not restore data from that project.

## Start or resume testing

Start Docker Desktop, connect/unlock the Android phone, allow USB debugging, and run from the repository root:

```powershell
pwsh -File backend/scripts/start_phone_testing.ps1
```

The helper starts the existing database, API, and workers, restores USB forwarding for connected authorized phones, and checks API readiness. It reuses recorded service processes instead of starting duplicate workers. Backend readiness now checks an actual database query rather than only the presence of a connection string.

Install and run the normal app from `patient_app/`:

```powershell
flutter run --debug -t lib/main.dart -d DEVICE_ID --dart-define-from-file=firebase-config.local.json --no-pub
```

Use `flutter devices` to find `DEVICE_ID`. The compiled debug APK is also available locally under `patient_app/build/app/outputs/flutter-apk/app-debug.apk`. Re-running the startup helper after reconnecting restores the USB route; keep the laptop, Docker, and services running during testing.

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

Cloud Supabase access remains a separate follow-up: retrieve the complete session-pooler string from the intended project's **Connect** dialog rather than guessing its host/region. Update only the ignored local configuration, inspect the target schema, and apply missing migrations through the existing helper. Do not replace the working local database until the cloud connection is verified.
