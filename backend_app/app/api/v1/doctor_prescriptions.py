"""Doctor-only API with strict tenant/category and cache boundaries."""

from __future__ import annotations

import json
import logging
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.categories import stored_category
from app.core.security import get_current_user_id
from app.db.models import AuditEvent, DoctorPatient, DoctorPrescription, IdempotencyKey, User
from app.db.session import get_db_session
from app.domain.doctor_prescriptions import format_dictation
from app.repositories.doctor_prescriptions import DoctorPrescriptionRepository
from app.schemas.doctor import DoctorVoiceRequest, PrintedPrescriptionRequest


logger = logging.getLogger(__name__)
router = APIRouter(prefix="/doctor-prescriptions", tags=["doctor prescriptions"])
_DOCTOR_CATEGORY = "Doctor Prescription"


def _no_store(response: Response) -> None:
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Pragma"] = "no-cache"


async def _doctor_user(session: AsyncSession, user_id: int, *, require_registration: bool = False) -> User:
    user = await session.get(User, user_id)
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Doctor account is unavailable")
    if stored_category(user.shop_category) != _DOCTOR_CATEGORY:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Doctor Prescription mode is required")
    if require_registration and not (user.medical_registration_number or "").strip():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Add a medical registration number in Profile before printing prescriptions.",
        )
    return user


def _prescription_payload(record: DoctorPrescription) -> dict[str, object]:
    return {
        "id": record.id,
        "patient_id": record.patient_id,
        "patient": {"name": record.patient_name, "age": record.patient_age, "gender": record.patient_gender or "", "phone": record.patient_phone or ""},
        "diagnosis": record.diagnosis or "", "medications": record.medications,
        "additional_notes": record.additional_notes or "",
        "doctor": {"name": record.doctor_name, "qualifications": record.doctor_qualifications or "", "medical_registration_number": record.medical_registration_number},
        "prescribed_at": record.prescribed_at.isoformat(), "printed_at": record.printed_at.isoformat(),
    }


@router.get("/profile-readiness")
async def profile_readiness(
    response: Response, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)
) -> dict[str, object]:
    _no_store(response)
    user = await _doctor_user(session, user_id)
    registration = (user.medical_registration_number or "").strip()
    return {"can_print": bool(registration), "doctor_name": (user.owner_name or user.shop_name or "").strip(), "qualifications": (user.qualifications or "").strip(), "medical_registration_number": registration}


@router.post("/voice/process")
async def process_doctor_voice(
    payload: DoctorVoiceRequest, response: Response, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)
) -> dict[str, object]:
    _no_store(response)
    await _doctor_user(session, user_id)
    # This bridge has no model access or record writes; realtime formatting is
    # migrated separately to the doctor-authorised LiveKit workflow.
    return format_dictation(payload.text)


@router.post("/printed", status_code=status.HTTP_201_CREATED)
async def record_printed_prescription(
    payload: PrintedPrescriptionRequest,
    response: Response,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key", max_length=128),
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> dict[str, object]:
    _no_store(response)
    if not idempotency_key or not idempotency_key.strip():
        raise HTTPException(status_code=status.HTTP_428_PRECONDITION_REQUIRED, detail="Idempotency-Key header is required to save a printed prescription")
    doctor = await _doctor_user(session, user_id, require_registration=True)
    existing = await session.scalar(select(IdempotencyKey).where(
        IdempotencyKey.owner_id == user_id, IdempotencyKey.key == idempotency_key.strip(), IdempotencyKey.action == "doctor.prescription.printed"
    ).with_for_update())
    if existing is not None:
        if existing.response is not None:
            return existing.response
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="This prescription request is still processing")
    request_key = IdempotencyKey(owner_id=user_id, key=idempotency_key.strip(), action="doctor.prescription.printed")
    session.add(request_key)
    await session.flush()
    signature_json = json.dumps(payload.signature_strokes, separators=(",", ":"))
    if len(signature_json.encode("utf-8")) > 20_000:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Signature is too large")
    repository = DoctorPrescriptionRepository(session)
    patient_id: int | None = None
    if payload.save_patient:
        patient = await repository.find_patient_by_name(user_id, payload.patient_name)
        if patient is None:
            patient = DoctorPatient(owner_id=user_id, full_name=payload.patient_name)
            session.add(patient)
        patient.age, patient.gender = payload.patient_age, payload.patient_gender or None
        patient.phone_number = payload.patient_phone or None
        await session.flush()
        patient_id = patient.id
    now = datetime.now(UTC)
    prescribed_at = payload.prescribed_at or now
    record = DoctorPrescription(
        owner_id=user_id, patient_id=patient_id, patient_name=payload.patient_name, patient_age=payload.patient_age,
        patient_gender=payload.patient_gender or None, patient_phone=payload.patient_phone or None,
        diagnosis=payload.diagnosis or None, additional_notes=payload.additional_notes or None,
        medications=[medication.model_dump() for medication in payload.medications],
        doctor_name=(doctor.owner_name or doctor.shop_name or "Doctor").strip()[:120],
        doctor_qualifications=(doctor.qualifications or "").strip() or None,
        medical_registration_number=(doctor.medical_registration_number or "").strip(),
        signature=payload.signature_strokes or None, prescribed_at=prescribed_at, printed_at=now,
    )
    session.add(record)
    await session.flush()
    result: dict[str, object] = {"message": "Printed prescription saved", "prescription": _prescription_payload(record)}
    request_key.response, request_key.status_code = result, status.HTTP_201_CREATED
    session.add(AuditEvent(created_at=now, owner_id=user_id, action="doctor.prescription.printed", outcome="success", metadata_={"prescription_id": record.id, "saved_patient": payload.save_patient}))
    await session.commit()
    logger.info("doctor_prescription_recorded", extra={"owner_id": user_id, "prescription_id": record.id})
    return result


