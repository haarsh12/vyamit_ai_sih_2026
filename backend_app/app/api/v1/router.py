"""Route composition for the new and compatibility endpoints."""

from fastapi import APIRouter

from app.api.v1 import health


router = APIRouter()
router.include_router(health.router)
