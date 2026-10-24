# MaatriWatch

A maternal-care companion for pregnant women and mothers, connected to wearable monitoring and clinician follow-up.

**Team CodeBlooded · AIBoomi Startup Weekend Kochi · 23–24 October 2026**

## Problem statement

Pregnant and postpartum women need a simple way to record concerns, understand report readings, and remember care events between consultations.
Clinicians need a concise history of what patients experienced, including recurring symptoms, severity and changes over time.

## Users & context

- **Pregnant women and mothers:** use the companion, record concerns in Malayalam or English, review reports and food suggestions, and manage reminders.
- **Guardians:** link a verified account to receive a patient's SOS requests on another Android phone.
- **Clinicians:** review hospital-scoped patient readings, alerts, reports, messages and follow-up information.
- **Hospital administrators:** provision patient accounts and manage wearable assignments through authenticated APIs; a complete administration interface is future work.

The intended setting is supervised maternal-care follow-up. This is a working engineering prototype; clinical effectiveness and suitability for unsupervised patient care have not been established.

## Solution overview

MaatriWatch brings a patient companion, longitudinal concern history, report review, guardian support and clinician workflows together. AI helps organise and explain information; patients confirm extracted details, and clinicians remain responsible for medical decisions.

### Current features

| Feature | Implemented behaviour | Current boundary |
| --- | --- | --- |
| Personal companion | English/Malayalam conversation, separately enabled chat history, explicit memories and patient-scoped health context. | Requires OpenAI and opt-in permissions; continuous voice interaction is future work. |
| Speak Your Concern | Record audio and edit its transcript, or add symptoms manually without a paragraph. Confirm onset, frequency, severity and details before saving to persistent history. | AI transcription/organisation needs consent. Audio-file upload was removed; recordings are not retained by the app. |
| Monthly concern report | Brief sections covering experienced symptoms, severity, patterns and major insights, with supporting-report links. | Summarises reported information rather than diagnosing conditions; sharing is optional. |
| Reports and Nourish | Extract PDF/image/text report readings for confirmation, apply supported pregnancy-specific comparison rules, then ask about diet, allergies, dislikes, nausea and other preferences before AI food suggestions. | Offers foods to consider, limit or avoid. No automatic weekly meal schedule; unsupported readings remain inconclusive and clinician review is needed. |
| Event reminders | Record the event, its date/time and notice at the event or an hour, day, three days or week before; persistent inbox and optional Android notifications. | Delivery depends on the worker, connectivity, permissions and host availability. |
| Guardian SOS | Invite up to three guardians using email-bound, one-use codes; verified guardians enable Android notifications and receive a durable SOS inbox. | Guardians receive no medical-report or chat access. Actual two-phone notification delivery remains a device-test item. |
| Consultations | Clinician availability, patient booking/cancellation/rescheduling and appointment reminders. Private Daily video integration exists in source. | **Video is disabled** in the current deployment; booking remains available. |
| Wearable and care team | XIAO ESP32-S3 telemetry, MAX30102 heart-rate/SpO₂ estimates, TMP117 skin-adjacent temperature, MPU6050 motion context, OLED/SOS button; clinician trends, alert actions, notes and messages. | Sensor estimates and fall-related rules are unvalidated; the watch does not measure blood pressure or core body temperature. |

Additional existing workflows include consent controls, care-task updates, confirmed lab entries, a non-diagnostic wellbeing check-in and patient-reported activity. See the [backend architecture](docs/BACKEND_ARCHITECTURE.md) and [clinical feedback notes](docs/clinical_feedback_implementation.md).

### Technology stack and architecture

| Layer | Tools used |
| --- | --- |
| Patient and guardian app | Flutter/Dart, Firebase client SDKs, Firebase Messaging, microphone recording and HTTP |
| Clinician dashboard | Flutter web, Firebase Authentication/RTDB, charts and HTTP |
| API | Python, Flask, Gunicorn, psycopg connection pools and Argon2 device-key hashing |
| Persistent storage | Supabase PostgreSQL, migrations `001`–`014`, tenant-scoped access and audit records |
| Identity and notifications | Firebase Authentication, Realtime Database and Cloud Messaging |
| AI | Server-side OpenAI Responses and audio transcription APIs |
| Hosting | Render Docker service supervising the API, realtime outbox worker and companion/SOS worker |
| Hardware and simulation | Arduino/ESP32 tooling, XIAO ESP32-S3, sensor libraries, HTTP simulator and Wokwi |