@router.get("/patients")
async def list_patients(
    response: Response, q: str = Query(default="", max_length=120), limit: int = Query(default=100, ge=1, le=200),
    user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session),
) -> dict[str, object]:
    _no_store(response)
    await _doctor_user(session, user_id)
    patients = await DoctorPrescriptionRepository(session).list_patients(user_id, q.strip(), limit)
    return {"patients": [{"id": patient.id, "name": patient.full_name, "age": patient.age, "gender": patient.gender or "", "phone": patient.phone_number or "", "updated_at": patient.updated_at.isoformat()} for patient in patients]}


@router.get("/patients/{patient_id}/prescriptions")
async def patient_prescriptions(
    patient_id: int, response: Response, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)
) -> dict[str, object]:
    _no_store(response)
    await _doctor_user(session, user_id)
    repository = DoctorPrescriptionRepository(session)
    patient = await repository.find_patient(user_id, patient_id)
    if patient is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient not found")
    records = await repository.list_prescriptions(user_id, patient_id=patient_id, limit=200)
    return {"patient": {"id": patient.id, "name": patient.full_name, "age": patient.age, "gender": patient.gender or "", "phone": patient.phone_number or ""}, "prescriptions": [_prescription_payload(record) for record in records]}


@router.delete("/patients/{patient_id}")
async def delete_patient(
    patient_id: int, response: Response, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)
) -> dict[str, str]:
    _no_store(response)
    await _doctor_user(session, user_id)
    repository = DoctorPrescriptionRepository(session)
    patient = await repository.find_patient(user_id, patient_id)
    if patient is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient not found")
    records = await repository.list_prescriptions(user_id, patient_id=patient_id, limit=10_000)
    for record in records:
        await session.delete(record)
    await session.delete(patient)
    await session.commit()
    logger.info("doctor_patient_deleted", extra={"owner_id": user_id, "patient_id": patient_id, "record_count": len(records)})
    return {"message": "Patient deleted"}


@router.delete("/history/{prescription_id}")
async def delete_prescription(
    prescription_id: int, response: Response, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)
) -> dict[str, str]:
    _no_store(response)
    await _doctor_user(session, user_id)
    record = await DoctorPrescriptionRepository(session).get_prescription(user_id, prescription_id)
    if record is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Prescription not found")
    await session.delete(record)
    await session.commit()
    logger.info("doctor_prescription_deleted", extra={"owner_id": user_id, "prescription_id": prescription_id})
    return {"message": "Prescription deleted"}


@router.get("/history")
async def prescription_history(
    response: Response, limit: int = Query(default=100, ge=1, le=200), user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)
) -> dict[str, object]:
    _no_store(response)
    await _doctor_user(session, user_id)
    records = await DoctorPrescriptionRepository(session).list_prescriptions(user_id, limit=limit)
    return {"prescriptions": [_prescription_payload(record) for record in records]}
