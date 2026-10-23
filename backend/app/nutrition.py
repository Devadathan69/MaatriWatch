"""Confirmed reports and preference-first AI food guidance with an ingredient catalog."""
from datetime import datetime, timezone
import hashlib
import json

from flask import Blueprint, abort, g, jsonify, request
from .auth import require_firebase_user, require_hospital_role
from .care_records import actor_patient, records, demo_enabled
from .companion import body, text
from .db import get_db

nutrition_bp = Blueprint('nutrition',__name__)
ALLERGENS = ['milk','egg','fish','soy','wheat','gluten','peanut','tree_nut','sesame','legume']
DEFAULTS = {'diet':'vegetarian','allergens':[], 'dislikes':[], 'allergies_confirmed':False}


def meal(id, name, slot, art, ingredients, portion, *, allergens=(), diet='vegan', tags=()):
    return {'id':id,'name':name,'slot':slot,'art':art,'ingredients':ingredients,
            'portion':portion,'allergens':list(allergens),'diet':diet,'tags':list(tags),
            'preparation':'Use clean water and washed produce. Cook thoroughly and serve fresh; refrigerate leftovers promptly.'}


CATALOG = [
    meal('idli','Idli with vegetable sambar','breakfast','idli',['rice','urad dal','toor dal','carrot','tomato','cumin','turmeric','cooking oil'],'Example: 2 idlis + a bowl of sambar',allergens=['legume']),
    meal('oats','Vegetable oats bowl','breakfast','oats',['oats','carrot','peas','cumin','cooking oil'],'Example: a medium bowl; discuss your portion needs',allergens=['legume','gluten'],tags=['balanced_carb']),
    meal('dosa','Moong dosa with tomato chutney','breakfast','dosa',['moong dal','tomato','cumin','cooking oil'],'Example: 2 small dosas with chutney',allergens=['legume'],tags=['iron_support','balanced_carb']),
    meal('puttu','Small ragi puttu with kadala','breakfast','rice',['ragi','coconut','chickpea','tomato','turmeric','cooking oil'],'Example: a small puttu + kadala curry',allergens=['legume'],tags=['iron_support']),
    meal('fruit','Guava and a small banana','morning_snack','fruit',['guava','banana'],'Example: one small fruit serving; adjust with your care team'),
    meal('curd','Plain pasteurised curd with berries','morning_snack','curd',['pasteurised milk curd','berries'],'Example: a small bowl, no added sugar',allergens=['milk'],diet='vegetarian'),
    meal('chana_snack','Steamed chickpea and cucumber bowl','morning_snack','salad',['chickpea','cucumber','lemon','cumin'],'Example: a small bowl; chickpeas thoroughly cooked',allergens=['legume'],tags=['balanced_carb']),
    meal('orange','Orange and pumpkin seeds','morning_snack','fruit',['orange','pumpkin seed'],'Example: an orange + a spoon of seeds'),
    meal('rice_dal','Matta rice, dal and greens','lunch','rice',['matta rice','moong dal','spinach','carrot','lemon','cumin','cooking oil'],'Example: a modest rice portion, dal, and vegetables',allergens=['legume'],tags=['iron_support','balanced_carb']),
    meal('roti_dal','Chapati, dal and mixed vegetables','lunch','dosa',['wheat','toor dal','carrot','beans','cumin','cooking oil'],'Example: 2 small chapatis, dal and vegetables',allergens=['wheat','gluten','legume'],tags=['balanced_carb']),
    meal('fish_rice','Fully cooked sardines, rice and vegetables','lunch','fish',['sardine','matta rice','carrot','spinach','lemon','turmeric','cooking oil'],'Example: a cooked fish serving, rice and vegetables',allergens=['fish'],diet='non_vegetarian',tags=['iron_support']),
    meal('quinoa','Quinoa, roasted vegetables and seeds','lunch','salad',['quinoa','carrot','pumpkin','pumpkin seed','lemon','cooking oil'],'Example: a bowl; individual portions need review',tags=['balanced_carb']),
    meal('sundal','Warm moong sundal','afternoon_snack','curry',['moong dal','coconut','cumin','lemon'],'Example: a small cooked bowl',allergens=['legume'],tags=['iron_support']),
    meal('makhana','Roasted makhana with a pear','afternoon_snack','fruit',['makhana','pear','cooking oil'],'Example: a small bowl + a small fruit'),
    meal('egg','Well-cooked egg with cucumber','afternoon_snack','egg',['egg','cucumber'],'Example: one fully cooked egg',allergens=['egg'],diet='non_vegetarian'),
    meal('yogurt','Plain pasteurised yogurt','afternoon_snack','curd',['pasteurised milk yogurt'],'Example: a small bowl, no added sugar',allergens=['milk'],diet='vegetarian'),
    meal('khichdi','Vegetable moong khichdi','dinner','curry',['rice','moong dal','carrot','spinach','cumin','cooking oil'],'Example: a bowl with extra cooked vegetables',allergens=['legume'],tags=['balanced_carb']),
    meal('idiyappam','Idiyappam with vegetable and lentil stew','dinner','rice',['rice','moong dal','carrot','coconut','cumin'],'Example: 2 small nests + stew',allergens=['legume']),
    meal('roti_paneer','Chapati with paneer and vegetables','dinner','dosa',['wheat','pasteurised milk paneer','carrot','spinach','cumin','cooking oil'],'Example: 2 small chapatis + cooked paneer/vegetables',allergens=['wheat','gluten','milk'],diet='vegetarian'),
    meal('rice_pumpkin','Rice, pumpkin and seed bowl','dinner','rice',['rice','pumpkin','pumpkin seed','spinach','cooking oil'],'Example: a bowl; discuss protein adequacy with your dietitian'),
]
def preferences(repo):
    values = repo.list('nutrition_preferences',1)
    return {**DEFAULTS, **(values[0]['data'] if values else {})}


