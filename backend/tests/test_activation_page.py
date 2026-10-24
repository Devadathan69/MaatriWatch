import unittest

from app import create_app


class ActivationContinueTests(unittest.TestCase):
    def test_continue_page_does_not_echo_action_codes_or_contact_external_services(self):
        app = create_app({'TESTING': True, 'DATABASE_URL': None})
        response = app.test_client().get('/activate?oobCode=private-one-time-code')
        self.assertEqual(response.status_code, 200)
        self.assertIn(b'Continue in MaatriWatch', response.data)
        self.assertNotIn(b'private-one-time-code', response.data)
        self.assertEqual(response.headers['Cache-Control'], 'no-store')
        self.assertEqual(response.headers['Referrer-Policy'], 'no-referrer')
        self.assertIn("default-src 'none'", response.headers['Content-Security-Policy'])
