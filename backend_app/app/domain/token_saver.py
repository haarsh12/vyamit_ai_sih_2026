"""Low-bandwidth text processing for the Token Saver voice mode.

Device STT and TTS stay on the phone.  The only network payload is the final
recognized text, delivered through a short-lived authenticated WebSocket.  Any
model output is treated as untrusted and resolved against the user's own
catalogue before a review-only bill draft is created.
"""

from __future__ import annotations

import json
import logging
import re
from datetime import UTC, datetime, timedelta
from decimal import Decimal, ROUND_HALF_UP
from uuid import uuid4

logger = logging.getLogger(__name__)

from jose import JWTError, jwt
from sqlalchemy.ext.asyncio import AsyncSession

from app.config.settings import Settings, get_settings
from app.db.models import User
from app.db.tenant import TenantContext
from app.domain.analytics import analytics_service
from app.domain.customer_ledger import customer_ledger_service
from app.domain.long_bill import printable_catalog_name
from app.domain.workflows import workflow_service
from app.integrations.vertex_gemini import create_vertex_gemini_client
from app.retrieval.customers import customer_search_service
from app.retrieval.inventory import inventory_search_service
from app.repositories.verified_customers import VerifiedCustomerRepository
from app.schemas.analytics import BillCreate
from app.schemas.ledger import LedgerAdjustmentRequest
from app.schemas.token_saver import TokenSaverProcessResponse, TokenSaverTicketResponse


_ALGORITHM = "HS256"
_TICKET_PURPOSE = "token-saver-ws"
_TICKET_TTL = timedelta(minutes=1)
_MAX_ITEMS = 20


def issue_token_saver_ticket(user_id: int, settings: Settings | None = None) -> TokenSaverTicketResponse:
    """Create a narrowly scoped, short-lived WebSocket credential."""

    settings = settings or get_settings()
    now = datetime.now(UTC)
    expires_at = now + _TICKET_TTL
    ticket = jwt.encode(
        {
            "sub": str(user_id),
            "purpose": _TICKET_PURPOSE,
            "iat": int(now.timestamp()),
            "exp": int(expires_at.timestamp()),
            "jti": uuid4().hex,
        },
        settings.require_jwt_secret(),
        algorithm=_ALGORITHM,
    )
    return TokenSaverTicketResponse(ticket=ticket, expires_at=expires_at)


def decode_token_saver_ticket(ticket: str, settings: Settings | None = None) -> int | None:
    """Accept only a valid ticket; a normal app JWT cannot open this socket."""

    settings = settings or get_settings()
    try:
        payload = jwt.decode(ticket, settings.require_jwt_secret(), algorithms=[_ALGORITHM])
        if payload.get("purpose") != _TICKET_PURPOSE:
            return None
        return int(payload["sub"])
    except (JWTError, KeyError, TypeError, ValueError, RuntimeError):
        return None


def _latin_item_name(name: str) -> str:
    """Format requested item name for receipt printer compatibility while preserving the user's requested word."""

    clean = name.strip()
    if not clean:
        return "Item"
    devanagari_map = {
        "गेहूं": "Gehun",
        "गेहू": "Gehun",
        "गेहूँ": "Gehun",
        "आटा": "Aata",
        "चावल": "Chawal",
        "टमाटर": "Tamatar",
        "धनिया": "Dhaniya",
        "चीनी": "Chini",
        "शक्कर": "Shakkar",
        "दाल": "Daal",
        "तेल": "Tel",
        "दूध": "Doodh",
        "नमक": "Namak",
        "हल्दी": "Haldi",
        "मिर्च": "Mirch",
        "जीरा": "Jeera",
        "प्याज": "Pyaz",
        "आलू": "Aloo",
    }
    for dev, lat in devanagari_map.items():
        clean = clean.replace(dev, lat)
    latin_only = re.sub(r"[^\x00-\x7F]+", "", clean).strip()
    return latin_only.title()[:120] if latin_only else "Item"