def prefs_digest(prefs):
    return hashlib.sha256(json.dumps(prefs,sort_keys=True).encode()).hexdigest()


@nutrition_bp.route('/patient/nutrition',methods=['GET','PUT','POST'])
@require_firebase_user
def nutrition_home():
    repo=records(actor_patient())
    prefs=preferences(repo)
    if request.method=='PUT':
        values=body()
        from .food_guidance import validate_preferences
        prefs = validate_preferences(values)
        repo.put('nutrition_preferences',prefs,stable_key='settings')
    if request.method=='POST':
        value=body()
        report=repo.get('report_analysis',value.get('report_id'))
        if not report:
            abort(404,description='Confirm and save a report first')
        if value.get('processing_consent') is not True:
            abort(400, description='Allow AI to analyse your report and food preferences first')
        from .food_guidance import generate_guidance
        from .companion import preferences as companion_preferences
        row=repo.put('diet_plan',generate_guidance(prefs,report,companion_preferences(repo)['language']))
        return jsonify({'plan':row}),201
    plans=repo.list('diet_plan',1)
    latest=plans[0] if plans and plans[0]['data'].get('format') == 'food_guidance_v1' else None
    refresh=bool(latest and latest['data']['preferences_digest']!=prefs_digest(prefs))
    return jsonify({'preferences':prefs,'plan':None if refresh else latest,'requires_refresh':refresh,
                    'profile_complete':prefs.get('questionnaire_version') == 1,'allergens':ALLERGENS})


def clinician_patient(hospital_id,patient_id):
    from uuid import UUID
    try:
        UUID(hospital_id);UUID(patient_id)
    except ValueError:
        abort(404)
    if demo_enabled():
        from .demo_store import demo_store
        patient=demo_store.patient_detail(patient_id)['patient']
    else:
        with get_db().cursor() as cur:
            cur.execute('SELECT id,hospital_id FROM patients WHERE hospital_id=%s AND id=%s AND is_active=true',(hospital_id,patient_id))
            patient=cur.fetchone()
    if not patient or str(patient['hospital_id'])!=hospital_id:
        abort(404)
    return patient


@nutrition_bp.get('/hospitals/<hospital_id>/patients/<patient_id>/nutrition')
@require_hospital_role('clinician')
def clinician_nutrition(hospital_id,patient_id):
    repo=records(clinician_patient(hospital_id,patient_id))
    return jsonify({'reports':repo.list('report_analysis',30),'plans':repo.list('diet_plan',10),'preferences':preferences(repo)})


@nutrition_bp.patch('/hospitals/<hospital_id>/patients/<patient_id>/nutrition/<identifier>')
@require_hospital_role('clinician')
def review_plan(hospital_id,patient_id,identifier):
    repo=records(clinician_patient(hospital_id,patient_id))
    row=repo.get('diet_plan',identifier)
    if not row:
        abort(404,description='Plan not found')
    values=body()
    action=values.get('action')
    if action not in ('approve','request_changes'):
        abort(400,description='action must be approve or request_changes')
    if row['data']['preferences_digest']!=prefs_digest(preferences(repo)):
        abort(409,description='Patient food preferences changed; review a new plan')
    row['data'].update(status='clinician_approved' if action=='approve' else 'changes_requested',
        review_note=text(values.get('note'),'review note',2000),reviewed_by=str(g.actor['id']),reviewed_at=datetime.now(timezone.utc).isoformat())
    return jsonify({'plan':repo.put('diet_plan',row['data'],identifier)})
