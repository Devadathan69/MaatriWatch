-- Explicit patient invitations; verified guardian identity; no clinical record access.
CREATE TABLE guardian_invitations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    guardian_email TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE CHECK (length(token_hash) = 64),
    expires_at TIMESTAMPTZ NOT NULL,
    claimed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE guardian_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    guardian_user_id UUID NOT NULL REFERENCES app_users(id),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE(patient_id, guardian_user_id)
);
CREATE INDEX guardian_links_user_idx ON guardian_links(guardian_user_id) WHERE is_active;
CREATE TABLE guardian_push_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guardian_user_id UUID NOT NULL REFERENCES app_users(id),
    token TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE CHECK (length(token_hash) = 64),
    is_active BOOLEAN NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE guardian_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    guardian_user_id UUID NOT NULL REFERENCES app_users(id),
    alert_id UUID NOT NULL REFERENCES alerts(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at TIMESTAMPTZ,
    push_status TEXT NOT NULL DEFAULT 'pending' CHECK (push_status IN ('pending','sent','failed','no_device','expired','cancelled')),
    push_attempts INTEGER NOT NULL DEFAULT 0,
    delivered_devices JSONB NOT NULL DEFAULT '[]'::jsonb,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX guardian_notifications_inbox_idx ON guardian_notifications(guardian_user_id,created_at DESC);
CREATE INDEX guardian_notifications_pending_idx ON guardian_notifications(next_attempt_at) WHERE push_status='pending';

DO $$
DECLARE app_table TEXT; api_role TEXT;
BEGIN
    FOREACH app_table IN ARRAY ARRAY['guardian_invitations','guardian_links','guardian_notifications'] LOOP
        EXECUTE format('CREATE TRIGGER %I BEFORE INSERT OR UPDATE OF hospital_id,patient_id ON public.%I FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match()', app_table || '_hospital_match', app_table);
    END LOOP;
    FOREACH app_table IN ARRAY ARRAY['guardian_invitations','guardian_links','guardian_push_devices','guardian_notifications'] LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', app_table);
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC', app_table);
        FOREACH api_role IN ARRAY ARRAY['anon','authenticated'] LOOP
            IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=api_role) THEN
                EXECUTE format('REVOKE ALL ON TABLE public.%I FROM %I', app_table,api_role);
            END IF;
        END LOOP;
    END LOOP;
END;
$$;
