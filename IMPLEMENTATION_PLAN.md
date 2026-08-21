# Vyamit — implementation plan and architecture record

**Status:** active. This is the single living planning artifact for the new backend. Update its checkboxes and decisions as implementation progresses.

## Current implementation snapshot (2026-08-20)

The new `backend_app/` contains a migration-owned async FastAPI foundation,
tenant/category-scoped inventory, bills, GST and doctor records, hashed/rate-
limited OTPs, an explicit Fast2SMS delivery adapter, transactional embedding
outbox, and a LiveKit agent/token flow that validates both room and participant
identity. The Flutter project now has a secure token store and a dedicated
`LiveKitVoiceService` transport layer. Retail billing, inventory proposals,
and doctor dictation now use focused LiveKit screens that preserve the existing
navigation and confirmation flows. The legacy device STT/TTS/WebSocket screens
and Flutter packages have been removed; physical-device/provider checks remain.

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
- `voice_turns`: optional future, retention-limited redacted transcript and tool
  outcome metadata; no microphone audio. It is intentionally not created until
  the consent and retention policy is approved.
- `workflow_drafts`: optimistic-versioned bill/GST/prescription draft state with expiry and explicit confirmation status.
- `embedding_jobs`: transactional outbox for create/update/delete/reindex tasks, retries, failure reason category, and content hash.
- `agent_memory`: opt-in summarized durable facts only; never use raw transcript as unbounded prompt history.
- `audit_events` and `idempotency_keys`: state-changing action records and duplicate-submission protection.

### pgvector

- Enable the `vector` extension through the first Alembic migration.
- Lock `VERTEX_EMBEDDING_MODEL` and its tested dimension before creating vector columns. The reference uses `text-embedding-004` at 768 dimensions; the new migration will reject a model/dimension mismatch rather than silently mixing vectors.
- Embed item aliases/category/unit on writes or backfill jobs, not every
  conversation. Customer lookup remains deterministic; customer embedding
  columns are deliberately absent until a separate privacy/consent model is
  approved.
- Use normalized exact/alias/phone lookup first. `search_inventory` generates a query embedding only if semantic search is needed.
- Use cosine distance and an HNSW cosine index after measuring corpus size/recall; keep owner/category filters inside SQL/RPC. Supabase recommends HNSW for read-heavy low-latency workloads.

## 6. Agent tools to implement

Read-only tools ship first:

- `get_shop_profile`
- `search_inventory` and catalog availability lookup. The current inventory model has no stock-quantity field, so the agent must not claim numerical stock until a separately approved stock-ledger feature is added.
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
- [x] Create clean backend package, typed settings, structured logging, `/health/live`, `/health/ready`, and Alembic foundation.
- [x] Port compatibility-safe HTTP domain endpoints and deterministic unit/contract tests.
- [x] Create Supabase-compatible migrations, API-only role strategy, pgvector schema, and a no-secret local environment template. Applying them to the new Supabase project remains credential-gated.
- [x] Implement asynchronous repositories, embedding outbox worker, hybrid retrieval, and a controlled reindex command.
- [x] Implement authenticated LiveKit token issuance, room/participant binding, agent runner, provider validation, and agent state events. Provider/device and interruption tests still require credentials.
- [x] Implement read-only agent tools.
- [x] Implement bill and inventory draft tools, explicit bill UI confirmation, optimistic draft versions, idempotency, and transactional bill confirmation. GST and prescription saving continue through their existing explicit UI routes.
- [x] Integrate the targeted Flutter LiveKit client controller into retail billing, inventory, and doctor dictation while retaining category navigation and the existing bill/printer path.
- [x] Remove legacy voice WebSocket and device STT/TTS dependencies after replacing every active voice route. Device testing remains required before release.
- [ ] Execute unit, API, database, agent/tool, provider smoke, Flutter, and end-to-end test matrices; record real latency measurements.

## 9. Required decisions/credentials before live integration tests

Implementation can proceed with mocks and local tests first. Live verification needs:

1. New Supabase project URL, a migration-capable PostgreSQL `DATABASE_URL`, and (if used) a server-only service-role key.
   The configured direct endpoint was verified to be IPv6-only from this
   Windows workspace. Provide the exact **Supavisor session-pooler** connection
   string from **Supabase Dashboard → Connect** for IPv4 runtime/testing, or
   enable the project's IPv4 add-on. Do not guess the AWS region/hostname.
2. LiveKit project URL/key/secret and the chosen agent deployment target.
3. Google service-account JSON mounted as a file, project ID/location, enabled Vertex AI and Speech-to-Text APIs, and the selected tested Gemini/embedding model IDs.
4. Cartesia API key and approved voice ID; Mistral API key and selected fallback model.
5. Confirmation of OTP/SMS provider production credentials and retention/consent policy for text transcripts and doctor data.

## 10. Verification targets

The implementation will test multilingual conversation, interruptions, no-tool greetings, semantic inventory lookup, ambiguous customers/items, category/tenant isolation, bill/GST confirmation, doctor dictation privacy, provider outages, Supabase outages, retry/idempotency, and performance telemetry. Claims of provider integration or latency will be made only after those credentials are supplied and tests are run.

### Verified locally (2026-08-21)

- Backend deterministic suite: **25 passed, 2 skipped**. The skipped tests are
  intentionally opt-in live Supabase checks; they do not silently pass when a
  database is unreachable.
- Added test coverage for Supabase URL normalization, TLS reachability,
  pgvector extension/vector dimension/HNSW index, migration head, browser-role
  table access, customer category uniqueness, parser safety, JWTs, GST,
  category aliases, and LiveKit library contracts.
- Flutter package resolution completed and refreshed the lockfile and desktop
  plugin registrants. A focused Flutter category regression test was added.
  Its runner can load the test, but final analyzer/test execution is blocked in
  this session by tool-state permission, not a source-code failure.
- FastAPI runtime smoke test: the application started on localhost and
  `/health/live` returned HTTP 200.

### Remaining external release gates

1. Replace the direct IPv6 database URL with the exact Supavisor session-pooler
   URL from the Supabase dashboard when running from this IPv4-only workspace.
2. Run `alembic upgrade head`, then opt into the live Supabase tests.
3. Supply and smoke-test LiveKit, Google/Vertex, Cartesia, Mistral, and Fast2SMS
   credentials on a non-production environment.
