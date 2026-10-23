# Local demonstration guide

The current PowerShell setup is in the root [README](README.md#setup--run). This guide distinguishes the separate demonstrations and their limits.

## Clinician workflow

1. Start the backend with `APP_ENV=development`, `DEMO_MODE=true`, and `DEMO_IN_MEMORY=true`, using the root setup steps. Bind it to localhost only.
2. Start the dashboard in a Flutter **debug** build with `DEMO_MODE=true` and the local API URL.
3. Choose Doctor to browse synthetic patients, trend history, alerts, and notes.
4. From the root, set `DEMO_MODE=true` and `DEMO_IN_MEMORY=true` in the trigger terminal, then run `.\.venv\Scripts\python.exe backend/scripts/trigger_demo_alert.py --scenario fall`.
5. Show the resulting possible-fall review signal and acknowledge/resolve it through the clinician workflow.

The in-memory fixture resets on restart. It exercises clinician routes and the deterministic alert engine, but does not persist PostgreSQL history or deliver Firebase projections. The role picker also has limited patient and hospital-admin presentation views.

The legacy trigger script still accepts `hypertension` and `pph` argument names. PPH detection is outside the current alert policy, and BP alerts require explicit validated-cuff/clinician-entered provenance. Those argument names are not proof of functioning clinical detection; use the fall scenario for this demo.

## Patient presentation

From `patient_app/`, run `flutter pub get`, then `flutter run --dart-define=DEMO_MODE=true` with an Android emulator/device selected. This is a debug-only presentation with synthetic state, separate from hospital account sign-in and the connected backend.

The connected patient workflow instead requires a hospital-provisioned Firebase account, linked PostgreSQL patient record, public Firebase client configuration, and the API. The current five-question wellbeing support check-in is not a validated EPDS/PHQ-9 screen or a depression score.

## Hardware simulation

The [Wokwi guide](simulation/wokwi/README.md) describes a standalone synthetic circuit. It labels output as simulation and prints telemetry to Serial Monitor; it does not send data to the clinical database. A public hosted Wokwi project URL has not been recorded.

## Connected demonstration

Use a disposable PostgreSQL/Firebase environment, disable the in-memory fallback, apply all nine migrations, provision the necessary accounts/devices, and start the outbox worker. Follow [deployment](backend/DEPLOYMENT.md) and the [watch guide](firmware/xiao_watch_prototype/README.md).

Do not enable public RTDB writes. The optional direct-Firebase watch transport is a latest-reading-only prototype path: it bypasses PostgreSQL history and clinical alerts. OpenAI chat and Twilio WhatsApp each require separate server-side configuration; their source code being present does not establish a working provider integration.

## Submission link

Add a verified hosted app, video, or presentation URL to the root README before submission. No public demo URL is claimed by these local instructions.
