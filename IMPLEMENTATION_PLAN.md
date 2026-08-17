# Vyamit — implementation plan and architecture record

**Status:** active. This is the single living planning artifact for the new backend. Update its checkboxes and decisions as implementation progresses.

## 1. Audit findings

The repository contains three sources of truth:

| Source | What it contains | Decision |
| --- | --- | --- |
| `frontend_app/` | Flutter application (not React), with authentication, category-specific retail/doctor workspaces, inventory, bills, GST, dashboard, printing, and voice UI. | Preserve UI and existing HTTP contracts wherever possible; make a focused LiveKit migration only in voice-related code. |
| `previous_backend_reference_codebase/` | Working FastAPI/SQLModel backend for OTP/JWT, inventory, bills, GST, doctor records, analytics, Gemini embedding/RAG, and legacy text WebSockets. | Port domain rules and contracts selectively. Do **not** reuse its monolith, runtime schema creation, synchronous data layer, old RAG orchestration, or voice WebSockets. |
| `previous_livekit_working_backend_codebase/` | Tested LiveKit AgentServer reference with Google STT, Gemini through Vertex credentials, Cartesia TTS, token issuing, turn detection, and agent lifecycle logging. | Reuse its provider and LiveKit patterns after adapting them for authenticated tenant context, business tools, and fallback. |

### Frontend compatibility inventory

The existing Flutter app calls these routes and they must remain stable during the backend rewrite:

- `/auth/send-otp`, `/auth/verify-otp`, `/auth/profile`, `/auth/update-profile`
- `/items/`, `/items/{id}/`
- `/analytics/bills`, `/analytics/dashboard`, `/analytics/overview`
- `/inventory/voice-parse`
- `/gst/configuration`, `/gst/invoices/*`
- `/doctor-prescriptions/*`

`VoiceAssistantScreen` currently combines the `speech_to_text` and `flutter_tts` plugins with `/voice/ws/stream`. `DoctorVoiceScreen` and `VoiceInventoryScreen` also use device STT. These are incompatible with the requested LiveKit + Google STT + Cartesia stack and will be migrated in focused frontend phases; no screen redesign is required.

## 2. Confirmed target architecture

```text
Flutter app -- authenticated HTTPS --> FastAPI application API
    |                                        |
    | GET /v1/voice/token                    +--> Supabase PostgreSQL + pgvector
    v                                        |       (domain data, voice sessions, jobs)
LiveKit Room <--- WebRTC audio/data ---> LiveKit Agent worker
                                             |
                                             +--> Google Cloud STT (Chirp)
                                             +--> Gemini via Vertex AI (primary reasoning)
                                             +--> Mistral (only transient-failure fallback)
                                             +--> Cartesia (streaming TTS)
                                             +--> authorized domain services/repositories
                                             +--> Vertex text embeddings on retrieval demand
```

Two independently deployable processes share one `backend_app/app` package:

1. **API process** — FastAPI, authentication, all existing HTTP contracts, migrations/health endpoints, and short-lived LiveKit token issuance.
2. **Agent process** — LiveKit `AgentServer`; no public HTTP API and no browser-accessible secret.

### Tenant boundary (non-negotiable)

The authenticated API caller creates a `voice_sessions` row before receiving a LiveKit token. The agent resolves the caller from the server-created `(room_name, participant_identity)` record. Repositories accept a trusted `TenantContext` and enforce owner/category filters internally. Neither the mobile client nor the LLM supplies an owner, shop, category, price, or authorization decision.

### Voice turn flow

1. Flutter obtains a token using its normal bearer token and joins a server-created room with `livekit_client`.
2. Google STT streams Hindi, Marathi, English, and configured alternatives to the agent.
3. Gemini decides whether a tool is necessary. Greetings/general answers do not call embeddings, pgvector, or database retrieval.
4. A tool invokes a domain service under the trusted tenant context. Semantic inventory retrieval generates an embedding only when the selected tool needs it.
5. Gemini generates the concise response; Cartesia streams audio and aligned transcription through LiveKit.
6. The agent publishes small typed UI events (`agent_state`, `draft_updated`, `tool_progress`, `error`) through LiveKit data topics. Flutter preserves the current orb, transcript, GST preview, and bill UI.

## 3. Reuse classification

### A — copy with no functional change (relocated only)

- `core/shop_categories.py`: canonical categories and backward-compatible aliases.
- `core/rate_limit.py`: in-process sliding-window guard (documented as development/single-worker protection).
- `gst/constants.py`, `gst/calculation.py`, `gst/validation.py`: pure Indian GST constants, integer-paise math, and structural validation.

### B — copy and modify