def _compact_catalog(catalog: list[object]) -> list[dict[str, object]]:
    """Project the catalogue into plain data, never instructions, for the model."""

    result: list[dict[str, object]] = []
    for item in catalog[:100]:
        printable_name = printable_catalog_name(item)  # type: ignore[arg-type]
        if printable_name is None:
            continue
        try:
            price_val = float(item.price)  # type: ignore[attr-defined]
        except (ValueError, TypeError, AttributeError):
            price_val = 0.0
        result.append(
            {
                "name": printable_name,
                "aliases": [name[:120] for name in item.names[:5]],  # type: ignore[union-attr]
                "price": price_val,
                "unit": str(item.unit)[:30],  # type: ignore[union-attr]
            }
        )
    return result


def _prompt_for(
    text: str,
    shop_category: str,
    catalog: list[object],
    shop_name: str = "",
    owner_name: str = "",
    address: str = "",
) -> str:
    """Constrain the model to an extraction/query task with untrusted-data boundaries."""

    shop_info = f"Shop Name: '{shop_name}', Owner: '{owner_name}', Address: '{address}', Category: '{shop_category}'"

    return f"""You are Vyamit AI, an intelligent billing & shop assistant for a {shop_category} shop.
Shop details: {shop_info}

Customer transcript: {json.dumps(text, ensure_ascii=False)}
Available inventory catalogue (with prices): {json.dumps(_compact_catalog(catalog), ensure_ascii=False)}

Return a JSON object only with exactly these keys:
{{
  "type": "BILL" | "QUERY" | "LEDGER_ADJUSTMENT" | "ERROR",
  "query_type": "SHOP_PROFILE" | "SALES_SUMMARY" | "INVENTORY_SEARCH" | "CUSTOMER_INFO" | "CUSTOMER_LEDGER" | "GENERAL",
  "query_param": "optional string parameter (e.g. search keyword, customer name, or days like '1' for today, '7', '30')",
  "items": [
    {{
      "name": "item name in Latin script ONLY (preserve user's spoken word e.g. Gehun, Tamatar, Chawal)",
      "quantity": positive number,
      "unit": "kg/litre/piece/packet/unit",
      "price": optional number (use catalogue price if available),
      "total": optional number
    }}
  ],
  "customer_name": "optional Latin-script name (Hinglish)",
  "payment_method": "cash" | "udhaar",
  "ledger_action": "udhaar" | "payment" | null,
  "ledger_amount": "positive number or null",
  "ledger_note": "optional brief note",
  "message": "short conversational single sentence (4 to 5 words max in Hinglish)"
}}

Rules:
1. FOR BILL TRANSACTIONS:
   - ITEM NAME PRESERVATION: Keep the EXACT item name spoken by the user (formatted in Latin script e.g. "Gehun", "Tamatar", "Chawal"). DO NOT substitute AI's own words or rename "Gehun" to "Aata".
   - PRINTER COMPATIBILITY: customer_name and item names MUST be in Latin script ONLY.
   - INDIAN RETAIL QUANTITIES:
     * "एक पाव" / "1 पाव" / "पाव" (1 Paav) = 0.25 kg (250 gm).
     * "आधा किलो" / "1/2 kg" = 0.5 kg.
     * "डेढ़ किलो" (1.5 kg) = 1.5 kg.
     * "ढाई किलो" (2.5 kg) = 2.5 kg.
     * "सवा किलो" = 1.25 kg.
     * "पौने किलो" = 0.75 kg.
   - RATE VS QUANTITY DISTINCTION:
     * "₹50 किलो के हिसाब से" or "50 रुपये किलो" specifies the RATE/PRICE = 50 per kg, NOT the quantity!
   - PRICE LOOKUP: Always check the catalogue first for item price! If item is in catalogue, use catalogue price.
   - Non-catalogue items with spoken price/rate: include them with calculated total.
   - If an item has NO price and is not in catalogue, ask for missing price in a 4-5 words sentence e.g. "Kripya Tamatar ka rate bataiye."

2. FOR QUERIES / QUESTIONS:
   - Set "type": "QUERY".
   - If user asks about shop name, owner, address, profile: set "query_type": "SHOP_PROFILE".
   - If user asks about sales, revenue, dashboard, bills count ("aaj ki sale", "total revenue", "dashboard summary"): set "query_type": "SALES_SUMMARY", set "query_param": "1" (for today) or "7" or "30".
   - If user asks if an item is in stock or its price ("chawal hai kya", "tamatar ka rate kya hai"): set "query_type": "INVENTORY_SEARCH", set "query_param": item name.
   - If user asks about customer info or bill history ("Ramesh ka bill", "customer details"): set "query_type": "CUSTOMER_INFO", set "query_param": customer name.
   - If user asks how much a customer owes, their udhaar, dues, payment, or ledger: set "query_type": "CUSTOMER_LEDGER", set "query_param" and "customer_name" to the customer name.
   - For general greetings or questions: set "query_type": "GENERAL".

3. FOR LEDGER CHANGES:
   - When the owner says to add udhaar/credit/due or says a customer paid and the ledger should reduce, set type "LEDGER_ADJUSTMENT".
   - Set customer_name, ledger_action to "udhaar" (increase) or "payment" (reduce), and ledger_amount to the exact positive rupee amount.
   - Never treat a customer question as a ledger change. The app will require a separate visible confirmation before any ledger adjustment is recorded.

4. CONVERSATIONAL SINGLE SENTENCE FORMAT (STRICT):
   - The "message" field MUST be a SHORT CONVERSATIONAL SINGLE SENTENCE of 4 TO 5 WORDS ONLY (in Hinglish/Hindi).
   - NEVER output long structured reports, technical bullet points, or multi-sentence paragraphs.
   - Examples:
     * Bill created: "Aapka bill ban gaya hai."
     * Missing price: "Kripya Tamatar ka rate bataiye."
     * Sales summary: "Aaj ki sale 1250 rupaye hai."
     * Shop details: "Dukaan Rajesh Sharma ki hai."
     * Stock/Price query: "Tamatar 40 rupaye kilo hai."
"""


