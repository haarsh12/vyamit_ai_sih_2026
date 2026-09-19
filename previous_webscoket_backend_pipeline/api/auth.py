"""
Authentication API Routes
OTP-based login and registration
"""
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlmodel import Session, select
from db.database import get_session
from db.models import User
from db.schemas import (
    OTPRequest,
    VerifyOTPRequest,
    TokenResponse,
    UpdateProfileRequest
)
from core.security import create_access_token, get_current_user
from core.shop_categories import stored_category, validate_category
from services.otp_service import otp_service
from services.sms_service import sms_service
from core.rate_limit import otp_rate_limiter
import logging
from datetime import datetime

logger = logging.getLogger(__name__)
router = APIRouter()


def _find_user_by_phone(session: Session, canonical_phone: str):
    """Find users saved by either the new or legacy phone representation."""
    digits = canonical_phone.removeprefix("+91")
    return session.exec(
        select(User).where(User.phone_number.in_((canonical_phone, digits, f"91{digits}")))
    ).first()


def _validated_category_or_422(category: str) -> str:
    """Keep invalid values out of profile and inventory namespaces."""
    try:
        return validate_category(category)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail=str(exc),
        ) from exc


@router.post("/send-otp", status_code=status.HTTP_200_OK)
def send_otp(
    payload: OTPRequest,
    request: Request,
    session: Session = Depends(get_session)
):
    """
    Send OTP for login or registration
    
    - **phone_number**: User's phone number
    - **is_login**: True for login, False for new registration
    """
    try:
        phone = payload.phone_number.strip()
        otp_rate_limiter.check(request.client.host if request.client else "unknown", phone)
        
        # Check if user exists
        user = _find_user_by_phone(session, phone)
        
        if payload.is_login and not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Phone number not registered. Please sign up first."
            )
        
        if not payload.is_login and user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Phone number already registered. Please login instead."
            )
        
        # Generate and save OTP
        otp_code = otp_service.create_otp(session, phone)
        
        # Send OTP via SMS
        sms_service.send_otp(phone, otp_code)
        
        return {
            "success": True,
            "message": "OTP sent successfully",
            "phone_number": phone
        }
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"OTP request failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send OTP. Please try again."
        )


@router.post("/verify-otp", response_model=TokenResponse)
def verify_otp(
    request: VerifyOTPRequest,
    session: Session = Depends(get_session)
):
    """
    Verify OTP and login/register user
    
    For new users, provide shop details:
    - **shop_name**: Name of the shop
    - **owner_name**: Owner's name
    - **address**: Shop address
    - **shop_category**: Category (Kirana, Dairy, etc.)
    """
    try:
        phone = request.phone_number.strip()
        requested_category = (
            _validated_category_or_422(request.shop_category)
            if request.shop_category is not None
            else None
        )
        
        # Verify OTP
        is_valid = otp_service.verify_otp(session, phone, request.otp_code)
        
        if not is_valid:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired OTP"
            )
        
        # Check if user exists
        user = _find_user_by_phone(session, phone)
        
        is_new_user = False
        
        if not user:
            # Create new user
            if requested_category is None:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="shop_category is required for new users"
                )
            
            user = User(
                phone_number=phone,
                shop_name=request.shop_name,
                owner_name=request.owner_name,
                address=request.address,
                shop_category=requested_category,
            )
            session.add(user)
            session.commit()
            session.refresh(user)
            is_new_user = True
            logger.info(f"New user registered: {user.id}")
        
        # Generate JWT token
        access_token = create_access_token(data={"sub": str(user.id)})
        
        return TokenResponse(
            access_token=access_token,
            token_type="bearer",
            is_new_user=is_new_user,
            user_id=user.id,
            shop_name=user.shop_name,
            owner_name=user.owner_name,
            address=user.address,
            phone2=user.phone2,
            shop_category=stored_category(user.shop_category),
            medical_registration_number=user.medical_registration_number,
            qualifications=user.qualifications,
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"OTP verification failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Verification failed. Please try again."
        )


@router.get("/profile", status_code=status.HTTP_200_OK)
def get_profile(
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session)
):
    """Get current user profile"""
    user = session.get(User, user_id)
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
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
        "created_at": user.created_at,
        "is_active": user.is_active
    }


@router.put("/profile", status_code=status.HTTP_200_OK)
@router.put("/update-profile", status_code=status.HTTP_200_OK, include_in_schema=False)
def update_profile(
    request: UpdateProfileRequest,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session)
):
    """Update user profile"""
    user = session.get(User, user_id)
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # Update fields if provided
    if request.shop_name is not None:
        user.shop_name = request.shop_name
    if request.owner_name is not None:
        user.owner_name = request.owner_name
    if request.address is not None:
        user.address = request.address
    if request.phone2 is not None:
        user.phone2 = request.phone2
    if request.shop_category is not None:
        user.shop_category = _validated_category_or_422(request.shop_category)
    if request.medical_registration_number is not None:
        user.medical_registration_number = request.medical_registration_number
    if request.qualifications is not None:
        user.qualifications = request.qualifications
    user.updated_at = datetime.utcnow()
    
    session.add(user)
    session.commit()
    session.refresh(user)
    
    logger.info(f"Profile updated for user {user.id}")
    
    # These profile fields are deliberately top-level: this is the response
    # contract already consumed by the existing Flutter AuthProvider.
    return {
        "success": True,
        "message": "Profile updated successfully",
        "user_id": user.id,
        "shop_name": user.shop_name,
        "owner_name": user.owner_name,
        "address": user.address,
        "phone2": user.phone2,
        "shop_category": stored_category(user.shop_category),
        "medical_registration_number": user.medical_registration_number,
        "qualifications": user.qualifications,
    }
