CREATE TABLE consultation_slots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    clinician_user_id UUID NOT NULL REFERENCES app_users(id),
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL,
    status TEXT NOT NULL DEFAULT 'published' CHECK(status IN ('published','closed')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK(end_at >= start_at + interval '10 minutes' AND end_at <= start_at + interval '60 minutes'),
    UNIQUE(id,hospital_id,clinician_user_id)
);
CREATE INDEX consultation_slots_time_idx ON consultation_slots(hospital_id,start_at);
CREATE UNIQUE INDEX consultation_slots_unique_start ON consultation_slots(clinician_user_id,start_at) WHERE status='published';
CREATE TABLE consultations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hospital_id UUID NOT NULL REFERENCES hospitals(id),
    patient_id UUID NOT NULL REFERENCES patients(id),
    clinician_user_id UUID NOT NULL REFERENCES app_users(id),
    slot_id UUID NOT NULL,
    status TEXT NOT NULL DEFAULT 'booked' CHECK(status IN ('booked','cancelled','completed')),
    reason TEXT NOT NULL DEFAULT '',
    cancellation_note TEXT,
    video_issued BOOLEAN NOT NULL DEFAULT false,
    video_revocation_pending BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY(slot_id,hospital_id,clinician_user_id) REFERENCES consultation_slots(id,hospital_id,clinician_user_id)
);
CREATE UNIQUE INDEX consultations_one_booking_per_slot ON consultations(slot_id) WHERE status='booked';
CREATE INDEX consultations_patient_idx ON consultations(patient_id,created_at DESC);
CREATE TRIGGER consultations_hospital_match
BEFORE INSERT OR UPDATE OF hospital_id,patient_id ON consultations
FOR EACH ROW EXECUTE FUNCTION enforce_patient_workflow_hospital_match();
COMMENT ON TABLE consultations IS 'No meeting tokens or provider keys are stored. Booking locks slots/patient rows; cancellation revocations retry in companion_worker.';
