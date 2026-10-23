# MaatriWatch

Connected maternal-care support through a wearable prototype, a patient companion app, and a clinician dashboard.

**AIBoomi Startup Weekend Kochi baseline — 23 October 2026.** This README follows the participants' handbook outline and describes the code already present before further weekend development. Existing features are prior work, not claimed hackathon achievements.

## Weekend development progress

The [four-phase implementation plan](docs/IMPLEMENTATION_PLAN.md) tracks the requested companion, bilingual concerns, report/nutrition, and video-consultation work. The feature inventory below remains the disclosed **prior-work baseline**.

- **Phase 1:** personal companion with opt-in memory, inspect/delete controls, separately consented health context, English/Malayalam replies, and timezone-aware reminders/inbox. The server reminder worker must run continuously; device push delivery is not included yet.
- **Phase 2:** English/Malayalam short audio transcription and typed concerns, editable structured symptoms, confirmation and sharing controls, recurring-symptom history, source-linked monthly summaries, and a clinician summary panel. Optional automatic AI month-end handoffs require explicit opt-in and the worker. Audio is not retained by the app; native/browser microphone behavior and real provider transcription still require device/integration validation.
- **Phase 3:** PDF/image/text report extraction with editable confirmation, versioned pregnancy-specific comparisons, and the Nourish meal planner. It includes seven-day meal drafts, original food illustrations, ingredients, shopping lists, allergy/preferences filtering, safe swap checks, and a clinician review panel. Plans use a bounded, explicit food catalog; they are not clinically validated nutrient prescriptions or a guarantee of extraction accuracy.
- **Phase 4:** planned, not yet delivered.

Apply migration `010_companion_memory.sql` using the migration helper. Run `python -m app.companion_worker` from `backend/` alongside the existing API/outbox worker. The local connected companion demo is `flutter run -t lib/companion_demo.dart -d chrome --web-port 3001 --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1` from `patient_app/`, against a localhost backend with both demo flags enabled and `http://localhost:3001` in CORS. This demo is debug-only and uses synthetic patient state. No model answer is fabricated if OpenAI is unconfigured.

Run credential-isolated backend tests with `.\.venv\Scripts\python.exe backend/scripts/run_tests.py` from the repository root.

For a credential-free synthetic demonstration of the new screens, run `.\.venv\Scripts\python.exe backend/scripts/run_local_demo.py` from the root, then start the connected Flutter demo above. It seeds a clearly labelled synthetic report, concern, and meal plan. Open **Nourish** to explore meal cards, reports, and the shopping list. AI and video provider calls are deliberately unconfigured in this fixture server.

## Problem statement

Pregnant and postpartum patients need a practical way to share changes in their wellbeing with their care team between visits. Clinicians need patient-linked readings, symptoms, and follow-up information in one place, with clear signals that need human review. MaatriWatch connects those workflows in an engineering prototype.

## Users & context

- **Patients:** hospital-provisioned accounts for reviewing wearable readings, requesting help, reporting symptoms, submitting reports, and following clinician guidance.
- **Clinicians:** hospital-scoped patient lists, trends, alert review, notes, messages, and follow-up guidance.
- **Hospital administrators:** patient invitations, wearable registration, assignment, and key rotation through authenticated APIs. A complete administration interface is not implemented.

The intended setting is supervised maternal-care follow-up. The prototype has not established clinical accuracy, clinical effectiveness, or readiness for unsupervised patient use.

## Solution overview

The default architecture is:

```text
XIAO ESP32-S3 watch / HTTP simulator
                 | HTTPS + device ID/key
                 v
             Flask API ------> PostgreSQL
                 |             history, alerts, care records, audits,
                 |             and durable realtime delivery queue
                 v
     Firebase Realtime Database
           |              |
     Clinician app     Patient app
           \              /
            authenticated REST API
```

Firebase Authentication establishes identity. Backend PostgreSQL memberships and patient links determine access. PostgreSQL is the durable record; Firebase Realtime Database (RTDB) supplies live projections.

### Features currently implemented

“Implemented” means present in source, subject to configuration and prototype limits. It does not imply a verified hosted deployment or clinical validation.

