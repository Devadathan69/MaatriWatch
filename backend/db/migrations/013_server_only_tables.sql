-- Firebase identity and tenant authorization are enforced by the Flask API.
-- These application tables must not be accessible through Supabase's Data API.
-- Keep owner access for the backend; do not FORCE RLS or grant client policies.
DO $$
DECLARE
    app_table TEXT;
    api_role TEXT;
    owned_sequence REGCLASS;
BEGIN
    FOREACH app_table IN ARRAY ARRAY[
        'hospitals', 'app_users', 'hospital_memberships', 'user_global_roles',
        'patients', 'devices', 'vital_readings', 'alerts', 'screenings',
        'clinical_notes', 'audit_log', 'alert_observations', 'realtime_outbox',
        'patient_consents', 'symptom_reports', 'care_plan_tasks',
        'patient_invitations', 'patient_lab_results', 'wellbeing_checkins',
        'patient_clinical_profiles', 'patient_report_documents', 'care_messages',
        'patient_activity_entries', 'patient_guidance',
        'wearable_validation_observations', 'companion_records',
        'consultation_slots', 'consultations', 'patient_push_devices'
    ] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', app_table);
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC', app_table);
        FOREACH api_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = api_role) THEN
                EXECUTE format('REVOKE ALL ON TABLE public.%I FROM %I', app_table, api_role);
            END IF;
        END LOOP;

        -- Revoke grants on serial/identity sequences belonging to this table only.
        FOR owned_sequence IN
            SELECT s.oid::regclass
            FROM pg_class s
            JOIN pg_depend d ON d.objid = s.oid AND d.classid = 'pg_class'::regclass
            WHERE s.relkind = 'S' AND d.refobjid = to_regclass(format('public.%I', app_table))
              AND d.refclassid = 'pg_class'::regclass AND d.deptype IN ('a', 'i')
        LOOP
            EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM PUBLIC', owned_sequence);
            FOREACH api_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
                IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = api_role) THEN
                    EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM %I', owned_sequence, api_role);
                END IF;
            END LOOP;
        END LOOP;
    END LOOP;
END;
$$;
