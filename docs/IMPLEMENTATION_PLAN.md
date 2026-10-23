# Maternal companion implementation plan

Requested on 23 October 2026. Build on baseline `66bdf6d`, preserve prior authorship, and deliver four independently tested commits to GitHub `main` in priority order. The existing local empty legacy firmware edit is outside this work.

## Product goal

Make MaatriWatch a warm, always-available companion for pregnancy and motherhood, with continuity between conversations, recorded concerns, report follow-up, nutrition support, and access to the human care team. “Always available” means a hosted API plus a continuously running reminder worker, not a continuously executing language model or guaranteed clinical monitoring.

## Phase 1 — Personal companion and reminders

Status: implemented. 59 backend tests, 11 patient widget tests, and four dashboard tests pass; patient analyzer clean. Live PostgreSQL/provider deployment is not verified on this machine (Docker daemon is unavailable).

- Persistent patient/hospital-scoped preferences, chat history, explicit memories, reminders, and notification inbox.
- Separate controls for storing conversation memory and sending uploaded health context to AI; inspect/delete memories and conversation history.
- Context includes sourced patient-reported and clinician-confirmed information, recent measurements with timestamps, and lab follow-up. Uploaded documents are untrusted data, not model instructions.
- Supportive English/Malayalam conversation; clear AI identity, no exclusivity/dependency messaging, no diagnosis or replacement of human PPD care.
- User-created reminders with timezone-aware recurrence; a worker creates idempotent inbox notifications. Availability requires hosting and the worker to be deployed.
- Warm companion screen linked from the existing home/help flow; API failure states remain explicit.
- Acceptance: patient isolation, consent controls, deletion, reminder scheduling/deduplication, urgent-language response, chat/provider-failure tests; existing suites pass. Commit and push.

## Phase 2 — Speak Your Concern and longitudinal summaries

Status: implemented. Bilingual extraction, confirmation, audio validation, repeated concerns, timezone boundaries, sharing, source-citation rejection, and scheduled summary opt-in have automated coverage. Live microphone/provider testing remains pending.

- Malayalam/English recording/upload and editable transcription; typed entry remains available when recording/provider access fails.
- Schema-constrained extraction of symptoms, onset, frequency, severity, and user language, with source text retained and user confirmation before saving.
- Repeated concerns remain separate dated occurrences with common symptom identifiers. An entry is not silently turned into a diagnosis.
- Monthly summaries combine deterministic counts/dates/severity changes with evidence-linked narrative; report counts derive from stored entries, never model guesses.
- Patient history and clinician summary view, with explicit sharing and review status.
- Acceptance: bilingual examples, malformed/invented model fields, confirmation, cross-patient boundaries, monthly timezone boundaries, recurring symptoms, and provider failures. Commit and push.

## Phase 3 — Reports and visual nutrition planning

Status: implemented. 72 backend, 15 patient, and four dashboard tests pass; both analyzers clean. The running web UI was visually inspected with synthetic data. Real OCR/model accuracy, native-device behavior, nutrient adequacy, and clinical validation remain unverified.

- PDF/image extraction through a configurable multimodal provider, with document-size/type checks, explicit processing consent, extracted value/unit/reference/source evidence, and a mandatory correction/confirmation screen.
- A deterministic, versioned interpretation layer compares supported tests using source-defined protocols and pregnancy context. Unsupported tests, unclear units, absent gestational information, and missing assay-specific ranges remain inconclusive.
- Distinguish within-range, high/low, and clinician-review-required results. No blanket “everything is normal” conclusion from a partial report.
- Build culturally familiar meal-plan drafts from an explicit ingredient/allergen catalog. Respect diet preferences, allergies, report findings, clinician restrictions, and pregnancy food safety. Do not infer medication changes or claim a clinically optimal prescription.
- Original warm food illustrations, day/meal navigation, portions, ingredients, swaps, shopping list, and clinician approval status. Inspiration: meal cards and planning structure, not copied assets or weight-loss UI.
- Clinician review before a generated draft is labelled approved/personalised clinical guidance.
- Acceptance: extraction validation, boundary/unit/protocol cases, unknown context, allergy exclusion, safe swaps, clinician approval controls, responsive UI/widget tests. Commit and push.

## Phase 4 — Booking and private video consultations

Status: implemented. 79 backend tests, 17 patient widget tests, and four dashboard tests pass; both analyzers clean. Android debug APK and patient web release builds succeeded. Browser booking with synthetic data was verified. Actual PostgreSQL/provider calls, native camera/microphone behavior, and push delivery remain staging/device checks. Optional Android FCM delivery is also integrated with the reminder worker.

