import unittest
from unittest.mock import patch
from app import create_app


class GuardianAccessTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app({'TESTING':True, 'DATABASE_URL':None, 'DEMO_MODE':False})
        self.app.config['FIREBASE_AUTH_READY'] = True
        self.client = self.app.test_client()

    def test_no_guardian_or_patient_data_without_authentication(self):
        for route in ['/account/access','/guardian/home','/patient/guardians']:
            result = self.client.get('/api/v1'+route,headers={'X-Demo-Role':'patient'})
            self.assertEqual(result.status_code,401)

    @patch('app.auth.firebase_auth.verify_id_token',return_value={'uid':'g','email':'g@example.test','email_verified':False})
    def test_unverified_identity_cannot_link_or_read_guardian_inbox(self, verifier):
        headers = {'Authorization':'Bearer synthetic-token'}
        self.assertEqual(self.client.get('/api/v1/guardian/home',headers=headers).status_code,403)
        self.assertEqual(self.client.post('/api/v1/guardian/link',json={'code':'anything'},headers=headers).status_code,403)
        verifier.assert_called_with('synthetic-token',check_revoked=True)

    @patch('app.guardians.lookup_app_user',return_value=None)
    @patch('app.auth.firebase_auth.verify_id_token',return_value={'uid':'g','email':'g@example.test','email_verified':True})
    def test_unlinked_verified_guardian_has_an_empty_inbox(self, verifier, lookup):
        result = self.client.get('/api/v1/guardian/home',headers={'Authorization':'Bearer synthetic-token'})
        self.assertEqual(result.status_code,200)
        self.assertEqual(result.json,{'patients':[],'notifications':[]})
