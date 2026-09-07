"""Versioned drafts keep agent proposals separate from financial writes."""

from __future__ import annotations

import re
from datetime import UTC, datetime, timedelta
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import WorkflowDraft
from app.db.tenant import TenantContext
from app.domain.analytics import analytics_service
from app.repositories.verified_customers import VerifiedCustomerRepository
from app.repositories.workflows import WorkflowDraftRepository
from app.retrieval.customers import customer_search_service
from app.schemas.analytics import BillCreate
from app.schemas.workflows import BillDraftResponse, CustomerVerificationSuggestion


class WorkflowService:
    bill_draft_ttl = timedelta(minutes=30)

    @staticmethod
    def _is_valid_customer_name(name: str | None) -> bool:
        """Check if customer name is valid and meaningful (not generic placeholders)."""
        if not name or not name.strip():
            return False
        
        clean_name = name.strip().lower()
        
        # Reject if too short (less than 2 characters)
        if len(clean_name) < 2:
            return False
        
        # Reject generic placeholders
        generic_terms = {
            "customer", "guest", "user", "anonymous", "unknown", "unnamed",
            "n/a", "na", "none", "test", "temp", "default", "cash", "walk-in",
            "walkin", "retail"
        }
        
        if clean_name in generic_terms:
            return False
        
        # Reject if it's just numbers
        if clean_name.replace(" ", "").isdigit():
            return False
        
        # Accept if it contains at least some letters
        return bool(re.search(r'[a-zA-Z]', clean_name))

    async def _generate_verification_suggestion(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        customer_name: str | None,
    ) -> CustomerVerificationSuggestion | None:
        """Generate customer verification suggestion after bill draft creation."""
        
        # No suggestion if name is missing or invalid
        if not self._is_valid_customer_name(customer_name):
            return None
        
        clean_name = customer_name.strip()
        
        # Check if customer already exists in verified list
        existing_customer, similar_customers = await customer_search_service.find_or_suggest(
            session, tenant, clean_name
        )
        
        # Customer already verified - no need to ask
        if existing_customer:
            return CustomerVerificationSuggestion(
                should_verify=False,
                customer_name=clean_name,
                existing_customer_id=existing_customer.id,
                existing_customer_name=existing_customer.name,
                is_duplicate=True,
                message=f"Customer '{existing_customer.name}' is already verified."
            )
        
        # Check for similar names (potential duplicates)
        if similar_customers:
            similar = similar_customers[0]  # Take the closest match
            if similar.score >= 0.85:  # High similarity threshold
                return CustomerVerificationSuggestion(
                    should_verify=True,
                    customer_name=clean_name,
                    existing_customer_id=similar.customer.id,
                    existing_customer_name=similar.customer.name,
                    is_duplicate=True,
                    message=f"Should I add '{clean_name}' to the existing customer '{similar.customer.name}'?"
                )
        
        # New customer - ask to verify
        return CustomerVerificationSuggestion(
            should_verify=True,
            customer_name=clean_name,
            existing_customer_id=None,
            existing_customer_name=None,
            is_duplicate=False,
            message=f"Should I add '{clean_name}' to verified customers?"
        )

    async def _response(
        self,
        draft: WorkflowDraft,
        session: AsyncSession,
        tenant: TenantContext,
    ) -> BillDraftResponse:
        """Generate draft response with customer verification suggestion."""
        state = BillCreate.model_validate(draft.state)
        
        # Generate verification suggestion for new drafts
        verification_suggestion = None
        if draft.kind == "bill" and state.customer_name:
            verification_suggestion = await self._generate_verification_suggestion(
                session, tenant, state.customer_name
            )
        
        return BillDraftResponse(
            id=draft.id,
            kind=draft.kind,
            version=draft.version,
            confirmation_status=draft.confirmation_status,
            expires_at=draft.expires_at,
            state=state,
            customer_verification_suggestion=verification_suggestion,
        )

    async def create_bill_draft(
        self, session: AsyncSession, tenant: TenantContext, payload: BillCreate
    ) -> BillDraftResponse:
        draft = WorkflowDraft(
            owner_id=tenant.owner_id,
            shop_category=tenant.shop_category,
            voice_session_id=tenant.session_id,
            kind="bill",
            state=payload.model_dump(mode="json"),
            confirmation_status="draft",
            expires_at=datetime.now(UTC) + self.bill_draft_ttl,
        )
        session.add(draft)
        await session.commit()
        await session.refresh(draft)
        return await self._response(draft, session, tenant)

    async def get_bill_draft(
        self, session: AsyncSession, tenant: TenantContext, draft_id: UUID
    ) -> BillDraftResponse:
        draft = await WorkflowDraftRepository(session).get(tenant, draft_id)
        if draft is None or draft.kind != "bill":
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bill draft not found or expired")
        return await self._response(draft, session, tenant)

    async def replace_bill_draft(
        self, session: AsyncSession, tenant: TenantContext, draft_id: UUID, *, expected_version: int, payload: BillCreate
    ) -> BillDraftResponse:
        draft = await WorkflowDraftRepository(session).get(tenant, draft_id, lock=True)
        if draft is None or draft.kind != "bill":
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bill draft not found or expired")
        if draft.confirmation_status != "draft" or draft.version != expected_version:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Bill draft was changed; refresh before saving")
        draft.state = payload.model_dump(mode="json")
        draft.version += 1
        await session.commit()
        await session.refresh(draft)
        return await self._response(draft, session, tenant)

    async def confirm_bill_draft(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        draft_id: UUID,
        *,
        expected_version: int,
        idempotency_key: str,
        verified_customer_id: int | None = None,
    ) -> dict[str, object]:
        draft = await WorkflowDraftRepository(session).get(tenant, draft_id, lock=True)
        if draft is None or draft.kind != "bill":
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Bill draft not found or expired")
        if draft.confirmation_status == "confirmed":
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Bill draft was already confirmed")
        if draft.confirmation_status != "draft" or draft.version != expected_version:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Bill draft was changed; refresh before confirming")
        # Validate again at the financial write boundary. Draft JSON is never
        # blindly trusted, even when it was produced by our own agent.
        result = await analytics_service.create_bill(
            session,
            tenant,
            BillCreate.model_validate(draft.state),
            idempotency_key=idempotency_key,
            commit=False,
            verified_customer_id=verified_customer_id,
        )
        draft.confirmation_status = "confirmed"
        draft.version += 1
        await session.commit()
        return {"bill": result, "draft_id": str(draft.id), "confirmation_status": "confirmed"}


workflow_service = WorkflowService()