| Area | Current capability | Boundary / evidence |
| --- | --- | --- |
| Integrated wearable | XIAO ESP32-S3 firmware reads MAX30102 PPG heart-rate/SpO₂ estimates, TMP117 skin-adjacent/device temperature, and MPU6050 motion context; shows status on an OLED; supports a held-button SOS. | [Watch guide](firmware/xiao_watch_prototype/README.md). No BP sensor or wired battery-percentage measurement. |
| Wearable connectivity | Authenticated HTTPS telemetry, Wi-Fi setup/recovery portal, and password-protected local Arduino OTA maintenance. | Default XIAO upload interval is 15 seconds. Local `secrets.h` required; signed fleet updates are not implemented. |
| Telemetry ingestion | Device ID/key authentication, Argon2-hashed stored device keys, payload validation, event-ID idempotency, conflict detection, and out-of-order event handling. | [Ingestion](backend/app/ingestion.py). Identical retries do not create duplicate readings. |
| Measurement integrity | Source labels, contact/quality metadata, stale/unavailable states, explicit skin/device temperature labeling, and filtering of unsupported BP sources. | [Measurement representation](backend/app/measurements.py). Missing measurements are not evidence that a patient is well. |
| Risk signals and SOS | Versioned deterministic BP-risk, possible-fall, and physical-SOS rules; repeated breaches update unresolved episodes. | [Rules](backend/app/alerting.py). BP requires a validated-cuff/clinician-entered source; the watch has no validated fall classifier. PPH detection is outside scope. |
| Clinician dashboard | Firebase sign-in, hospital selection, patient sorting, live reading overlays, vital trends, alert acknowledge/resolve/escalate actions, and clinical notes. | [Dashboard](dashboard/README.md). Resolve/escalate requires a note; actions are audited. |
| Patient home | Hospital-linked Firebase account flow, email verification, current readings/device status, alerts, care tasks, and warning-sign education. | [Patient companion](patient_app/README.md). Android project included; backend and public Firebase configuration required. |
| Patient safety actions | Confirmed SOS submission, symptom reports, monitoring/sharing consent controls, and care-task completion/skipping. | [Patient API](backend/app/patient.py). SOS requests care-team help; it does not dispatch emergency services. |
| Reports and labs | PDF/JPEG/PNG uploads (default maximum 4 MB), file-signature validation, confirmed OGTT/thyroid entries, and narrow text extraction requiring confirmation. | [Workflow helpers](backend/app/patient_workflows.py). Regex extraction; no image OCR or automatic clinical interpretation. |
| Wellbeing support | Five-question support check-in, wellbeing education, urgent handling of an immediate-safety disclosure, and optional consented guardian WhatsApp delivery. | Not EPDS/PHQ-9 scoring or a depression diagnosis. Twilio requires provider setup and recipient opt-in; delivery is best-effort. |
| Continuing care | Patient/care-team messages, patient-reported and clinician-confirmed profiles, clinician-authored guidance, and patient-reported walking/activity after clinician clearance. | Patient screens and APIs exist; parts of the clinician review interface remain incomplete. Automatic steps/activity tracking is not implemented. |
| Validation records | Clinician APIs record paired wearable/reference observations with absolute and percentage error. | A comparison log exists; no completed validation study or accuracy result is claimed. |
| Device lifecycle | APIs for registration, assignment/unassignment, key rotation, inventory, and device-health status. | [Device API](backend/app/devices.py). Device-health issues are separate from clinical alerts. |
| Realtime resilience | PostgreSQL transactions queue Firebase projections in a durable outbox, with immediate delivery attempts and a separate retry worker. | [Worker](backend/app/realtime_worker.py). A failed live update does not discard the durable reading. |
| MaatriCare AI assistant | Optional authenticated education chat through the OpenAI Responses API, local urgent-term handling, bounded messages, and per-process rate limiting. | [Assistant](backend/app/ai_chat.py). Requires a server-only key; cannot read clinical records or live watch data. |
| Demo and simulation | Local role picker/in-memory clinician fixtures, debug-only patient presentation screens, HTTP device simulator, and Wokwi synthetic optical/temperature models. | Demo mode covers only a subset of workflows. [Wokwi](simulation/wokwi/README.md) prints synthetic telemetry without sending it to the patient database. |

### Technology stack and tools

| Layer | Technologies |
| --- | --- |
| Backend | Python 3.11+, Flask, psycopg, Argon2, Gunicorn, python-dotenv |
| Durable storage | PostgreSQL; Supabase Postgres hosting supported; nine SQL migrations (`001`–`009`) |
| Identity and live updates | Firebase Authentication, Firebase Admin SDK, Firebase Realtime Database |
| Clinician interface | Flutter/Dart, Firebase client SDKs, HTTP, fl_chart |
| Patient interface | Flutter/Dart, Firebase client SDKs, HTTP, file_picker; Android project included |
| Hardware | Seeed Studio XIAO ESP32-S3, MAX30102, TMP117, MPU6050, SSD1306 OLED, SOS button |
| Firmware tooling | Arduino ESP32 core, WiFiManager, SparkFun MAX3010x, Adafruit sensor/display libraries, ArduinoOTA |
| Optional services | OpenAI education chat; Twilio guardian WhatsApp |
| Hosting preparation | Gunicorn Procfile, Firebase Hosting configuration, Vercel build configuration; not proof of a working deployment |

