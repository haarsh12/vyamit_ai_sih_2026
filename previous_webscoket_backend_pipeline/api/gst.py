"""Authenticated GST configuration and invoice API."""

from __future__ import annotations

from fastapi import APIRouter, Depends, status
from sqlmodel import Session, select

from core.security import get_current_user
from db.database import get_session
from db.models import GstInvoice
from gst.schemas import (
    GstConfigurationInput,
    GstInvoiceDraftRequest,
    GstPrintConfirmationRequest,
)
from gst.service import gst_billing_service


router = APIRouter()


@router.get("/configuration")
def get_configuration(
    user_id: int = Depends(get_current_user), session: Session = Depends(get_session)
):
    return gst_billing_service.get_configuration(session, user_id)


@router.put("/configuration")
def save_configuration(
    payload: GstConfigurationInput,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return gst_billing_service.save_configuration(session, user_id, payload)


@router.delete("/configuration")
def disable_configuration(
    user_id: int = Depends(get_current_user), session: Session = Depends(get_session)
):
    return gst_billing_service.disable_configuration(session, user_id)


@router.post("/invoices/preview")
def preview_invoice(
    payload: GstInvoiceDraftRequest,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return gst_billing_service.build_invoice_preview(session, user_id, payload)


@router.post("/invoices", status_code=status.HTTP_201_CREATED)
def finalize_invoice(
    payload: GstInvoiceDraftRequest,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return gst_billing_service.finalize_invoice(session, user_id, payload)


@router.get("/invoices")
def list_invoices(
    limit: int = 50,
    offset: int = 0,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    safe_limit = min(max(limit, 1), 100)
    rows = session.exec(
        select(GstInvoice)
        .where(GstInvoice.owner_id == user_id)
        .order_by(GstInvoice.issued_at.desc())
        .offset(max(offset, 0))
        .limit(safe_limit)
    ).all()
    return {
        "invoices": [
            {
                "id": invoice.id,
                "invoice_number": invoice.invoice_number,
                "status": invoice.status,
                "issued_at": invoice.issued_at.isoformat(),
                "grand_total_paise": invoice.grand_total_paise,
            }
            for invoice in rows
        ]
    }


@router.get("/invoices/{invoice_id}")
def get_invoice(
    invoice_id: int,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return gst_billing_service.get_invoice(session, user_id, invoice_id)


@router.post("/invoices/{invoice_id}/printed")
def mark_invoice_printed(
    invoice_id: int,
    _payload: GstPrintConfirmationRequest,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return gst_billing_service.mark_printed(session, user_id, invoice_id)