def _repair_json(text: str) -> str:
    """Attempt to repair truncated or slightly malformed JSON strings."""
    text = text.strip()
    open_curly = text.count("{") - text.count("}")
    open_square = text.count("[") - text.count("]")
    in_quote = text.count('"') % 2 != 0
    if in_quote:
        text += '"'
    if open_square > 0:
        text += "]" * open_square
    if open_curly > 0:
        text += "}" * open_curly
    return text


def _read_json(content: object) -> dict[str, object]:
    if isinstance(content, list):
        content = "".join(str(part) for part in content)
    if not isinstance(content, str):
        raise ValueError("Model returned no text")
    cleaned = content.strip()
    if cleaned.startswith("```"):
        cleaned = "\n".join(cleaned.splitlines()[1:]).removesuffix("```").strip()
    try:
        parsed = json.loads(cleaned)
    except json.JSONDecodeError:
        repaired = _repair_json(cleaned)
        parsed = json.loads(repaired)
    if not isinstance(parsed, dict):
        raise ValueError("Model response must be an object")
    return parsed


def _model_response(settings: Settings, prompt: str) -> dict[str, object]:
    """Direct Vertex Gemini or Gemini API extraction with retries and model fallbacks."""

    import time
    from google.genai import Client
    from google.genai.types import GenerateContentConfig

    configured_model = settings.vertex_gemini_model.strip() or "gemini-2.5-flash"
    candidate_models = [configured_model]
    for alt in ["gemini-2.5-flash", "gemini-1.5-flash-002", "gemini-flash-latest", "gemini-2.0-flash"]:
        if alt not in candidate_models:
            candidate_models.append(alt)

    clients: list[tuple[str, Client]] = []
    try:
        vertex_client = create_vertex_gemini_client(settings)
        clients.append(("vertex", vertex_client))
    except Exception:
        pass

    try:
        api_client = Client()
        clients.append(("api_key", api_client))
    except Exception:
        pass

    if not clients:
        raise RuntimeError("No Gemini client could be initialized")

    last_exc: Exception | None = None
    for client_type, client in clients:
        for model in candidate_models:
            for attempt in range(3):
                try:
                    response = client.models.generate_content(
                        model=model,
                        contents=prompt,
                        config=GenerateContentConfig(
                            response_mime_type="application/json",
                            temperature=0.1,
                            max_output_tokens=2048,
                        ),
                    )
                    if response and response.text:
                        return _read_json(response.text)
                except Exception as exc:
                    last_exc = exc
                    exc_str = str(exc)
                    if "429" in exc_str or "RESOURCE_EXHAUSTED" in exc_str or "Quota" in exc_str or "Too Many Requests" in exc_str:
                        time.sleep(0.5 * (attempt + 1))
                        continue
                    break

    if last_exc:
        raise last_exc
    raise RuntimeError("All Gemini model generation attempts failed")