- Clinician publishes hospital-scoped availability. Patient books a slot with timezone-aware confirmation; database constraints prevent double booking.
- Both sides see upcoming visits; cancellation/rescheduling releases availability with audit history.
- Server creates a private Daily room and short-lived, appointment-bound participant tokens; only the booked patient and assigned clinician can join within the permitted time window.
- In-app video surface, camera/microphone permission states, no automatic recording, no public room links, and explicit provider-unconfigured failure states.
- Appointment reminders reuse the worker/inbox foundation. Clinicians can open the concern summary before a visit.
- Acceptance: concurrent booking, patient/clinician authorization, cancellations, join-window checks, token scope/expiry, provider failures, and full regression tests. Commit and push.

## Delivery and verification

At each phase: apply the new migration to a disposable database, run meaningful domain/API tests and relevant Flutter tests/analyzer, exercise the feature with synthetic data, update this plan and README, scan the outgoing files/history for secrets, commit, push to `origin/main`, and verify the remote SHA. Provider calls use server-only environment keys. Real patient data must not be used for development tests.

Unit and mock-provider tests establish implementation behavior, not medical accuracy or a verified cloud deployment. Record any integration that cannot be exercised because credentials, hardware, native permissions, or hosting are unavailable. Do not claim those integrations are live.

## Research and design sources

- [OpenAI conversation state](https://developers.openai.com/api/docs/guides/conversation-state): application-managed bounded history with server storage under patient control.
- [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs): strict JSON schemas plus independent domain validation.
- [OpenAI transcription](https://developers.openai.com/api/docs/guides/speech-to-text): recorded audio transcription; configurable current transcription model, original-language text, user correction.
- [WHO hyperglycaemia in pregnancy](https://www.who.int/publications/i/item/WHO-NMH-MND-13.2): explicitly identify 75 g OGTT and diagnostic protocol; do not mix screening and treatment targets.
- [American Thyroid Association](https://www.thyroid.org/hypothyroidism-in-pregnancy/): pregnancy/trimester-specific thyroid interpretation and clinician involvement.
- [US pregnancy nutrition guidance](https://health.gov/sites/default/files/2021-12/DGA_Pregnancy_FactSheet-508.pdf): variety and pregnancy/breastfeeding nutrition, not weight-loss goals.
- [Eat This Much](https://www.eatthismuch.com/): preference-aware meal planning, meal navigation, and shopping lists as UI inspiration; no assets copied.
- [Daily private rooms](https://docs.daily.co/reference/rest-api/rooms/create-room) and [meeting tokens](https://docs.daily.co/reference/rest-api/meeting-tokens/create-meeting-token): server-controlled room access, participant permissions, and expiry.

## Final submission updates

After implementation, replace baseline-only wording with a dated distinction between prior work and these weekend features. Keep the demo link/team roster pending until actual values are available. Include deployment instructions, environment templates, required worker processes, test results, provider limitations, and a revised AI Impact Statement under 200 words.




## Phase commits

| Phase | Published commit |
| --- | --- |
| Personal companion | `2ab7aee` |
| Speak Your Concern | `dfa1db7` |
| Reports and nutrition | `582a0fa` |
| Consultation and reminder delivery | This phase-4 commit |

## Local phone setup follow-up

The 24 October patient-feedback update below supersedes the earlier weekly meal-planning and paragraph-first concern-entry design.

The normal Firebase Android application was registered and built after phase delivery. Local PostgreSQL synthetic API/storage checks and a database-restart persistence check passed. On 24 October 2026, the existing Supabase database was backed up, migrated through `013`, and selected by the API and both workers through the TLS Session pooler. Original cloud records were preserved; the isolated synthetic phone-test profiles and feature records were copied with their Firebase links intact. Public client database access is denied. Firebase Admin credentials were verified, and the backend suite passes 83 tests. The local database remains a fallback. See [phone testing and remaining device checks](PHONE_TESTING.md); physical-phone password sign-in and native push delivery remain pending until the phone is reconnected.

## Patient feedback implementation — 24 October 2026

- Guardian Android mode, verified-email private linking, durable SOS inbox/push queue, retries and revocation. Migration `014` protects all four new tables from public client roles.
- Removed the redundant care-team symptom button and audio-file upload. Manual entry starts with symptom fields; recorded entry provides an editable transcript and AI organisation.
- Fixed the old global 16 KB upload setting and contextual upload errors. Telemetry retains its own 16 KB limit.
- Monthly reports use short sections for experiences, severity, patterns and major insights. Supporting-report links hide raw record IDs.
- Reminders capture the event name/date/time and at-event, one-hour, one-day, three-day or one-week notice.
- Replaced weekly meal generation with a questionnaire and AI food suggestions/limit/avoid explanations. Report confirmation, allergy exclusions and clinician review remain enforced.
- Verification: 92 backend tests, 17 patient tests, four dashboard tests; real Supabase and live synthetic OpenAI checks passed. Guardian FCM sends were mocked; two-phone delivery remains a device check.
