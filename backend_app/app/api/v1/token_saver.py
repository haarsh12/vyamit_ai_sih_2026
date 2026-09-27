"""Short-lived authenticated WebSocket API for Token Saver mode."""

from __future__ import annotations

import asyncio
import json
import re
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect, status

from app.config.settings import Settings, get_settings
from app.core.rate_limit import SlidingWindowRateLimiter
from app.core.security import get_current_user_id
from app.db.session import get_session_factory
from app.domain.token_saver import decode_token_saver_ticket, issue_token_saver_ticket, token_saver_service
from app.repositories.tenants import get_tenant_context
from app.schemas.token_saver import TokenSaverTicketResponse


router = APIRouter(prefix="/voice/token-saver", tags=["token saver"])
_ticket_limiter = SlidingWindowRateLimiter(max_requests=12, window_seconds=60)
_turn_limiter = SlidingWindowRateLimiter(max_requests=30, window_seconds=60)
_REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,120}$")


@router.post("/ticket", response_model=TokenSaverTicketResponse, status_code=status.HTTP_201_CREATED)
async def create_token_saver_ticket(
    user_id: int = Depends(get_current_user_id),
    settings: Settings = Depends(get_settings),
) -> TokenSaverTicketResponse:
    _ticket_limiter.check("token-saver-ticket", str(user_id))
    return issue_token_saver_ticket(user_id, settings)


@router.websocket("/ws")
async def token_saver_websocket(websocket: WebSocket) -> None:
    """Accept final recognized text only; audio never traverses this socket."""

    # Native apps usually omit Origin. When a browser supplies it, enforce the
    # same allow-list as HTTP so another site cannot spend a user's ticket.
    origin = websocket.headers.get("origin")
    if origin and origin.rstrip("/") not in get_settings().allowed_origins:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Origin is not allowed")
        return
    protocols = [
        value.strip()
        for value in websocket.headers.get("sec-websocket-protocol", "").split(",")
        if value.strip()
    ]
    ticket_values = [value for value in protocols if value != "vyamit-token-saver"]
    if protocols.count("vyamit-token-saver") != 1 or len(ticket_values) != 1:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Authentication is required")
        return
    ticket = ticket_values[0]
    user_id = decode_token_saver_ticket(ticket)
    if user_id is None:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION, reason="Authentication is required")
        return

    await websocket.accept(subprotocol="vyamit-token-saver")
    await websocket.send_json({"type": "connected"})
    active_task: asyncio.Task[None] | None = None
    active_request_id: str | None = None
    send_lock = asyncio.Lock()

    async def send_event(payload: dict[str, object]) -> None:
        async with send_lock:
            await websocket.send_json(payload)

    async def process_turn(request_id: str, transcript: str) -> None:
        async def send_current(payload: dict[str, object]) -> bool:
            if request_id != active_request_id:
                return False
            async with send_lock:
                if request_id != active_request_id:
                    return False
                await websocket.send_json({**payload, "request_id": request_id})
            return request_id == active_request_id

        try:
            if not await send_current({"type": "processing", "message": "Processing your request…"}):
                return
            session_factory = get_session_factory()
            if session_factory is None:
                await send_current({"type": "error", "message": "Token Saver is temporarily unavailable."})
                return
            result = None
            last_exc = None
            for attempt in range(3):
                try:
                    async with session_factory() as session:
                        tenant = await get_tenant_context(session, user_id)
                        result = await token_saver_service.process(session, tenant, transcript)
                    break
                except Exception as exc:
                    last_exc = exc
                    if attempt < 2:
                        await asyncio.sleep(0.5 * (attempt + 1))
                    else:
                        raise exc
            if result is not None:
                await send_current({"type": "complete", "response": result.model_dump(mode="json")})
        except asyncio.CancelledError:
            raise
        except Exception:
            # No transcript, provider response, or token is included in this event.
            await send_current({"type": "error", "message": "Token Saver is temporarily unavailable."})

    try:
        while True:
            raw_message = await websocket.receive_text()
            try:
                message = json.loads(raw_message)
            except json.JSONDecodeError:
                await send_event({"type": "error", "message": "Invalid request."})
                continue
            if not isinstance(message, dict):
                await send_event({"type": "error", "message": "Invalid request."})
                continue
            action = message.get("action")
            if action == "ping":
                await send_event({"type": "pong"})
                continue
            if action == "interrupt":
                if active_task is not None and not active_task.done():
                    active_task.cancel()
                active_request_id = None
                await send_event({"type": "interrupted"})
                continue
            if action != "process":
                await send_event({"type": "error", "message": "Unsupported action."})
                continue

            transcript = str(message.get("text") or "").strip()
            request_id = str(message.get("request_id") or uuid4().hex)
            if not _REQUEST_ID_PATTERN.fullmatch(request_id):
                await send_event({"type": "error", "message": "Invalid request id."})
                continue
            if not 1 <= len(transcript) <= 1_000:
                await send_event({"type": "error", "message": "Voice text must be between 1 and 1000 characters."})
                continue
            try:
                _turn_limiter.check("token-saver-turn", str(user_id))
            except HTTPException:
                await send_event({"type": "error", "message": "Too many requests. Please wait before trying again."})
                continue
            if active_task is not None and not active_task.done():
                active_task.cancel()
            active_request_id = request_id
            active_task = asyncio.create_task(process_turn(request_id, transcript))
    except WebSocketDisconnect:
        pass
    finally:
        if active_task is not None and not active_task.done():
            active_task.cancel()