def _positive_decimal(value: object) -> Decimal | None:
    try:
        quantity = Decimal(str(value))
    except Exception:
        return None
    if quantity <= 0 or quantity > Decimal("100000"):
        return None
    return quantity.quantize(Decimal("0.001"))


def _safe_customer_name(value: object) -> str | None:
    name = str(value or "").strip()
    if not name or len(name) > 120:
        return None
    # Receipt printers in this application require a Latin-script customer name.
    if not re.fullmatch(r"[A-Za-z][A-Za-z .'-]{0,119}", name):
        return None
    return name


class TokenSaverService:
    async def process(
        self,
        session: AsyncSession,
        tenant: TenantContext,
        transcript: str,
        settings: Settings | None = None,
    ) -> TokenSaverProcessResponse:
        settings = settings or get_settings()

        # Fetch shop profile info for prompt context
        user = await session.get(User, tenant.owner_id)
        shop_name = user.shop_name if user else ""
        owner_name = user.owner_name if user else ""
        address = user.address if user else ""

        catalog = await inventory_search_service.list_catalog(session, tenant)

        import asyncio

        try:
            model_output = await asyncio.wait_for(
                asyncio.to_thread(
                    _model_response,
                    settings,
                    _prompt_for(transcript, tenant.shop_category, catalog or [], shop_name, owner_name, address),
                ),
                timeout=25,
            )
        except TimeoutError:
            return TokenSaverProcessResponse(type="ERROR", message="Kripya phir se koshish karein.")
        except Exception as exc:
            logger.exception("TokenSaverService process failed: %s", exc)
            return TokenSaverProcessResponse(type="ERROR", message="Kripya phir se koshish karein.")

        response_type = str(model_output.get("type", "ERROR")).upper()
        message = str(model_output.get("message") or "").strip()

        # Handle QUERY responses (Shop details, Dashboard sales, Inventory, Customer search)
        if response_type == "QUERY":
            query_type = str(model_output.get("query_type") or "GENERAL").upper()
            query_param = str(model_output.get("query_param") or "").strip()

            if query_type == "SHOP_PROFILE":
                if user and user.shop_name:
                    message = f"Dukaan {user.shop_name} ki hai."
                else:
                    message = message or "Dukaan details mil gayi hain."
                return TokenSaverProcessResponse(type="QUERY", message=message)

            elif query_type == "SALES_SUMMARY":
                days = 1 if query_param in ("1", "today", "aaj") else (int(query_param) if query_param.isdigit() else 30)
                try:
                    overview = await analytics_service.overview(session, tenant, days=days)
                    revenue = int(overview.get("total_revenue", 0.0))
                    if days == 1:
                        message = f"Aaj ki sale {revenue:,} rupaye hai."
                    else:
                        message = f"Pichle {days} dino ki sale {revenue:,} rupaye."
                except Exception as exc:
                    logger.warning("Failed to fetch analytics for TokenSaver query: %s", exc)
                    message = message or "Sales summary nahi mili."
                return TokenSaverProcessResponse(type="QUERY", message=message)

            elif query_type == "INVENTORY_SEARCH":
                search_term = query_param or transcript
                try:
                    matches = await inventory_search_service.search(session, tenant, search_term, limit=1)
                    if matches and matches[0].item:
                        item = matches[0].item
                        p_name = _latin_item_name(search_term) if search_term else (printable_catalog_name(item) or item.names[0])
                        price_int = int(item.price)
                        unit_str = item.unit or "kg"
                        message = f"{p_name} {price_int} rupaye {unit_str} hai."
                    else:
                        message = f"{search_term} catalog me nahi hai."
                except Exception as exc:
                    logger.warning("Inventory search failed in query: %s", exc)
                    message = message or f"{search_term} nahi mila."
                return TokenSaverProcessResponse(type="QUERY", message=message)

            elif query_type == "CUSTOMER_INFO":
                search_term = query_param or transcript
                try:
                    cust_matches = await customer_search_service.search(session, tenant, search_term, limit=1)
                    if cust_matches:
                        cust = cust_matches[0].customer
                        message = f"{cust.name} ke {cust.total_bills} bills hain."
                    else:
                        message = f"Grahak {search_term} nahi mila."
                except Exception as exc:
                    logger.warning("Customer search failed in query: %s", exc)
                    message = message or "Grahak jankari nahi mili."
                return TokenSaverProcessResponse(type="QUERY", message=message)

            elif query_type == "CUSTOMER_LEDGER":
                customer_query = str(
                    model_output.get("customer_name") or query_param
                ).strip()
                if not customer_query:
                    return TokenSaverProcessResponse(
                        type="QUERY",
                        message="Grahak ka naam batayiye.",
                    )
                matches = await customer_search_service.search(
                    session, tenant, customer_query, limit=2
                )
                if not matches:
                    return TokenSaverProcessResponse(
                        type="QUERY",
                        message=f"Verified grahak {customer_query} nahi mila.",
                    )
                if len(matches) > 1:
                    return TokenSaverProcessResponse(
                        type="QUERY",
                        message="Do grahak mile, naam saaf batayiye.",
                    )
                customer = matches[0].customer
                return TokenSaverProcessResponse(
                    type="QUERY",
                    message=f"{customer.name} ka udhaar {int(customer.ledger_balance):,} rupaye hai.",
                )

            return TokenSaverProcessResponse(type="QUERY", message=message or "Aapki kya sahayata karoon?")

        if response_type == "LEDGER_ADJUSTMENT":
            customer_query = str(model_output.get("customer_name") or "").strip()
            action = str(model_output.get("ledger_action") or "").strip().casefold()
            aliases = {
                "add": "udhaar",
                "increase": "udhaar",
                "credit": "udhaar",
                "paid": "payment",
                "reduce": "payment",
                "remove": "payment",
            }
            action = aliases.get(action, action)
            amount = _positive_decimal(model_output.get("ledger_amount"))
            if not customer_query or action not in {"udhaar", "payment"} or amount is None:
                return TokenSaverProcessResponse(
                    type="ERROR",
                    message="Grahak aur sahi rakam batayiye.",
                )
            matches = await customer_search_service.search(
                session, tenant, customer_query, limit=2
            )
            if not matches:
                return TokenSaverProcessResponse(
                    type="ERROR",
                    message=f"Verified grahak {customer_query} nahi mila.",
                )
            if len(matches) > 1:
                return TokenSaverProcessResponse(
                    type="ERROR",
                    message="Do grahak mile, naam saaf batayiye.",
                )
            customer = matches[0].customer
            try:
                ledger_draft = await customer_ledger_service.create_adjustment_draft(
                    session,
                    tenant,
                    customer.id,
                    LedgerAdjustmentRequest(
                        entry_type=action,
                        amount=amount.quantize(Decimal("0.01")),
                        note=str(model_output.get("ledger_note") or "").strip() or None,
                        source="token_saver",
                    ),
                )
            except Exception as error:
                detail = getattr(error, "detail", None)
                return TokenSaverProcessResponse(
                    type="ERROR",
                    message=str(detail or "Ledger change prepare nahi hua."),
                )
            action_text = "udhaar" if action == "udhaar" else "payment"
            return TokenSaverProcessResponse(
                type="LEDGER",
                message=f"{customer.name} ka {action_text} confirm kijiye.",
                ledger_draft=ledger_draft,
            )

        # Handle BILL responses
        if response_type != "BILL" or not isinstance(model_output.get("items"), list):
            return TokenSaverProcessResponse(type="ERROR", message=message or "Kripya phir se boliye.")

        proposed_by_master_id: dict[str, dict[str, object]] = {}
        on_spot_items: list[dict[str, object]] = []
        unresolved_items: list[str] = []

        for raw_item in model_output["items"][:_MAX_ITEMS]:
            if not isinstance(raw_item, dict):
                continue
            raw_name = str(raw_item.get("name") or raw_item.get("item") or "").strip()
            requested_name = _latin_item_name(raw_name)
            quantity = _positive_decimal(raw_item.get("quantity", raw_item.get("qty", 1)))
            if not requested_name or quantity is None:
                continue

            # Indian unit post-processing safety check for Paav (250g = 0.25kg)
            if re.search(r"\b(पाव|paav|1/4|quarter)\b", transcript, re.IGNORECASE) and quantity > Decimal("2"):
                quantity = Decimal("0.25")
            elif re.search(r"\b(आधा|aadha|adha|half)\b", transcript, re.IGNORECASE) and quantity > Decimal("2"):
                quantity = Decimal("0.5")

            # 1. Search catalogue for matching item using raw user query
            matches = []
            try:
                matches = await inventory_search_service.search(session, tenant, raw_name, limit=1)
            except Exception as exc:
                logger.warning("Search exception for %s: %s", raw_name, exc)
                matches = []

            catalog_item = matches[0].item if (matches and matches[0].item) else None

            # Determine price: first from model, if missing/0 then from catalog_item
            raw_price = raw_item.get("price") or raw_item.get("rate")
            price_dec = _positive_decimal(raw_price) if raw_price is not None else None

            if (price_dec is None or price_dec <= 0) and catalog_item is not None:
                try:
                    price_dec = Decimal(str(catalog_item.price)).quantize(Decimal("0.01"))
                except Exception:
                    price_dec = None

            if catalog_item is not None and price_dec is not None and price_dec > 0:
                unit_str = str(catalog_item.unit)[:30] or "unit"
                item_key = f"{catalog_item.master_id}_{requested_name}"
                existing = proposed_by_master_id.get(item_key)
                if existing is None:
                    proposed_by_master_id[item_key] = {
                        "name": requested_name,
                        "quantity": quantity,
                        "unit": unit_str,
                        "price": price_dec,
                        "total": (quantity * price_dec).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP),
                    }
                else:
                    merged_quantity = Decimal(str(existing["quantity"])) + quantity
                    existing["quantity"] = merged_quantity.quantize(Decimal("0.001"))
                    existing["total"] = (merged_quantity * price_dec).quantize(
                        Decimal("0.01"), rounding=ROUND_HALF_UP
                    )
            else:
                # Spoken or custom line item logic
                raw_total = raw_item.get("total")
                total_dec = _positive_decimal(raw_total) if raw_total is not None else None

                if price_dec is None and total_dec is not None and quantity > 0:
                    price_dec = (total_dec / quantity).quantize(Decimal("0.01"))

                if price_dec is not None and price_dec > 0:
                    unit_str = str(raw_item.get("unit") or "unit")[:30]
                    total_calc = (quantity * price_dec).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
                    on_spot_items.append({
                        "name": requested_name[:120],
                        "quantity": quantity,
                        "unit": unit_str,
                        "price": price_dec,
                        "total": total_calc,
                    })
                else:
                    unresolved_items.append(requested_name[:120])

        proposed_items = list(proposed_by_master_id.values()) + on_spot_items

        if not proposed_items:
            err_msg = message
            if unresolved_items:
                err_msg = f"Kripya {unresolved_items[0]} ka rate bataiye."
            elif not err_msg or len(err_msg) > 30:
                err_msg = "Item ka rate bataiye."
            return TokenSaverProcessResponse(
                type="ERROR",
                message=err_msg,
                unresolved_items=unresolved_items[:_MAX_ITEMS],
            )

        payload = BillCreate.model_validate(
            {
                "items": proposed_items,
                "total_amount": sum((item["total"] for item in proposed_items), Decimal("0.00")).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP),
                "customer_name": _safe_customer_name(model_output.get("customer_name")),
                "payment_method": model_output.get("payment_method") or "cash",
                "bill_type": "printed",
                "billing_source": "voice",
            }
        )
        if payload.payment_method == "udhaar":
            verified_customer = await VerifiedCustomerRepository(session).find_by_exact_name(
                tenant, payload.customer_name or ""
            )
            if verified_customer is None:
                return TokenSaverProcessResponse(
                    type="ERROR",
                    message="Udhaar ke liye verified grahak chuniye.",
                )
            payload = payload.model_copy(
                update={
                    "verified_customer_id": verified_customer.id,
                    "customer_name": verified_customer.name,
                }
            )
        draft = await workflow_service.create_bill_draft(session, tenant, payload)

        bill_msg = message
        if unresolved_items:
            bill_msg = f"Kripya {unresolved_items[0]} ka rate bataiye."
        elif not bill_msg or len(bill_msg) > 35 or "review" in bill_msg.lower() or "added" in bill_msg.lower():
            bill_msg = "Aapka bill ban gaya hai."

        return TokenSaverProcessResponse(
            type="BILL",
            message=bill_msg,
            draft=draft,
            unresolved_items=unresolved_items[:_MAX_ITEMS],
        )


token_saver_service = TokenSaverService()