- `core/security.py`, `services/otp_service.py`, `api/auth.py`, `db/schemas.py`: retain phone/OTP/JWT behavior and Flutter payloads, but use typed settings, hashed OTPs, async repositories, and no development secret in production.
- `api/items.py`, `api/analytics.py`, `services/customer_service.py`: retain contracts and domain behaviour; move persistence to repositories, use `Decimal`/paise-safe calculations, and enqueue item embeddings after writes.
- `gst/schemas.py`, `gst/service.py`, `api/gst.py`: retain tested business rules and endpoint shapes; replace direct sessions and runtime table creation with async transactions and migrations.
- `services/voice_inventory_service.py`: retain its deterministic parsing fallback and response shape; make Gemini extraction a tool/service and keep mutations in existing inventory APIs.
- `services/doctor_prescription_voice_service.py`, `api/doctor_prescriptions.py`: retain editing/printing/patient-history workflow; migrate dictation transport to a dedicated, category-authorized LiveKit agent.
- LiveKit `settings.py`, `providers.py`, `runner.py`, token issuer, and prompt: retain the tested provider setup/lifecycle patterns, but add tenant binding, tools, structured logs, model validation, and real fallback.

### C — reimplement

- `main.py` and `db/database.py`: no runtime `create_all`, no hidden schema upgrades; use SQLAlchemy async engine, Alembic, explicit readiness checks, and Supabase-compatible pooling.
- `db/models.py`: preserve business entities/field intent, but create migration-owned SQLAlchemy models and add voice/session/embedding/audit tables.
- `pipeline/embedding_pipeline.py`: use Vertex AI service-account credentials and an explicitly versioned embedding model/dimension; content hashes and jobs prevent duplicate embedding work.
- `pipeline/retrieval_pipeline.py`: service-owned, tenant-filtered hybrid retrieval (exact/alias first, vector only when needed) with ranking and result compression.
- `pipeline/llm_pipeline*.py`, `prompt_pipeline.py`, `api/rag.py`: remove request-level “embed every query then send generic RAG prompt” orchestration; LiveKit tool calls now decide retrieval.

### D — do not use

- `/voice/ws/stream`, `/doctor-prescriptions/voice/ws/stream`, and their JSON token-stream protocols.
- Flutter’s orchestration based on `speech_to_text`, `flutter_tts`, client silence timers, and queued local TTS.
- Legacy Mistral-primary/Gemini-fallback `LLMPipeline` and unconditional `/rag/*` query path.
- Reference runtime migration helpers, `run_migration.py`, direct secret-bearing logs, and any reference `.env`/virtual-environment contents.

## 4. Target package tree

```text
backend_app/
  pyproject.toml
  alembic.ini
  app/
    main.py                    # FastAPI composition only
    config/settings.py          # typed, secret-safe environment config
    core/                       # auth, logging, errors, categories, rate limits
    api/v1/                     # compatibility routes plus realtime token route
    db/                         # async engine, ORM entities, migration metadata
    repositories/               # tenant-scoped data access
    domain/                     # business services and request/response models
    retrieval/                  # embedding queue, hybrid search, compression
    agent/                      # runner, provider factories, tools, session state
    workers/                    # embedding/outbox worker entry point
  migrations/versions/          # Alembic revisions only
  tests/                        # unit, API, repository, agent/tool, integration tests
```

## 5. Database and retrieval design

### Existing domain tables retained

`users`, `otps`, `items`, `bills`, `sale_items`, `customers`, `gst_configurations`, `gst_invoice_sequences`, `gst_invoices`, `doctor_patients`, and `doctor_prescriptions` are retained conceptually and receive explicit migrations. Existing category-scoping, GST, and doctor isolation semantics are preserved.

### New tables

- `voice_sessions`: server-created room/participant binding, owner/category snapshot, lifecycle timestamps, selected provider, no raw audio.
- `voice_turns`: optional/retention-limited redacted transcript and tool outcome metadata; no microphone audio.
- `workflow_drafts`: optimistic-versioned bill/GST/prescription draft state with expiry and explicit confirmation status.
- `embedding_jobs`: transactional outbox for create/update/delete/reindex tasks, retries, failure reason category, and content hash.
- `agent_memory`: opt-in summarized durable facts only; never use raw transcript as unbounded prompt history.
- `audit_events` and `idempotency_keys`: state-changing action records and duplicate-submission protection.

### pgvector

- Enable the `vector` extension through the first Alembic migration.
- Lock `VERTEX_EMBEDDING_MODEL` and its tested dimension before creating vector columns. The reference uses `text-embedding-004` at 768 dimensions; the new migration will reject a model/dimension mismatch rather than silently mixing vectors.
- Embed item aliases/category/unit and customer search material on writes or backfill jobs, not every conversation.
- Use normalized exact/alias/phone lookup first. `search_inventory` generates a query embedding only if semantic search is needed.
- Use cosine distance and an HNSW cosine index after measuring corpus size/recall; keep owner/category filters inside SQL/RPC. Supabase recommends HNSW for read-heavy low-latency workloads.

