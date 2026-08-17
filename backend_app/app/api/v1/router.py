"""Route composition for the new and compatibility endpoints."""

from fastapi import APIRouter

from app.api.v1 import auth, health, items


router = APIRouter()
router.include_router(health.router)
router.include_router(auth.router)
router.include_router(items.router)
