"""OTP/JWT routes preserving the existing Flutter contract."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config.settings import Settings, get_settings
from app.core.categories import stored_category, validate_category
from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.security import create_access_token, get_current_user_id
from app.db.models import User
from app.db.session import get_db_session
from app.domain.otp import otp_service
from app.integrations.sms import SmsDeliveryError, sms_delivery
from app.repositories.users import UserRepository
from app.schemas.auth import OTPRequest, UpdateProfileRequest, VerifyOTPRequest


router = APIRouter(prefix="/auth", tags=["authentication"])
_otp_limiter = SlidingWindowRateLimiter(max_requests=3, window_seconds=300)
_otp_verification_limiter = SlidingWindowRateLimiter(max_requests=8, window_seconds=300)


def _profile_payload(user: User) -> dict[str, object]:
    return {
        "user_id": user.id,
        "phone_number": user.phone_number,
        "shop_name": user.shop_name,
        "owner_name": user.owner_name,
        "address": user.address,
        "phone2": user.phone2,
        "shop_category": stored_category(user.shop_category),
        "medical_registration_number": user.medical_registration_number,
        "qualifications": user.qualifications,
    }


@router.post("/send-otp")
async def send_otp(
    payload: OTPRequest,
    session: AsyncSession = Depends(get_db_session),
    settings: Settings = Depends(get_settings),
) -> dict[str, str]:
    _otp_limiter.check("otp", payload.phone_number)
    user = await UserRepository(session).get_by_phone(payload.phone_number)
    if payload.is_login and user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No account exists for this phone number")
    if not payload.is_login and user is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="An account already exists for this phone number")
    code = await otp_service.issue(session, phone_number=payload.phone_number, settings=settings)
    try:
        await sms_delivery.send_otp(phone_number=payload.phone_number, code=code, settings=settings)
    except (RuntimeError, SmsDeliveryError) as error:
        # The code was committed before contacting an external system. Mark it
        # unusable if delivery was not accepted, rather than leaving a valid
        # code that the user never received.
        await UserRepository(session).invalidate_open_otps(payload.phone_number)
        await session.commit()
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="OTP delivery is temporarily unavailable. Please try again.",
        ) from error
    return {"message": "OTP sent successfully"}


@router.post("/verify-otp")
async def verify_otp(
    payload: VerifyOTPRequest,
    session: AsyncSession = Depends(get_db_session),
    settings: Settings = Depends(get_settings),
) -> dict[str, object]:
    _otp_verification_limiter.check("otp-verify", payload.phone_number)
    if not await otp_service.verify(session, phone_number=payload.phone_number, code=payload.otp_code):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired OTP")

    repository = UserRepository(session)
    user = await repository.get_by_phone(payload.phone_number)
    is_new_user = user is None
    if user is None:
        missing = [
            name
            for name, value in (
                ("shop_name", payload.shop_name),
                ("owner_name", payload.owner_name),
                ("address", payload.address),
                ("shop_category", payload.shop_category),
            )
            if not value or not value.strip()
        ]
        if missing:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail=f"Registration requires: {', '.join(missing)}",
            )
        try:
            category = validate_category(payload.shop_category)
        except ValueError as error:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(error)) from error
        user = await repository.create_user(
            phone_number=payload.phone_number,
            shop_name=(payload.shop_name or "").strip(),
            owner_name=(payload.owner_name or "").strip(),
            address=(payload.address or "").strip(),
            shop_category=category,
        )
        await session.commit()
        await session.refresh(user)
    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account is unavailable")

    return {
        "access_token": create_access_token(subject=user.id, settings=settings),
        "token_type": "bearer",
        "is_new_user": is_new_user,
        **_profile_payload(user),
    }


@router.get("/profile")
async def get_profile(
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> dict[str, object]:
    user = await UserRepository(session).get_by_id(user_id)
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return _profile_payload(user)


@router.put("/profile")
@router.put("/update-profile", include_in_schema=False)
async def update_profile(
    payload: UpdateProfileRequest,
    user_id: int = Depends(get_current_user_id),
    session: AsyncSession = Depends(get_db_session),
) -> dict[str, object]:
    user = await UserRepository(session).get_by_id(user_id)
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    updates = payload.model_dump(exclude_unset=True)
    if "shop_category" in updates:
        try:
            updates["shop_category"] = validate_category(updates["shop_category"])
        except ValueError as error:
            raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(error)) from error
    for field, value in updates.items():
        setattr(user, field, value)
    await session.commit()
    await session.refresh(user)
    return _profile_payload(user)
