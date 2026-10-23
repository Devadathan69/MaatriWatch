"""Patient-approved guardian links and durable, non-clinical SOS notifications."""
import hashlib
import re
import secrets
from datetime import datetime, timedelta, timezone
from uuid import UUID

from firebase_admin import messaging
from flask import Blueprint, abort, current_app, g, jsonify, request
from psycopg.types.json import Jsonb
from .auth import require_firebase_user, require_verified_identity, lookup_app_user
from .care_records import actor_patient, wire
from .companion import body, text
from .db import get_db

guardians_bp = Blueprint('guardians', __name__)


def guardian_actor():
    actor = lookup_app_user(g.firebase_claims['uid'])
    if not actor or not actor['is_active']:
        abort(403, description='Link your guardian account first')
    return actor


@guardians_bp.get('/account/access')
@require_verified_identity
def account_access():
    actor = lookup_app_user(g.firebase_claims['uid'])
    patient = guardian = False
    if actor and actor['is_active']:
        with get_db().cursor() as cur:
            cur.execute('SELECT EXISTS(SELECT 1 FROM patients WHERE user_id=%s AND is_active) AS patient, EXISTS(SELECT 1 FROM guardian_links WHERE guardian_user_id=%s AND is_active) AS guardian', (actor['id'],actor['id']))
            row = cur.fetchone()
            patient, guardian = row['patient'], row['guardian']
    return jsonify({'patient': patient, 'guardian': guardian})


@guardians_bp.route('/patient/guardians', methods=['GET','POST'])
@require_firebase_user
def patient_guardians():
    patient = actor_patient()
    conn = get_db()
    with conn.cursor() as cur:
        if request.method == 'GET':
            cur.execute('''SELECT l.id,u.display_name,u.email,l.created_at FROM guardian_links l
                JOIN app_users u ON u.id=l.guardian_user_id WHERE l.patient_id=%s AND l.hospital_id=%s AND l.is_active ORDER BY l.created_at''', (patient['id'],patient['hospital_id']))
            return jsonify({'items': wire(cur.fetchall())})
        email = text(body().get('email'), 'guardian email', 254).casefold()
        if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',email):
            abort(400, description='Enter the guardian’s email address')
        if email == (g.actor.get('email') or '').casefold():
            abort(400, description='Invite another person as your guardian')
        cur.execute('SELECT id FROM patients WHERE id=%s FOR UPDATE', (patient['id'],))
        cur.execute('SELECT count(*) AS total FROM guardian_links WHERE patient_id=%s AND is_active', (patient['id'],))
        if cur.fetchone()['total'] >= 3:
            abort(409, description='Three guardians are already linked. Remove one before adding another.')
        # Reissuing an invitation invalidates earlier codes for that recipient.
        cur.execute('UPDATE guardian_invitations SET expires_at=now() WHERE patient_id=%s AND guardian_email=%s AND claimed_at IS NULL', (patient['id'],email))
        token = secrets.token_urlsafe(24)
        digest = hashlib.sha256(token.encode()).hexdigest()
        expires = datetime.now(timezone.utc) + timedelta(hours=24)
        cur.execute('INSERT INTO guardian_invitations(hospital_id,patient_id,guardian_email,token_hash,expires_at) VALUES (%s,%s,%s,%s,%s)', (patient['hospital_id'],patient['id'],email,digest,expires))
    conn.commit()
    return jsonify({'code':token,'expires_at':expires.isoformat(),'email':email}),201


@guardians_bp.delete('/patient/guardians/<identifier>')
@require_firebase_user
def revoke_guardian(identifier):
    try: UUID(identifier)
    except ValueError: abort(404)
    patient = actor_patient()
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute('SELECT id FROM patients WHERE id=%s FOR UPDATE', (patient['id'],))
        cur.execute('UPDATE guardian_links SET is_active=false WHERE id=%s AND hospital_id=%s AND patient_id=%s RETURNING guardian_user_id', (identifier,patient['hospital_id'],patient['id']))
        link = cur.fetchone()
        if not link: abort(404)
        cur.execute("UPDATE guardian_notifications SET push_status='cancelled' WHERE patient_id=%s AND guardian_user_id=%s AND push_status IN ('pending','no_device')", (patient['id'],link['guardian_user_id']))
    conn.commit()
    return jsonify({'removed':True})


