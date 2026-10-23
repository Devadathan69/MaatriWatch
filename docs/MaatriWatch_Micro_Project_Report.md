# MaatriWatch: IoT Maternal Health Monitoring System

## Micro Project Report

**Project title:** MaatriWatch – A Connected Wearable and Digital Maternal-Care Platform  
**Project type:** IoT micro project / healthcare technology prototype  
**Prepared by:** ______________________________  
**Team members:** _____________________________  
**Institution:** ________________________________  
**Department:** ________________________________  
**Academic year:** 2026–2027  
**Date of submission:** _________________________

> **Prototype and clinical-safety note:** MaatriWatch is an engineering prototype for remote maternal-care support and demonstration. MAX30102 measurements are PPG-derived wearable estimates, TMP117 is a device or skin-adjacent temperature sensor, and blood pressure must come from a validated cuff or clinician-entered source. The prototype is not a diagnostic device and must not replace clinical examination or emergency services.

---

## Abstract

MaatriWatch is an Internet of Things (IoT) system designed to support maternal monitoring between hospital visits. The project combines a compact wearable prototype with an Android patient application, a web-based clinician dashboard, a Flask backend, PostgreSQL storage, and Firebase Authentication and Realtime Database services.

The wearable prototype is built around a Seeed Studio XIAO ESP32-S3 microcontroller. A MAX30102 optical sensor provides photoplethysmography (PPG)-derived heart-rate and SpO₂ estimates, a TMP117 provides device or skin-adjacent temperature, and an MPU6050 provides motion context. An OLED gives the wearer immediate feedback, while a push button provides an SOS input. The device connects to Wi-Fi and sends authenticated telemetry to the MaatriWatch cloud service. For a short prototype demonstration, an opt-in direct Firebase transport can publish the latest live reading to an existing Firebase Realtime Database node.

The software platform separates durable clinical records from low-latency live status. PostgreSQL stores users, patients, devices, telemetry history, alerts, audit records, care tasks, messages, reports, and follow-up data. Firebase Realtime Database acts as a live projection for authorized patient and clinician views. Firebase Authentication identifies users, while backend role and patient-link checks control access. The patient application presents current readings, device status, care-plan actions, safety guidance, laboratory follow-up, wellbeing check-ins, and communication with the care team. The clinician dashboard provides patient lists, live readings, alerts, trends, clinical notes, device assignments, and patient messaging.

The project demonstrates a complete IoT-to-application data path and establishes a foundation for future clinical validation, stronger device provisioning, activity-aware interpretation, secure deployment, and integration with hospital workflows.

**Keywords:** Internet of Things, maternal care, wearable device, ESP32-S3, MAX30102, TMP117, MPU6050, Firebase, PostgreSQL, Flutter, remote monitoring, patient safety.

---

## Contents