## 6. Agent tools to implement

Read-only tools ship first:

- `get_shop_profile`
- `search_inventory` and `get_stock_availability`
- `find_customer`, `get_customer_purchase_summary`, `search_bills`
- `get_sales_summary`
- `get_gst_configuration`

Controlled draft tools ship next:

- `create_or_update_bill_draft`, `remove_bill_draft_line`, `preview_bill_draft`
- `parse_inventory_changes` (returns an editable proposal; it never writes inventory autonomously)
- `draft_gst_invoice`
- `format_prescription_dictation` (doctor-category rooms only; formats a doctor’s dictation and does not prescribe treatment)

State-changing tools require confirmation, server-side validation, idempotency, and audit records:

- `confirm_bill_draft` / `finalize_gst_invoice`
- `save_inventory_changes`
- `save_printed_prescription`

There is no `order` tool in the first release because the current product contains bills, not an order-fulfilment schema. Add orders only after product requirements define lifecycle, payment, and fulfilment rules.

## 7. Provider and secret policy

| Capability | Target | Credential |
| --- | --- | --- |
| Realtime media/session | LiveKit | `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET` |
| STT | Google Cloud STT via LiveKit Google plugin | mounted `GOOGLE_APPLICATION_CREDENTIALS` JSON / workload identity |
| Primary LLM and embeddings | Gemini / Vertex AI | same GCP identity with least-privilege Vertex role |
| LLM fallback | Mistral plugin/client | `MISTRAL_API_KEY` |
| TTS | Cartesia | `CARTESIA_API_KEY` |
| Data | Supabase PostgreSQL + pgvector | runtime `DATABASE_URL`; migration role/connection; optional server-only `SUPABASE_SERVICE_ROLE_KEY` only where the REST/Storage API is needed |

The new Supabase URL/key alone is insufficient for transactional migrations and efficient vector SQL. Before database implementation, obtain a migration-capable `DATABASE_URL` (direct or transaction-pooler as appropriate) in addition to the new Supabase values. No secret, Supabase key, or service-account JSON is committed or sent to Flutter.

Gemini is called first. A Mistral call is made only after a classified transient Gemini failure/timeout and never in parallel. Tool input/output schemas and the recent bounded context are preserved for the retry; business authorization is rechecked by the tool/domain layer.

## 8. Implementation phases and acceptance criteria

- [x] Audit all three codebases and official provider documentation.
- [ ] Create clean backend package, typed settings, structured logging, `/health/live`, `/health/ready`, and Alembic foundation.
- [ ] Port compatibility-safe HTTP domain endpoints with contract tests.
- [ ] Create Supabase migrations, RLS/role strategy, pgvector functions/indexes, and a no-secret local environment template.
- [ ] Implement asynchronous repositories, embedding outbox worker, hybrid retrieval, and reindex command.
- [ ] Implement authenticated LiveKit token issuance, room/session binding, agent runner, provider validation, agent state events, and interruption tests.
- [ ] Implement tools in read-only → draft → confirmed-write order.
- [ ] Add targeted Flutter LiveKit client controller; retain the current visual screens, billing provider, GST preview, printer flow, and category navigation.
- [ ] Remove legacy voice WebSocket and device STT/TTS dependencies only after the matching LiveKit paths pass device tests.
- [ ] Execute unit, API, database, agent/tool, provider smoke, Flutter, and end-to-end test matrices; record real latency measurements.

## 9. Required decisions/credentials before live integration tests

Implementation can proceed with mocks and local tests first. Live verification needs:

1. New Supabase project URL, a migration-capable PostgreSQL `DATABASE_URL`, and (if used) a server-only service-role key.
2. LiveKit project URL/key/secret and the chosen agent deployment target.
3. Google service-account JSON mounted as a file, project ID/location, enabled Vertex AI and Speech-to-Text APIs, and the selected tested Gemini/embedding model IDs.
4. Cartesia API key and approved voice ID; Mistral API key and selected fallback model.
5. Confirmation of OTP/SMS provider production credentials and retention/consent policy for text transcripts and doctor data.

## 10. Verification targets

The implementation will test multilingual conversation, interruptions, no-tool greetings, semantic inventory lookup, ambiguous customers/items, category/tenant isolation, bill/GST confirmation, doctor dictation privacy, provider outages, Supabase outages, retry/idempotency, and performance telemetry. Claims of provider integration or latency will be made only after those credentials are supplied and tests are run.
