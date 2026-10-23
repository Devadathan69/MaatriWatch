"""Transactional slot booking. Memory adapter is explicitly demo-only."""

from copy import deepcopy
from datetime import datetime, timezone
from threading import RLock
from uuid import UUID, uuid4
from flask import abort, current_app, g
from .care_records import demo_enabled, wire
from .db import get_db


def identifier(value):
    try:
        return str(UUID(str(value)))
    except (ValueError, TypeError):
        abort(404, description="Consultation not found")


def overlap(a, b, c, d):
    return a < d and c < b


def schedule():
    if demo_enabled():
        backing = current_app.extensions.setdefault(
            "consultation_demo", ({"slots": {}, "appointments": {}}, RLock())
        )
        return MemorySchedule(*backing)
    return PostgresSchedule()


class MemorySchedule:
    def __init__(self, data, lock):
        self.data, self.lock = data, lock

    def slots(self, hospital):
        booked = {
            r["slot_id"]
            for r in self.data["appointments"].values()
            if r["status"] == "booked"
        }
        return deepcopy(
            sorted(
                [
                    r
                    for r in self.data["slots"].values()
                    if r["hospital_id"] == hospital
                    and r["status"] == "published"
                    and r["id"] not in booked
                    and datetime.fromisoformat(r["start_at"])
                    > datetime.now(timezone.utc)
                ],
                key=lambda r: r["start_at"],
            )
        )

    def publish(self, hospital, clinician, start, end):
        with self.lock:
            if any(
                r["clinician_user_id"] == clinician
                and r["status"] == "published"
                and overlap(
                    start,
                    end,
                    datetime.fromisoformat(r["start_at"]),
                    datetime.fromisoformat(r["end_at"]),
                )
                for r in self.data["slots"].values()
            ):
                abort(
                    409,
                    description="This clinician already has overlapping availability",
                )
            row = {
                "id": str(uuid4()),
                "hospital_id": hospital,
                "clinician_user_id": clinician,
                "clinician_name": "Demo clinician",
                "start_at": start.isoformat(),
                "end_at": end.isoformat(),
                "status": "published",
            }
            self.data["slots"][row["id"]] = row
            return deepcopy(row)

    def appointments(self, hospital, *, patient=None, clinician=None):
        with self.lock:
            return deepcopy(
                sorted(
                    [
                        r
                        for r in self.data["appointments"].values()
                        if r["hospital_id"] == hospital
                        and (patient is None or r["patient_id"] == patient)
                        and (clinician is None or r["clinician_user_id"] == clinician)
                    ],
                    key=lambda r: r["start_at"],
                )
            )

    def get(self, id, hospital, *, patient=None, clinician=None):
        return next(
            (
                r
                for r in self.appointments(
                    hospital, patient=patient, clinician=clinician
                )
                if r["id"] == id
            ),
            None,
        )

    def book(self, patient, slot_id, reason, replace_id=None):
        with self.lock:
            slot = self.data["slots"].get(slot_id)
            if (
                not slot
                or slot["hospital_id"] != str(patient["hospital_id"])
                or slot["status"] != "published"
            ):
                abort(404, description="Slot not found")
            if datetime.fromisoformat(slot["start_at"]) <= datetime.now(timezone.utc):
                abort(409, description="This slot is no longer available")
            prior = (
                self.get(replace_id, slot["hospital_id"], patient=str(patient["id"]))
                if replace_id
                else None
            )
            if replace_id and (not prior or prior["status"] != "booked"):
                abort(409, description="This visit cannot be rescheduled")
            for row in self.data["appointments"].values():
                if row["status"] != "booked" or row["id"] == replace_id:
                    continue
                if row["slot_id"] == slot_id:
                    abort(409, description="Someone has already booked this slot")
                if row["patient_id"] == str(patient["id"]) and overlap(
                    slot["start_at"], slot["end_at"], row["start_at"], row["end_at"]
                ):
                    abort(409, description="You already have a visit at this time")
            if prior:
                old = self.data["appointments"][replace_id]
                old.update(
                    status="cancelled",
                    cancellation_note="Rescheduled",
                    video_revocation_pending=old["video_issued"],
                )
            row = {
                **slot,
                "id": str(uuid4()),
                "slot_id": slot_id,
                "patient_id": str(patient["id"]),
                "patient_name": patient.get("full_name", "Patient"),
                "status": "booked",
                "reason": reason,
                "video_issued": False,
                "video_revocation_pending": False,
            }
            self.data["appointments"][row["id"]] = row
            return deepcopy(row)

    def change(self, row, status, note):
        with self.lock:
            current = self.data["appointments"][row["id"]]
            if current["status"] != "booked":
                abort(409, description="This visit is no longer booked")
            current.update(
                status=status,
                cancellation_note=note,
                video_revocation_pending=current["video_issued"],
            )
            return deepcopy(current)

    def issued(self, row):
        with self.lock:
            current = self.data["appointments"][row["id"]]
            current.update(
                video_issued=True,
                video_revocation_pending=current["status"] != "booked",
            )
            return current["status"] == "booked"

    def close(self, id, hospital, clinician):
        with self.lock:
            slot = self.data["slots"].get(id)
            if (
                not slot
                or slot["hospital_id"] != hospital
                or slot["clinician_user_id"] != clinician
            ):
                abort(404)
            if any(
                r["slot_id"] == id and r["status"] == "booked"
                for r in self.data["appointments"].values()
            ):
                abort(
                    409, description="Cancel the booked visit before closing its slot"
                )
            slot["status"] = "closed"


