"""Optimized LiveKit AgentServer for fast, responsive voice interactions."""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from livekit.agents import AgentServer, AgentSession, JobContext, TurnHandlingOptions, cli, inference, room_io
from livekit.plugins import ai_coustics

from app.agent.instructions import DOCTOR_VOICE_INSTRUCTIONS, VOICE_ASSISTANT_INSTRUCTIONS
from app.agent.providers import create_llm, create_stt, create_tts
from app.agent.tools import VyamitAssistant
from app.config.settings import get_settings
from app.core.logging import configure_logging
from app.db.session import get_agent_db_session
from app.repositories.voice_sessions import VoiceSessionRepository


_BACKEND_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(_BACKEND_ROOT / ".env")
load_dotenv(_BACKEND_ROOT / ".env.local", override=True)
configure_logging()
logger = logging.getLogger("vyamit.agent")
server = AgentServer()


def _event_value(event: object, name: str, default: Any = None) -> Any:
    return getattr(event, name, default)


async def _publish_ui_event(ctx: JobContext, event_type: str, **payload: object) -> None:
    """Publish minimal state for Flutter UI; never publish credentials or raw tool input."""
    try:
        event_data = {"type": event_type, **payload}
        logger.debug(f"📤 Publishing {event_type} event with keys: {list(payload.keys())}")
        await ctx.room.local_participant.publish_data(
            json.dumps(event_data, separators=(",", ":")).encode("utf-8"),
            reliable=True,
            topic="vyamit.ui",
        )
        logger.info(f"✅ Published {event_type} event successfully")
    except Exception as e:
        logger.error(f"❌ Failed to publish UI event {event_type}: {e}", exc_info=True)


@server.rtc_session(agent_name=get_settings().livekit_agent_name)
async def vyamit_voice_agent(ctx: JobContext) -> None:
    """Optimized session startup for minimal latency."""

    settings = get_settings()
    settings.require_agent_providers()
    
    # Get room name early for logging
    room_name = ctx.room.name
    ctx.log_context_fields = {"room": room_name}
    
    # Verify session authorization asynchronously while setting up audio
    async def verify_session():
        async with get_agent_db_session() as db_session:
            expected_identity = await VoiceSessionRepository(db_session).expected_participant_identity(room_name)
        if expected_identity is None:
            logger.warning("agent_rejected_unbound_room", extra={"room": room_name})
            return None, None
        
        try:
            participant = await asyncio.wait_for(
                ctx.wait_for_participant(identity=expected_identity), timeout=15.0
            )
        except TimeoutError:
            logger.warning("agent_rejected_missing_bound_participant", extra={"room": room_name})
            return None, None
        
        async with get_agent_db_session() as db_session:
            tenant = await VoiceSessionRepository(db_session).resolve_tenant(room_name, participant.identity)
            await db_session.commit()
        
        if tenant is None:
            logger.warning("agent_rejected_invalid_participant", extra={"room": room_name})
            return None, None
        
        return tenant, participant
    
    # Setup room options
    room_options = room_io.RoomOptions()
    if settings.enable_enhanced_noise_cancellation:
        room_options = room_io.RoomOptions(audio_input=room_io.AudioInputOptions(
            noise_cancellation=ai_coustics.audio_enhancement(model=ai_coustics.EnhancerModel.QUAIL_VF_S)
        ))
    
    # Create session with minimal setup
    session = AgentSession(
        stt=create_stt(settings),
        llm=create_llm(settings),
        tts=create_tts(settings),
        turn_handling=TurnHandlingOptions(turn_detection=inference.TurnDetector()),
        preemptive_generation=True,
        use_tts_aligned_transcript=True,
    )
    
    # Event handlers (lightweight, no await in handlers)
    @session.on("user_input_transcribed")
    def user_input_transcribed(event: object) -> None:
        language = _event_value(event, "language")
        final = bool(_event_value(event, "is_final", False))
        transcript = _event_value(event, "transcript", "")
        
        # Update TTS language for next utterance
        if final and language in {"en", "hi", "mr"}:
            session.tts.update_options(language=language)
        
        # Async publish to UI
        asyncio.create_task(_publish_ui_event(ctx, "user_transcript", text=str(transcript), final=final, language=language))

    @session.on("agent_state_changed")
    def agent_state_changed(event: object) -> None:
        state = _event_value(event, "state", "unknown")
        asyncio.create_task(_publish_ui_event(ctx, "agent_state", state=state))

    @session.on("agent_speech_transcribed")
    def agent_speech_transcribed(event: object) -> None:
        transcript = _event_value(event, "transcript", "")
        asyncio.create_task(_publish_ui_event(ctx, "agent_transcript", text=str(transcript)))

    @session.on("overlapping_speech")
    def overlapping_speech(_: object) -> None:
        logger.debug("interruption_detected")
        asyncio.create_task(_publish_ui_event(ctx, "interruption"))

    # Verify session authorization
    tenant, participant = await verify_session()
    if tenant is None:
        ctx.shutdown(reason="Invalid voice session")
        return
    
    # Update context with tenant info
    ctx.log_context_fields.update({"session_id": str(tenant.session_id), "owner_id": tenant.owner_id})
    
    # Callback handlers for tool results
    async def on_bill_draft(draft: dict[str, object]) -> None:
        logger.info(f"💰 Bill draft created: {draft.get('draft_id')}")
        await _publish_ui_event(ctx, "bill_draft", **draft)
    
    async def on_prescription_draft(draft: dict[str, object]) -> None:
        logger.info(f"📋 Prescription draft created")
        await _publish_ui_event(ctx, "prescription_draft", **draft)
    
    async def on_inventory_draft(draft: dict[str, object]) -> None:
        logger.info(f"📦 Inventory draft created")
        await _publish_ui_event(ctx, "inventory_draft", **draft)
    
    # Cleanup callback
    async def close_database_session() -> None:
        async with get_agent_db_session() as db_session:
            await VoiceSessionRepository(db_session).close(tenant.session_id)
            await db_session.commit()
    
    ctx.add_shutdown_callback(close_database_session)
    
    # Start session BEFORE connecting to reduce latency
    await session.start(
        agent=VyamitAssistant(
            instructions=(
                DOCTOR_VOICE_INSTRUCTIONS
                if tenant.shop_category == "Doctor Prescription"
                else VOICE_ASSISTANT_INSTRUCTIONS
            ),
            tenant=tenant,
            on_bill_draft_created=on_bill_draft,
            on_prescription_draft_created=on_prescription_draft,
            on_inventory_draft_created=on_inventory_draft,
        ),
        room=ctx.room,
        room_options=room_options,
    )
    
    # Connect AFTER session is ready
    await ctx.connect()
    await _publish_ui_event(ctx, "connected", session_id=str(tenant.session_id))
    
    logger.info(
        "session_started",
        extra={"room": room_name, "session_id": str(tenant.session_id), "owner_id": tenant.owner_id},
    )


if __name__ == "__main__":
    try:
        get_settings().require_agent_providers()
        cli.run_app(server)
    except RuntimeError as error:
        logger.error("agent_configuration_error", extra={"error_type": type(error).__name__})
        raise SystemExit(2) from error
