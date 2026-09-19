"""
SMS API - Bill Sharing via SMS
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session
from pydantic import BaseModel
import logging
from db.database import get_session
from core.security import get_current_user
from services.sms_service import sms_service

logger = logging.getLogger(__name__)
router = APIRouter()


class SMSBillRequest(BaseModel):
    """SMS bill sharing request"""
    phone_number: str
    shop_name: str
    items: list
    total_amount: float
    payment_method: str = "cash"


@router.post("/send-bill")
def send_bill_sms(
    request: SMSBillRequest,
    user_id: int = Depends(get_current_user)
):
    """
    Send bill details via SMS
    Formats bill nicely for SMS
    """
    try:
        logger.info(f"Sending bill SMS from user {user_id} to {request.phone_number}")
        
        # Format bill message
        message_parts = []
        message_parts.append(f"{request.shop_name}")
        message_parts.append("Bill Details:")
        message_parts.append("-" * 30)
        
        # Add items (limit to avoid SMS length issues)
        for idx, item in enumerate(request.items[:10], 1):
            item_name = item.get('name', 'Item')
            quantity = item.get('quantity', 0)
            unit = item.get('unit', '')
            price = item.get('price', 0)
            total = item.get('total', 0)
            
            message_parts.append(
                f"{idx}. {item_name} - {quantity}{unit} @ ₹{price} = ₹{total}"
            )
        
        if len(request.items) > 10:
            message_parts.append(f"...and {len(request.items) - 10} more items")
        
        message_parts.append("-" * 30)
        message_parts.append(f"Total: ₹{request.total_amount}")
        message_parts.append(f"Payment: {request.payment_method.upper()}")
        message_parts.append("")
        message_parts.append("Thank you for your business!")
        
        message = "\n".join(message_parts)
        
        # Send SMS
        result = sms_service.send_bill_sms(request.phone_number, message)
        
        if result["success"]:
            logger.info(f"Bill SMS sent successfully to {request.phone_number}")
            return {
                "success": True,
                "message": "Bill sent via SMS successfully",
                "message_id": result.get("message_id")
            }
        else:
            logger.warning(f"Bill SMS failed: {result.get('error')}")
            return {
                "success": False,
                "message": "Failed to send SMS",
                "error": result.get("error")
            }
        
    except Exception as e:
        logger.error(f"SMS sending failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send SMS"
        )


@router.post("/send-custom")
def send_custom_sms(
    phone_number: str,
    message: str,
    user_id: int = Depends(get_current_user)
):
    """Send custom SMS message"""
    try:
        logger.info(f"Sending custom SMS from user {user_id}")
        
        result = sms_service.send_bill_sms(phone_number, message)
        
        return {
            "success": result["success"],
            "message": "SMS sent" if result["success"] else "Failed to send",
            "message_id": result.get("message_id"),
            "error": result.get("error")
        }
        
    except Exception as e:
        logger.error(f"Custom SMS failed: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send SMS"
        )