@guardians_bp.post('/guardian/link')
@require_verified_identity
def accept_invitation():
    from .ai_chat import _allow_request
    if not _allow_request('guardian-link:'+g.firebase_claims['uid'], limit=10, window_seconds=900):
        abort(429, description='Too many linking attempts. Please try again later.')
    code = text(body().get('code'), 'invitation code', 128)
    digest = hashlib.sha256(code.encode()).hexdigest()
    conn = get_db()
    with conn.cursor() as cur:
        cur.execute('''SELECT * FROM guardian_invitations WHERE token_hash=%s AND guardian_email=%s
            AND claimed_at IS NULL AND expires_at>now() FOR UPDATE''', (digest,g.firebase_claims['email'].casefold()))
        invitation = cur.fetchone()
        if not invitation: abort(400, description='The code is invalid, expired or intended for another email address')
        cur.execute('SELECT id,user_id FROM patients WHERE id=%s AND is_active FOR UPDATE', (invitation['patient_id'],))
        patient = cur.fetchone()
        if not patient: abort(409, description='This patient profile is unavailable')
        cur.execute('''INSERT INTO app_users(firebase_uid,email,display_name) VALUES (%s,%s,%s)
            ON CONFLICT(firebase_uid) DO UPDATE SET firebase_uid=EXCLUDED.firebase_uid RETURNING id,is_active''',
            (g.firebase_claims['uid'],g.firebase_claims['email'].casefold(),g.firebase_claims.get('name') or 'My guardian'))
        actor = cur.fetchone()
        if not actor['is_active'] or actor['id'] == patient['user_id']:
            abort(403, description='This account cannot be linked as a guardian')
        cur.execute('SELECT count(*) AS total FROM guardian_links WHERE patient_id=%s AND is_active', (patient['id'],))
        if cur.fetchone()['total'] >= 3: abort(409, description='The patient already has three guardians')
        cur.execute('''INSERT INTO guardian_links(hospital_id,patient_id,guardian_user_id) VALUES (%s,%s,%s)
            ON CONFLICT(patient_id,guardian_user_id) DO UPDATE SET is_active=true''', (invitation['hospital_id'],patient['id'],actor['id']))
        cur.execute('UPDATE guardian_invitations SET claimed_at=now() WHERE id=%s', (invitation['id'],))
    conn.commit()
    return jsonify({'linked':True}),201


@guardians_bp.get('/guardian/home')
@require_verified_identity
def guardian_home():
    actor = lookup_app_user(g.firebase_claims['uid'])
    if not actor: return jsonify({'patients':[],'notifications':[]})
    if not actor['is_active']: abort(403)
    with get_db().cursor() as cur:
        cur.execute('''SELECT l.id,p.full_name FROM guardian_links l JOIN patients p ON p.id=l.patient_id
            WHERE l.guardian_user_id=%s AND l.is_active AND p.is_active ORDER BY l.created_at''', (actor['id'],))
        patients = cur.fetchall()
        cur.execute('''SELECT n.id,n.created_at,n.read_at,n.push_status,p.full_name FROM guardian_notifications n
            JOIN guardian_links l ON l.patient_id=n.patient_id AND l.guardian_user_id=n.guardian_user_id AND l.hospital_id=n.hospital_id
            JOIN patients p ON p.id=n.patient_id WHERE n.guardian_user_id=%s AND l.is_active AND p.is_active ORDER BY n.created_at DESC LIMIT 100''', (actor['id'],))
        notifications = cur.fetchall()
    return jsonify({'patients':wire(patients),'notifications':wire(notifications)})


@guardians_bp.patch('/guardian/notifications/<identifier>')
@require_verified_identity
def mark_read(identifier):
    try: UUID(identifier)
    except ValueError: abort(404)
    actor = guardian_actor()
    with get_db().cursor() as cur:
        cur.execute('''UPDATE guardian_notifications n SET read_at=now() FROM guardian_links l WHERE n.id=%s AND n.guardian_user_id=%s
            AND l.patient_id=n.patient_id AND l.guardian_user_id=n.guardian_user_id AND l.is_active RETURNING n.id''', (identifier,actor['id']))
        if not cur.fetchone(): abort(404)
    get_db().commit()
    return jsonify({'read':True})


