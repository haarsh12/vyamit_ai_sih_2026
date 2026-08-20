"""Independently deployed LiveKit AgentServer for Vyamit realtime conversations."""

from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from livekit.agents import AgentServer, AgentSession, JobContext, TurnHandlingOptions, cli, inference, room_io
from livekit.plugins import ai_coustics

from app.agent.instructions import VOICE_ASSISTANT_INSTRUCTIONS
from app.agent.providers import create_llm, create_stt, create_tts
from app.agent.tools import VyamitAssistant
from app.config.settings import get_settings
from app.core.logging import configure_logging
from app.db.session import get_session_factory
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

    await ctx.room.local_participant.publish_data(
        json.dumps({"type": event_type, **payload}, separators=(",", ":")).encode("utf-8"),
        reliable=True,
        topic="vyamit.ui",
    )


@server.rtc_session(agent_name=get_settings().livekit_agent_name)
async def vyamit_voice_agent(ctx: JobContext) -> None:
    """Join a room only after resolving its server-created tenant binding."""

    settings = get_settings()
    settings.require_agent_providers()
    await ctx.connect()
    factory = get_session_factory()
    if factory is None:
        raise RuntimeError("DATABASE_URL is required by the Vyamit agent.")
    async with factory() as db_session:
        # An agent joins only a room/identity pair issued by the authenticated
        # API.  Room names are not an authorization boundary by themselves.
        tenant = None
        for participant_identity in ctx.room.remote_participants:
            tenant = await VoiceSessionRepository(db_session).resolve_tenant(
                ctx.room.name, participant_identity
            )
            if tenant is not None:
                break
        await db_session.commit()
    if tenant is None:
        logger.warning("agent_rejected_unbound_room", extra={"room": ctx.room.name})
        # Python JobContext.shutdown is non-awaitable; no AgentSession has
        # started yet, so it is the correct lifecycle primitive here.
        ctx.shutdown(reason="A valid Vyamit voice session is required.")
        return
    ctx.log_context_fields = {"room": ctx.room.name, "session_id": str(tenant.session_id), "owner_id": tenant.owner_id}
    room_options = room_io.RoomOptions()
    if settings.enable_enhanced_noise_cancellation:
        room_options = room_io.RoomOptions(audio_input=room_io.AudioInputOptions(
            noise_cancellation=ai_coustics.audio_enhancement(model=ai_coustics.EnhancerModel.QUAIL_VF_S)
        ))
    session = AgentSession(
        stt=create_stt(settings), llm=create_llm(settings), tts=create_tts(settings),
        turn_handling=TurnHandlingOptions(turn_detection=inference.TurnDetector()),
        preemptive_generation=True, use_tts_aligned_transcript=True,
    )

    @session.on("user_input_transcribed")
    def user_input_transcribed(event: object) -> None:
        language, final, transcript = _event_value(event, "language"), bool(_event_value(event, "is_final", False)), _event_value(event, "transcript", "")
        logger.info("stt_transcript", extra={"room": ctx.room.name, "session_id": str(tenant.session_id), "latency_ms": None})
        if final and language in {"en", "hi", "mr"}:
            session.tts.update_options(language=language)
        asyncio.create_task(_publish_ui_event(ctx, "user_transcript", text=str(transcript), final=final, language=language))

    @session.on("agent_state_changed")
    def agent_state_changed(event: object) -> None:
        state = _event_value(event, "state", "unknown")
        logger.info("agent_state", extra={"room": ctx.room.name, "session_id": str(tenant.session_id)})
        asyncio.create_task(_publish_ui_event(ctx, "agent_state", state=state))

    @session.on("overlapping_speech")
    def overlapping_speech(_: object) -> None:
        asyncio.create_task(_publish_ui_event(ctx, "interruption"))

    try:
        await session.start(agent=VyamitAssistant(instructions=VOICE_ASSISTANT_INSTRUCTIONS, tenant=tenant), room=ctx.room, room_options=room_options)
        await _publish_ui_event(ctx, "connected", session_id=str(tenant.session_id))
        logger.info("agent_session_started", extra={"room": ctx.room.name, "session_id": str(tenant.session_id), "owner_id": tenant.owner_id})
    finally:
        async with factory() as db_session:
            await VoiceSessionRepository(db_session).close(tenant.session_id)
            await db_session.commit()


if __name__ == "__main__":
    try:
        get_settings().require_agent_providers()
        cli.run_app(server)
    except RuntimeError as error:
        logger.error("agent_configuration_error", extra={"error_type": type(error).__name__})
        raise SystemExit(2) from error
