"""Authenticated HTTP and WebSocket voice billing endpoints."""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any, Awaitable, Callable, Dict, List, Optional, Tuple
from uuid import uuid4

from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect, status
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from core.security import get_current_user, verify_token
from core.shop_categories import stored_category
from db.database import database_is_configured, engine, get_session
from db.models import Item, User
from gst.service import gst_billing_service
from gst.voice import gst_voice_service
from pipeline.embedding_pipeline import EmbeddingServiceError, embedding_pipeline
from pipeline.retrieval_pipeline import RetrievalPipeline
from services.voice_service import voice_service


logger = logging.getLogger(__name__)
router = APIRouter()


class VoiceRequest(BaseModel):
    text: str = Field(..., min_length=1, max_length=1_000)
    # Kept for Flutter request compatibility. The authenticated user's stored
    # category is used instead so a client cannot override shop context.
    shop_category: Optional[str] = Field(default=None, max_length=60)
    # GST is a request for a different extraction pipeline.  The server still
    # authorizes it against persisted shop configuration before using it.
    gst_mode: bool = False


def _context_from_session(session: Session, user_id: int) -> Tuple[List[Dict[str, Any]], str]:
    user = session.get(User, user_id)
    if user is None or not user.is_active:
        raise LookupError("Account is unavailable")
    shop_category = stored_category(user.shop_category)
    items = session.exec(
        select(Item).where(
            Item.owner_id == user_id,
            Item.shop_category == shop_category,
        )
    ).all()
    inventory = [
        {
            "master_id": item.master_id,
            "names": item.names,
            "price": item.price,
            "unit": item.unit,
            "category": item.category,
            "gst_rate_bps": item.gst_rate_bps,
            "hsn_code": item.hsn_code,
            "tax_category": item.tax_category,
        }
        for item in items
    ]
    return inventory, shop_category


def _load_context(user_id: int) -> Tuple[List[Dict[str, Any]], str]:
    if not database_is_configured() or engine is None:
        raise RuntimeError("The database is not configured")
    with Session(engine) as session:
        return _context_from_session(session, user_id)


def _verified_customer_context(user_id: int, query: str) -> List[Dict[str, Any]]:
    """Return the five nearest verified names plus their linked bills.

    Customer-history enrichment must never make a normal voice bill unusable,
    so an unavailable embedding provider only omits this optional context.
    """
    if engine is None:
        return []
    try:
        query_embedding, _ = embedding_pipeline.generate_query_embedding(query)
        return RetrievalPipeline(engine).retrieve_customers(
            query_embedding=query_embedding,
            user_id=user_id,
            top_k=5,
        )
    except (EmbeddingServiceError, ValueError) as exc:
        logger.warning("Verified customer context unavailable user=%s: %s", user_id, exc)
        return []
    except Exception:
        logger.exception("Verified customer context lookup failed user=%s", user_id)
        return []


def _process_command(
    user_id: int, text: str, gst_mode: bool = False, session: Session | None = None
) -> Dict[str, Any]:
    inventory, shop_category = (
        _context_from_session(session, user_id) if session is not None else _load_context(user_id)
    )
    if gst_mode:
        if session is None:
            if not database_is_configured() or engine is None:
                raise RuntimeError("The database is not configured")
            with Session(engine) as owned_session:
                gst_billing_service.require_tax_invoice_configuration(owned_session, user_id)
        else:
            gst_billing_service.require_tax_invoice_configuration(session, user_id)
        return gst_voice_service.process(text, inventory, shop_category)
    return voice_service.process(
        text,
        inventory,
        shop_category,
        verified_customers=_verified_customer_context(user_id, text),
    )


@router.post("/process")
def process_voice(
    request: VoiceRequest,
    user_id: int = Depends(get_current_user),
    session: Session = Depends(get_session),
) -> Dict[str, Any]:
    """HTTP fallback used by Flutter when the continuous WebSocket is offline."""
    try:
        return _process_command(user_id, request.text.strip(), request.gst_mode, session)
    except LookupError:
        from fastapi import HTTPException

        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account is unavailable")


