"""
Security Module - JWT Token Management
Secure authentication with proper error handling
"""
from datetime import datetime, timedelta
from typing import Optional
from jose import jwt, JWTError
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import os

# Configuration
_DEFAULT_DEV_SECRET = "dev-secret-key-change-in-production"
SECRET_KEY = os.getenv("SECRET_KEY", _DEFAULT_DEV_SECRET)
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 days

# Security check for production. Render is retained for compatibility; APP_ENV
# lets the same deployment rule work on other hosts as well.
_production_environment = os.getenv("APP_ENV", "").lower() in {"prod", "production"}
if (os.getenv("RENDER") or _production_environment) and SECRET_KEY == _DEFAULT_DEV_SECRET:
    raise RuntimeError(
        "SECRET_KEY must be set to a secure random value in production. "
        "Generate with: python -c 'import secrets; print(secrets.token_urlsafe(32))'"
    )

# Bearer token scheme
security = HTTPBearer()


def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """
    Create JWT access token
    
    Args:
        data: Token payload (e.g., {"sub": "user_id"})
        expires_delta: Optional expiration time
    
    Returns:
        Encoded JWT token
    """
    to_encode = data.copy()
    
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def verify_token(token: str) -> Optional[int]:
    """
    Verify JWT token and extract user ID
    
    Args:
        token: JWT token string
    
    Returns:
        User ID if valid, None otherwise
    """
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id: str = payload.get("sub")
        
        if user_id is None:
            return None
        
        return int(user_id)
    except JWTError:
        return None
    except ValueError:
        return None


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> int:
    """
    Dependency to get current authenticated user ID
    
    Usage:
        @router.get("/protected")
        def protected_route(user_id: int = Depends(get_current_user)):
            return {"user_id": user_id}
    
    Returns:
        User ID
    
    Raises:
        HTTPException: If token is invalid
    """
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid or expired authentication token",
        headers={"WWW-Authenticate": "Bearer"},
    )
    
    token = credentials.credentials
    user_id = verify_token(token)
    
    if user_id is None:
        raise credentials_exception
    
    return user_id
