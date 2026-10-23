# Report comparison and AI food-guidance policy

Version: `pregnancy-report-2026-10-23-v1`. This is an auditable prototype comparison policy, not a diagnostic protocol approved for a clinical deployment.

## Extraction and confirmation

The report endpoint accepts text, PDF, JPEG, or PNG with explicit processing consent. PDF pages/images are sent to the configured multimodal OpenAI model using the Responses API. The app does not retain the uploaded file through this extraction endpoint. Confirmed structured values are retained under the authenticated patient/hospital scope; the older report-document upload workflow remains separate.

Each extracted reading includes its printed label, numeric value or unreadable marker, units, range if present, range population/trimester, source quote, and an uncertainty marker. Text extraction quotes are checked against input text; PDF/image extraction quotes are checked against the model's transcription. The latter is a consistency check, not independent OCR accuracy validation. The patient must compare the draft against the original and correct it before saving.

## Supported comparisons

| Test | Preconditions | Comparison | Source |
| --- | --- | --- | --- |
| Fasting glucose | Confirmed pregnancy and fasting 75 g OGTT | At or above 92 mg/dL, or 5.1 mmol/L in native units, is flagged for clinician review | [WHO pregnancy assessment](https://www.who.int/tools/elena/interventions/assessment-methods-pregnancy) |
| OGTT one hour | Same protocol | At or above 180 mg/dL or 10.0 mmol/L | Same WHO source |
| OGTT two hours | Same protocol | At or above 153 mg/dL or 8.5 mmol/L | Same WHO source |
| Haemoglobin | Pregnancy, known trimester, g/dL or g/L | Below 11.0 g/dL in trimesters one/three; below 10.5 in trimester two; g/L converted by dividing by ten | [WHO 2024 haemoglobin guideline](https://www.who.int/publications/i/item/9789240088542) |
| TSH/free T4 | Confirmed matching pregnancy/trimester-specific lab range | Compare only against the printed range in the same units; no universal adult cutoff | [American Thyroid Association](https://www.thyroid.org/hypothyroidism-in-pregnancy/) |
| Other test | Explicit pregnancy-specific printed range | Label comparison to that range only; otherwise needs clinician context | Patient-confirmed report; no invented source |

These glucose decision limits are not treatment targets. “Below diagnostic threshold” is not an all-clear and does not exclude other problems. Missing units, an unconfirmed protocol, duplicate analyte values/dates, postpartum status, or absent ranges produce an unresolved result. Multiple dates need separate confirmed reports.

A haemoglobin value below 7 g/dL flags prompt clinical assessment and blocks food-guidance generation. The system never substitutes food suggestions for treatment or changes medications. Source thresholds and their clinical suitability need local approval before patient deployment.

## Nutrition design

Updated 24 October 2026: Nourish asks about dietary pattern, sweet tastes, morning sickness, appetite, spice, favourite foods, exclusions, allergies and care-team instructions before food guidance is generated. Unknown allergies require dietitian review.

With explicit processing consent, the AI considers the selected confirmed report and questionnaire, selects food IDs from a bounded ingredient/allergen catalog, and explains suggestions and items to limit or avoid. Server checks reject excluded foods, unsafe recommendations, unknown or duplicate food IDs and invented report references. There is no automatic weekly plan, calorie target, supplement recommendation or treatment promise. An unavailable provider produces a visible error rather than a static fallback plan.

The catalog cannot guarantee cross-contact prevention or suitability for every condition or medication. Guidance does not establish nutrient adequacy or replace clinician/dietitian advice. Pregnancy comparisons are not applied to postpartum reports. Changing preferences invalidates existing advice; selecting a different report requires fresh analysis. Patients cannot approve their own guidance. Previous weekly-plan records remain stored as history but are not presented as current food guidance.

References: [NHS nausea and food-tolerance guidance](https://www.nhs.uk/pregnancy/common-symptoms/vomiting-and-morning-sickness/), [FDA pregnancy food safety](https://www.fda.gov/food/people-risk-foodborne-illness/food-safety-moms-be-glance), and [pregnancy and breastfeeding nutrition](https://health.gov/sites/default/files/2021-12/DGA_Pregnancy_FactSheet-508.pdf). The original code-drawn food illustrations are retained; no third-party app assets or patient images are copied.