class PostgresSchedule:
    BASE = """SELECT a.*,s.start_at,s.end_at,u.display_name AS clinician_name,p.full_name AS patient_name
        FROM consultations a JOIN consultation_slots s ON s.id=a.slot_id JOIN app_users u ON u.id=a.clinician_user_id
        JOIN patients p ON p.id=a.patient_id"""

    def audit(self, cur, hospital, action, entity):
        cur.execute(
            """INSERT INTO audit_log(actor_user_id,hospital_id,action,entity_type,entity_id)
            VALUES (%s,%s,%s,'consultation',%s)""",
            (getattr(g, "actor", {}).get("id"), hospital, action, str(entity)),
        )

    def slots(self, hospital):
        with get_db().cursor() as cur:
            cur.execute(
                """SELECT s.*,u.display_name AS clinician_name FROM consultation_slots s JOIN app_users u ON u.id=s.clinician_user_id
                WHERE s.hospital_id=%s AND s.status='published' AND s.start_at>now() AND u.is_active=true
                AND EXISTS(SELECT 1 FROM hospital_memberships hm WHERE hm.hospital_id=s.hospital_id AND hm.user_id=s.clinician_user_id AND hm.role='clinician' AND hm.is_active=true)
                AND NOT EXISTS(SELECT 1 FROM consultations a WHERE a.slot_id=s.id AND a.status='booked') ORDER BY s.start_at LIMIT 500""",
                (hospital,),
            )
            return wire(cur.fetchall())

    def publish(self, hospital, clinician, start, end):
        connection = get_db()
        with connection.cursor() as cur:
            # Serialise availability changes for this clinician, across hospitals.
            cur.execute("SELECT id FROM app_users WHERE id=%s FOR UPDATE", (clinician,))
            cur.execute(
                "SELECT id FROM consultation_slots WHERE clinician_user_id=%s AND status='published' AND start_at<%s AND end_at>%s LIMIT 1",
                (clinician, end, start),
            )
            if cur.fetchone():
                abort(
                    409,
                    description="This clinician already has overlapping availability",
                )
            cur.execute(
                "INSERT INTO consultation_slots(hospital_id,clinician_user_id,start_at,end_at) VALUES (%s,%s,%s,%s) RETURNING *",
                (hospital, clinician, start, end),
            )
            row = cur.fetchone()
            self.audit(cur, hospital, "consultation.slot_published", row["id"])
        connection.commit()
        return wire(row)

    def appointments(self, hospital, *, patient=None, clinician=None):
        args = [hospital]
        sql = self.BASE + " WHERE a.hospital_id=%s"
        if patient:
            sql += " AND a.patient_id=%s"
            args.append(patient)
        if clinician:
            sql += " AND a.clinician_user_id=%s"
            args.append(clinician)
        with get_db().cursor() as cur:
            cur.execute(sql + " ORDER BY s.start_at DESC LIMIT 500", args)
            return wire(cur.fetchall())

    def get(self, id, hospital, *, patient=None, clinician=None):
        id = identifier(id)
        args = [hospital, id]
        sql = self.BASE + " WHERE a.hospital_id=%s AND a.id=%s"
        if patient:
            sql += " AND a.patient_id=%s"
            args.append(patient)
        if clinician:
            sql += " AND a.clinician_user_id=%s"
            args.append(clinician)
        with get_db().cursor() as cur:
            cur.execute(sql, args)
            return wire(cur.fetchone())

    def book(self, patient, slot_id, reason, replace_id=None):
        connection = get_db()
        slot_id = identifier(slot_id)
        with connection.cursor() as cur:
            # All booking paths lock patient first, then slot, in the same order.
            cur.execute(
                "SELECT id FROM patients WHERE id=%s AND hospital_id=%s FOR UPDATE",
                (patient["id"], patient["hospital_id"]),
            )
            cur.execute(
                """SELECT s.*,u.is_active FROM consultation_slots s JOIN app_users u ON u.id=s.clinician_user_id
                WHERE s.id=%s AND s.hospital_id=%s AND s.status='published' AND s.start_at>now()
                AND u.is_active=true AND EXISTS(SELECT 1 FROM hospital_memberships hm WHERE hm.hospital_id=s.hospital_id
                    AND hm.user_id=s.clinician_user_id AND hm.role='clinician' AND hm.is_active=true) FOR UPDATE OF s""",
                (slot_id, patient["hospital_id"]),
            )
            slot = cur.fetchone()
            if not slot:
                abort(409, description="This slot is no longer available")
            if replace_id:
                replace_id = identifier(replace_id)
                cur.execute(
                    "SELECT id FROM consultations WHERE id=%s AND patient_id=%s AND hospital_id=%s AND status='booked' FOR UPDATE",
                    (replace_id, patient["id"], patient["hospital_id"]),
                )
                if not cur.fetchone():
                    abort(409, description="This visit cannot be rescheduled")
            cur.execute(
                "SELECT id FROM consultations WHERE slot_id=%s AND status='booked' AND id<>%s LIMIT 1",
                (slot_id, replace_id or UUID(int=0)),
            )
            if cur.fetchone():
                abort(409, description="Someone has already booked this slot")
            cur.execute(
                """SELECT a.id FROM consultations a JOIN consultation_slots s ON s.id=a.slot_id
                WHERE a.patient_id=%s AND a.status='booked' AND a.id<>%s AND s.start_at<%s AND s.end_at>%s LIMIT 1""",
                (
                    patient["id"],
                    replace_id or UUID(int=0),
                    slot["end_at"],
                    slot["start_at"],
                ),
            )
            if cur.fetchone():
                abort(409, description="You already have a visit at this time")
            if replace_id:
                cur.execute(
                    "UPDATE consultations SET status='cancelled',cancellation_note='Rescheduled',video_revocation_pending=video_issued,updated_at=now() WHERE id=%s",
                    (replace_id,),
                )
                self.audit(
                    cur, patient["hospital_id"], "consultation.rescheduled", replace_id
                )
            cur.execute(
                """INSERT INTO consultations(hospital_id,patient_id,clinician_user_id,slot_id,reason)
                VALUES (%s,%s,%s,%s,%s) RETURNING id""",
                (
                    patient["hospital_id"],
                    patient["id"],
                    slot["clinician_user_id"],
                    slot_id,
                    reason,
                ),
            )
            id = cur.fetchone()["id"]
            self.audit(cur, patient["hospital_id"], "consultation.booked", id)
        connection.commit()
        return self.get(id, patient["hospital_id"], patient=patient["id"])

    def change(self, row, status, note):
        connection = get_db()
        with connection.cursor() as cur:
            cur.execute(
                "UPDATE consultations SET status=%s,cancellation_note=%s,video_revocation_pending=video_issued,updated_at=now() WHERE id=%s AND hospital_id=%s AND status='booked' RETURNING id",
                (status, note, row["id"], row["hospital_id"]),
            )
            if not cur.fetchone():
                abort(409, description="This visit is no longer booked")
            self.audit(cur, row["hospital_id"], "consultation." + status, row["id"])
        connection.commit()
        return {
            **row,
            "status": status,
            "video_revocation_pending": row["video_issued"],
        }

    def issued(self, row):
        connection = get_db()
        with connection.cursor() as cur:
            cur.execute(
                "UPDATE consultations SET video_issued=true,video_revocation_pending=(status<>'booked') WHERE id=%s AND hospital_id=%s RETURNING status",
                (row["id"], row["hospital_id"]),
            )
            result = cur.fetchone()
        connection.commit()
        return bool(result and result["status"] == "booked")

    def close(self, id, hospital, clinician):
        connection = get_db()
        with connection.cursor() as cur:
            cur.execute(
                "SELECT id FROM consultation_slots WHERE id=%s AND hospital_id=%s AND clinician_user_id=%s FOR UPDATE",
                (identifier(id), hospital, clinician),
            )
            if not cur.fetchone():
                abort(404)
            cur.execute(
                "SELECT id FROM consultations WHERE slot_id=%s AND status='booked'",
                (id,),
            )
            if cur.fetchone():
                abort(
                    409, description="Cancel the booked visit before closing its slot"
                )
            cur.execute(
                "UPDATE consultation_slots SET status='closed' WHERE id=%s", (id,)
            )
            self.audit(cur, hospital, "consultation.slot_closed", id)
        connection.commit()