@guardians_bp.route('/guardian/push-device',methods=['POST','DELETE'])
@require_verified_identity
def push_device():
    actor = guardian_actor()
    token = text(body().get('token'),'device token',4096)
    if len(token)<20: abort(400, description='Invalid device token')
    digest = hashlib.sha256(token.encode()).hexdigest()
    with get_db().cursor() as cur:
        if request.method=='DELETE':
            cur.execute('UPDATE guardian_push_devices SET is_active=false WHERE guardian_user_id=%s AND token_hash=%s',(actor['id'],digest))
        else:
            cur.execute('SELECT 1 FROM guardian_links WHERE guardian_user_id=%s AND is_active LIMIT 1',(actor['id'],))
            if not cur.fetchone(): abort(403,description='Link a patient before enabling SOS notifications')
            cur.execute('SELECT count(*) AS total FROM guardian_push_devices WHERE guardian_user_id=%s AND is_active AND token_hash<>%s',(actor['id'],digest))
            if cur.fetchone()['total']>=5: abort(409,description='Five guardian devices are already registered')
            cur.execute('''INSERT INTO guardian_push_devices(guardian_user_id,token,token_hash) VALUES (%s,%s,%s)
                ON CONFLICT(token_hash) DO UPDATE SET guardian_user_id=EXCLUDED.guardian_user_id,token=EXCLUDED.token,is_active=true,updated_at=now()''',(actor['id'],token,digest))
            cur.execute("UPDATE guardian_notifications SET push_status='pending',next_attempt_at=now() WHERE guardian_user_id=%s AND push_status='no_device' AND created_at>now()-interval '15 minutes'",(actor['id'],))
    get_db().commit()
    return jsonify({'enabled':request.method=='POST'})


def queue_guardian_sos(cur, patient, alert_id):
    """Persist notifications in the SOS transaction; never promise delivery."""
    cur.execute('''INSERT INTO guardian_notifications(hospital_id,patient_id,guardian_user_id,alert_id)
        SELECT l.hospital_id,l.patient_id,l.guardian_user_id,%s FROM guardian_links l
        JOIN app_users u ON u.id=l.guardian_user_id AND u.is_active WHERE l.patient_id=%s AND l.hospital_id=%s AND l.is_active
        AND NOT EXISTS(SELECT 1 FROM guardian_notifications n WHERE n.patient_id=l.patient_id AND n.guardian_user_id=l.guardian_user_id AND n.created_at>now()-interval '1 minute') RETURNING id''', (alert_id,patient['id'],patient['hospital_id']))
    return len(cur.fetchall())


def deliver_guardian_notifications():
    if not current_app.config.get('FIREBASE_AUTH_READY'): return 0
    conn = get_db()
    delivered = 0
    with conn.cursor() as cur:
        cur.execute('''SELECT n.* FROM guardian_notifications n JOIN guardian_links l
            ON l.patient_id=n.patient_id AND l.guardian_user_id=n.guardian_user_id AND l.hospital_id=n.hospital_id
            JOIN app_users u ON u.id=n.guardian_user_id AND u.is_active JOIN patients p ON p.id=n.patient_id AND p.is_active
            WHERE n.push_status='pending' AND n.next_attempt_at<=now() AND l.is_active
            ORDER BY n.created_at LIMIT 20 FOR UPDATE OF n,l SKIP LOCKED''')
        rows = cur.fetchall()
        for row in rows:
            if row['created_at'] < datetime.now(timezone.utc)-timedelta(minutes=15):
                cur.execute("UPDATE guardian_notifications SET push_status='expired' WHERE id=%s",(row['id'],)); continue
            cur.execute('SELECT token,token_hash FROM guardian_push_devices WHERE guardian_user_id=%s AND is_active',(row['guardian_user_id'],))
            targets = cur.fetchall()
            sent = set(row['delivered_devices'])
            for device in targets:
                if device['token_hash'] in sent: continue
                try:
                    messaging.send(messaging.Message(token=device['token'],
                        notification=messaging.Notification(title='MaatriWatch SOS', body='Someone linked to you has requested urgent help. Open MaatriWatch now.'),
                        data={'notification_id':str(row['id']),'screen':'guardian'},
                        android=messaging.AndroidConfig(priority='high',ttl=timedelta(minutes=5),
                            notification=messaging.AndroidNotification(channel_id='guardian_sos',sound='default',visibility='private'))))
                    sent.add(device['token_hash'])
                except Exception:
                    pass  # Device tokens and provider error details must never be logged.
            attempts = row['push_attempts']+1
            complete = bool(targets) and all(t['token_hash'] in sent for t in targets)
            status = 'no_device' if not targets else 'sent' if complete else 'failed' if attempts>=5 else 'pending'
            cur.execute('UPDATE guardian_notifications SET push_status=%s,push_attempts=%s,delivered_devices=%s,next_attempt_at=%s WHERE id=%s',
                (status,attempts,Jsonb(sorted(sent)),datetime.now(timezone.utc)+timedelta(seconds=30*2**attempts),row['id']))
            delivered += int(complete)
    conn.commit()
    return delivered
