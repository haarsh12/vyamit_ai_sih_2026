"""Optimized LiveKit AgentServer for fast, responsive voice interactions."""

from __future__ import annotations

import asyncio
import json
import logging
import time
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


# Performance tracking for detailed timing logs
class PerformanceTimer:
    """Track timing for each stage of voice processing."""
    
    def __init__(self, room_name: str):
        self.room_name = room_name
        self.stage_times: dict[str, float] = {}
        self.stage_starts: dict[str, float] = {}
    
    def start_stage(self, stage: str) -> None:
        """Mark the start of a processing stage."""
        self.stage_starts[stage] = time.perf_counter()
        logger.info(f"⏱️ [{self.room_name}] STAGE_START: {stage}")
    
    def end_stage(self, stage: str) -> float:
        """Mark the end of a processing stage and return duration."""
        if stage not in self.stage_starts:
            return 0.0
        duration = time.perf_counter() - self.stage_starts[stage]
        self.stage_times[stage] = duration
        logger.info(f"⏱️ [{self.room_name}] STAGE_END: {stage} took {duration*1000:.2f}ms")
        return duration
    
    def log_summary(self) -> None:
        """Log summary of all stages."""
        total = sum(self.stage_times.values())
        logger.info(f"📊 [{self.room_name}] Performance Summary:")
        for stage, duration in self.stage_times.items():
            percentage = (duration / total * 100) if total > 0 else 0
            logger.info(f"  - {stage}: {duration*1000:.2f}ms ({percentage:.1f}%)")
        logger.info(f"  - TOTAL: {total*1000:.2f}ms")


def _event_value(event: object, name: str, default: Any = None) -> Any:
    return getattr(event, name, default)


async def _publish_ui_event(ctx: JobContext, event_type: str, **payload: object) -> None:
    """Publish minimal state for Flutter UI; never publish credentials or raw tool input."""
    try:
        event_data = {"type": event_type, "timestamp": time.time(), **payload}
        logger.debug(f"📤 [{ctx.room.name}] Publishing {event_type} event")
        await ctx.room.local_participant.publish_data(
            json.dumps(event_data, separators=(",", ":")).encode("utf-8"),
            reliable=True,
            topic="vyamit.ui",
        )
    except Exception as e:
        logger.error(f"❌ [{ctx.room.name}] Failed to publish UI event {event_type}: {e}", exc_info=True)


