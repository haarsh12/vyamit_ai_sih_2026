"""Business logic for verified customer management and bill linking."""

from __future__ import annotations

import re
from datetime import UTC, datetime
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import EmbeddingJob, VerifiedCustomer
from app.db.tenant import TenantContext
from app.domain.billing_source import billing_source_from_items
from app.repositories.verified_customers import VerifiedCustomerRepository
from app.retrieval.customers import customer_search_service
from app.schemas.customers import CustomerVerificationSuggestionResponse
from app.workers.embeddings import verified_customer_embedding_source_hash


def is_meaningful_customer_name(name: str | None) -> bool:
    """Return whether a supplied name is suitable for an explicit customer record.

    This deliberately validates only obvious placeholders.  The app cannot prove a
    spoken name is a real person, but it must never offer to save "walk-in",
    "unknown", a number, or an empty voice transcription as a customer.
    """
    if not name:
        return False

    clean_name = " ".join(name.split())
    if len(clean_name) < 2:
        return False

    normalized = clean_name.casefold()
    generic_terms = {
        "customer", "guest", "user", "anonymous", "unknown", "unnamed",
        "n/a", "na", "none", "test", "temp", "default", "cash", "walk-in",
        "walkin", "walk in", "retail", "no name", "name not provided",
        "the customer", "customer name", "customer is", "naam nahi hai",
    }
    if normalized in generic_terms:
        return False

    # ``[^\W\d_]`` means a Unicode letter, so Hindi/Marathi names are accepted
    # alongside Latin-script names while numeric or punctuation-only input is not.
    return bool(re.search(r"[^\W\d_]", clean_name, flags=re.UNICODE))


