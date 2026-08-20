"""Tenant-scoped persistence for sensitive doctor records."""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import DoctorPatient, DoctorPrescription


class DoctorPrescriptionRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def find_patient(self, owner_id: int, patient_id: int) -> DoctorPatient | None:
        return await self.session.scalar(select(DoctorPatient).where(
            DoctorPatient.id == patient_id, DoctorPatient.owner_id == owner_id
        ))

    async def find_patient_by_name(self, owner_id: int, full_name: str) -> DoctorPatient | None:
        patients = await self.session.scalars(select(DoctorPatient).where(DoctorPatient.owner_id == owner_id))
        target = full_name.casefold()
        return next((patient for patient in patients if patient.full_name.casefold() == target), None)

    async def list_patients(self, owner_id: int, query: str, limit: int) -> list[DoctorPatient]:
        patients = (await self.session.scalars(select(DoctorPatient).where(
            DoctorPatient.owner_id == owner_id
        ).order_by(DoctorPatient.full_name).limit(limit))).all()
        needle = query.casefold()
        return [patient for patient in patients if not needle or needle in patient.full_name.casefold()]

    async def get_prescription(self, owner_id: int, prescription_id: int) -> DoctorPrescription | None:
        return await self.session.scalar(select(DoctorPrescription).where(
            DoctorPrescription.id == prescription_id, DoctorPrescription.owner_id == owner_id
        ))

    async def list_prescriptions(
        self, owner_id: int, *, patient_id: int | None = None, limit: int = 100
    ) -> list[DoctorPrescription]:
        statement = select(DoctorPrescription).where(DoctorPrescription.owner_id == owner_id)
        if patient_id is not None:
            statement = statement.where(DoctorPrescription.patient_id == patient_id)
        return (await self.session.scalars(
            statement.order_by(DoctorPrescription.printed_at.desc()).limit(limit)
        )).all()
