import unittest
from datetime import datetime, timedelta, timezone
from threading import RLock
from unittest.mock import patch

from app import create_app
from app.care_records import MemoryRecords
from app.companion import deliver_due, next_occurrence, urgent


class CompanionTest(unittest.TestCase):
    def setUp(self):
        self.app = create_app({'TESTING': True, 'DEMO_MODE': True, 'DEMO_IN_MEMORY': True,
                               'DATABASE_URL': None, 'OPENAI_CHAT_MAX_REQUESTS': 1000})
        self.client = self.app.test_client()
        self.headers = {'X-Demo-Role': 'patient'}

    def call(self, method, path='', data=None):
        return self.client.open('/api/v1/patient/companion' + path, method=method, json=data, headers=self.headers)

    def test_private_by_default_and_explicit_consent(self):
        home = self.call('GET').json
        self.assertFalse(home['preferences']['memory_enabled'])
        self.assertIsNone(home['context'])
        self.assertEqual(self.call('POST', '/memories', {'text': 'I prefer Malayalam'}).status_code, 409)
        self.assertEqual(self.call('PUT', data={'memory_enabled': 'false'}).status_code, 400)
        self.assertEqual(self.call('PUT', data={'timezone': 'invalid/zone'}).status_code, 400)
        self.call('PUT', data={'memory_enabled': True, 'context_enabled': True})
        result = self.call('POST', '/memories', {'text': 'I prefer evening reminders'})
        self.assertEqual(result.status_code, 201)
        self.assertEqual(self.call('DELETE', '/memories/' + result.json['memory']['id']).json['deleted'], 1)

    @patch('app.companion.ai_provider.response', return_value='I am here to listen. What has today been like?')
    def test_chat_continuity_and_deletion(self, provider):
        self.call('PUT', data={'memory_enabled': True})
        self.call('POST', '/chat', {'message': 'I have been feeling lonely'})
        self.assertEqual(len(self.call('GET').json['messages']), 2)
        self.call('POST', '/chat', {'message': 'Can we talk more?'})
        self.assertIn('I have been feeling lonely', str(provider.call_args))
        self.call('DELETE', '/messages')
        self.assertEqual(self.call('GET').json['messages'], [])
        self.call('PUT', data={'memory_enabled': False})
        self.call('POST', '/chat', {'message': 'A private conversation'})
        self.assertEqual(self.call('GET').json['messages'], [])

    def test_urgent_malayalam_works_without_a_model_key(self):
        self.assertTrue(urgent('എനിക്ക് ശ്വാസംമുട്ടൽ ഉണ്ട്'))
        self.call('PUT', data={'language': 'ml'})
        result = self.call('POST', '/chat', {'message': 'എനിക്ക് നെഞ്ചുവേദന ഉണ്ട്'})
        self.assertEqual(result.status_code, 200)
        self.assertTrue(result.json['urgent'])
        self.assertIn('അടിയന്തര', result.json['answer'])

    def test_provider_unavailable_does_not_fabricate_a_reply(self):
        result = self.call('POST', '/chat', {'message': 'Can we talk?'})
        self.assertEqual(result.status_code, 503)

    def test_patient_isolation_and_notification_idempotency(self):
        backing = ({}, RLock())
        a = MemoryRecords({'id': 'a', 'hospital_id': 'h'}, backing)
        b = MemoryRecords({'id': 'b', 'hospital_id': 'h'}, backing)
        other_hospital = MemoryRecords({'id': 'a', 'hospital_id': 'other'}, backing)
        due = datetime.now(timezone.utc) - timedelta(minutes=1)
        reminder = a.put('reminder', {'title': 'Rest', 'due_at': due.isoformat(), 'status': 'active', 'recurrence': 'daily', 'timezone': 'Asia/Kolkata'})
        self.assertIsNone(b.get('reminder', reminder['id']))
        self.assertEqual(other_hospital.list('reminder'), [])
        with self.app.app_context():
            self.assertEqual(deliver_due(a), 1)
            self.assertEqual(deliver_due(a), 0)
        self.assertEqual(len(a.list('notification')), 1)
        self.assertEqual(b.list('notification'), [])

    def test_timezone_recurrence_and_input_boundaries(self):
        due = datetime(2026, 3, 7, 14, tzinfo=timezone.utc)  # 09:00 New York
        now = datetime(2026, 3, 8, 14, tzinfo=timezone.utc)
        self.assertEqual(next_occurrence(due, 'daily', 'America/New_York', now).hour, 13)
        self.assertEqual(self.call('POST', '/reminders', {'title': 'Rest', 'due_at': '2026-10-25T10:00:00'}).status_code, 400)
        future = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
        created = self.call('POST', '/reminders', {'title': 'Ask my care team', 'due_at': future})
        self.assertEqual(created.status_code, 201)
        changed = self.call('PATCH', '/reminders/' + created.json['reminder']['id'], {'action': 'snooze'})
        self.assertEqual(changed.status_code, 200)

    def test_event_reminders_compute_notice_and_reject_elapsed_or_invalid_offsets(self):
        event = datetime.now(timezone.utc) + timedelta(days=10)
        result = self.call('POST','/reminders',{'title':'Doctor visit','event_at':event.isoformat(),'lead_minutes':4320})
        self.assertEqual(result.status_code,201)
        data = result.json['reminder']['data']
        self.assertEqual(datetime.fromisoformat(data['due_at']),event-timedelta(days=3))
        self.assertEqual(datetime.fromisoformat(data['event_at']),event)
        self.assertEqual(self.call('POST','/reminders',{'title':'Visit','event_at':event.isoformat(),'lead_minutes':True}).status_code,400)
        elapsed = datetime.now(timezone.utc)+timedelta(hours=1)
        self.assertEqual(self.call('POST','/reminders',{'title':'Visit','event_at':elapsed.isoformat(),'lead_minutes':4320}).status_code,400)