```text
Patient / guardian Android app     Clinician Flutter dashboard
                 \                    /
                  Firebase identity + HTTPS
                            |
                     Flask API on Render ---- OpenAI APIs
                            |
                   Supabase PostgreSQL
                  /                    \
      Realtime outbox worker     Companion / SOS worker
               |                         |
        Firebase RTDB             Firebase Messaging
               |                         |
       Live reading views          Phone notifications
```

The watch or HTTP simulator sends authenticated telemetry to the API. PostgreSQL stores durable records; Firebase RTDB provides live projections. Database access remains server-side.

### Product demo

**Product demo video, hosted user interface or presentation: pending — the team will add the link.**

The [hosted API status](https://maatriwatch-api.onrender.com/healthz) and [readiness endpoint](https://maatriwatch-api.onrender.com/readyz) are live. These are backend checks, **not a product demo showing the prototype in action**.

Suggested demo flow: sign into the patient app, record and save a concern, show its history/monthly summary, review a confirmed report and AI food suggestions, create an event reminder, then demonstrate a linked guardian's SOS inbox/notification. Use synthetic patient data. Signed-in phone setup is documented in [phone testing](docs/PHONE_TESTING.md).

### Prior work and weekend development

This project builds on an existing prototype. Wearable telemetry, clinician workflows, patient follow-up and synthetic demos predate the event; the source baseline is commit `71ee2ef`. The prior source repository is [Devananda888/MaatriWatch](https://github.com/Devananda888/MaatriWatch), with history and authorship retained.

Weekend work added the companion (`2ab7aee`), bilingual concern history/summaries (`dfa1db7`), report/nutrition workflows (`582a0fa`) and consultation integration (`f9c5001`). Later updates refined the patient flows and guardian SOS (`6ee3e68`), deployed the HTTPS service (`8338eca`) and fixed database recovery during symptom saving (`46f478c`). See the [implementation plan](docs/IMPLEMENTATION_PLAN.md).

Organizer confirmation of the prior-prototype declaration and required surprise element is still pending in the project record; this README does not establish judging eligibility.

## Setup & run

### 1. Install dependencies and configure the backend

Use PowerShell from the repository root. Requirements: Git, Python 3.11+, Flutter/Dart compatible with the lockfiles, and Android tooling for phones or Chrome for web demos.

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r backend/requirements.txt
if (-not (Test-Path backend/.env)) { Copy-Item backend/.env.example backend/.env }
```

Fill the ignored `backend/.env` with the PostgreSQL TLS connection, Firebase project/RTDB settings, Firebase Admin JSON, application secret and allowed web origins. OpenAI is required for AI features. Keep `DEMO_MODE`, `DEMO_IN_MEMORY` and `ALLOW_UNVERIFIED_PATIENT_DEMO` false for signed-in use. Leave `DAILY_API_KEY` empty while video is skipped.

Firebase email/password sign-in must be enabled. Patient accounts need verified email and an active database patient link; guardian accounts are linked using the patient's private invitation code. Full setup and provisioning steps are in [backend deployment](backend/DEPLOYMENT.md).

### 2. Run the connected backend locally

Apply migrations to the intended database, then start the API:

```powershell
Set-Location backend
..\.venv\Scripts\python.exe scripts/apply_migrations.py
..\.venv\Scripts\python.exe -m flask --app 'app:create_app()' run --host 127.0.0.1 --port 8000 --no-reload
```

From `backend/`, start each worker in its own additional terminal:

```powershell
..\.venv\Scripts\python.exe -m app.realtime_worker
```

```powershell
..\.venv\Scripts\python.exe -m app.companion_worker
```

Migrations run as a controlled setup step, not on each web request. Use a disposable database for synthetic demos. The [portable deployment guide](deploy/README.md) covers Docker/HTTPS hosting; [render.yaml](render.yaml) defines the free Render configuration.

### 3. Run the Android app and clinician dashboard

Create the ignored `patient_app/firebase-config.local.json` using the public client settings listed in the [patient app guide](patient_app/README.md). Set `API_BASE_URL` to `https://maatriwatch-api.onrender.com/api/v1` for the current hosted environment, with demo mode false. Server credentials must never be included in this file.

```powershell
Set-Location patient_app
flutter pub get
flutter run --debug -t lib/main.dart -d DEVICE_ID --dart-define-from-file=firebase-config.local.json
```

Use `flutter devices` to find the device ID. Install the same build on patient and guardian phones one at a time; the hosted build then works over Wi-Fi/mobile data without USB. For a local API, use the explicit emulator/USB configuration in [phone testing](docs/PHONE_TESTING.md).

For clinician web setup, Firebase client fields and launch commands, follow the [dashboard guide](dashboard/README.md). The clinician's web origin must be included in the backend's CORS configuration.

### 4. Run a synthetic demonstration or hardware prototype

The [companion demo guide](docs/COMPANION_DEPLOYMENT.md) provides a debug-only local demonstration. From the root, `.\.venv\Scripts\python.exe backend/scripts/run_local_demo.py` starts its synthetic backend; AI calls require explicit opt-in. Its data and role bypasses must not be used for production accounts.

Hardware setup, firmware dependencies and local secret templates are in the [XIAO watch guide](firmware/xiao_watch_prototype/README.md). The [Wokwi demonstration](simulation/wokwi/README.md) and [HTTP simulator](backend/scripts/simulate_device.py) use synthetic readings. The optional direct-Firebase watch transport updates live readings but bypasses the default database/alert pipeline.

## Models & data

| Model or method | Purpose and choice |
| --- | --- |
| `gpt-5-mini` | Currently configured for companion replies, structured extraction, concern summaries and food explanations. Used to prototype conversational and structured-output tasks with a small model; comparative quality/cost evaluation is pending. |
| `gpt-transcribe` | Currently configured for recorded English/Malayalam transcription. Transcripts are editable and require review; multilingual accuracy has not been established. |
| Deterministic rules | Versioned report comparisons, alert rules, reminder scheduling, source/quote checks and food exclusion/allergen checks constrain the AI workflows. No locally trained diagnostic classifier is included. |

Model names are configurable through server environment variables. No local model weights, fine-tuning dataset or retrieval corpus is bundled. Neysa's event quickstart provides separate model inference endpoints; this deployment currently uses OpenAI.

**Data provenance:** demo stores, seed scripts, simulators and automated tests use synthetic examples. No external clinical dataset is bundled. Connected records originate from patients, uploaded reports, wearable measurements and clinician entries, with provenance and consent controls. Confirmed records persist in PostgreSQL. Recorded audio is sent for transcription and is not retained by the app; retention of other uploaded documents depends on the workflow. OpenAI Responses calls set `store=false`; provider retention terms still apply.

**Licenses and attribution:** project code retains [Apache License 2.0](LICENSE). Third-party libraries, fonts, hardware tooling and hosted providers retain their own licenses/terms; see [backend requirements](backend/requirements.txt), [patient dependencies](patient_app/pubspec.yaml), [dashboard dependencies](dashboard/pubspec.yaml) and firmware sources. No license to patient data is granted by the code license.

**Secret handling:** [`.gitignore`](.gitignore) and the [Docker context allowlist](backend/.dockerignore) exclude private environment files, Firebase Admin credentials, signing keys, firmware secrets, patient exports and build output. Keep actual keys and health records out of Git; review and scan outgoing changes before publication.

## Evaluation & guardrails

### Recorded verification

As of 24 October 2026: **99 backend tests, 21 patient-app tests and four dashboard tests passed**, with clean Flutter analysis recorded for both apps. These are software checks rather than clinical validation.

- Isolated Supabase checks covered persistent records, guardian email binding, invitation reuse prevention, tenant/role isolation, revocation and reminder/food storage. Firebase verification and notification sends were mocked inside those isolated checks.
- A Malayalam concern saved, appeared in history and persisted on a fresh Supabase connection after a simulated health-check timeout. The synthetic fixture was removed afterward.
- Live OpenAI synthetic checks exercised chat, symptom/report extraction, audio transcription, concise monthly summaries and preference/report-aware food guidance. These smoke checks do not establish model accuracy or clinical benefit.
- Render readiness and unauthenticated rejection were verified. Actual two-phone push delivery and two-party video calls remain device/provider checks.

Run credential-isolated backend tests from the root:

```powershell
.\.venv\Scripts\python.exe backend/scripts/run_tests.py
```

Run Flutter tests and analysis from each app directory after `flutter pub get`:

```powershell
flutter test
flutter analyze
```

### Guardrails

- Verify Firebase identity, email and hospital/patient linkage; enforce scoped database access and audit writes. Public client roles cannot directly access the 33 application tables.
- Use separate consent for AI processing, memory, health context and sharing. Guardians receive SOS requests without report/chat access.
- Treat uploaded text and documents as untrusted data; constrain model output with schemas, source quotes/IDs and patient confirmation of extracted values.
- Keep clinical comparisons and food exclusions deterministic. Unclear units, unsupported tests, missing context or urgent values prevent confident food guidance; clinician review remains necessary.
- Provide urgent-language handling and readable service failures. AI unavailability does not fabricate a reply, report interpretation or fallback diet plan.
- Next evaluation should compare English/Malayalam outputs against clinician-reviewed cases for omissions, unsupported claims, bias and unsafe reassurance, alongside notification delivery tests.

### AI Impact Statement (200 words maximum)

MaatriWatch augments maternal-care conversations, English/Malayalam transcription, symptom and report extraction, monthly concern summaries, and preference-aware food explanations. The configured models are `gpt-5-mini` for conversational/structured tasks and `gpt-transcribe` for audio. They support rapid prototyping; comparative clinical and multilingual evaluation is pending.

Inputs come from synthetic fixtures or consented patient, wearable and clinician records. No external clinical dataset or fine-tuned model is bundled. Code uses Apache-2.0; dependencies and providers retain their terms. Confirmed records persist, and provider retention policies apply.

Guardrails include verified identity, scoped context, separate consent, output schemas, source checks, deterministic comparisons and food exclusions, and confirmation before saving extracted information. AI does not diagnose conditions or prescribe treatment. Software and integration checks cover key failure paths; planned clinician-reviewed English/Malayalam cases will examine omissions, bias and unsafe reassurance.

Expected outcomes are better continuity for mothers, clearer consultation histories and a potential hospital follow-up workflow. Clinical benefit, business viability and continuous emergency delivery have not been demonstrated.

## Known limitations & risks

- **Availability:** Render Free sleeps after 15 minutes without inbound traffic and can take about a minute to wake. Workers also stop during sleep; reminders and SOS have no continuous-delivery guarantee. See [Render's limits](https://render.com/docs/free).
- **Clinical scope:** wearable estimates, report thresholds and food suggestions are not a validated medical product. The watch does not measure blood pressure/core temperature; no validated fall classifier, PPH detection or PPD diagnosis is provided.
- **AI reliability:** extraction, multilingual understanding and summaries can omit or misinterpret information. Confirmation and clinician review remain required; schema checks do not prove medical correctness.
- **Feature status:** video is disabled. Full localization, offline store-and-forward, automatic activity tracking, signed fleet OTA updates, continuous voice interaction and a complete admin interface are future work.
- **Remaining validation:** actual guardian push delivery, clinical outcomes, nutrition adequacy, production retention/security operations and a distributable privately signed release need further work.
- **Submission gaps:** the product demo link and pitch deck have not been supplied; organizer confirmation of prior-work disclosure and surprise-element completion is not recorded.

### Assumptions and trade-offs

Hospitals provision patient access and clinicians own follow-up/escalation. Patients and guardians have internet access. PostgreSQL stores history while Firebase RTDB supplies live views, requiring a projection worker. Wi-Fi is the watch transport; phone Bluetooth pairing is not implemented. Render Free enables no-card testing at the cost of sleeping workers. Debug demos simplify presentation using synthetic state and cover less than the full connected workflow.

## Team

**Team name: CodeBlooded**

| Member | Role |
| --- | --- |
| Devadathan M R | Hardware and backend |
| Shifa Usman | Flutter app |

**Team/repository contact:** [Devadathan69 on GitHub](https://github.com/Devadathan69). Additional preferred contact details can be added by the team.

**Submission repository:** [Devadathan69/MaatriWatch](https://github.com/Devadathan69/MaatriWatch). Product demo link will be added when supplied; the separate pitch deck must contain no more than six slides.