@server.rtc_session(agent_name=get_settings().livekit_agent_name)
async def vyamit_voice_agent(ctx: JobContext) -> None:
    """Optimized session startup for minimal latency."""

    session_start_time = time.perf_counter()
    settings = get_settings()
    settings.require_agent_providers()
    
    # Get room name early for logging
    room_name = ctx.room.name
    ctx.log_context_fields = {"room": room_name}
    
    # Initialize performance timer
    perf_timer = PerformanceTimer(room_name)
    
    logger.info(f"🚀 [{room_name}] Session initialization started")
    perf_timer.start_stage("session_authorization")
    
    # Verify session authorization asynchronously while setting up audio
    async def verify_session():
        async with get_agent_db_session() as db_session:
            expected_identity = await VoiceSessionRepository(db_session).expected_participant_identity(room_name)
        if expected_identity is None:
            logger.warning(f"⚠️ [{room_name}] agent_rejected_unbound_room")
            return None, None
        
        try:
            participant = await asyncio.wait_for(
                ctx.wait_for_participant(identity=expected_identity), timeout=15.0
            )
        except TimeoutError:
            logger.warning(f"⚠️ [{room_name}] agent_rejected_missing_bound_participant")
            return None, None
        
        async with get_agent_db_session() as db_session:
            tenant = await VoiceSessionRepository(db_session).resolve_tenant(room_name, participant.identity)
            await db_session.commit()
        
        if tenant is None:
            logger.warning(f"⚠️ [{room_name}] agent_rejected_invalid_participant")
            return None, None
        
        return tenant, participant
    
    # Setup room options
    perf_timer.start_stage("room_options_setup")
    room_options = room_io.RoomOptions()
    if settings.enable_enhanced_noise_cancellation:
        room_options = room_io.RoomOptions(audio_input=room_io.AudioInputOptions(
            noise_cancellation=ai_coustics.audio_enhancement(model=ai_coustics.EnhancerModel.QUAIL_VF_S)
        ))
    perf_timer.end_stage("room_options_setup")
    
    # Parallelize provider creation and session verification
    perf_timer.start_stage("parallel_provider_creation")
    
    logger.info(f"🔧 [{room_name}] Creating STT, LLM, TTS providers in parallel...")
    stt_task = asyncio.create_task(asyncio.to_thread(create_stt, settings))
    llm_task = asyncio.create_task(asyncio.to_thread(create_llm, settings))
    tts_task = asyncio.create_task(asyncio.to_thread(create_tts, settings))
    verify_task = asyncio.create_task(verify_session())
    
    # Wait for all to complete
    stt, llm, tts = await asyncio.gather(stt_task, llm_task, tts_task)
    perf_timer.end_stage("parallel_provider_creation")
    
    tenant, participant = await verify_task
    perf_timer.end_stage("session_authorization")
    
    if tenant is None:
        ctx.shutdown(reason="Invalid voice session")
        return
    
    # Update context with tenant info
    ctx.log_context_fields.update({"session_id": str(tenant.session_id), "owner_id": tenant.owner_id})
    logger.info(f"✅ [{room_name}] Tenant verified: {tenant.owner_id}, session: {tenant.session_id}")
    
    # Create session with pre-created providers
    perf_timer.start_stage("session_creation")
    
    session = AgentSession(
        stt=stt,
        llm=llm,
        tts=tts,
        turn_handling=TurnHandlingOptions(
            turn_detection=inference.TurnDetector()  # Using default settings - works better with current LiveKit SDK
        ),
        preemptive_generation=True,  # Start generating response before user finishes
        use_tts_aligned_transcript=True,
    )
    perf_timer.end_stage("session_creation")
    
    # Event handlers with detailed state tracking
    perf_timer.start_stage("event_handler_setup")
    
    # Track LLM and tool execution timing
    llm_start_time = None
    tool_start_time = None
    
    @session.on("user_input_transcribed")
    def user_input_transcribed(event: object) -> None:
        nonlocal llm_start_time
        language = _event_value(event, "language")
        final = bool(_event_value(event, "is_final", False))
        transcript = _event_value(event, "transcript", "")
        
        # Update TTS language for next utterance
        if final and language in {"en", "hi", "mr"}:
            # Map language codes for Google TTS
            tts_voice_map = {
                "en": "en-US-Standard-A",
                "hi": "hi-IN-Standard-A", 
                "mr": "mr-IN-Standard-A"
            }
            lang_code_map = {
                "en": "en-US",
                "hi": "hi-IN",
                "mr": "mr-IN"
            }
            if language in tts_voice_map:
                session.tts.update_options(
                    voice=tts_voice_map[language],
                    language=lang_code_map[language]
                )
                logger.info(f"🌐 [{room_name}] TTS voice updated to: {tts_voice_map[language]}")
        
        # Log final transcripts and start timing
        if final:
            logger.info(f"🎤 [{room_name}] USER (final): '{transcript}' [{language}]")
            llm_start_time = time.perf_counter()
        
        # Async publish to UI
        asyncio.create_task(_publish_ui_event(
            ctx, 
            "user_transcript", 
            text=str(transcript), 
            final=final, 
            language=language
        ))

    @session.on("agent_state_changed")
    def agent_state_changed(event: object) -> None:
        nonlocal llm_start_time
        state = _event_value(event, "state", "unknown")
        state_lower = str(state).lower()
        
        # Log state changes with timing
        if llm_start_time and "thinking" in state_lower:
            elapsed = (time.perf_counter() - llm_start_time) * 1000
            logger.info(f"🧠 [{room_name}] AGENT_STATE: {state} (STT→LLM: {elapsed:.2f}ms)")
        else:
            logger.info(f"🤖 [{room_name}] AGENT_STATE: {state}")
        
        # Publish detailed state to UI with proper labels
        if "listening" in state_lower:
            asyncio.create_task(_publish_ui_event(ctx, "agent_state", state="listening", label="Listening"))
        elif "thinking" in state_lower or "processing" in state_lower:
            asyncio.create_task(_publish_ui_event(ctx, "agent_state", state="thinking", label="Thinking"))
        elif "speaking" in state_lower:
            if llm_start_time:
                total_elapsed = (time.perf_counter() - llm_start_time) * 1000
                logger.info(f"⚡ [{room_name}] RESPONSE_TIME: {total_elapsed:.2f}ms (user speech end → agent speech start)")
                llm_start_time = None
            asyncio.create_task(_publish_ui_event(ctx, "agent_state", state="speaking", label="AI Speaking"))
        else:
            asyncio.create_task(_publish_ui_event(ctx, "agent_state", state=state_lower, label=str(state).title()))

    @session.on("agent_speech_transcribed")
    def agent_speech_transcribed(event: object) -> None:
        transcript = _event_value(event, "transcript", "")
        if transcript:
            logger.info(f"🔊 [{room_name}] AGENT: '{transcript}'")
        asyncio.create_task(_publish_ui_event(ctx, "agent_transcript", text=str(transcript)))

    @session.on("overlapping_speech")
    def overlapping_speech(_: object) -> None:
        logger.info(f"🚫 [{room_name}] INTERRUPTION_DETECTED - User spoke while agent was speaking")
        asyncio.create_task(_publish_ui_event(ctx, "interruption", label="Interrupted"))
    
    @session.on("agent_speech_interrupted")
    def agent_speech_interrupted(_: object) -> None:
        logger.info(f"⏹️ [{room_name}] AGENT_SPEECH_INTERRUPTED - Stopping current response")
        asyncio.create_task(_publish_ui_event(ctx, "speech_interrupted", label="Stopping"))
    
    # Track tool execution
    @session.on("function_call_started")
    def function_call_started(event: object) -> None:
        nonlocal tool_start_time
        tool_name = _event_value(event, "function_name", "unknown")
        tool_start_time = time.perf_counter()
        logger.info(f"🔧 [{room_name}] TOOL_CALL_STARTED: {tool_name}")
        asyncio.create_task(_publish_ui_event(
            ctx, 
            "tool_executing", 
            state="tool_executing",
            tool=tool_name, 
            label=f"Executing tool"
        ))
    
    @session.on("function_call_finished")
    def function_call_finished(event: object) -> None:
        nonlocal tool_start_time
        tool_name = _event_value(event, "function_name", "unknown")
        if tool_start_time:
            elapsed = (time.perf_counter() - tool_start_time) * 1000
            logger.info(f"✅ [{room_name}] TOOL_CALL_FINISHED: {tool_name} took {elapsed:.2f}ms")
            tool_start_time = None
        else:
            logger.info(f"✅ [{room_name}] TOOL_CALL_FINISHED: {tool_name}")
    
    perf_timer.end_stage("event_handler_setup")

    # Callback handlers for tool results
    async def on_bill_draft(draft: dict[str, object]) -> None:
        logger.info(f"💰 [{room_name}] Bill draft created: {draft.get('draft_id')}")
        await _publish_ui_event(ctx, "bill_draft", **draft)
    
    async def on_prescription_draft(draft: dict[str, object]) -> None:
        logger.info(f"📋 [{room_name}] Prescription draft created")
        await _publish_ui_event(ctx, "prescription_draft", **draft)
    
    async def on_inventory_draft(draft: dict[str, object]) -> None:
        logger.info(f"📦 [{room_name}] Inventory draft created")
        await _publish_ui_event(ctx, "inventory_draft", **draft)
    
    # Cleanup callback
    async def close_database_session() -> None:
        async with get_agent_db_session() as db_session:
            await VoiceSessionRepository(db_session).close(tenant.session_id)
            await db_session.commit()
        logger.info(f"🔒 [{room_name}] Database session closed")
        perf_timer.log_summary()
    
    ctx.add_shutdown_callback(close_database_session)
    
    # Start session BEFORE connecting to reduce latency
    perf_timer.start_stage("session_start")
    
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
    perf_timer.end_stage("session_start")
    
    # Connect AFTER session is ready - this makes local_participant available
    perf_timer.start_stage("room_connection")
    await ctx.connect()
    perf_timer.end_stage("room_connection")
    
    total_startup = time.perf_counter() - session_start_time
    logger.info(f"🎉 [{room_name}] Session fully ready in {total_startup*1000:.2f}ms")
    
    # Now we can publish events since we're connected
    await _publish_ui_event(
        ctx, 
        "ready", 
        session_id=str(tenant.session_id),
        startup_time_ms=round(total_startup * 1000, 2),
        label="Ready to listen"
    )
    
    # Automatically transition to listening after brief moment
    await asyncio.sleep(0.5)
    await _publish_ui_event(ctx, "agent_state", state="listening", label="Listening")
    
    logger.info(
        "session_started",
        extra={"room": room_name, "session_id": str(tenant.session_id), "owner_id": tenant.owner_id, "startup_ms": round(total_startup * 1000, 2)},
    )


if __name__ == "__main__":
    try:
        get_settings().require_agent_providers()
        cli.run_app(server)
    except RuntimeError as error:
        logger.error("agent_configuration_error", extra={"error_type": type(error).__name__})
        raise SystemExit(2) from error
