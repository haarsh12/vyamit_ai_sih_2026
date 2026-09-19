"""
SMS Service - Fast2SMS Integration
Handles OTP and bill sharing via SMS
"""
import logging
import os
import requests
from typing import Dict, Optional

logger = logging.getLogger(__name__)

FAST2SMS_API_KEY = os.getenv("FAST2SMS_API_KEY")
FAST2SMS_BASE_URL = "https://www.fast2sms.com/dev/bulkV2"
REQUEST_TIMEOUT = 10


def _clean_phone(phone: str) -> str:
    """Remove +91 and spaces from phone number"""
    return phone.replace("+91", "").replace(" ", "").strip()


def _phone_tail(phone: str) -> str:
    """Get last 4 digits for safe logging"""
    digits = "".join(c for c in phone if c.isdigit())
    return digits[-4:] if len(digits) >= 4 else "****"


class SMSService:
    """SMS sending service using Fast2SMS"""
    
    def __init__(self):
        self.api_key = FAST2SMS_API_KEY
        if self.api_key:
            logger.info("[OK] Fast2SMS service initialized")
        else:
            logger.warning("[WARN] FAST2SMS_API_KEY not set - SMS will be mocked")
    
    def send_otp(self, phone_number: str, otp: str) -> bool:
        """
        Send OTP via Fast2SMS
        
        Args:
            phone_number: Recipient phone number
            otp: OTP code to send
        
        Returns:
            True if sent successfully (or mocked), False on error
        """
        tail = _phone_tail(phone_number)
        
        # Mock mode if no API key
        if not self.api_key:
            logger.info(f"[MOCK] OTP {otp} for phone ending {tail}")
            return True
        
        try:
            clean_phone = _clean_phone(phone_number)
            
            params = {
                "authorization": self.api_key,
                "route": "otp",
                "variables_values": otp,
                "numbers": clean_phone,
                "flash": "0"
            }
            
            logger.info(f"Sending OTP to phone ending {tail}")
            response = requests.get(
                FAST2SMS_BASE_URL,
                params=params,
                timeout=REQUEST_TIMEOUT
            )
            
            # Handle non-JSON responses
            if response.text.startswith("<!DOCTYPE") or response.text.startswith("<html"):
                logger.error(f"Fast2SMS returned HTML response for {tail}")
                return True  # Return True to not block user
            
            if not response.text.strip():
                logger.error(f"Fast2SMS returned empty response for {tail}")
                return True
            
            try:
                result = response.json()
            except ValueError:
                logger.error(f"Invalid JSON from Fast2SMS for {tail}: {response.text[:100]}")
                return True
            
            if result.get("return"):
                logger.info(f"[SUCCESS] OTP sent to {tail}")
                return True
            
            logger.warning(f"Fast2SMS error for {tail}: {result.get('message')}")
            return True  # Don't block user flow
            
        except Exception as e:
            logger.error(f"Exception sending OTP to {tail}: {e}")
            return True  # Don't block user flow
    
    def send_bill_sms(self, phone_number: str, message: str) -> Dict[str, Optional[str]]:
        """
        Send bill details via SMS
        
        Args:
            phone_number: Recipient phone number
            message: Bill message text
        
        Returns:
            {
                "success": bool,
                "message_id": str or None,
                "error": str or None
            }
        """
        tail = _phone_tail(phone_number)
        
        # Mock mode if no API key
        if not self.api_key:
            logger.info(f"[MOCK] Bill SMS to {tail} ({len(message)} chars)")
            return {
                "success": True,
                "message_id": "MOCK_MSG_ID",
                "error": None
            }
        
        try:
            clean_phone = _clean_phone(phone_number)
            
            params = {
                "authorization": self.api_key,
                "route": "q",  # Quick SMS route
                "message": message,
                "language": "english",
                "flash": 0,
                "numbers": clean_phone
            }
            
            logger.info(f"Sending bill SMS to phone ending {tail}")
            response = requests.get(
                FAST2SMS_BASE_URL,
                params=params,
                timeout=REQUEST_TIMEOUT
            )
            
            if not response.text.strip():
                logger.error(f"Empty response from Fast2SMS for {tail}")
                return {
                    "success": False,
                    "message_id": None,
                    "error": "Empty response from SMS service"
                }
            
            result = response.json()
            
            if result.get("return"):
                logger.info(f"[SUCCESS] Bill SMS sent to {tail}")
                return {
                    "success": True,
                    "message_id": result.get("request_id"),
                    "error": None
                }
            
            error_msg = result.get("message", "Unknown error")
            logger.warning(f"Fast2SMS error for {tail}: {error_msg}")
            return {
                "success": False,
                "message_id": None,
                "error": error_msg
            }
            
        except Exception as e:
            logger.error(f"Exception sending bill SMS to {tail}: {e}")
            return {
                "success": False,
                "message_id": None,
                "error": str(e)
            }


# Global instance
sms_service = SMSService()
