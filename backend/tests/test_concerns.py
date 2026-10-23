import io
from datetime import datetime, timezone
from threading import RLock
import unittest
from unittest.mock import patch

from app import create_app
from app.care_records import MemoryRecords
from app.concerns import monthly_summary, finalize_previous_month, month_bounds


def symptom(name='Headache', severity='mild'):
    return {'symptom_key': 'headache', 'name': name, 'onset': 'yesterday', 'frequency': 'twice',
            'severity': severity, 'details': '', 'source_quote': 'headache'}


class ConcernTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app({'TESTING': True, 'DEMO_MODE': True, 'DEMO_IN_MEMORY': True,
                               'DATABASE_URL': None, 'OPENAI_CHAT_MAX_REQUESTS': 1000})
        self.client = self.app.test_client()
        self.headers = {'X-Demo-Role': 'patient'}

    def test_confirmation_required_and_manual_path_needs_no_ai(self):
        payload = {'original_text': 'I have a headache', 'language': 'en', 'symptoms': [symptom()]}
        self.assertEqual(self.client.post('/api/v1/patient/concerns', json=payload, headers=self.headers).status_code, 400)
        payload.update(confirmed=True, share_with_care_team=False)
        saved = self.client.post('/api/v1/patient/concerns', json=payload, headers=self.headers)
        self.assertEqual(saved.status_code, 201)
        self.assertFalse(saved.json['concern']['data']['share_with_care_team'])

    @patch('app.concerns.ai_provider.response')
    def test_bilingual_extraction_is_grounded_and_does_not_invent_evidence(self, provider):
        row = symptom('തലവേദന')
        row['source_quote'] = 'തലവേദന'
        provider.return_value = {'symptoms': [row]}
        payload = {'text': 'ഇന്നലെ മുതൽ തലവേദന ഉണ്ട്', 'language': 'ml', 'processing_consent': True}
        result = self.client.post('/api/v1/patient/concerns/draft', json=payload, headers=self.headers)
        self.assertEqual(result.status_code, 200)
        provider.return_value['symptoms'][0]['source_quote'] = 'invented fever'
        self.assertEqual(self.client.post('/api/v1/patient/concerns/draft', json=payload, headers=self.headers).status_code, 502)

    def test_urgent_guidance_works_before_provider_or_consent(self):
        result = self.client.post('/api/v1/patient/concerns/draft', json={'text': 'I have chest pain', 'language': 'en'}, headers=self.headers)
        self.assertEqual(result.status_code, 200)
        self.assertTrue(result.json['urgent'])

    @patch('app.concerns.ai_provider.transcribe_audio', return_value='എനിക്ക് തലവേദന ഉണ്ട്')
    def test_audio_requires_consent_and_checks_file_content(self, transcribe):
        data = {'language': 'ml', 'processing_consent': 'true', 'audio': (io.BytesIO(b'RIFF0000WAVE' + b'\x00' * 48), 'record.wav')}
        result = self.client.post('/api/v1/patient/concerns/transcribe', data=data, headers=self.headers)
        self.assertEqual(result.status_code, 200)
        self.assertFalse(result.json['audio_stored'])
        result = self.client.post('/api/v1/patient/concerns/transcribe', data={'language': 'en', 'processing_consent': 'true', 'audio': (io.BytesIO(b'<html>fake</html>'), 'record.wav')}, headers=self.headers)
        self.assertEqual(result.status_code, 400)
        self.assertEqual(transcribe.call_count, 1)

    def test_monthly_recurrence_counts_and_sharing(self):
        repo = MemoryRecords({'id': 'a', 'hospital_id': 'h'}, ({}, RLock()))
        a = repo.put('concern', {'symptoms': [symptom(), symptom()], 'urgent': False, 'share_with_care_team': True})
        b = repo.put('concern', {'symptoms': [symptom(severity='severe')], 'urgent': False, 'share_with_care_team': False})
        repo.rows[a['id']]['created_at'] = '2026-10-01T06:00:00+00:00'
        repo.rows[b['id']]['created_at'] = '2026-10-03T06:00:00+00:00'
        report = monthly_summary(repo, '2026-10')
        self.assertEqual(report['report_count'], 2)
        self.assertEqual(report['patterns'][0]['count'], 2)  # duplicates in one report count once
        self.assertEqual(report['patterns'][0]['reported_severity_change'], 'increased')
        self.assertEqual(monthly_summary(repo, '2026-10', shared_only=True)['report_count'], 1)
        start, _ = month_bounds('2026-10', 'Asia/Kolkata')
        self.assertEqual(start.isoformat(), '2026-09-30T18:30:00+00:00')
        self.assertEqual(finalize_previous_month(repo, datetime(2026,11,2,tzinfo=timezone.utc)), 1)
        self.assertEqual(finalize_previous_month(repo, datetime(2026,11,2,tzinfo=timezone.utc)), 0)

    @patch('app.concerns.ai_provider.response', return_value={'insights': [{'text': 'A fabricated claim', 'source_report_ids': ['unknown']}]})
    def test_ai_summary_rejects_unknown_source_reports(self, provider):
        self.client.post('/api/v1/patient/concerns', json={'original_text': 'headache', 'language': 'en', 'symptoms': [symptom()], 'confirmed': True}, headers=self.headers)
        result = self.client.post('/api/v1/patient/concerns/summary', json={'processing_consent': True}, headers=self.headers)
        self.assertEqual(result.status_code, 502)

    @patch('app.concerns.ai_provider.response')
    def test_scheduled_ai_handoff_requires_explicit_opt_in(self, provider):
        repo = MemoryRecords({'id': 'a', 'hospital_id': 'h'}, ({}, RLock()))
        row = repo.put('concern', {'symptoms': [symptom()], 'urgent': False, 'share_with_care_team': True})
        repo.rows[row['id']]['created_at'] = '2026-10-01T06:00:00+00:00'
        with self.app.app_context():
            self.assertEqual(finalize_previous_month(repo, datetime(2026,11,2,tzinfo=timezone.utc)), 1)
            provider.assert_not_called()
            repo.delete('summary')
            repo.put('preferences', {'auto_summary_enabled': True}, stable_key='settings')
            self.app.config['OPENAI_API_KEY'] = 'unit-test-placeholder'
            provider.return_value = {'insights': [{'text': 'Headache was reported; review the original report.', 'source_report_ids': [row['id']]}]}
            self.assertEqual(finalize_previous_month(repo, datetime(2026,11,2,tzinfo=timezone.utc)), 1)
            self.assertEqual(repo.list('summary')[0]['data']['review_status'], 'draft_for_review')
