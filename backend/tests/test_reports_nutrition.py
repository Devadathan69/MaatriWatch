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

    def test_meal_plan_allergens_swaps_review_and_preference_invalidation(self):
        report=self.save_report()
        prefs={'diet':'vegan','allergens':['milk','wheat','gluten'],'dislikes':[],'allergies_confirmed':True}
        self.assertEqual(self.client.put('/api/v1/patient/nutrition',json=prefs,headers=self.headers).status_code,200)
        result=self.client.post('/api/v1/patient/nutrition',json={'report_id':report['id']},headers=self.headers)
        self.assertEqual(result.status_code,201)
        row=result.json['plan']
        self.assertEqual(len(row['data']['days']),7)
        for day in row['data']['days']:
            for meal in day['meals']:
                self.assertFalse(set(meal['allergens'])&set(prefs['allergens']))
                self.assertEqual(meal['diet'],'vegan')
        bad=self.client.patch('/api/v1/patient/nutrition/plans/'+row['id'],json={'day':0,'slot':'lunch','swap_to':'roti_dal'},headers=self.headers)
        self.assertEqual(bad.status_code,400)
        doctor=f'/api/v1/hospitals/{DEMO_HOSPITAL_ID}/patients/{_demo_id("patient",1)}/nutrition/{row["id"]}'
        self.assertEqual(self.client.patch(doctor,json={'action':'approve','note':'Reviewed for prototype presentation only.'},headers=self.headers).status_code,403)
        approved=self.client.patch(doctor,json={'action':'approve','note':'Reviewed ingredients and individual portions.'},headers={'X-Demo-Role':'doctor'})
        self.assertEqual(approved.status_code,200)
        self.assertEqual(approved.json['plan']['data']['status'],'clinician_approved')
        swapped=self.client.patch('/api/v1/patient/nutrition/plans/'+row['id'],json={'day':0,'slot':'breakfast','swap_to':'dosa'},headers=self.headers)
        self.assertEqual(swapped.json['plan']['data']['status'],'draft_for_clinician_review')
        prefs['allergens'].append('sesame')
        self.client.put('/api/v1/patient/nutrition',json=prefs,headers=self.headers)
        self.assertTrue(self.client.get('/api/v1/patient/nutrition',headers=self.headers).json['requires_refresh'])
