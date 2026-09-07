"""Route composition for the new and compatibility endpoints."""

from fastapi import APIRouter

from app.api.v1 import analytics, auth, customers, doctor_prescriptions, gst, health, items, voice, voice_inventory, workflows


router = APIRouter()
router.include_router(health.router)
router.include_router(auth.router)
router.include_router(items.router)
router.include_router(gst.router)
router.include_router(analytics.router)
router.include_router(voice.router)
router.include_router(voice_inventory.router)
router.include_router(doctor_prescriptions.router)
router.include_router(workflows.router)
router.include_router(customers.router)
