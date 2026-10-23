# Report comparison and meal-planning policy

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

A haemoglobin value below 7 g/dL flags prompt clinical assessment and blocks meal-plan generation. The system never substitutes food suggestions for treatment or changes medications. Source thresholds and their clinical suitability need local approval before patient deployment.

## Nutrition design

Nourish uses an original, explicit food catalog with ingredients, allergens, dietary categories, illustrative household portions, and cooking guidance. It personalises a seven-day draft to confirmed food preferences and supported report flags. It does not ask a language model to invent nutrient targets, hidden ingredients, or a therapeutic prescription.

Unknown allergies and restrictions need dietitian input. The catalog cannot guarantee cross-contact prevention or suitability for every disease/medication. Portions are examples; calories, protein adequacy, micronutrient totals, gestational weight goals, lactation needs, and treatment-specific targets have not been clinically validated. Postpartum reports are not interpreted using pregnancy cutoffs; any food draft still needs individual review.

Patient-created plans are drafts. A hospital-scoped clinician must review and leave a note to mark a plan approved. Swapping an approved meal returns it to draft. Changing allergy/preferences invalidates the current recommendation. Patient API calls cannot approve plans.

Food-safety references: [FDA pregnancy food safety](https://www.fda.gov/food/people-risk-foodborne-illness/food-safety-moms-be), [pregnancy and breastfeeding nutrition](https://health.gov/sites/default/files/2021-12/DGA_Pregnancy_FactSheet-508.pdf). UI planning inspiration: [Eat This Much](https://www.eatthismuch.com/). The meal illustrations are original code-drawn vectors; no third-party app assets or patient images are copied.
