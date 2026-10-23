# MaatriWatch clinical-feedback implementation

This document records how the gynaecologist and dietician feedback was
implemented on 11 September 2026. It is a product-safety handoff, not a
clinical protocol or a substitute for local hospital governance.

## Implemented now

| Feedback | Product behaviour |
| --- | --- |
| Medical-report upload | Patient can choose a PDF, JPEG, or PNG up to 4 MB; the API validates the magic bytes, stores it under the patient/hospital boundary, never returns blobs in list responses, and audits the upload. Values remain confirmation-first. |
| GDM and thyroid follow-up | Existing confirmed 75 g OGTT and thyroid entry is preserved. A result is always pending clinician review. The clinician dashboard can publish individualised GDM, thyroid, activity, or wellbeing guidance. The patient app labels it as clinician-approved rather than an automated diet. |
| Doubt resolution | Patient and assigned care team can exchange hospital-scoped, asynchronous messages. The UI says it is non-emergency, preserves the message in the care record, and never reveals a clinician's private phone number. |
| PPD / perinatal wellbeing | A PPD-awareness section appears before the twice-weekly five-question support check-in. A positive immediate-safety answer creates an urgent clinical alert; the optional, consented guardian WhatsApp path remains best-effort. The short check-in is explicitly not a depression score or a modified EPDS. |
| Walking / activity | Morning/evening patient-reported walking can be recorded only after a clinician sets activity clearance. The app does not claim steps from the MPU6050. Future wearable-classified activity needs a confidence value and validation before it can be displayed as context. |
| Activity-aware interpretation | Telemetry accepts a quality-qualified activity context (`resting`, `walking`, or `exercising`) only with classifier confidence. It is descriptive only: it cannot suppress a clinical alert, SOS, or fall pathway. There is currently no heart-rate-only clinical alert rule. |
| Personalised profile | Previous hypertension, GDM/diabetes history, pregnancy stage, pregnancy complications, other conditions, allergies, and medications are collected as **patient-reported**. Clinicians have a separate confirmed-history/clearance record; only that confirmed layer is appropriate for clinical workflow personalisation. |
| Alert wording | The backend severity model maps to patient-facing language: no active alert = Normal; `info` = Recheck required; `warning` = Clinical review recommended; `critical` = Urgent medical attention required. It never says “preeclampsia detected.” |
| Accuracy-validation log | Clinicians can record a paired wearable/reference-device observation with device label, time, absolute error, and percentage error. This is labelled prototype comparison data, not clinical validation. |
| PPH scope | PPH telemetry ingestion, simulator scenario, and risk rule are removed from the wearable MVP. Immediate post-delivery observation belongs to the clinical setting. |

## Clinical choices behind the design

- ACOG recommends standardised, validated perinatal depression/anxiety screening at the initial prenatal visit, later in pregnancy, and postpartum, with systems for assessment, treatment, monitoring, and follow-up. The app therefore keeps its five questions as a support check-in and routes validated screening to a governed clinician workflow rather than claiming that an altered five-question form is EPDS or PHQ-9. [ACOG perinatal screening](https://www.acog.org/programs/perinatal-mental-health/patient-screening)
- Guidance for diabetes in pregnancy should be individualised, including diet, activity, and weight management, with specialist input where useful. The app consequently does not create a diet or diagnose GDM from uploaded values; a clinician/dietitian must publish personalised guidance. [WHO diabetes-in-pregnancy recommendations](https://www.ncbi.nlm.nih.gov/books/NBK619436/)
- Regular activity can be appropriate in an uncomplicated pregnancy, but a clinical evaluation is needed before recommending an exercise programme when there are complications or contraindications. The app gates activity logging behind clinician clearance and repeats stop/seek-advice language. [ACOG activity guidance](https://www.acog.org/clinical/clinical-guidance/committee-opinion/articles/2020/04/physical-activity-and-exercise-during-pregnancy-and-the-postpartum-period)

## Additional improvements recommended before a clinical launch

1. Obtain hospital approval for exact alert rules, response ownership, acknowledgement and escalation time targets, and a 24/7 emergency escalation procedure.
2. Complete a privacy impact assessment: retention period, report-document encryption/key management, access audit review, breach process, backups, and patient deletion/correction workflow.
3. Connect the report pipeline to an approved OCR/document service only after a data-processing agreement, language accuracy testing, confidence thresholds, and mandatory patient confirmation. Scanned images must not become an automatic diagnosis.
4. Choose licensed/approved local-language versions of EPDS or PHQ-9 with clinical governance, scoring ownership, immediate self-harm response, and referral capacity before embedding a validated questionnaire.
5. Add clinician UI for reviewing report attachments, profile history, lab results, validation-observation summaries, and message-service-level queues. The secure API foundations are present; operational workflow still needs hospital configuration.
6. Validate the activity classifier against a labelled dataset before displaying automatic walking minutes or using activity as more than descriptive context.
7. Run a prospective validation protocol comparing PPG heart rate/SpO2 and TMP117 skin-adjacent temperature against named reference devices across fit, skin tones, motion, ambient light, battery level, and network conditions. Do not claim clinical accuracy from a small pilot log.
8. Provide Malayalam/English accessibility review, plain-language emergency wording, larger text support, low-connectivity behaviour, and tested notification consent/opt-out flows.

## Explicit scope limits

- The MAX30102 is only shown as PPG-derived heart rate/SpO2; it does not estimate blood pressure.
- TMP117 remains device/skin-adjacent temperature, not core body temperature.
- Blood pressure appears only from a validated cuff or clinician-entered source.
- No automatic diagnosis, medication change, diet prescription, depression diagnosis, or “normal/abnormal” lab conclusion is generated.
- A care message and guardian WhatsApp notification are not emergency services; in danger, the patient must seek emergency care immediately.

## Deployment sequence

1. Apply migration `009_clinical_followup_and_validation.sql` using `backend/scripts/apply_migrations.py`.
2. Set `MAX_CONTENT_LENGTH=4000000`, `REPORT_UPLOAD_MAX_BYTES=4000000`, and `TELEMETRY_MAX_CONTENT_LENGTH=16384` in the backend environment, then redeploy the API.
3. Run `flutter pub get` in `patient_app` and `dashboard`, then rebuild/deploy both clients.
4. Configure clinician access, patient consent, approved response process, and (only if opted-in) Twilio WhatsApp before enabling guardian notifications.