async def _stream_response(
    response: Dict[str, Any],
    send_current: Callable[[Dict[str, Any]], Awaitable[bool]],
) -> None:
    """Send a token stream only while its request still owns the turn."""
    payload = json.dumps(response, ensure_ascii=False, separators=(",", ":"))
    accumulated = ""
    for start in range(0, len(payload), 64):
        token = payload[start : start + 64]
        accumulated += token
        if not await send_current(
            {"type": "stream_token", "token": token, "accumulated": accumulated}
        ):
            return
        await asyncio.sleep(0)
    await send_current({"type": "complete", "response": response})


@router.websocket("/ws/stream")
async def voice_websocket_stream(websocket: WebSocket, token: Optional[str] = None) -> None:
    """Continuous, authenticated voice protocol used by ``VoiceAssistantScreen``."""
    user_id = verify_token(token) if token else None
    if user_id is None:
        await websocket.close(code=1008, reason="Authentication is required")
        return

    await websocket.accept()
    await websocket.send_json({"type": "connected", "message": "Voice stream connected"})
    active_task: asyncio.Task[None] | None = None
    active_request_id: str | None = None
    send_lock = asyncio.Lock()

    async def send_event(payload: Dict[str, Any]) -> None:
        """Serialise socket writes so tokens from turns can never interleave."""
        async with send_lock:
            await websocket.send_json(payload)

    async def process_message(request_id: str, text: str, gst_mode: bool = False) -> None:
        async def send_current(payload: Dict[str, Any]) -> bool:
            if active_request_id != request_id:
                return False
            # The active request may change while this task is waiting for a
            # previous socket write. Re-check under the same writer lock before
            # putting anything on the wire.
            async with send_lock:
                if active_request_id != request_id:
                    return False
                await websocket.send_json({**payload, "request_id": request_id})
            return active_request_id == request_id

        try:
            if not await send_current(
                {"type": "processing", "msg": "Vyamit AI is processing..."}
            ):
                return
            response = await asyncio.to_thread(_process_command, user_id, text, gst_mode)
            await _stream_response(response, send_current)
        except asyncio.CancelledError:
            # asyncio.to_thread cannot terminate the provider call already
            # running in a worker. Request-id checks above ensure its eventual
            # result is never emitted after interruption or a newer turn.
            raise
        except LookupError:
            await send_current({"type": "error", "message": "Account is unavailable"})
        except RuntimeError as exc:
            logger.warning("Voice WebSocket unavailable user=%s reason=%s", user_id, type(exc).__name__)
            await send_current(
                {"type": "error", "message": "Voice service is temporarily unavailable"}
            )
        except Exception:
            logger.exception("Voice WebSocket processing failed user=%s", user_id)
            await send_current({"type": "error", "message": "Unable to process the voice request"})

    try:
        while True:
            raw_message = await websocket.receive_text()
            try:
                message = json.loads(raw_message)
            except json.JSONDecodeError:
                message = {"action": "process", "text": raw_message}
            if not isinstance(message, dict):
                await websocket.send_json({"type": "error", "message": "Invalid request"})
                continue
            action = message.get("action", "process")
            if action == "ping":
                await send_event({"type": "pong"})
                continue
            if action == "session_start":
                await send_event({"type": "session_started"})
                continue
            if action == "session_stop":
                if active_task and not active_task.done():
                    active_task.cancel()
                active_request_id = None
                await send_event({"type": "session_stopped"})
                continue
            if action == "interrupt":
                requested_id = str(message.get("request_id") or active_request_id or "")
                if requested_id and requested_id == active_request_id and active_task and not active_task.done():
                    active_task.cancel()
                if requested_id == active_request_id:
                    active_request_id = None
                await send_event({"type": "interrupted", "request_id": requested_id})
                continue
            if action != "process":
                await send_event({"type": "error", "message": "Unsupported action"})
                continue
            text = str(message.get("text") or "").strip()
            if not text or len(text) > 1_000:
                await send_event(
                    {"type": "error", "message": "Voice text must be between 1 and 1000 characters"}
                )
                continue
            if active_task and not active_task.done():
                active_task.cancel()
            request_id = str(message.get("request_id") or uuid4())[:120]
            active_request_id = request_id
            active_task = asyncio.create_task(
                process_message(request_id, text, bool(message.get("gst_mode", False)))
            )
    except WebSocketDisconnect:
        logger.info("Voice WebSocket disconnected user=%s", user_id)
    finally:
        if active_task and not active_task.done():
            active_task.cancel()
