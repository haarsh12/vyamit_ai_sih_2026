"""Business logic for verified customer management and bill linking."""

from __future__ import annotations

from datetime import UTC, datetime
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import EmbeddingJob, VerifiedCustomer
from app.db.tenant import TenantContext
from app.repositories.verified_customers import VerifiedCustomerRepository
from app.retrieval.customers import customer_search_service
from app.workers.embeddings import verified_customer_embedding_source_hash


class CustomerService:
    """Domain service for verified customer operations."""

    async def verify_customer(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        *,
        customer_name: str,
        phone_number: str | None = None,
        merge_with_existing_id: int | None = None,
    ) -> dict[str, object]:
        """
        Verify a customer and add them to the verified list.
        
        Args:
            session: Database session
            tenant: Tenant context
            customer_name: Customer's name
            phone_number: Optional phone number
            merge_with_existing_id: If provided, merge with existing customer instead of creating new
        
        Returns:
            Dict with verification result including customer_id and whether it was merged
        """
        repository = VerifiedCustomerRepository(session)
        
        clean_name = customer_name.strip()
        if not clean_name or len(clean_name) < 2:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Customer name must be at least 2 characters"
            )
        
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
            
            await session.commit()
            
            return {
                "success": True,
                "customer_id": existing.id,
                "customer_name": existing.name,
                "merged": True,
                "message": f"Bills will be linked to existing customer '{existing.name}'"
            }
        
        # Check for exact duplicate
        existing_customer = await repository.find_by_exact_name(tenant, clean_name)
        if existing_customer:
            return {
                "success": True,
                "customer_id": existing_customer.id,
                "customer_name": existing_customer.name,
                "merged": False,
                "message": f"Customer '{existing_customer.name}' already verified"
            }
        
        # Create new verified customer
        customer = await repository.create(
            tenant,
            name=clean_name,
            phone_number=phone_number,
        )
        
        # Schedule embedding generation
        embedding_job = EmbeddingJob(
            entity_type="verified_customer",
            entity_id=customer.id,
            owner_id=tenant.owner_id,
            operation="upsert",
            source_hash=verified_customer_embedding_source_hash(customer),
            status="pending",
            available_at=datetime.now(UTC),
        )
        session.add(embedding_job)
        
        await session.commit()
        await session.refresh(customer)
        
        return {
            "success": True,
            "customer_id": customer.id,
            "customer_name": customer.name,
            "merged": False,
            "message": f"Customer '{customer.name}' added to verified list"
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
