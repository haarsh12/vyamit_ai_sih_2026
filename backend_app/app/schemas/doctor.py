"""Validated, size-bounded contracts for the doctor-only workflow."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, Field, field_validator


class DoctorVoiceRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2_000)

    @field_validator("text")
    @classmethod
    def clean_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("text cannot be empty")
        return value


class MedicationInput(BaseModel):
    name: str = Field(min_length=1, max_length=120)
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
    patient_name: str = Field(min_length=1, max_length=120)
    patient_age: int | None = Field(default=None, ge=0, le=130)
    patient_gender: str = Field(default="", max_length=30)
    patient_phone: str = Field(default="", max_length=20)
    diagnosis: str = Field(default="", max_length=500)
    medications: list[MedicationInput] = Field(min_length=1, max_length=20)
    additional_notes: str = Field(default="", max_length=1_500)
    signature_strokes: list[list[list[float]]] = Field(default_factory=list, max_length=80)
    prescribed_at: datetime | None = None
    save_patient: bool = False

    @field_validator("patient_name", "patient_gender", "patient_phone", "diagnosis", "additional_notes")
    @classmethod
    def clean_fields(cls, value: str) -> str:
        return value.strip()


class VoiceInventoryRequest(BaseModel):
    raw_text: str = Field(min_length=1, max_length=2_000)

    @field_validator("raw_text")
    @classmethod
    def clean_raw_text(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("raw_text cannot be empty")
        return value
