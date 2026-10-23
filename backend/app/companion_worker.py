"""Run continuously alongside the API: python -m app.companion_worker [--once]."""
import argparse
import time

from . import create_app
from .care_records import PostgresRecords
from .companion import deliver_due
from .db import get_db
from .concerns import finalize_previous_month
from .consultations import reconcile_appointments


def tick():
    reconcile_appointments()
    with get_db().cursor() as cur:
        cur.execute("""SELECT DISTINCT p.id,p.hospital_id FROM patients p JOIN companion_records r ON r.patient_id=p.id
            WHERE p.is_active=true AND (r.kind='concern' OR (r.kind='notification' AND r.data->>'push_status'='pending') OR
                (r.kind='reminder' AND r.data->>'status'='active' AND (r.data->>'due_at')::timestamptz <= now()))""")
        patients = cur.fetchall()
    return sum(deliver_due(PostgresRecords(p)) + finalize_previous_month(PostgresRecords(p)) for p in patients)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--once', action='store_true')
    args = parser.parse_args()
    app = create_app()
    while True:
        try:
            with app.app_context():
                count = tick()
                app.logger.info('Companion reminder notifications processed: %s', count)
        except Exception:
            # No credential values, reminder titles, patient details, or SQL parameters in logs.
            app.logger.error('Reminder worker could not process this batch; check service configuration')
            if args.once:
                raise SystemExit(1)
        if args.once:
            return
        time.sleep(30)


if __name__ == '__main__':
    main()
