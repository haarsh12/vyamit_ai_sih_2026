"""REST API endpoints for verified customer management."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user_id
from app.db.session import get_db_session
from app.domain.customers import customer_service
from app.repositories.tenants import get_tenant_context
from app.schemas.customers import (
    CustomerBillHistoryResponse,
    CustomerDetailResponse,
    CustomerListResponse,
    CustomerVerificationSuggestionResponse,
    CustomerVerifyRequest,
)


router = APIRouter(prefix="/customers", tags=["customers"])


@router.post("/verify", status_code=status.HTTP_201_CREATED)
async def verify_customer(
    payload: CustomerVerifyRequest,
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    """
    Verify a customer and add them to the verified list.
    
    This endpoint is typically called after bill confirmation when the user
    accepts the verification suggestion.
    
    - **customer_name**: Customer's name (2-120 characters)
    - **phone_number**: Optional phone number
    - **merge_with_existing_id**: If provided, use an existing verified customer
    - **link_bill_id**: If provided, add that saved printed or virtual bill to the customer history
    """
    tenant = await get_tenant_context(session, user_id)
    return await customer_service.verify_customer(
        session,
        tenant,
        customer_name=payload.customer_name,
        phone_number=payload.phone_number,
        merge_with_existing_id=payload.merge_with_existing_id,
        link_bill_id=payload.link_bill_id,
    )


@router.get("/", response_model=CustomerListResponse)
async def list_verified_customers(
    limit: int = Query(default=100, ge=1, le=100, description="Maximum number of customers to return"),
    offset: int = Query(default=0, ge=0, description="Number of customers to skip"),
    order_by: str = Query(
        default="name",
        description="Sort order: 'name' (alphabetical), 'recent' (last purchase), or 'total_spent' (highest spending)",
    ),
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> CustomerListResponse:
    """
    List all verified customers for the authenticated shop.
    
    Supports pagination and multiple sort orders:
    - **name**: Alphabetical order by customer name (default)
    - **recent**: Most recent purchase first
    - **total_spent**: Highest spending customers first
    """
    tenant = await get_tenant_context(session, user_id)
    result = await customer_service.list_verified_customers(
        session,
        tenant,
        limit=limit,
        offset=offset,
        order_by=order_by,
    )
    return CustomerListResponse.model_validate(result)


@router.get(
    "/verification-suggestion",
    response_model=CustomerVerificationSuggestionResponse | None,
)
async def get_customer_verification_suggestion(
    customer_name: str = Query(min_length=1, max_length=120),
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> CustomerVerificationSuggestionResponse | None:
    """Check a final typed bill name before offering customer verification."""
    return await customer_service.get_verification_suggestion(
        session,
        await get_tenant_context(session, user_id),
        customer_name,
    )


@router.get("/{customer_id}", response_model=CustomerDetailResponse)
async def get_customer_details(
    customer_id: int,
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> CustomerDetailResponse:
    """
    Get detailed information about a specific verified customer.
    
    Returns customer profile with purchase statistics.
    """
    tenant = await get_tenant_context(session, user_id)
    result = await customer_service.get_customer_details(session, tenant, customer_id)
    return CustomerDetailResponse.model_validate(result["customer"])


@router.get("/{customer_id}/bills", response_model=CustomerBillHistoryResponse)
async def get_customer_bills(
    customer_id: int,
    limit: int = Query(default=50, ge=1, le=50, description="Maximum number of bills to return"),
    offset: int = Query(default=0, ge=0, description="Number of bills to skip"),
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> CustomerBillHistoryResponse:
    """
    Get bill history for a verified customer.
    
    Returns the most recent bills first, with full item details.
    This is useful for displaying purchase history in the customer detail view.
    """
    tenant = await get_tenant_context(session, user_id)
    result = await customer_service.get_customer_bills(
        session,
        tenant,
        customer_id,
        limit=limit,
        offset=offset,
    )
    return CustomerBillHistoryResponse.model_validate(result)


@router.delete("/{customer_id}", status_code=status.HTTP_200_OK)
async def remove_verified_customer(
    customer_id: int,
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> dict:
    """
    Remove a customer from the verified list.
    
    This doesn't delete historical bills, just removes the verified status.
    Bills will remain in the system but won't be linked to this verified customer.
    """
    tenant = await get_tenant_context(session, user_id)
    return await customer_service.remove_customer(session, tenant, customer_id)
