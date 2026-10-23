"""Pregnancy meal-planning drafts built from an explicit, allergen-labelled catalog."""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
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
BY_ID = {m['id']:m for m in CATALOG}
SLOTS = ['breakfast','morning_snack','lunch','afternoon_snack','dinner']


def preferences(repo):
    values = repo.list('nutrition_preferences',1)
    return {**DEFAULTS, **(values[0]['data'] if values else {})}


def prefs_digest(prefs):
    return hashlib.sha256(json.dumps(prefs,sort_keys=True).encode()).hexdigest()


def eligible(prefs, slot):
    rows=[]
    for item in CATALOG:
        if item['slot'] != slot or set(item['allergens']) & set(prefs['allergens']):
            continue
        if prefs['diet']=='vegan' and item['diet']!='vegan' or prefs['diet']=='vegetarian' and item['diet']=='non_vegetarian':
            continue
        if any(dislike.casefold() in ' '.join(item['ingredients']).casefold() for dislike in prefs['dislikes']):
            continue
        rows.append(item)
    return rows


def build_plan(prefs, report, start=None):
    if not prefs['allergies_confirmed']:
        abort(409,description='Confirm food allergies/preferences before creating a plan. Unlisted allergies need dietitian review.')
    if report['data']['context']['stage'] not in ('pregnant','postpartum'):
        abort(409,description='Record pregnancy or postpartum context first. A dietitian must adapt portions and lactation needs.')
    analysis=report['data']['analysis']
    if analysis['urgent_review']:
        abort(409,description='This report needs prompt clinical assessment. Please contact your care team; a meal plan is not treatment.')
    focus=[]
    if any(r['analyte'].startswith('ogtt_') and r['status']=='above_threshold' for r in analysis['readings']):
        focus.append('balanced_carb')
    if any(r['analyte']=='hemoglobin' and r['status']=='below_threshold' for r in analysis['readings']):
        focus.append('iron_support')
    start=start or datetime.now(timezone.utc).date()
    days=[]
    for i in range(7):
        meals=[]
        for slot in SLOTS:
            options=eligible(prefs,slot)
            if not options:
                abort(409,description=f'No safe catalog option for {slot}. Ask your dietitian to create a plan for these restrictions.')
            options=sorted(options,key=lambda m: -sum(tag in m['tags'] for tag in focus))
            selected=deepcopy(options[i%len(options)])
            selected['completed']=False
            meals.append(selected)
        days.append({'date':(start+timedelta(days=i)).isoformat(),'meals':meals})
    return {'title':'A week of gentle nourishment','days':days,'status':'draft_for_clinician_review',
        'report_id':report['id'],'preferences_digest':prefs_digest(prefs),'preferences':prefs,
        'focus':focus,'source_policy':analysis['policy_version'],'review_note':None,
        'notice':'A food-planning draft, not a prescribed therapeutic diet. Portions are examples and nutrient adequacy is not clinically validated. A dietitian must adapt this to your needs.',
        'food_safety':['Use pasteurised dairy and fully cooked eggs/fish.','Wash produce; cook, chill and store food safely.','No alcohol, raw/undercooked animal foods, or weight-loss targets are suggested.'],
        'sources':['https://www.fda.gov/food/people-risk-foodborne-illness/food-safety-moms-be', 'https://health.gov/sites/default/files/2021-12/DGA_Pregnancy_FactSheet-508.pdf']}


@nutrition_bp.route('/patient/nutrition',methods=['GET','PUT','POST'])
@require_firebase_user
def nutrition_home():
    repo=records(actor_patient())
    prefs=preferences(repo)
    if request.method=='PUT':
        values=body()
        if values.get('diet') not in ('vegetarian','vegan','non_vegetarian'):
            abort(400,description='Choose a supported dietary preference')
        allergens=values.get('allergens',[])
        dislikes=values.get('dislikes',[])
        if not isinstance(allergens,list) or any(a not in ALLERGENS for a in allergens):
            abort(400,description='Unlisted allergies need a dietitian plan; this catalog cannot safely personalise them')
        if not isinstance(dislikes,list) or len(dislikes)>20 or any(not isinstance(v,str) or not v.strip() or len(v)>80 for v in dislikes):
            abort(400,description='Invalid disliked ingredients')
        if not isinstance(values.get('allergies_confirmed'),bool):
            abort(400,description='Explicitly confirm food allergy information')
        prefs={'diet':values['diet'],'allergens':sorted(set(allergens)),'dislikes':dislikes,'allergies_confirmed':values['allergies_confirmed']}
        repo.put('nutrition_preferences',prefs,stable_key='settings')
    if request.method=='POST':
        value=body()
        report=repo.get('report_analysis',value.get('report_id'))
        if not report:
            abort(404,description='Confirm and save a report first')
        row=repo.put('diet_plan',build_plan(prefs,report))
        return jsonify({'plan':row}),201
    plans=repo.list('diet_plan',1)
    latest=plans[0] if plans else None
    refresh=bool(latest and latest['data']['preferences_digest']!=prefs_digest(prefs))
    return jsonify({'preferences':prefs,'plan':None if refresh else latest,'requires_refresh':refresh,
                    'catalog':CATALOG,'allergens':ALLERGENS})


@nutrition_bp.patch('/patient/nutrition/plans/<identifier>')
@require_firebase_user
def change_plan(identifier):
    repo=records(actor_patient())
    row=repo.get('diet_plan',identifier)
    if not row:
        abort(404,description='Plan not found')
    prefs=preferences(repo)
    data=row['data']
    if data['preferences_digest']!=prefs_digest(prefs):
        abort(409,description='Preferences changed; create a fresh plan first')
    values=body()
    day=values.get('day')
    slot=values.get('slot')
    if isinstance(day,bool) or not isinstance(day,int) or not 0<=day<7 or slot not in SLOTS:
        abort(400,description='Choose a valid day and meal')
    index=SLOTS.index(slot)
    if 'swap_to' in values:
        replacement=next((m for m in eligible(prefs,slot) if m['id']==values['swap_to']),None)
        if not replacement:
            abort(400,description='This meal is not compatible with your preferences/allergies')
        data['days'][day]['meals'][index]={**deepcopy(replacement),'completed':False}
        data.update(status='draft_for_clinician_review',review_note=None)
        data.pop('reviewed_by',None);data.pop('reviewed_at',None)
    elif isinstance(values.get('completed'),bool):
        data['days'][day]['meals'][index]['completed']=values['completed']
    else:
        abort(400,description='Choose a replacement meal or completion state')
    return jsonify({'plan':repo.put('diet_plan',data,identifier)})


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
