"""User and OTP persistence.  Authentication is still app-owned, not client Supabase Auth."""

from __future__ import annotations

from datetime import UTC, datetime

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import OTP, User


class UserRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def get_by_id(self, user_id: int) -> User | None:
        return await self.session.get(User, user_id)

    async def get_by_phone(self, phone_number: str) -> User | None:
        return await self.session.scalar(select(User).where(User.phone_number == phone_number))

    async def create_user(
        self,
        *,
        phone_number: str,
        shop_name: str,
        owner_name: str,
        address: str,
        shop_category: str,
    ) -> User:
        user = User(
            phone_number=phone_number,
            shop_name=shop_name,
            owner_name=owner_name,
            address=address,
            shop_category=shop_category,
        )
        self.session.add(user)
        await self.session.flush()
        return user

    async def invalidate_open_otps(self, phone_number: str) -> None:
        await self.session.execute(
            update(OTP).where(OTP.phone_number == phone_number, OTP.is_used.is_(False)).values(is_used=True)
        )

    async def create_otp(self, *, phone_number: str, code_hash: str, expires_at: datetime) -> OTP:
        otp = OTP(phone_number=phone_number, code_hash=code_hash, expires_at=expires_at)
        self.session.add(otp)
        await self.session.flush()
        return otp

    async def consume_latest_otp(self, *, phone_number: str) -> OTP | None:
        now = datetime.now(UTC)
        return await self.session.scalar(
            select(OTP)
            .where(
                OTP.phone_number == phone_number,
                OTP.is_used.is_(False),
                OTP.expires_at > now,
                (OTP.locked_until.is_(None) | (OTP.locked_until <= now)),
            )
            .order_by(OTP.id.desc())
            .with_for_update()
        )