1. [Introduction](#introduction)
   1. [Motivation](#motivation)
   2. [Problem statement](#problem-statement)
   3. [Objectives](#objectives)
2. [Literature survey](#literature-survey)
3. [Proposed architecture](#proposed-architecture)
4. [Hardware components](#hardware-components)
5. [Software components](#software-components)
6. [Working principle](#working-principle)
7. [Deployment](#deployment)
8. [Results and discussions](#results-and-discussions)
9. [Cost, advantages, challenges, and future scope](#cost-advantages-challenges-and-future-scope)
10. [Conclusion](#conclusion)
11. [References](#references)
12. [Appendix: code snippets](#appendix-code-snippets)

---

## Introduction

### Motivation

Pregnancy and the postpartum period require regular observation, timely communication, and easy access to care teams. Hospital visits provide high-quality clinical assessment, but readings and symptoms between visits may not be visible to clinicians. A low-cost connected wearable can help collect supportive observations, identify missing or stale data, and provide a structured way for patients to communicate concerns.

The motivation behind MaatriWatch is to connect three parts of care:

1. **The mother and wearable:** simple, calm, and understandable feedback.
2. **The patient application:** readings, safety guidance, tasks, reports, wellbeing support, and questions.
3. **The care team:** current patient state, history, alerts, messages, and audit-friendly records.

### Problem statement

Existing low-cost sensor prototypes often stop at displaying values locally. They may not provide secure patient identity, device assignment, historical storage, role-based access, stale-data handling, clinician workflows, or a clear distinction between a sensor estimate and a clinical measurement. MaatriWatch addresses this systems problem by combining embedded sensing, secure communication, structured data storage, patient software, and clinician software in one prototype platform.

### Objectives

The main objectives are:

- Develop a compact wearable prototype using readily available components.
- Measure PPG-derived heart rate and SpO₂ when the finger is correctly positioned.
- Measure device or skin-adjacent temperature using TMP117.
- Record motion context and an SOS button event.
- Show clear readings and measurement status on an OLED.
- Send authenticated telemetry over Wi-Fi.
- Display live readings in the patient application and clinician dashboard.
- Store durable telemetry, alerts, and audit data in PostgreSQL.
- Use Firebase Authentication for identity and Firebase Realtime Database for authorized low-latency live projections.
- Provide patient safety actions, care-plan tasks, report follow-up, wellbeing check-ins, and care-team messaging.
- Build a foundation for later validation against clinically approved devices.

---

## Literature survey

### Wearable photoplethysmography

PPG sensors illuminate tissue and measure changes in reflected light caused by pulsatile blood flow. The MAX30102 contains red and infrared LEDs and a photodetector. Heart-rate estimation generally uses the periodicity of the PPG waveform, while SpO₂ estimation uses the relationship between red and infrared optical signals. Accuracy depends on contact pressure, skin characteristics, motion, ambient light, sampling configuration, and signal quality.

Therefore, MaatriWatch labels these measurements as **PPG-derived heart rate** and **PPG-derived SpO₂**. They are not presented as a diagnostic result. The firmware rejects or clears readings when contact or signal quality is insufficient.

### Temperature measurement

TMP117 is a high-accuracy digital temperature sensor. When placed near the wrist or skin, the measurement is affected by enclosure design, ambient conditions, contact pressure, airflow, and heat generated by electronics. It is consequently labelled **device / skin-adjacent temperature** in the application and is not treated as core body temperature or a fever diagnosis.

### Motion sensing and activity context

The MPU6050 combines a three-axis accelerometer and gyroscope. It can provide orientation and movement context, but raw accelerometer data alone should not be claimed to be a clinically validated fall detector or step counter. MaatriWatch stores motion context separately from clinical alerts and reserves activity classification for future validation.

### Blood pressure limitations

Blood pressure requires validated pressure measurement, normally using an appropriately sized cuff or an approved clinical device. A MAX30102 alone does not provide validated systolic and diastolic blood pressure. MaatriWatch therefore accepts blood pressure only when the source is explicitly marked as a validated cuff, validated external device, or clinician-entered value. PPG-based blood-pressure estimation is intentionally outside the current clinical claims of this project.

### Digital maternal-care platforms

Digital maternal-care systems commonly combine vital-sign observation, reminders, education, symptom reporting, escalation, and clinician communication. The important engineering requirements are not only sensor measurement but also identity, consent, auditability, data freshness, role-based access, reliable notification, and safe interpretation. MaatriWatch follows this systems approach by separating the live overlay from the durable clinical record.

### Research and technical sources reviewed

The project design is informed by research on PPG and cuffless blood-pressure estimation, MAX30102 application notes, TMP117 and MPU6050 datasheets, Firebase security guidance, Flutter application architecture, and maternal-care clinical guidance. Research results are used to identify limitations and validation requirements, not to make unsupported clinical claims.

---

## Proposed architecture

### High-level architecture

```text
+---------------------------+
| MaatriWatch wearable      |
| XIAO ESP32-S3             |
| MAX30102 | TMP117 | MPU  |
| OLED | SOS button        |
+-------------+-------------+
              |
              | Wi-Fi / HTTPS
              v
+---------------------------+
| Flask API                 |
| Authentication, RBAC,     |
| telemetry validation,     |
| alerts, patient APIs      |
+-------------+-------------+
              |
       +------+------+
       |             |
       v             v
+--------------+  +------------------+
| PostgreSQL   |  | Firebase RTDB    |
| system of    |  | live projection  |
| record       |  | latest status    |
+------+-------+  +--------+---------+
       |                   |
       v                   v
+--------------+  +------------------+
| Patient app  |  | Clinician web    |
| Flutter      |  | dashboard        |
| Android      |  | Flutter web      |
+--------------+  +------------------+
```

### Data responsibilities

**Wearable:** samples sensors, performs quality checks, produces normalized telemetry, shows local status, and sends an SOS event.

**Flask API:** authenticates devices, validates payloads, enforces idempotency, evaluates safety rules, writes durable records, and publishes authorized live projections.

**PostgreSQL:** source of record for users, hospitals, patients, devices, vital readings, alerts, messages, reports, care plans, audit logs, and validation observations.

**Firebase Authentication:** identifies patient and clinician accounts and provides ID tokens.

**Firebase Realtime Database:** low-latency projection of the newest authorized live reading and alert state. It is not the durable clinical history.

**Patient app:** authenticated Android companion for patient-facing readings, tasks, safety actions, reports, check-ins, and care-team communication.

**Clinician dashboard:** hospital-scoped patient and alert management, trends, notes, device assignment, messages, and review workflows.

### Identity and assignment model

The intended lifecycle is:

1. A hospital administrator creates or imports the patient profile.
2. A Firebase Authentication account is created for the patient.
3. The Firebase UID is linked to `app_users` and `patients.user_id` in PostgreSQL.
4. The device is assigned to the patient in the device record.
5. Firebase access projections allow the patient to read only their own live-vitals leaf.
6. The patient signs in using the hospital-issued account.
7. When the device is returned, the hospital can deactivate the assignment and provision it for another patient.

---

## Hardware components

| Component | Function | Interface / connection |
|---|---|---|
| Seeed Studio XIAO ESP32-S3 | Microcontroller, Wi-Fi, firmware execution | 3.3 V logic; USB-C for programming |
| MAX30102 | Red/IR optical PPG for heart rate and SpO₂ estimates | I²C; address normally `0x57` |
| TMP117 | Device or skin-adjacent temperature | I²C; address normally `0x48` |
| MPU6050 | Accelerometer and gyroscope for movement context | I²C; normally `0x68` or `0x69` |
| Small OLED | Local display of status and readings | I²C; normally `0x3C` |
| Push button | SOS input and configuration interaction | XIAO D0/GPIO1 to GND, internal pull-up |
| Slide switch | Battery power isolation | Battery positive routed through switch |
| 3.7 V LiPo battery | Portable power | Protected battery to BAT+ and BAT− |
| Wires / perfboard / enclosure | Mechanical and electrical assembly | Short insulated wires and strain relief |

### Common I²C wiring

All I²C devices share the same bus:

| XIAO ESP32-S3 pin | Connect to |
|---|---|
| D4 / GPIO5 | SDA of MAX30102, TMP117, MPU6050, and OLED |
| D5 / GPIO6 | SCL of MAX30102, TMP117, MPU6050, and OLED |
| 3V3 | VCC/VIN of 3.3 V-compatible sensor modules |
| GND | Common ground of every module |

Additional connections:

| Signal | Connection |
|---|---|
| SOS button | One terminal to D0/GPIO1, other terminal to GND |
| Battery positive | Through the slide switch to XIAO BAT+ |
| Battery negative | Directly to XIAO BAT− |
| MAX30102 INT | Leave open in the current polling firmware |
| TMP117 ALERT | Leave open |
| MPU6050 INT | Leave open |

### Hardware safety

- Never connect the LiPo directly to the 3V3 sensor rail.
- Confirm battery polarity before powering the board.
- Use a protected LiPo and a suitable charger.
- Insulate solder joints and provide strain relief before closing the enclosure.
- Do not charge a damaged, swollen, hot, or punctured LiPo.
- Confirm that every module is 3.3 V logic compatible.
- The XIAO ESP32-S3 has integrated radio hardware; an external antenna sticker is not required for the standard board variant unless the specific board version provides an external-antenna connector.

---

## Software components

### Embedded firmware

The Arduino-compatible firmware is written in C/C++ for the XIAO ESP32-S3. It provides:

- Wi-Fi connection and protected first-boot provisioning.
- HTTPS telemetry transport.
- Firebase Email/Password device authentication for the direct prototype transport.
- TLS certificate validation.
- MAX30102 contact detection, PPG quality gating, heart-rate estimation, and SpO₂ estimation.
- TMP117 temperature sampling.
- MPU6050 motion-context sampling.
- OLED display and a calm heartbeat animation.
- SOS button handling and debouncing.
- OTA firmware update support on the local network.
- Stale/unavailable states instead of fabricated readings.

### Flask backend

The Flask backend provides:

- Device-key authenticated telemetry ingestion.
- Payload validation and event idempotency.
- PostgreSQL transactions for readings, alerts, and audit events.
- Firebase Admin SDK integration.
- Patient and clinician APIs.
- Role-based hospital access.
- Patient invitation and activation workflows.
- Clinical notes, care plans, patient messages, report metadata, activity entries, and wellbeing check-ins.
- Realtime outbox support for reliable Firebase projection.

### PostgreSQL

The database stores relational and auditable records including:

- `hospitals`
- `app_users`
- `hospital_memberships`
- `patients`
- `devices`
- `vital_readings`
- `alerts`
- `audit_log`
- `patient_invitations`
- `patient_lab_results`
- `wellbeing_checkins`
- `patient_clinical_profiles`
- `patient_report_documents`
- `care_messages`
- `patient_activity_entries`
- `patient_guidance`
- `wearable_validation_observations`

### Firebase

Firebase Authentication identifies users. Firebase Realtime Database contains protected live projections such as:

```text
live_vitals/<hospital_id>/<patient_id>
live_alerts/<hospital_id>/<alert_id>
access/<clinician_uid>/<hospital_id>
patient_access/<patient_uid>/<hospital_id>/<patient_id>
device_assignments/<watch_uid>
```

### Flutter patient app

The patient app provides:

- Firebase sign-in and sign-out.
- Account access and email-verification states.
- Live Firebase vital overlay with API fallback.
- Wearable connectivity and data-freshness status.
- PPG-derived heart-rate and SpO₂ display.
- Device/skin-adjacent temperature display.
- Validated-source-only blood-pressure display.
- SOS and symptom reporting.
- Care-plan tasks and activity reporting.
- Laboratory report workflow with patient confirmation and clinician review status.
- Wellbeing check-ins and safety guidance.
- Patient profile and care-team messaging.

### Flutter clinician dashboard

The dashboard provides:

- Hospital-scoped patient list.
- Patient risk/status summary.
- Live vital overlay.
- Vital trend views from durable API history.
- Alert review, acknowledgement, resolution, and escalation.
- Clinical notes.
- Device identity and assignment information.
- Patient messages and replies.
- Validation observation recording.

---

## Working principle

### 1. Sensing

The firmware initializes the I²C bus and checks the expected sensor addresses. The MAX30102 samples red and infrared optical signals. TMP117 is polled for temperature. MPU6050 readings provide motion context. The OLED displays a short status and does not display stale PPG values as if they were current.

### 2. PPG processing

The MAX30102 signal is accepted only when optical contact and signal-quality conditions are met. A window of samples is processed to estimate pulse periodicity and the red/infrared ratio. Heart rate and SpO₂ are emitted only when the estimate is fresh and quality-gated.

The high-level pipeline is:

```text
IR/red samples
      |
      v
Contact and signal-quality check
      |
      v
Windowing and noise rejection
      |
      +--> Pulse-period estimation --> heart-rate estimate
      |
      +--> Red/IR ratio estimation --> SpO₂ estimate
      |
      v
Freshness and source labels
```

### 3. Temperature processing

TMP117 is read periodically and stored as `skin_adjacent_temperature_c`. The application labels it as device or skin-adjacent temperature. It is not converted into a core body-temperature or fever claim.

### 4. Motion and SOS

The MPU6050 provides movement context for future activity-aware interpretation. The push button is debounced in firmware. A deliberate hold queues an SOS event. An SOS is a request for care-team attention, not a replacement for emergency services.

### 5. Telemetry creation

Each upload includes a stable event ID, sequence number, capture time, observation time, device ID, sensor values, quality, contact state, sensor state, source labels, freshness, motion context, and optional SOS state.

### 6. Cloud ingestion

In the standard architecture, the watch sends HTTPS telemetry to the Flask API with device credentials. The API validates the device and payload, rejects malformed or duplicate events, stores the reading in PostgreSQL, evaluates configured safety rules, and publishes the newest authorized live state to Firebase.

For a short prototype demonstration, the firmware can use the opt-in direct Firebase transport. That path signs in with the watch-only Firebase account and writes the latest reading to the assigned `live_vitals` leaf. The direct path is useful for live demonstration but does not replace durable API history, alerts, or audit processing.

### 7. Application presentation

The patient app calls the authenticated patient API to resolve the patient profile and assignment. It then subscribes to the patient’s Firebase live-vitals leaf. The newest Firebase value replaces the last saved API value. If the live stream is unavailable, the application shows a visible stale/unavailable message rather than silently displaying a fabricated value.

The dashboard uses the same principle: PostgreSQL-backed REST data is authoritative for history and clinical actions, while Firebase supplies low-latency live overlays.

---

## Deployment

### Local backend deployment

1. Install Python 3.11 or later.
2. Create a virtual environment.
3. Install `backend/requirements.txt`.
4. Configure backend environment variables in an ignored `.env` file.
5. Apply database migrations in lexical order.
6. Start Flask locally or with Gunicorn.

The backend must not receive a Firebase service-account JSON in a mobile or firmware build. It belongs only in the server environment.

### Render backend deployment

The Flask service is deployed on Render using Gunicorn. Render must contain:

- A working PostgreSQL `DATABASE_URL`.
- Firebase project configuration.
- Firebase service-account JSON as a server-only environment variable.
- A strong `SECRET_KEY`.
- Exact CORS origins for the patient app and dashboard.
- `DEMO_MODE=false` and `DEMO_IN_MEMORY=false` outside a clearly isolated presentation environment.

The schema must be migrated before enabling patient routes. A missing migration produces server errors such as `relation "patient_invitations" does not exist`.

### Vercel dashboard deployment

The Flutter web dashboard is built with the production API URL and Firebase public client configuration. The build output is the Flutter `build/web` directory. Vercel serves the static web application; the backend remains responsible for authenticated APIs and PostgreSQL access.

### Android patient application

The Android app is built with `--dart-define` values for the API endpoint and Firebase public client settings. Release builds require an HTTPS API URL and configured Firebase Android app ID. The application must not contain service-account credentials, database passwords, or device API secrets.

### Device provisioning

For every physical watch:

1. Generate a unique device ID and device key.
2. Store only the device-key hash in PostgreSQL.
3. Assign the device to one active patient.
4. Create a separate Firebase watch account only when using direct Firebase prototype transport.
5. Create the corresponding `device_assignments` mapping in the existing RTDB.
6. Flash and test the watch.
7. Record firmware version and provisioning date.

### Release checklist

- Confirm API and Firebase URLs are HTTPS.
- Confirm demo mode is disabled for a production build.
- Confirm the patient is active and linked to exactly one patient profile.
- Confirm device assignment and patient access projections.
- Confirm migrations are applied.
- Confirm database backups and retention policy.
- Confirm no secrets are committed to Git.
- Test stale data, sign-out, revoked access, SOS, and network loss.
- Test the device against a reference pulse oximeter and thermometer before any clinical evaluation.

---

## Results and discussions

### Prototype results

The prototype demonstrates:

- Multi-sensor I²C integration on a small ESP32-S3 board.
- Local OLED feedback for sensor state and readings.
- Wi-Fi provisioning and authenticated telemetry transport.
- Live Firebase updates from the existing watch path.
- Patient and clinician applications using the same identity and assignment model.
- Durable backend schema for historical readings and clinical workflows.
- Role-scoped data access and patient-specific live-vitals permissions.
- An SOS path from wearable to care-team workflow.

### Interpretation of observed readings

The prototype values are affected by sensor placement, finger pressure, motion, ambient light, sample window length, LED current, and hardware assembly. A reading should be interpreted together with:

- Contact state.
- Signal quality or perfusion index.
- Sensor state.
- Observation time.
- Freshness state.
- Source label.

For example, a displayed heart-rate value with `contact_lost` or `unavailable` state must not be treated as a current measurement. A TMP117 value around the wrist should not be compared directly with a clinical core-temperature measurement. A blood-pressure card should remain unavailable when there is no validated cuff or clinician-entered observation.

### Limitations of the prototype

- MAX30102 estimates are not clinically validated maternal measurements.
- No PPG-derived blood-pressure algorithm is used for clinical decisions.
- The current wearable has no validated cuff, ECG, or medical-grade pulse-oximeter reference.
- The prototype battery circuit and enclosure require electrical, thermal, and mechanical validation.
- Wi-Fi dependence affects availability outside configured networks.
- Direct Firebase transport provides a live projection but not full durable history.
- Activity and fall interpretation require clinical and field validation.
- The prototype does not replace in-person prenatal, delivery, or postpartum care.

### Discussion

The most important result is the end-to-end architecture rather than a claim of medical accuracy. The project demonstrates how a low-cost device can be connected to a patient identity, assigned by a hospital, routed through a controlled backend, and shown to a patient and clinician with explicit freshness and source semantics. This separation makes future validation possible without presenting unvalidated sensor output as a diagnosis.

---

## Cost, advantages, challenges, and future scope

### Indicative prototype cost

Prices vary by supplier and region. The following table is an approximate planning estimate in Indian rupees and should be replaced with actual invoices.

| Item | Approximate cost (INR) |
|---|---:|
| XIAO ESP32-S3 | 700–1,200 |
| MAX30102 module | 150–400 |
| TMP117 module | 300–900 |
| MPU6050 module | 100–250 |
| Small I²C OLED | 100–300 |
| Push button and slide switch | 20–80 |
| LiPo battery and protection/charging hardware | 250–700 |
| Perfboard, wires, solder, insulation | 150–500 |
| Enclosure and wrist strap | 200–1,000 |
| **Estimated hardware prototype total** | **1,970–5,330** |

Cloud hosting, database, Firebase, messaging, domain, and testing costs are separate and depend on usage and service plans.

### Advantages

- Low-cost and modular hardware.
- Wearable form factor with local feedback.
- Hospital-scoped patient and clinician access.
- Clear separation between live data and durable records.
- Support for offline/stale/unavailable states.
- Reusable device assignment model.
- Extensible patient-care workflows.
- Open, replaceable sensor and software components.

### Challenges

- PPG sensitivity to motion and placement.
- Small enclosure and battery constraints.
- Wi-Fi provisioning in real homes and hospitals.
- Battery-life optimization.
- Firmware update and fleet-management security.
- Data privacy and access control.
- Reliable notifications and escalation.
- Clinical validation and regulatory classification.
- Avoiding false reassurance or unnecessary alarm.
- Maintaining database migrations across environments.

### Future scope

#### Hardware

- A medically suitable optical enclosure and validated finger/wrist placement.
- Battery fuel-gauge measurement and low-power duty cycling.
- Better optical shielding and mechanical pressure control.
- Haptic feedback after safety and comfort review.
- Improved waterproofing, charging, and enclosure certification.
- Optional cellular or gateway connectivity for homes without Wi-Fi.

#### Sensing and algorithms

- Paired-observation studies against reference devices.
- Motion-artifact detection and signal-quality scoring.
- Activity classification validated against annotated sessions.
- Clinician-approved cuff integration for blood pressure.
- ECG or additional physiological sensors only after a clear clinical and regulatory plan.
- Calibration, bias, missingness, and subgroup-performance analysis.

#### Software

- Signed firmware releases and controlled OTA rollout.
- Device inventory, replacement, return, and decommission workflows.
- Push notification and audited escalation channels.
- Role-based doctor–patient messaging with read receipts.
- Offline queueing with explicit conflict handling.
- Hospital integration through FHIR-compatible interfaces where appropriate.
- Localization and accessibility for regional languages.
- Clinician-approved education and diet guidance.
- Secure report storage using approved encrypted object storage.

#### Clinical and business development

- Institutional ethics and clinical validation approval.
- Prospective studies with reference-device comparison.
- Hospital pilot with defined alert response protocols.
- Training for nurses, doctors, ASHA workers, and patients.
- Subscription or hospital licensing model.
- Device leasing, maintenance, and replacement program.
- Partnerships with obstetricians, dieticians, laboratories, and telehealth providers.
- Regulatory assessment before any medical-device or diagnostic claim.

---

## Conclusion

MaatriWatch demonstrates a complete IoT maternal-care support platform from wearable sensing to patient and clinician applications. The XIAO ESP32-S3 coordinates the MAX30102, TMP117, MPU6050, OLED, and SOS input. The backend authenticates devices and users, stores durable records, applies access control, and projects current status to Firebase. The Flutter patient application and clinician dashboard present the information in a usable care workflow.

The project’s central design principle is responsible interpretation. PPG-derived heart rate and SpO₂ are shown with quality and freshness information, TMP117 is clearly identified as skin-adjacent/device temperature, and blood pressure is reserved for validated sources. The result is a practical and extensible engineering prototype that can support future validation and clinical collaboration without making unsupported diagnostic claims.

---

## References

1. Analog Devices, **MAX30102 High-Sensitivity Pulse Oximeter and Heart-Rate Sensor for Wearable Health**, datasheet.
2. Texas Instruments, **TMP117 High-Accuracy, Low-Power, Digital Temperature Sensor**, datasheet.
3. TDK InvenSense, **MPU-6050 Product Specification**, datasheet.
4. Seeed Studio, **XIAO ESP32-S3 documentation and hardware design resources**.
5. Espressif Systems, **ESP32-S3 Series Datasheet and Technical Reference Manual**.
6. Firebase Documentation, **Firebase Authentication**, https://firebase.google.com/docs/auth.
7. Firebase Documentation, **Realtime Database Security Rules**, https://firebase.google.com/docs/database/security.
8. Firebase Documentation, **Realtime Database REST API**, https://firebase.google.com/docs/database/rest.
9. Flutter Documentation, **Flutter mobile and web application development**, https://docs.flutter.dev/.
10. Flask Documentation, **Flask web application framework**, https://flask.palletsprojects.com/.
11. PostgreSQL Documentation, **PostgreSQL current documentation**, https://www.postgresql.org/docs/.
12. American College of Obstetricians and Gynecologists, **Hypertensive Disorders of Pregnancy**, https://www.acog.org/.
13. World Health Organization, **WHO recommendations on antenatal care for a positive pregnancy experience**, https://www.who.int/.
14. Research literature on PPG-based heart-rate and oxygen-saturation estimation and cuffless blood-pressure estimation, including the MDPI paper supplied for the project review: https://www.mdpi.com/2793314.

> References must be formatted according to the institution’s required citation style before final submission. Any clinical statement used in a final product should be reviewed against current local guidance and by qualified clinicians.

---

## Appendix: code snippets

The following snippets are abbreviated examples for explaining the prototype in a presentation. They are not complete firmware or production security configurations.

### A. Wearable telemetry fields

```cpp
// Simplified structure of a live reading.
{
  "device_id": "<device UUID>",
  "source_event_id": "<stable event ID>",
  "source_sequence": 42,
  "captured_at": "2026-09-12T10:12:00Z",
  "observed_at": "2026-09-12T10:12:00Z",
  "heart_rate_bpm": 78,
  "spo2_percent": 98.0,
  "skin_adjacent_temperature_c": 33.8,
  "contact_detected": true,
  "signal_quality": 0.82,
  "sensor_status": "ok",
  "heart_rate_source": "wearable_ppg",
  "spo2_source": "wearable_ppg",
  "temperature_source": "wearable_skin_adjacent",
  "freshness": "current"
}
```

### B. Fixed I²C pin configuration

```cpp
constexpr uint8_t SDA_PIN = D4;       // GPIO5
constexpr uint8_t SCL_PIN = D5;       // GPIO6
constexpr uint8_t SOS_BUTTON_PIN = D0; // GPIO1

void setup() {
  Wire.begin(SDA_PIN, SCL_PIN);
  pinMode(SOS_BUTTON_PIN, INPUT_PULLUP);
}
```

### C. Firebase live-vitals path

```cpp
String base(FIREBASE_DATABASE_URL);
while (base.endsWith("/")) base.remove(base.length() - 1);

String url = base + "/live_vitals/" +
             String(FIREBASE_HOSPITAL_ID) + "/" +
             String(FIREBASE_PATIENT_ID) + ".json?auth=" +
             urlEncode(firebaseIdToken);
```

The direct Firebase path is an opt-in prototype transport. The standard production path should use the authenticated device ingestion API so that PostgreSQL history, alerting, auditing, and retryable Firebase projection remain available.

### D. Patient Flutter live subscription

```dart
Stream<Map<String, dynamic>?> latestForPatient({
  required String hospitalId,
  required String patientId,
}) {
  return FirebaseDatabase.instance
      .ref('live_vitals/$hospitalId/$patientId')
      .onValue
      .map((event) {
        final value = event.snapshot.value;
        return value is Map ? Map<String, dynamic>.from(value) : null;
      });
}
```

### E. Source-aware display rule

```dart
String displayHeartRate(Map<String, dynamic> vital) {
  final value = vital['heart_rate_bpm'];
  final source = vital['heart_rate_source'];
  final contact = vital['contact_detected'];

  if (value is! num || source != 'wearable_ppg' || contact == false) {
    return 'Not currently available';
  }
  return '${value.round()} bpm';
}
```

### F. PostgreSQL migration command

```powershell
cd backend
.\.venv\Scripts\python.exe scripts\apply_migrations.py
```

The command reads `DATABASE_URL` from the local ignored `.env` file or the process environment. Production deployments should apply migrations through a controlled database-release procedure.

### G. Suggested presentation demonstration sequence

1. Show the wearable sensors and explain the I²C bus.
2. Place a finger on the MAX30102 and show contact/stabilisation on the OLED.
3. Show the PPG-derived heart rate and SpO₂ labels.
4. Show skin-adjacent temperature and the current sensor state.
5. Demonstrate the SOS button without presenting it as an emergency-service replacement.
6. Show the patient app updating the live reading.
7. Open the clinician dashboard and show the assigned patient and live overlay.
8. Demonstrate a patient message or care-plan action.
9. Explain that PostgreSQL stores history while Firebase supplies the live projection.
10. State the current validation limitations and future clinical-validation plan.
