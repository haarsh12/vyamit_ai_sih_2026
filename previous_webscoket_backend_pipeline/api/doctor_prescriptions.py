"""Authenticated, doctor-only prescription and clinical directory API.

The router is deliberately independent from retail bills, inventory and the
general voice route.  Every query is scoped to the authenticated owner and
requires the active Doctor Prescription category.
"""

from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Response, WebSocket, WebSocketDisconnect, status
from pydantic import BaseModel, Field, field_validator
from sqlmodel import Session, select

from core.security import get_current_user, verify_token
from core.shop_categories import stored_category
from db.database import database_is_configured, engine, get_session
from db.models import DoctorPatient, DoctorPrescription, User
from services.doctor_prescription_voice_service import doctor_prescription_voice_service


logger = logging.getLogger(__name__)
router = APIRouter()

_DOCTOR_CATEGORY = "Doctor Prescription"


class DoctorVoiceRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=2_000)


class MedicationInput(BaseModel):
    name: str = Field(..., min_length=1, max_length=120)
    dose: str = Field(default="", max_length=80)
    frequency: str = Field(default="", max_length=120)
    duration: str = Field(default="", max_length=120)
    timing: str = Field(default="", max_length=120)
    route: str = Field(default="", max_length=80)
    instructions: str = Field(default="", max_length=400)

    @field_validator("name", "dose", "frequency", "duration", "timing", "route", "instructions")
    @classmethod
    def clean_text(cls, value: str) -> str:
        return value.strip()


class PrintedPrescriptionRequest(BaseModel):
    patient_name: str = Field(..., min_length=1, max_length=120)
    patient_age: Optional[int] = Field(default=None, ge=0, le=130)
    patient_gender: str = Field(default="", max_length=30)
    patient_phone: str = Field(default="", max_length=20)
    diagnosis: str = Field(default="", max_length=500)
    medications: List[MedicationInput] = Field(..., min_length=1, max_length=20)
    additional_notes: str = Field(default="", max_length=1500)
    # Pen strokes remain compact JSON vectors; a client must never submit an
    # arbitrary URL or filesystem path as a clinician signature.
    signature_strokes: List[List[List[float]]] = Field(default_factory=list, max_length=80)
    prescribed_at: Optional[datetime] = None
    save_patient: bool = False

    @field_validator("patient_name", "patient_gender", "patient_phone", "diagnosis", "additional_notes")
    @classmethod
    def clean_fields(cls, value: str) -> str:
        return value.strip()


def _no_store(response: Response) -> None:
    # Patient data must not be stored by browser/proxy caches.
    response.headers["Cache-Control"] = "no-store, private"
    response.headers["Pragma"] = "no-cache"


def _doctor_user(session: Session, user_id: int, *, require_registration: bool = False) -> User:
    user = session.get(User, user_id)
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


def _load_doctor_user(user_id: int) -> None:
    if not database_is_configured() or engine is None:
        raise RuntimeError("The database is not configured")
    with Session(engine) as session:
        _doctor_user(session, user_id)


def _prescription_dict(record: DoctorPrescription) -> Dict[str, Any]:
    try:
        medications = json.loads(record.medications_json)
    except (TypeError, json.JSONDecodeError):
        medications = []
    return {
        "id": record.id,
        "patient_id": record.patient_id,
        "patient": {
            "name": record.patient_name,
            "age": record.patient_age,
            "gender": record.patient_gender or "",
            "phone": record.patient_phone or "",
        },
        "diagnosis": record.diagnosis or "",
        "medications": medications if isinstance(medications, list) else [],
        "additional_notes": record.additional_notes or "",
        "doctor": {
            "name": record.doctor_name,
            "qualifications": record.doctor_qualifications or "",
            "medical_registration_number": record.medical_registration_number,
        },
        "prescribed_at": record.prescribed_at.isoformat(),
        "printed_at": record.printed_at.isoformat(),
    }


