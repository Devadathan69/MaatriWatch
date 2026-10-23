import io
import unittest
from unittest.mock import patch
from app import create_app
from app.report_rules import confirmed_readings, report_context, interpret
from app.demo_store import DEMO_HOSPITAL_ID, _demo_id


def reading(analyte='ogtt_fasting', value=92, unit='mg/dL', **extra):
    return {'analyte':analyte,'name':analyte,'value':value,'unit':unit,'reference_min':None,'reference_max':None,
            'reference_scope':'unspecified','reference_trimester':None,'source_quote':f'{analyte} {value} {unit}',**extra}


class ReportAndNutritionTests(unittest.TestCase):
    def setUp(self):
        self.app=create_app({'TESTING':True,'DEMO_MODE':True,'DEMO_IN_MEMORY':True,'DATABASE_URL':None,'OPENAI_CHAT_MAX_REQUESTS':1000})
        self.client=self.app.test_client()
        self.headers={'X-Demo-Role':'patient'}
        self.context={'stage':'pregnant','trimester':2,'protocol':'75g_ogtt_fasting'}

    def compare(self,rows,context=None):
        return interpret(confirmed_readings(rows),context or self.context)

    def save_report(self):
        result=self.client.post('/api/v1/patient/reports/analyses',json={'confirmed':True,'readings':[reading(value=95)],'context':self.context},headers=self.headers)
        self.assertEqual(result.status_code,201)
        return result.json['report']

    def test_ogtt_native_unit_boundaries_and_protocol(self):
        self.assertEqual(self.compare([reading(value=91.99)])['flag_count'],0)
        self.assertEqual(self.compare([reading(value=92)])['flag_count'],1)
        self.assertEqual(self.compare([reading(value=5.1,unit='mmol/L')])['flag_count'],1)
        self.assertEqual(self.compare([reading('ogtt_1h',180)])['flag_count'],1)
        self.assertEqual(self.compare([reading('ogtt_2h',153)])['flag_count'],1)
        self.assertEqual(self.compare([reading()],{**self.context,'protocol':'other'})['unresolved_count'],1)
        self.assertEqual(self.compare([reading()],{**self.context,'stage':'postpartum'})['unresolved_count'],1)

    def test_haemoglobin_requires_trimester_and_converts_units(self):
        self.assertEqual(self.compare([reading('hemoglobin',105,'g/L')])['flag_count'],0)
        self.assertEqual(self.compare([reading('hemoglobin',10.49,'g/dL')])['flag_count'],1)
        self.assertEqual(self.compare([reading('hemoglobin',10.6,'g/dL')],{**self.context,'trimester':1})['flag_count'],1)
        self.assertEqual(self.compare([reading('hemoglobin',10,'g/dL')],{**self.context,'trimester':None})['unresolved_count'],1)
        self.assertTrue(self.compare([reading('hemoglobin',6.9,'g/dL')])['urgent_review'])

    def test_thyroid_needs_confirmed_matching_reference_range(self):
        row=reading('tsh',4.2,'mIU/L',reference_min=0.1,reference_max=4.0)
        self.assertEqual(self.compare([row])['unresolved_count'],1)
        row.update(reference_scope='trimester',reference_trimester=1)
        self.assertEqual(self.compare([row])['unresolved_count'],1)
        row.update(reference_trimester=2)
        self.assertEqual(self.compare([row])['readings'][0]['status'],'above_reported_range')

    def test_duplicate_results_and_nonfinite_values(self):
        self.assertEqual(self.compare([reading(),reading(value=90)])['unresolved_count'],2)
        with self.app.app_context():
            from werkzeug.exceptions import BadRequest
            with self.assertRaises(BadRequest):confirmed_readings([reading(value=float('nan'))])

    @patch('app.reports.ai_provider.response')
    def test_extraction_retains_uncertainty_and_requires_confirmation(self,provider):
        provider.return_value={'extracted_text':'Hb 10.2 g/dL','readings':[{**reading('hemoglobin',10.2,'g/dL'),'source_quote':'Hb 10.2 g/dL','uncertain':False}],'protocol':'unknown'}
        result=self.client.post('/api/v1/patient/reports/extract',json={'report_text':'Hb 10.2 g/dL','processing_consent':True},headers=self.headers)
        self.assertEqual(result.status_code,200)
        self.assertTrue(result.json['requires_confirmation'])
        provider.return_value['readings'][0]['value']=102
        result=self.client.post('/api/v1/patient/reports/extract',json={'report_text':'Hb 10.2 g/dL','processing_consent':True},headers=self.headers)
        self.assertTrue(result.json['draft']['readings'][0]['uncertain'])
        bad=self.client.post('/api/v1/patient/reports/extract',data={'processing_consent':'true','document':(io.BytesIO(b'not a pdf'),'report.pdf')},headers=self.headers)
        self.assertEqual(bad.status_code,400)
        self.assertEqual(self.client.post('/api/v1/patient/reports/analyses',json={'readings':[reading()]},headers=self.headers).status_code,400)

    def food_preferences(self):
        return {'diet':'vegan','allergens':['milk','wheat','gluten'],'dislikes':[],
            'allergies_confirmed':True,'sweet_preference':'sometimes','morning_sickness':True,
            'appetite':'low','spice_preference':'mild','favourite_foods':['idli']}

    def food_response(self):
        return {'overview':'Food ideas based on your confirmed report and preferences.',
            'foods':[{'food_id':key,'advice':advice,'reason':'A preference-aware food idea to discuss with your care team.','report_analytes':[]}
                for key,advice in [('idli','suggest'),('fruit','suggest'),('khichdi','suggest'),('sugary_drinks','limit')]],'discussion_points':[]}

    @patch('app.food_guidance.ai_provider.response')
    def test_ai_food_guidance_requires_questionnaire_consent_and_invalidates_changed_preferences(self,provider):
        report=self.save_report()
        endpoint='/api/v1/patient/nutrition'
        self.assertEqual(self.client.post(endpoint,json={'report_id':report['id'],'processing_consent':True},headers=self.headers).status_code,409)
        prefs=self.food_preferences()
        self.assertEqual(self.client.put(endpoint,json=prefs,headers=self.headers).status_code,200)
        self.assertEqual(self.client.post(endpoint,json={'report_id':report['id']},headers=self.headers).status_code,400)
        provider.return_value=self.food_response()
        result=self.client.post(endpoint,json={'report_id':report['id'],'processing_consent':True},headers=self.headers)
        self.assertEqual(result.status_code,201)
        row=result.json['plan']
        self.assertEqual(row['data']['format'],'food_guidance_v1')
        self.assertNotIn('days',row['data'])
        self.assertEqual(len(row['data']['foods']),4)
        self.assertIn('morning_sickness',str(provider.call_args))
        doctor=f'/api/v1/hospitals/{DEMO_HOSPITAL_ID}/patients/{_demo_id("patient",1)}/nutrition/{row["id"]}'
        self.assertEqual(self.client.patch(doctor,json={'action':'approve','note':'Reviewed food suggestions.'},headers=self.headers).status_code,403)
        self.assertEqual(self.client.patch(doctor,json={'action':'approve','note':'Reviewed food suggestions.'},headers={'X-Demo-Role':'doctor'}).status_code,200)
        prefs['sweet_preference']='no'
        self.client.put(endpoint,json=prefs,headers=self.headers)
        self.assertTrue(self.client.get(endpoint,headers=self.headers).json['requires_refresh'])

    @patch('app.food_guidance.ai_provider.response')
    def test_ai_cannot_suggest_excluded_or_unsafe_foods_or_unknown_report_results(self,provider):
        report=self.save_report()
        endpoint='/api/v1/patient/nutrition'
        self.client.put(endpoint,json=self.food_preferences(),headers=self.headers)
        for food_id in ['roti_paneer','alcohol','unpasteurised']:
            value=self.food_response(); value['foods'][0]['food_id']=food_id; provider.return_value=value
            result=self.client.post(endpoint,json={'report_id':report['id'],'processing_consent':True},headers=self.headers)
            self.assertEqual(result.status_code,502)
        value=self.food_response();value['foods'][0]['report_analytes']=['invented_test'];provider.return_value=value
        self.assertEqual(self.client.post(endpoint,json={'report_id':report['id'],'processing_consent':True},headers=self.headers).status_code,502)
        self.assertIsNone(self.client.get(endpoint,headers=self.headers).json['plan'])
