"""Tenant-scoped companion repository; isolated in-memory adapter for demos/tests."""
from __future__ import annotations

from copy import deepcopy
from datetime import date, datetime, timezone
from threading import RLock
from uuid import UUID, uuid4

from flask import abort, current_app, g
from psycopg.types.json import Jsonb

from .db import get_db
from .patient import _patient_for_actor

KINDS = {'preferences', 'memory', 'message', 'reminder', 'notification', 'concern',
         'summary', 'report_analysis', 'diet_plan', 'nutrition_preferences'}


def wire(value):
    if isinstance(value, dict):
        return {str(k): wire(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [wire(v) for v in value]
    if isinstance(value, datetime):
        return value.astimezone(timezone.utc).isoformat()
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, UUID):
        return str(value)
    # psycopg numeric values are intentionally converted only at the API edge.
    from decimal import Decimal
    if isinstance(value, Decimal):
        return float(value)
    return value


def demo_enabled():
    return bool(current_app.config.get('DEMO_MODE') and current_app.config.get('DEMO_IN_MEMORY'))


def actor_patient():
    if demo_enabled() and getattr(g, 'demo_role', None) == 'patient':
        from .demo_store import demo_store, _demo_id
        return demo_store.patient_detail(_demo_id('patient', 1))['patient']
    with get_db().cursor() as cursor:
        return _patient_for_actor(cursor)


def records(patient):
    if demo_enabled():
        backing = current_app.extensions.setdefault('companion_demo_records', ({}, RLock()))
        return MemoryRecords(patient, backing)
    return PostgresRecords(patient)


def _kind(kind):
    if kind not in KINDS:
        raise ValueError('Unsupported companion record kind')


class MemoryRecords:
    def __init__(self, patient, backing):
        self.patient = patient
        self.rows, self.lock = backing

    def list(self, kind, limit=100):
        _kind(kind)
        with self.lock:
            rows = [r for r in self.rows.values() if r['patient_id'] == str(self.patient['id'])
                    and r['hospital_id'] == str(self.patient['hospital_id']) and r['kind'] == kind]
            return deepcopy(sorted(rows, key=lambda r: (r['created_at'], r['id']), reverse=True)[:limit])

    def get(self, kind, identifier):
        return next((r for r in self.list(kind, 10000) if r['id'] == str(identifier)), None)

    def put(self, kind, data, identifier=None, stable_key=None):
        _kind(kind)
        with self.lock:
            prior = self.get(kind, identifier) if identifier else next(
                (r for r in self.list(kind, 10000) if stable_key is not None and r['stable_key'] == stable_key), None)
            if identifier and prior is None:
                abort(404, description='Record not found')
            now = datetime.now(timezone.utc).isoformat()
            row = {**(prior or {}), 'id': prior['id'] if prior else str(uuid4()),
                   'hospital_id': str(self.patient['hospital_id']), 'patient_id': str(self.patient['id']),
                   'kind': kind, 'data': deepcopy(data), 'stable_key': stable_key if not prior else prior['stable_key'],
                   'created_at': prior['created_at'] if prior else now, 'updated_at': now}
            self.rows[row['id']] = row
            return deepcopy(row)

    def delete(self, kind, identifier=None):
        with self.lock:
            keys = [r['id'] for r in self.list(kind, 10000) if identifier is None or r['id'] == identifier]
            for key in keys:
                del self.rows[key]
            return len(keys)


class PostgresRecords:
    def __init__(self, patient):
        self.patient = patient

    @property
    def scope(self):
        return (self.patient['hospital_id'], self.patient['id'])

    def list(self, kind, limit=100):
        _kind(kind)
        with get_db().cursor() as cur:
            cur.execute('SELECT * FROM companion_records WHERE hospital_id=%s AND patient_id=%s AND kind=%s ORDER BY created_at DESC,id DESC LIMIT %s', (*self.scope, kind, min(limit, 10000)))
            return wire(cur.fetchall())

    def get(self, kind, identifier):
        _kind(kind)
        try:
            UUID(str(identifier))
        except ValueError:
            abort(404, description='Record not found')
        with get_db().cursor() as cur:
            cur.execute('SELECT * FROM companion_records WHERE hospital_id=%s AND patient_id=%s AND kind=%s AND id=%s', (*self.scope, kind, identifier))
            return wire(cur.fetchone())

    def put(self, kind, data, identifier=None, stable_key=None):
        _kind(kind)
        connection = get_db()
        with connection.cursor() as cur:
            if identifier:
                if not self.get(kind, identifier):
                    abort(404, description='Record not found')
                cur.execute('UPDATE companion_records SET data=%s,updated_at=now() WHERE hospital_id=%s AND patient_id=%s AND kind=%s AND id=%s RETURNING *', (Jsonb(data), *self.scope, kind, identifier))
            else:
                cur.execute('''INSERT INTO companion_records(hospital_id,patient_id,kind,data,stable_key)
                    VALUES (%s,%s,%s,%s,%s) ON CONFLICT(patient_id,kind,stable_key)
                    DO UPDATE SET data=EXCLUDED.data,updated_at=now()
                    WHERE companion_records.hospital_id=EXCLUDED.hospital_id RETURNING *''', (*self.scope, kind, Jsonb(data), stable_key))
            row = cur.fetchone()
            if not row:
                abort(409, description='Record scope conflict')
            cur.execute('''INSERT INTO audit_log(actor_user_id,hospital_id,action,entity_type,entity_id,metadata)
                VALUES (%s,%s,%s,'companion_record',%s,%s)''',
                (g.actor['id'] if hasattr(g, 'actor') else None, self.patient['hospital_id'], f'companion.{kind}.saved', str(row['id']), Jsonb({'kind': kind})))
        connection.commit()
        return wire(row)

    def delete(self, kind, identifier=None):
        _kind(kind)
        connection = get_db()
        with connection.cursor() as cur:
            sql = 'DELETE FROM companion_records WHERE hospital_id=%s AND patient_id=%s AND kind=%s'
            args = (*self.scope, kind)
            if identifier:
                if not self.get(kind, identifier):
                    abort(404, description='Record not found')
                sql += ' AND id=%s'
                args += (identifier,)
            cur.execute(sql, args)
            count = cur.rowcount
            cur.execute('''INSERT INTO audit_log(actor_user_id,hospital_id,action,entity_type,metadata)
                VALUES (%s,%s,%s,'companion_record',%s)''',
                (g.actor['id'], self.patient['hospital_id'], f'companion.{kind}.deleted', Jsonb({'count': count})))
        connection.commit()
        return count
