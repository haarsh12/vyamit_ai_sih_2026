"""
OTP Service - Secure OTP generation and verification
"""
import logging
import os
import secrets
import string
from datetime import datetime, timedelta
from sqlalchemy import update
from sqlmodel import Session, select
from db.models import OTP

logger = logging.getLogger(__name__)

# Configuration
OTP_DEMO_MODE = os.getenv("OTP_DEMO_MODE", "0") in ("1", "true", "yes")
LOG_OTP_CODES = os.getenv("LOG_OTP_CODES", "0") in ("1", "true", "yes")
OTP_LENGTH = 6
OTP_EXPIRY_MINUTES = 5


class OTPService:
    """OTP generation and verification service"""
    
    @staticmethod
    def generate_otp() -> str:
        """
        Generate 6-digit OTP
        
        Returns:
            OTP code (112233 in demo mode, random otherwise)
        """
        if OTP_DEMO_MODE:
            return "112233"
        return "".join(secrets.choice(string.digits) for _ in range(OTP_LENGTH))
    
    @staticmethod
    def create_otp(session: Session, phone_number: str) -> str:
        """
        Create and store OTP for phone number
        
        Args:
            session: Database session
            phone_number: User's phone number
        
        Returns:
            Generated OTP code
        """
        clean_phone = phone_number.strip()
        code = OTPService.generate_otp()
        expires_at = datetime.utcnow() + timedelta(minutes=OTP_EXPIRY_MINUTES)
        
        # Only the most recently issued code may be used. This is especially
        # important in demo mode, where every code has the same value.
        session.execute(
            update(OTP)
            .where(OTP.phone_number == clean_phone, OTP.is_used.is_(False))
            .values(is_used=True)
        )

        otp_record = OTP(
            phone_number=clean_phone,
            otp_code=code,
            expires_at=expires_at,
            is_used=False
        )
        
        session.add(otp_record)
        session.commit()
        session.refresh(otp_record)
        
        # Safe logging (only last 4 digits)
        tail = clean_phone[-4:] if len(clean_phone) >= 4 else "****"
        logger.info(f"OTP generated for phone ending {tail}")
        
        if LOG_OTP_CODES:
            logger.warning(f"[DEBUG] OTP code for {tail}: {code}")
        
        return code
    
    @staticmethod
    def verify_otp(session: Session, phone_number: str, code: str) -> bool:
        """
        Verify OTP code
        
        Args:
            session: Database session
            phone_number: User's phone number
            code: OTP code to verify
        
        Returns:
            True if valid and not expired, False otherwise
        """
        clean_phone = phone_number.strip()
        tail = clean_phone[-4:] if len(clean_phone) >= 4 else "****"
        
        # A phone can request several codes. Verify only the newest unused
        # code; accepting an older matching code weakens the login flow.
        statement = select(OTP).where(
            OTP.phone_number == clean_phone,
            OTP.is_used == False,
            OTP.expires_at > datetime.utcnow()
        ).order_by(OTP.id.desc())
        
        result = session.exec(statement).first()
        
        if not result or not secrets.compare_digest(result.otp_code, code):
            logger.warning(f"OTP verification failed for phone ending {tail}")
            return False
        
        # Conditional update prevents concurrent requests from consuming the
        # same code successfully. Exactly one request can change is_used.
        update_result = session.execute(
            update(OTP)
            .where(
                OTP.id == result.id,
                OTP.is_used.is_(False),
                OTP.expires_at > datetime.utcnow(),
            )
            .values(is_used=True)
        )
        session.commit()
        if update_result.rowcount != 1:
            logger.warning(f"OTP verification raced or expired for phone ending {tail}")
            return False
        
        logger.info(f"OTP verified successfully for phone ending {tail}")
        return True
    
    @staticmethod
    def cleanup_expired_otps(session: Session) -> int:
        """
        Delete expired OTPs (maintenance task)
        
        Args:
            session: Database session
        
        Returns:
            Number of deleted records
        """
        statement = select(OTP).where(OTP.expires_at < datetime.utcnow())
        expired_otps = session.exec(statement).all()
        
        count = len(expired_otps)
        for otp in expired_otps:
            session.delete(otp)
        
        session.commit()
        logger.info(f"Cleaned up {count} expired OTPs")
        return count


# Global instance
otp_service = OTPService()