Source: [`backend/`](backend), [`dashboard/`](dashboard), [`patient_app/`](patient_app), [`firmware/`](firmware), [`simulation/wokwi/`](simulation/wokwi), [backend architecture](docs/BACKEND_ARCHITECTURE.md), and [clinical feedback notes](docs/clinical_feedback_implementation.md).

## Product demo

**Hosted app, video, or presentation link: pending.** No verified public product demo URL is recorded. Add the actual link before submission; local setup instructions do not replace the handbook's required product-demo link.

Suggested local demonstration: open the clinician demo, post a synthetic fall event, then show alert acknowledgement and notes. Patient presentation screens and Wokwi are separate demonstrations using synthetic state.

## Setup & run

Commands use PowerShell from the repository root unless a directory change is shown. Install Git, Python 3.11+, and Flutter with Dart 3.4+ compatible with the locked dependencies. Chrome is needed for the dashboard; Android tooling is needed for the patient app. Use a disposable database/project for demos.

### 1. Dependencies and local configuration

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
Copy-Item backend/.env.example backend/.env
```

Copy the template only for a fresh setup; preserve an existing `.env`. Configure `backend/.env` locally with your own PostgreSQL URL, Firebase project/RTDB settings, Firebase Admin credentials, application secret, and allowed browser origins for the connected workflow. Optional OpenAI/Twilio keys belong only in the backend environment. Never put credentials in source, screenshots, documentation, or Flutter builds.

### 2. Local clinician demo without external services

First terminal:

```powershell
$env:APP_ENV = 'development'
$env:FLASK_ENV = 'development'
$env:DEMO_MODE = 'true'
$env:DEMO_IN_MEMORY = 'true'
$env:DATABASE_URL = ''
$env:FIREBASE_SERVICE_ACCOUNT_JSON = ''
$env:CORS_ALLOWED_ORIGINS = 'http://localhost:3000'
Set-Location backend
..\.venv\Scripts\python.exe -m flask --app 'app:create_app()' run --host 127.0.0.1 --port 8000 --no-reload
```

Second terminal, starting from the repository root:

```powershell
Set-Location dashboard
flutter pub get
flutter run -d chrome --web-hostname localhost --web-port 3000 --dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1 --dart-define=DEMO_MODE=true
```

Choose **Doctor**. Third terminal, starting from the root:

```powershell
$env:DEMO_MODE = 'true'
$env:DEMO_IN_MEMORY = 'true'
.\.venv\Scripts\python.exe backend/scripts/trigger_demo_alert.py --scenario fall
```

The fixture store resets on restart. The patient/admin role-picker views are limited presentation views, not complete database workflows. For the separate patient presentation on an Android emulator, run `flutter pub get` and `flutter run --dart-define=DEMO_MODE=true` from `patient_app/`; it uses local sample state without backend/Firebase sign-in. Flutter demo modes require debug builds.

### 3. Connected application

Use fresh terminals so demo environment overrides do not carry over. Configure `backend/.env`, keep `DEMO_MODE=false`, `DEMO_IN_MEMORY=false`, and `ALLOW_UNVERIFIED_PATIENT_DEMO=false`, then run:

```powershell
Set-Location backend
..\.venv\Scripts\python.exe scripts/apply_migrations.py
..\.venv\Scripts\python.exe -m flask --app 'app:create_app()' run --host 127.0.0.1 --port 8000 --no-reload
```

The migration helper applies missing migrations `001` through `009` in order. `scripts/seed_demo.py` can create synthetic fixtures in a disposable development database. Its deliberately public demo device credentials must never be used for real patients or production.

Run the retry worker separately from `backend/`:

```powershell
..\.venv\Scripts\python.exe -m app.realtime_worker
```

Enable Firebase email/password authentication; provision hospital memberships and patient links; deploy [backend RTDB rules](backend/firebase/database.rules.json) and server-maintained read entitlements. Supply the **public client** Firebase settings from the [dashboard guide](dashboard/README.md) and [patient guide](patient_app/README.md). Server credentials and device secrets must never be embedded in clients. Production requires secure configuration and disabled demo flags; the explicit patient email-verification bypass must also remain disabled outside demonstrations.

See [deployment and provisioning](backend/DEPLOYMENT.md) for account activation, CORS, readiness, and worker configuration. Liveness: `GET /healthz`; readiness: `GET /readyz`.

### 4. Hardware and simulators

Follow the [XIAO watch guide](firmware/xiao_watch_prototype/README.md), copying `secrets.example.h` to an ignored local `secrets.h` and supplying your own values. The [legacy ESP32 guide](firmware/maatriwatch_prototype/README.md) describes the earlier MAX30102/DHT11 design; DHT11 reports ambient conditions only. A [XIAO sensor-test sketch](firmware/xiao_watch_sensor_test/xiao_watch_sensor_test.ino) and [Wokwi circuit](simulation/wokwi/README.md) support development.

`backend/scripts/simulate_device.py` posts synthetic readings for a provisioned device. The optional direct-Firebase watch transport updates only the newest live reading: it bypasses PostgreSQL history, clinical alert creation, and the outbox, so it cannot demonstrate the complete default architecture.

## Models & data

- **Generative model:** MaatriCare defaults to `gpt-5-mini`, configurable through `OPENAI_CHAT_MODEL`, for short educational replies. No locally trained model, weights, fine-tuning dataset, or retrieval corpus is included. Comparative model-quality/cost evaluation is pending.
- **Rules and parsing:** risk evaluation is deterministic and versioned; report-text extraction uses regular expressions. Motion hardware does not by itself implement a trained activity/fall classifier.
- **Demo data:** the in-memory store, seed/simulator scripts, patient presentation screens, and Wokwi use synthetic examples. No external clinical dataset is bundled; fixtures are not evidence of clinical performance.
- **Connected data:** patient profiles, symptoms, check-ins, reports, clinician records, and device readings require appropriate consent/permissions and hospital privacy/retention procedures before real use. Patient data must never be committed to Git.
- **Licenses and attribution:** original project code uses [Apache-2.0](LICENSE). Third-party packages, Arduino libraries, Wokwi interfaces, datasets, fonts, and hosted APIs retain their own licenses/terms. Dependencies are declared in [requirements](backend/requirements.txt), [dashboard pubspec](dashboard/pubspec.yaml), [patient pubspec](patient_app/pubspec.yaml), firmware headers, and [Wokwi sources](simulation/wokwi/README.md). The [font directory](dashboard/assets/fonts/README.md) documents a proposed bundle; a complete regional font collection is not included. The code license grants no rights to patient data.

## Evaluation & guardrails

Existing tests cover risk rules, ingestion validation, measurement provenance, patient/lab/wellbeing input validation, provisioning helpers, device health, notifications, demo behavior, runtime configuration, and selected Flutter widgets. They do not establish clinical sensitivity/specificity, regulatory compliance, or complete database/provider integration.

```powershell
Set-Location backend
..\.venv\Scripts\python.exe -m unittest discover -s tests -v
Set-Location ../patient_app
flutter pub get
flutter test
Set-Location ../dashboard
flutter pub get
flutter test
```

Baseline verification on 23 October 2026: 53 backend tests, nine patient-app tests, and four dashboard tests passed. Backend tests ran without external-service credentials. A local in-memory smoke check also passed patient listing, synthetic fall ingestion, alert creation, and acknowledgement. Live provider integrations and physical-device accuracy were not verified by these checks.

Safeguards include backend authorization, restricted RTDB access, audit events, source labeling, human review of risk signals, confirmation of extracted lab values, and separation of clinician guidance from patient-reported information. A normal reading does not automatically resolve an alert.

The AI route checks account linkage, bounds input/output, and matches a small English urgent-term list before model calls. Only the message and fixed instructions are sent; clinical records/telemetry are not automatically added, although users can type sensitive information. Requests set `store=false`, and this endpoint does not save chat in the clinical database; this is not a zero-provider-retention claim. Instructions prohibit diagnosis/prescribing and refer concerning questions to the care team. Keyword and prompt safeguards can miss paraphrases, non-English emergencies, hallucinations, and bias. Current AI tests check helpers, not model outputs. Multilingual safety, adversarial prompts, and answer quality still require evaluation.

### AI Impact Statement (under 200 words)

MaatriWatch optionally augments maternal-care education through MaatriCare, an authenticated assistant using the OpenAI Responses API with configurable model selection, defaulting to `gpt-5-mini`. The implementation requests brief answers with bounded output; comparative model evaluation is pending. AI does not diagnose, prescribe, interpret reports, assess wearable safety, or generate clinical alerts. Alerts use deterministic rules.

Demo records and simulator readings are synthetic. No external training dataset or model weights are bundled. Connected patient records require consent and hospital governance; their contents are not automatically sent to the model. Original code uses Apache-2.0; dependencies and APIs retain separate terms.

Guardrails include local English urgent-term responses, account checks, input/output limits, process-local rate limits, educational instructions, and care-team referral. The endpoint requests `store=false` and does not save chat in the clinical database. Keyword coverage, model hallucinations, and multilingual bias remain unresolved risks. Helper tests exist; model-output and emergency-language evaluations remain pending.

The intended benefit is accessible education and clearer follow-up. No measured clinical improvement, validated screening accuracy, or business outcome is claimed.

## Known limitations & risks

- Hardware estimates are unvalidated. Skin/device temperature is not core body temperature; MAX30102 does not measure BP. Fall rules accept qualifying evidence, but the current watch has no validated fall classifier.
- This prototype is not an emergency-response service. Delivery depends on connectivity, configured providers, and staffed care processes; no clinical response-time guarantee is established.
- The wellbeing check-in is not a validated depression questionnaire. The system does not detect PPH, diagnose preeclampsia, prescribe treatment/diets, or interpret labs automatically.
- Report upload and narrow text extraction exist; image OCR, complete clinician attachment review, and production document retention/encryption processes remain incomplete.
- In-memory/demo roles cover a subset of features. Persistent storage, Firebase, Twilio, and OpenAI need separate setup and integration verification.
- Complete local-language translation, validated multilingual AI safety, bundled regional fonts, offline store-and-forward, automatic activity tracking, signed OTA fleet updates, and a full admin interface are not implemented.
- No public demo link, completed clinical validation results, or registered team roster is recorded. Unit/widget tests do not replace physical-device, database, and end-to-end testing.

### Assumptions and trade-offs

A hospital provisions patient accounts/device assignments; patients have app/network access; clinicians own response and follow-up. Wi-Fi is the watch transport; phone Bluetooth pairing is not implemented. PostgreSQL plus RTDB separates durable history from fast live views, at the cost of operating a projection worker. Optional direct-Firebase firmware and debug demos simplify presentation but exercise less than the complete connected workflow.

## Prior work and event development

The starting codebase predates AIBoomi Startup Weekend Kochi. It includes the features above, tests, firmware, synthetic demos, and clinical-feedback notes. The source checkout baseline is commit `71ee2ef`; existing local documentation, sensor-test, and Wokwi additions are also prior work, not weekend achievements. The prior source remote is [Devananda888/MaatriWatch](https://github.com/Devananda888/MaatriWatch); history and authorship are retained.

The handbook requires an existing prototype to be declared at kickoff and the event surprise element to be implemented for judging eligibility. This README records the baseline; it does not establish that organizer disclosure has happened.

| Submission item | Status |
| --- | --- |
| Repository | [Devadathan69/MaatriWatch](https://github.com/Devadathan69/MaatriWatch) |
| Prior prototype declaration | Baseline documented; team must declare it to organizers |
| Weekend core feature / surprise element | Not yet recorded; add actual implementation, commits, and evidence |
| Product demo link | Pending a verified hosted app, video, or presentation |
| Pitch deck (six slides maximum) | Not supplied in this repository |
| AI Impact Statement | Included above |
| Registered team names, roles, contacts | Pending team confirmation |

Future feature research and roadmap choices are deferred to development, as requested. Keep researched proposals separate from shipped functionality, then record the actual weekend work and evaluation results here.

## Team

**Repository maintainer/contact:** [Devadathan69 on GitHub](https://github.com/Devadathan69). Registered participant names, roles, and preferred contacts have not been supplied and must be added before submission. Commit authorship and repository ownership are not a substitute for the registered roster.

## License and secret handling

The repository retains its existing [Apache License 2.0](LICENSE). It permits commercial use, modification, and redistribution and includes an explicit contributor patent grant, with notice and redistribution obligations. This is a reasonable choice for an openly published prototype and commercial follow-on development. It also allows others to reuse the published code; it does not provide commercial exclusivity. See the [official Apache license](https://www.apache.org/licenses/LICENSE-2.0). Respect third-party terms and contributors' rights; this review is not a complete transitive dependency license audit.

The root [`.gitignore`](.gitignore) excludes environment variants, Firebase Admin/service accounts, local firmware secrets, private keys/signing files, local databases/uploads, builds, downloaded dependencies, and scratch/export directories. Placeholder-only `.env.example` and `secrets.example.h` templates remain tracked, along with Dart lockfiles and migration sources.

Ignore rules cannot remove historical secrets or detect every hardcoded credential. Before each push, review staged content and scan the staged export and Git history. If a real secret is committed, revoke/rotate it and clean affected history before publication. Keep patient records and report attachments out of Git.