class CustomerService:
    """Domain service for verified customer operations."""

    async def get_verification_suggestion(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        customer_name: str | None,
    ) -> CustomerVerificationSuggestionResponse | None:
        """Return the explicit post-bill choice appropriate for a typed name."""
        if not is_meaningful_customer_name(customer_name):
            return None

        clean_name = " ".join((customer_name or "").split())
        existing_customer, similar_customers = await customer_search_service.find_or_suggest(
            session,
            tenant,
            clean_name,
        )
        if existing_customer:
            return CustomerVerificationSuggestionResponse(
                should_verify=True,
                customer_name=clean_name,
                existing_customer_id=existing_customer.id,
                existing_customer_name=existing_customer.name,
                is_duplicate=True,
                message=f"Add this bill to existing customer '{existing_customer.name}'?",
            )

        if similar_customers and similar_customers[0].score >= 0.85:
            similar = similar_customers[0]
            return CustomerVerificationSuggestionResponse(
                should_verify=True,
                customer_name=clean_name,
                existing_customer_id=similar.customer.id,
                existing_customer_name=similar.customer.name,
                is_duplicate=True,
                message=(
                    f"Should I add '{clean_name}' to the existing customer "
                    f"'{similar.customer.name}'?"
                ),
            )

        return CustomerVerificationSuggestionResponse(
            should_verify=True,
            customer_name=clean_name,
            is_duplicate=False,
            message=f"Should I add '{clean_name}' to verified customers?",
        )

    async def verify_customer(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        *,
        customer_name: str,
        phone_number: str | None = None,
        merge_with_existing_id: int | None = None,
        link_bill_id: int | None = None,
    ) -> dict[str, object]:
        """
        Verify a customer and add them to the verified list.
        
        Args:
            session: Database session
            tenant: Tenant context
            customer_name: Customer's name
            phone_number: Optional phone number
            merge_with_existing_id: If provided, use this existing verified customer
            link_bill_id: If provided, add this tenant-owned saved bill to the customer's history
        
        Returns:
            Dict with verification result including customer_id and whether it was merged
        """
        repository = VerifiedCustomerRepository(session)
        
        clean_name = " ".join(customer_name.split())
        if not is_meaningful_customer_name(clean_name):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="A meaningful customer name is required"
            )

        customer: VerifiedCustomer
        created = False
        merged = False
        
        # If merging with existing customer
        if merge_with_existing_id:
            existing = await repository.get_by_id(tenant, merge_with_existing_id)
            if not existing:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Existing customer not found"
                )
            
            # Update phone if provided and not already set
            if phone_number and not existing.phone_number:
                existing.phone_number = phone_number.strip()
            customer = existing
            merged = True

        else:
            # This also protects callers that retry after the initial prompt: an
            # exact match is never allowed to create a second customer row.
            existing_customer = await repository.find_by_exact_name(tenant, clean_name)
            if existing_customer:
                customer = existing_customer
                merged = True
                if phone_number and not customer.phone_number:
                    customer.phone_number = phone_number.strip()
            else:
                customer = await repository.create(
                    tenant,
                    name=clean_name,
                    phone_number=phone_number,
                )
                created = True

        if created:
            # Generate pgvector data asynchronously, so the post-print UI does
            # not wait on Vertex.  The outbox worker retries failures safely.
            session.add(EmbeddingJob(
                entity_type="verified_customer",
                entity_id=customer.id,
                owner_id=tenant.owner_id,
                operation="upsert",
                source_hash=verified_customer_embedding_source_hash(customer),
                status="pending",
                available_at=datetime.now(UTC),
            ))

        bill_linked = False
        if link_bill_id is not None:
            bill = await repository.get_bill_for_linking(tenant, link_bill_id)
            if bill is None:
                raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Saved bill not found")
            if bill.verified_customer_id not in (None, customer.id):
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail="This bill is already linked to a different verified customer",
                )
            if bill.verified_customer_id is None:
                bill.verified_customer_id = customer.id
                await repository.update_purchase_stats(
                    customer,
                    amount=bill.total_amount,
                    purchased_at=bill.bill_date,
                )
                bill_linked = True

        await session.commit()
        await session.refresh(customer)

        if bill_linked:
            message = f"Bill added to verified customer '{customer.name}'"
        elif merged:
            message = f"Customer '{customer.name}' is already verified"
        else:
            message = f"Customer '{customer.name}' added to verified list"

        return {
            "success": True,
            "customer_id": customer.id,
            "customer_name": customer.name,
            "merged": merged,
            "bill_linked": bill_linked,
            "message": message,
        }

    async def list_verified_customers(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        *,
        limit: int = 100,
        offset: int = 0,
        order_by: str = "name",
    ) -> dict[str, object]:
        """
        List all verified customers with pagination.
        
        Args:
            session: Database session
            tenant: Tenant context
            limit: Maximum number of customers to return (1-100)
            offset: Number of customers to skip
            order_by: Sort order - "name" (default), "recent", or "total_spent"
        
        Returns:
            Dict with customers list and total count
        """
        repository = VerifiedCustomerRepository(session)
        
        safe_limit = min(max(limit, 1), 100)
        safe_offset = max(offset, 0)
        
        # Validate order_by
        valid_orders = {"name", "recent", "total_spent"}
        if order_by not in valid_orders:
            order_by = "name"
        
        customers = await repository.list_all(
            tenant,
            limit=safe_limit,
            offset=safe_offset,
            order_by=order_by,
        )
        
        total_count = await repository.count_all(tenant)
        
        return {
            "success": True,
            "customers": [
                {
                    "id": customer.id,
                    "name": customer.name,
                    "phone_number": customer.phone_number,
                    "total_bills": customer.total_bills,
                    "total_spent": float(customer.total_spent),
                    "last_purchase_date": (
                        customer.last_purchase_date.isoformat()
                        if customer.last_purchase_date
                        else None
                    ),
                    "created_at": customer.created_at.isoformat(),
                }
                for customer in customers
            ],
            "total": total_count,
            "limit": safe_limit,
            "offset": safe_offset,
            "order_by": order_by,
        }

    async def get_customer_details(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        customer_id: int,
    ) -> dict[str, object]:
        """
        Get detailed information about a verified customer.
        
        Args:
            session: Database session
            tenant: Tenant context
            customer_id: Customer ID
        
        Returns:
            Dict with customer details and statistics
        """
        repository = VerifiedCustomerRepository(session)
        
        customer = await repository.get_by_id(tenant, customer_id)
        if not customer:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Verified customer not found"
            )
        
        bill_count = await repository.count_bills(tenant, customer_id)
        
        return {
            "success": True,
            "customer": {
                "id": customer.id,
                "name": customer.name,
                "phone_number": customer.phone_number,
                "total_bills": customer.total_bills,
                "total_spent": float(customer.total_spent),
                "last_purchase_date": (
                    customer.last_purchase_date.isoformat()
                    if customer.last_purchase_date
                    else None
                ),
                "created_at": customer.created_at.isoformat(),
                "updated_at": customer.updated_at.isoformat(),
                "bill_count": bill_count,
            }
        }

    async def get_customer_bills(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        customer_id: int,
        *,
        limit: int = 50,
        offset: int = 0,
    ) -> dict[str, object]:
        """
        Get bill history for a verified customer.
        
        Args:
            session: Database session
            tenant: Tenant context
            customer_id: Customer ID
            limit: Maximum number of bills to return (1-50)
            offset: Number of bills to skip
        
        Returns:
            Dict with bills list and customer info
        """
        repository = VerifiedCustomerRepository(session)
        
        customer = await repository.get_by_id(tenant, customer_id)
        if not customer:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Verified customer not found"
            )
        
        safe_limit = min(max(limit, 1), 50)
        safe_offset = max(offset, 0)
        
        bills = await repository.get_bill_history(
            tenant,
            customer_id,
            limit=safe_limit,
            offset=safe_offset,
        )
        
        total_bills = await repository.count_bills(tenant, customer_id)
        
        return {
            "success": True,
            "customer": {
                "id": customer.id,
                "name": customer.name,
                "phone_number": customer.phone_number,
                "total_bills": customer.total_bills,
                "total_spent": float(customer.total_spent),
            },
            "bills": [
                {
                    "id": bill.id,
                    "total_amount": float(bill.total_amount),
                    "total_items": bill.total_items,
                    "items": bill.items,
                    "payment_method": bill.payment_method,
                    "bill_type": bill.bill_type,
                    "billing_source": billing_source_from_items(bill.items),
                    "bill_date": bill.bill_date.isoformat(),
                    "created_at": bill.created_at.isoformat(),
                }
                for bill in bills
            ],
            "total_bills": total_bills,
            "limit": safe_limit,
            "offset": safe_offset,
        }

    async def remove_customer(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        customer_id: int,
    ) -> dict[str, object]:
        """
        Remove a customer from the verified list.
        
        Note: This doesn't delete historical bills, just removes the verified status.
        Bills will remain but won't be linked to this verified customer anymore.
        
        Args:
            session: Database session
            tenant: Tenant context
            customer_id: Customer ID
        
        Returns:
            Dict with success status
        """
        repository = VerifiedCustomerRepository(session)
        
        customer = await repository.get_by_id(tenant, customer_id)
        if not customer:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Verified customer not found"
            )
        
        customer_name = customer.name
        await repository.delete(customer)
        await session.commit()
        
        return {
            "success": True,
            "message": f"Customer '{customer_name}' removed from verified list"
        }

    async def update_customer_stats_after_bill(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        customer_id: int,
        *,
        amount: Decimal,
        bill_date: datetime,
    ) -> None:
        """
        Update customer's purchase statistics after a bill is confirmed.
        
        This should be called within the same transaction as bill creation.
        
        Args:
            session: Database session
            tenant: Tenant context
            customer_id: Customer ID
            amount: Bill total amount
            bill_date: Bill date
        """
        repository = VerifiedCustomerRepository(session)
        
        customer = await repository.get_by_id(tenant, customer_id)
        if customer:
            await repository.update_purchase_stats(
                customer,
                amount=amount,
                purchased_at=bill_date,
            )
            # Note: Caller is responsible for commit


customer_service = CustomerService()
