"""Versioned, deterministic comparison of confirmed report values, not diagnosis."""
import math
from collections import Counter
from flask import abort

POLICY_VERSION = 'pregnancy-report-2026-10-23-v1'
WHO_GLUCOSE = 'https://www.who.int/tools/elena/interventions/assessment-methods-pregnancy'
WHO_HB = 'https://www.who.int/publications/i/item/9789240088542'
ATA = 'https://www.thyroid.org/hypothyroidism-in-pregnancy/'
ANALYTES = ['ogtt_fasting', 'ogtt_1h', 'ogtt_2h', 'hemoglobin', 'tsh', 'free_t4', 'other']


def number(value, field, nullable=False):
    if value is None and nullable:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0 or value > 100000:
        abort(400, description=f'{field} must be a finite non-negative number')
    return float(value)


def confirmed_readings(values):
    if not isinstance(values, list) or not 1 <= len(values) <= 50:
        abort(400, description='Confirm one to fifty report readings')
    rows = []
    for item in values:
        if not isinstance(item, dict) or item.get('analyte') not in ANALYTES:
            abort(400, description='Unsupported analyte; use other for unrecognised tests')
        row = {'analyte': item['analyte'], 'value': number(item.get('value'), 'value'),
               'reference_min': number(item.get('reference_min'), 'reference_min', True),
               'reference_max': number(item.get('reference_max'), 'reference_max', True)}
        for key, limit in [('name',120),('unit',40),('source_quote',500)]:
            value = item.get(key, '')
            if not isinstance(value, str) or len(value) > limit:
                abort(400, description=f'Invalid {key}')
            row[key] = value.strip()
        if not row['name'] or not row['unit']:
            abort(400, description='Confirm the test name and units for every reading')
        if row['reference_min'] is not None and row['reference_max'] is not None and row['reference_min'] >= row['reference_max']:
            abort(400, description='The reference minimum must be below the maximum')
        scope = item.get('reference_scope', 'unspecified')
        if scope not in ('unspecified', 'pregnancy', 'trimester'):
            abort(400, description='Invalid reference scope')
        ref_trimester = item.get('reference_trimester')
        if ref_trimester is not None and (isinstance(ref_trimester, bool) or ref_trimester not in (1,2,3)):
            abort(400, description='Invalid reference trimester')
        row.update(reference_scope=scope, reference_trimester=ref_trimester)
        rows.append(row)
    return rows


def report_context(values):
    if not isinstance(values, dict):
        abort(400, description='Report context must be an object')
    stage = values.get('stage', 'not_recorded')
    if stage not in ('pregnant', 'postpartum', 'not_recorded'):
        abort(400, description='Invalid pregnancy stage')
    trimester = values.get('trimester')
    if trimester is not None and (isinstance(trimester, bool) or trimester not in (1,2,3)):
        abort(400, description='Choose trimester 1, 2, or 3, or leave it unknown')
    protocol = values.get('protocol', 'unknown')
    if protocol not in ('unknown', '75g_ogtt_fasting', 'other'):
        abort(400, description='Invalid test protocol')
    return {'stage': stage, 'trimester': trimester, 'protocol': protocol}


def interpret(readings, context):
    results = []
    duplicates = Counter(r['analyte'] for r in readings if r['analyte'] != 'other')
    for row in readings:
        item = {**row, 'status': 'needs_context', 'source': None, 'comparison': None,
                'explanation': 'This test needs clinician interpretation or a verified pregnancy-specific range.', 'urgent_review': False}
        key, value = row['analyte'], row['value']
        unit = row['unit'].casefold().replace(' ', '').replace('μ','u').replace('µ','u')
        if context['stage'] != 'pregnant':
            item['explanation'] = 'Pregnancy-specific comparisons are not applied until pregnancy status is confirmed. Postpartum needs a separate clinical policy.'
        elif duplicates[key] > 1:
            item['explanation'] = 'Multiple values for this test were found. Separate their dates/timepoints before comparison.'
        elif key.startswith('ogtt_'):
            if context['protocol'] != '75g_ogtt_fasting':
                item['explanation'] = 'Confirm a fasting 75 g OGTT protocol. Screening tests and other glucose protocols use different thresholds.'
            elif unit not in ('mg/dl', 'mgdl', 'mmol/l'):
                item['explanation'] = 'Glucose units must be mg/dL or mmol/L.'
            else:
                limits = {'ogtt_fasting':(92,5.1),'ogtt_1h':(180,10.0),'ogtt_2h':(153,8.5)}
                limit = limits[key][1 if unit == 'mmol/l' else 0]
                high = value >= limit
                item.update(status='above_threshold' if high else 'below_diagnostic_threshold', source=WHO_GLUCOSE,
                            comparison=f'{limit:g} {row["unit"]} (at or above triggers clinical review)',
                            explanation='At or above the WHO 75 g OGTT decision threshold; ask your care team to interpret and confirm.' if high else
                            'Below this diagnostic decision threshold only. This does not establish that the whole report or pregnancy is normal.')
        elif key == 'hemoglobin':
            if context['trimester'] is None or unit not in ('g/dl','g/l'):
                item['explanation'] = 'Haemoglobin comparison requires trimester and g/dL or g/L units.'
            else:
                native = value / 10 if unit == 'g/l' else value
                limit = 10.5 if context['trimester'] == 2 else 11.0
                item.update(status='below_threshold' if native < limit else 'not_below_threshold', source=WHO_HB,
                            comparison=f'Lower cutoff {limit:g} g/dL for trimester {context["trimester"]}', urgent_review=native < 7,
                            explanation='Below the trimester-specific haemoglobin cutoff. A clinician must assess the cause; diet alone may not address it.' if native < limit else
                            'Not below this lower cutoff; this is not a full normal-range or iron-status assessment.')
        elif key in ('tsh','free_t4','other'):
            compatible = row['reference_scope'] == 'pregnancy' or (row['reference_scope'] == 'trimester' and row['reference_trimester'] == context['trimester'] and context['trimester'] is not None)
            if compatible and row['reference_min'] is not None and row['reference_max'] is not None:
                status = 'below_reported_range' if value < row['reference_min'] else 'above_reported_range' if value > row['reference_max'] else 'within_reported_range'
                item.update(status=status, source=ATA if key in ('tsh','free_t4') else 'Patient-confirmed pregnancy-specific range printed on report',
                            comparison=f'{row["reference_min"]:g}–{row["reference_max"]:g} {row["unit"]}',
                            explanation='Compared only with the pregnancy-specific lab range you confirmed. Lab method and clinical history still matter.')
            elif key in ('tsh','free_t4'):
                item.update(source=ATA, explanation='A lab/assay and pregnancy/trimester-specific range is needed. A universal adult thyroid cutoff is not substituted.')
        results.append(item)
    flags = [r for r in results if r['status'] in ('above_threshold','below_threshold','above_reported_range','below_reported_range')]
    unknown = [r for r in results if r['status'] == 'needs_context']
    return {'policy_version': POLICY_VERSION, 'readings': results, 'flag_count': len(flags),
            'unresolved_count': len(unknown), 'urgent_review': any(r['urgent_review'] for r in results),
            'conclusion': 'Values need clinician review.' if flags else 'More context is needed before interpreting the report.' if unknown else
            'No supported comparison was flagged. This is not an all-clear or diagnosis.',
            'notice': 'Comparisons are informational and require clinician review. Do not change medication or use a diet plan as treatment.'}