@router.get("/profile-readiness")
def profile_readiness(
    response: Response,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Dict[str, Any]:
    _no_store(response)
    user = _doctor_user(session, user_id)
    registration = (user.medical_registration_number or "").strip()
    return {
        "can_print": bool(registration),
        "doctor_name": (user.owner_name or user.shop_name or "").strip(),
        "qualifications": (user.qualifications or "").strip(),
        "medical_registration_number": registration,
    }


@router.post("/voice/process")
def process_doctor_voice(
    request: DoctorVoiceRequest,
    response: Response,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Dict[str, Any]:
    """HTTP fallback for voice transcription; returns only an editable draft."""
    _no_store(response)
    _doctor_user(session, user_id)
    return doctor_prescription_voice_service.process(request.text.strip())


@router.post("/printed", status_code=status.HTTP_201_CREATED)
def record_printed_prescription(
    payload: PrintedPrescriptionRequest,
    response: Response,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Dict[str, Any]:
    """Persist an immutable record after the connected printer succeeds."""
    _no_store(response)
    doctor = _doctor_user(session, user_id, require_registration=True)

    signature_json = json.dumps(payload.signature_strokes, separators=(",", ":"))
    if len(signature_json) > 20_000:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail="Signature is too large")

    patient_id: Optional[int] = None
    if payload.save_patient:
        # A directory entry is optional.  Avoid duplicate rows while allowing
        # the latest age/contact details to be corrected by the doctor.
        candidates = session.exec(
            select(DoctorPatient).where(DoctorPatient.owner_id == user_id)
        ).all()
        patient = next(
            (item for item in candidates if item.full_name.casefold() == payload.patient_name.casefold()),
            None,
        )
        if patient is None:
            patient = DoctorPatient(owner_id=user_id, full_name=payload.patient_name)
        patient.age = payload.patient_age
        patient.gender = payload.patient_gender or None
        patient.phone_number = payload.patient_phone or None
        patient.updated_at = datetime.utcnow()
        session.add(patient)
        session.flush()
        patient_id = patient.id

    now = datetime.utcnow()
    prescribed_at = payload.prescribed_at or now
    record = DoctorPrescription(
        owner_id=user_id,
        patient_id=patient_id,
        patient_name=payload.patient_name,
        patient_age=payload.patient_age,
        patient_gender=payload.patient_gender or None,
        patient_phone=payload.patient_phone or None,
        diagnosis=payload.diagnosis or None,
        additional_notes=payload.additional_notes or None,
        medications_json=json.dumps(
            [medicine.model_dump() for medicine in payload.medications],
            ensure_ascii=False,
            separators=(",", ":"),
        ),
        doctor_name=(doctor.owner_name or doctor.shop_name or "Doctor").strip()[:120],
        doctor_qualifications=(doctor.qualifications or "").strip() or None,
        medical_registration_number=doctor.medical_registration_number.strip(),
        signature_json=signature_json if payload.signature_strokes else None,
        prescribed_at=prescribed_at,
        printed_at=now,
    )
    session.add(record)
    session.commit()
    session.refresh(record)
    logger.info("Doctor prescription recorded owner=%s prescription=%s", user_id, record.id)
    return {"message": "Printed prescription saved", "prescription": _prescription_dict(record)}


@router.get("/patients")
def list_patients(
    response: Response,
    q: str = Query(default="", max_length=120),
    limit: int = Query(default=100, ge=1, le=200),
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Dict[str, Any]:
    _no_store(response)
    _doctor_user(session, user_id)
    needle = q.strip().casefold()
    patients = session.exec(
        select(DoctorPatient).where(DoctorPatient.owner_id == user_id).order_by(DoctorPatient.full_name)
    ).all()
    if needle:
        patients = [patient for patient in patients if needle in patient.full_name.casefold()]
    patients = patients[:limit]
    return {
        "patients": [
            {
                "id": patient.id,
                "name": patient.full_name,
                "age": patient.age,
                "gender": patient.gender or "",
                "phone": patient.phone_number or "",
                "updated_at": patient.updated_at.isoformat(),
            }
            for patient in patients
        ]
    }


@router.get("/patients/{patient_id}/prescriptions")
def patient_prescriptions(
    patient_id: int,
    response: Response,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Dict[str, Any]:
    _no_store(response)
    _doctor_user(session, user_id)
    patient = session.get(DoctorPatient, patient_id)
    if patient is None or patient.owner_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient not found")
    records = session.exec(
        select(DoctorPrescription)
        .where(DoctorPrescription.owner_id == user_id, DoctorPrescription.patient_id == patient_id)
        .order_by(DoctorPrescription.printed_at.desc())
    ).all()
    return {
        "patient": {
            "id": patient.id,
            "name": patient.full_name,
            "age": patient.age,
            "gender": patient.gender or "",
            "phone": patient.phone_number or "",
        },
        "prescriptions": [_prescription_dict(record) for record in records],
    }


@router.delete("/patients/{patient_id}")
def delete_patient(
    patient_id: int,
    response: Response,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Dict[str, str]:
    """Delete a directory entry and its doctor-owned prescription records."""
    _no_store(response)
    _doctor_user(session, user_id)
    patient = session.get(DoctorPatient, patient_id)
    if patient is None or patient.owner_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Patient not found")
    records = session.exec(
        select(DoctorPrescription).where(
            DoctorPrescription.owner_id == user_id,
            DoctorPrescription.patient_id == patient_id,
        )
    ).all()
    for record in records:
        session.delete(record)
    session.delete(patient)
    session.commit()
    logger.info("Doctor patient deleted owner=%s patient=%s records=%s", user_id, patient_id, len(records))
    return {"message": "Patient deleted"}


@router.delete("/history/{prescription_id}")
def delete_prescription(
    prescription_id: int,
    response: Response,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Dict[str, str]:
    """Remove one doctor-owned history record after explicit UI confirmation."""
    _no_store(response)
    _doctor_user(session, user_id)
    record = session.get(DoctorPrescription, prescription_id)
    if record is None or record.owner_id != user_id:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Prescription not found")
    session.delete(record)
    session.commit()
    logger.info("Doctor prescription deleted owner=%s prescription=%s", user_id, prescription_id)
    return {"message": "Prescription deleted"}


@router.get("/history")
def prescription_history(
    response: Response,
    limit: int = Query(default=100, ge=1, le=200),
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Dict[str, Any]:
    _no_store(response)
    _doctor_user(session, user_id)
    records = session.exec(
        select(DoctorPrescription)
        .where(DoctorPrescription.owner_id == user_id)
        .order_by(DoctorPrescription.printed_at.desc())
        .limit(limit)
    ).all()
    return {"prescriptions": [_prescription_dict(record) for record in records]}


async def _stream_response(websocket: WebSocket, response: Dict[str, Any]) -> None:
    payload = json.dumps(response, ensure_ascii=False, separators=(",", ":"))
    accumulated = ""
    for start in range(0, len(payload), 96):
        token = payload[start : start + 96]
        accumulated += token
        await websocket.send_json({"type": "stream_token", "token": token, "accumulated": accumulated})
        await asyncio.sleep(0)
    await websocket.send_json({"type": "complete", "response": response})


@router.websocket("/voice/ws/stream")
async def doctor_voice_websocket_stream(websocket: WebSocket, token: Optional[str] = None) -> None:
    """Doctor-only continuous voice channel; retail WebSocket is never reused."""
    user_id = verify_token(token) if token else None
    if user_id is None:
        await websocket.close(code=1008, reason="Authentication is required")
        return
    try:
        await asyncio.to_thread(_load_doctor_user, user_id)
    except Exception:
        await websocket.close(code=1008, reason="Doctor Prescription mode is required")
        return

    await websocket.accept()
    await websocket.send_json({"type": "connected", "message": "Doctor voice stream connected"})
    active_task: Optional[asyncio.Task[None]] = None

    async def process_message(text: str) -> None:
        try:
            await websocket.send_json({"type": "processing", "message": "Formatting prescription draft..."})
            result = await asyncio.to_thread(doctor_prescription_voice_service.process, text)
            await _stream_response(websocket, result)
        except Exception:
            logger.exception("Doctor voice processing failed owner=%s", user_id)
            await websocket.send_json({"type": "error", "message": "Unable to format this prescription draft"})

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                message = json.loads(raw)
            except json.JSONDecodeError:
                message = {"action": "process", "text": raw}
            if not isinstance(message, dict):
                await websocket.send_json({"type": "error", "message": "Invalid request"})
                continue
            action = message.get("action", "process")
            if action == "ping":
                await websocket.send_json({"type": "pong"})
                continue
            if action == "interrupt":
                if active_task and not active_task.done():
                    active_task.cancel()
                await websocket.send_json({"type": "interrupted"})
                continue
            text = str(message.get("text") or "").strip()
            if action != "process" or not text or len(text) > 2_000:
                await websocket.send_json({"type": "error", "message": "Voice text must be between 1 and 2000 characters"})
                continue
            if active_task and not active_task.done():
                active_task.cancel()
            active_task = asyncio.create_task(process_message(text))
    except WebSocketDisconnect:
        logger.info("Doctor voice WebSocket disconnected owner=%s", user_id)
    finally:
        if active_task and not active_task.done():
            active_task.cancel()
