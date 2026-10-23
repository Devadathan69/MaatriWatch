-- Application-managed companion state. Clinical records remain separate.
CREATE TABLE companion_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('preferences','memory','message','reminder','notification',
        'concern','summary','report_analysis','diet_plan','nutrition_preferences')),
    data JSONB NOT NULL CHECK (jsonb_typeof(data) = 'object'),
    stable_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (patient_id, kind, stable_key)
);
CREATE INDEX companion_records_scope_idx ON companion_records(hospital_id, patient_id, kind, created_at DESC);
CREATE TRIGGER companion_records_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id, patient_id ON companion_records
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();
COMMENT ON TABLE companion_records IS 'Sensitive patient-scoped companion state; do not expose directly to client database SDKs.';
