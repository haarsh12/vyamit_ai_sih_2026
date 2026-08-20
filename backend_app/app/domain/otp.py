"""OTP issue/verification with hashed codes and safe delivery logging."""

from __future__ import annotations

import logging
import secrets
import string
from datetime import UTC, datetime, timedelta

from argon2 import PasswordHasher
from argon2.exceptions import VerificationError
from sqlalchemy.ext.asyncio import AsyncSession

from app.config.settings import Settings
from app.repositories.users import UserRepository


logger = logging.getLogger(__name__)
_hasher = PasswordHasher()


class OTPService:
    expiry_minutes = 5
    max_verification_attempts = 5

    @staticmethod
    def generate(settings: Settings) -> str:
        if settings.otp_demo_mode:
            return "112233"
        return "".join(secrets.choice(string.digits) for _ in range(6))

    async def issue(self, session: AsyncSession, *, phone_number: str, settings: Settings) -> str:
        repository = UserRepository(session)
        code = self.generate(settings)
        await repository.invalidate_open_otps(phone_number)
        await repository.create_otp(
            phone_number=phone_number,
            code_hash=_hasher.hash(code),
            expires_at=datetime.now(UTC) + timedelta(minutes=self.expiry_minutes),
        )
        await session.commit()
        tail = phone_number[-4:]
        logger.info("otp_issued phone_tail=%s", tail)
        if settings.log_otp_codes and not settings.is_production:
            logger.warning("otp_debug_code phone_tail=%s code=%s", tail, code)
        return code

    async def verify(self, session: AsyncSession, *, phone_number: str, code: str) -> bool:
        repository = UserRepository(session)
        otp = await repository.consume_latest_otp(phone_number=phone_number)
        if otp is None:
            return False
        try:
            valid = _hasher.verify(otp.code_hash, code)
        except VerificationError:
            valid = False
        if valid:
            otp.is_used = True
            await session.commit()
        else:
            # Persist failure state while the row remains locked.  Rolling the
            # transaction back here would make unlimited online guessing
            # possible against the same valid OTP.
            otp.failed_attempts += 1
            if otp.failed_attempts >= self.max_verification_attempts:
                otp.is_used = True
            await session.commit()
        return valid


otp_service = OTPService()
