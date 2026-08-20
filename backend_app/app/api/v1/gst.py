"""Authenticated GST configuration and invoice API."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user_id
from app.db.models import GstInvoice
from app.db.session import get_db_session
from app.domain.gst import gst_billing_service
from app.repositories.tenants import get_tenant_context
from app.schemas.gst import GstConfigurationInput, GstInvoiceDraftRequest, GstPrintConfirmationRequest


router = APIRouter(prefix="/gst", tags=["gst billing"])


@router.get("/configuration")
async def get_configuration(user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)) -> dict:
    return await gst_billing_service.get_configuration(session, await get_tenant_context(session, user_id))


@router.put("/configuration")
async def save_configuration(payload: GstConfigurationInput, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)) -> dict:
    return await gst_billing_service.save_configuration(session, await get_tenant_context(session, user_id), payload)


@router.delete("/configuration")
async def disable_configuration(user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)) -> dict:
    return await gst_billing_service.disable_configuration(session, await get_tenant_context(session, user_id))


@router.post("/invoices/preview")
async def preview_invoice(payload: GstInvoiceDraftRequest, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)) -> dict:
    return await gst_billing_service.build_invoice_preview(session, await get_tenant_context(session, user_id), payload)


@router.post("/invoices", status_code=status.HTTP_201_CREATED)
async def finalize_invoice(
    payload: GstInvoiceDraftRequest,
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key", max_length=128),
    user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session),
) -> dict:
    if not idempotency_key or not idempotency_key.strip():
        raise HTTPException(status_code=428, detail="Idempotency-Key header is required to finalize an invoice")
    return await gst_billing_service.finalize_invoice(session, await get_tenant_context(session, user_id), payload, idempotency_key=idempotency_key.strip())


@router.get("/invoices")
async def list_invoices(
    limit: int = 50, offset: int = 0, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)
) -> dict:
    tenant = await get_tenant_context(session, user_id)
    invoices = (await session.scalars(
        select(GstInvoice).where(GstInvoice.owner_id == tenant.owner_id).order_by(GstInvoice.issued_at.desc()).offset(max(offset, 0)).limit(min(max(limit, 1), 100))
    )).all()
    return {"invoices": [{"id": invoice.id, "invoice_number": invoice.invoice_number, "status": invoice.status, "issued_at": invoice.issued_at.isoformat(), "grand_total_paise": invoice.grand_total_paise} for invoice in invoices]}


@router.get("/invoices/{invoice_id}")
async def get_invoice(invoice_id: int, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)) -> dict:
    return await gst_billing_service.get_invoice(session, await get_tenant_context(session, user_id), invoice_id)


@router.post("/invoices/{invoice_id}/printed")
async def mark_invoice_printed(invoice_id: int, _payload: GstPrintConfirmationRequest, user_id: int = Depends(get_current_user_id), session: AsyncSession = Depends(get_db_session)) -> dict:
    return await gst_billing_service.mark_printed(session, await get_tenant_context(session, user_id), invoice_id)
