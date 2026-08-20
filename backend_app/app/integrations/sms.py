"""Fast2SMS OTP delivery adapter.

Only the API layer sees the generated one-time code.  This adapter never logs
the code, API key, complete phone number, or provider response body.
"""

from __future__ import annotations

import logging

import httpx

from app.config.settings import Settings


logger = logging.getLogger(__name__)


class SmsDeliveryError(RuntimeError):
    """The OTP was not confirmed as accepted by the configured delivery provider."""


class Fast2SmsDelivery:
    async def send_otp(self, *, phone_number: str, code: str, settings: Settings) -> None:
        if settings.otp_demo_mode:
            logger.info("otp_demo_issued phone_tail=%s", phone_number[-4:])
            return
        settings.require_sms_delivery()
        api_key = settings.fast2sms_api_key
        if api_key is None:
            raise SmsDeliveryError("OTP delivery is not configured")
        phone = "".join(character for character in phone_number if character.isdigit())[-10:]
        try:
            async with httpx.AsyncClient(timeout=httpx.Timeout(10.0, connect=4.0)) as client:
                response = await client.post(
                    settings.fast2sms_base_url,
                    headers={"authorization": api_key.get_secret_value()},
                    data={"route": "otp", "variables_values": code, "numbers": phone, "flash": "0"},
                )
        except httpx.HTTPError as error:
            logger.warning("otp_delivery_transport_error phone_tail=%s error_type=%s", phone[-4:], type(error).__name__)
            raise SmsDeliveryError("OTP delivery is unavailable") from error
        if not response.is_success:
            logger.warning("otp_delivery_rejected phone_tail=%s status=%s", phone[-4:], response.status_code)
            raise SmsDeliveryError("OTP delivery was rejected")
        logger.info("otp_delivery_accepted phone_tail=%s", phone[-4:])


sms_delivery = Fast2SmsDelivery()
