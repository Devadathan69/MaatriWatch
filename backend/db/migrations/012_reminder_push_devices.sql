CREATE TABLE patient_push_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    token_hash TEXT NOT NULL UNIQUE CHECK(char_length(token_hash)=64),
    is_active BOOLEAN NOT NULL DEFAULT true,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX patient_push_devices_scope_idx ON patient_push_devices(hospital_id,patient_id) WHERE is_active=true;
CREATE TRIGGER patient_push_devices_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id,patient_id ON patient_push_devices
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();
COMMENT ON TABLE patient_push_devices IS 'Sensitive FCM registration tokens; never return in patient lists, prompts, logs, or source control. Payloads contain no clinical information.';
