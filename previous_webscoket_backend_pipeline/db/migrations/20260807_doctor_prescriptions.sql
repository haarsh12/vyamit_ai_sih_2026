-- Doctor Prescription mode is deliberately isolated from retail sales data.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS medical_registration_number VARCHAR(100),
    ADD COLUMN IF NOT EXISTS qualifications VARCHAR(500);

CREATE TABLE IF NOT EXISTS doctor_patients (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    owner_id INTEGER NOT NULL REFERENCES users(id),
    full_name VARCHAR(120) NOT NULL,
    age INTEGER,
    gender VARCHAR(30),
    phone_number VARCHAR(20)
);
CREATE INDEX IF NOT EXISTS idx_doctor_patients_owner_name
    ON doctor_patients (owner_id, full_name);

CREATE TABLE IF NOT EXISTS doctor_prescriptions (
    id SERIAL PRIMARY KEY,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    owner_id INTEGER NOT NULL REFERENCES users(id),
    patient_id INTEGER REFERENCES doctor_patients(id),
    patient_name VARCHAR(120) NOT NULL,
    patient_age INTEGER,
    patient_gender VARCHAR(30),
    patient_phone VARCHAR(20),
    diagnosis VARCHAR(500),
    additional_notes VARCHAR(1500),
    medications_json TEXT NOT NULL,
    doctor_name VARCHAR(120) NOT NULL,
    doctor_qualifications VARCHAR(500),
    medical_registration_number VARCHAR(100) NOT NULL,
    signature_json VARCHAR(20000),
    prescribed_at TIMESTAMP NOT NULL DEFAULT NOW(),
    printed_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_doctor_prescriptions_owner_printed
    ON doctor_prescriptions (owner_id, printed_at);
CREATE INDEX IF NOT EXISTS idx_doctor_prescriptions_patient_printed
    ON doctor_prescriptions (patient_id, printed_at);
