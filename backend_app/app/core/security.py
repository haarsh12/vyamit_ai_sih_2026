"""JWT authentication primitives for the existing Flutter bearer-token contract."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from app.config.settings import Settings, get_settings


ALGORITHM = "HS256"
_bearer = HTTPBearer(auto_error=False)


def create_access_token(*, subject: int, settings: Settings | None = None) -> str:
    """Issue the normal app token; LiveKit credentials are issued separately."""

    settings = settings or get_settings()
    secret = settings.require_jwt_secret()
    expires_at = datetime.now(UTC) + timedelta(minutes=settings.jwt_access_token_minutes)
    return jwt.encode({"sub": str(subject), "exp": expires_at}, secret, algorithm=ALGORITHM)


def decode_access_token(token: str, *, settings: Settings | None = None) -> int | None:
    settings = settings or get_settings()
    try:
        secret = settings.require_jwt_secret()
        subject = jwt.decode(token, secret, algorithms=[ALGORITHM]).get("sub")
        return int(subject) if subject is not None else None
    except (JWTError, ValueError, RuntimeError):
        return None


async def get_current_user_id(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> int:
    """Require a valid app JWT for protected API endpoints."""

    user_id = decode_access_token(credentials.credentials) if credentials else None
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user_id
