# Vyamit backend

This is the replacement backend for the Flutter application in `../frontend_app`.
It is deliberately split into two independently deployable processes that share
the same package and Supabase PostgreSQL database:

- **API:** FastAPI authentication, inventory, GST, bills/analytics, doctor
  records, compatibility endpoints, health checks, and short-lived LiveKit
  token minting.
- **Agent:** LiveKit `AgentServer` running Google STT, Gemini on Vertex AI,
  Mistral fallback, Cartesia TTS, and tenant-scoped read tools.

## Security invariants

- Flutter receives only an application JWT and a short-lived LiveKit participant
  token. It never receives database, LiveKit API, Google, Mistral, Cartesia, or
  SMS credentials.
- The API creates every LiveKit room and participant identity. The agent checks
  the pair against `voice_sessions` before making data tools available.
- Repository calls receive server-resolved `TenantContext`; they filter both
  owner and active shop category. An LLM cannot select a tenant.
- OTP values are Argon2-hashed, expire after five minutes, allow five stored
  verification attempts, and must be accepted by Fast2SMS before the API reports
  delivery. Set `OTP_DEMO_MODE=true` only in a non-production environment.
- Mutating bills, GST invoices, and printed prescriptions require an
  `Idempotency-Key`. The API records duplicate responses transactionally.
- Embeddings are generated for inventory and for names the owner explicitly
  adds to the verified-customer list. Customer phone numbers are never embedded.

## Local setup

1. Copy `.env.example` to `.env`; use values from your secret manager, never
   commit it. `GOOGLE_APPLICATION_CREDENTIALS` must point to a mounted service
   account JSON file.
2. Install dependencies with `python -m pip install -e .`.
3. Apply the schema through Alembic, never `create_all` from application startup:

   ```powershell
   alembic upgrade head
   ```

   On an IPv4-only machine, use the exact Supavisor **session-pooler** URL
   shown by Supabase Dashboard → Connect. The direct `db.<project>.supabase.co`
   endpoint requires IPv6 unless the project has the IPv4 add-on.

4. Start the API:

   ```powershell
   python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
   ```

5. In another process, start the LiveKit worker after all provider credentials
   are configured:

   ```powershell
   python -m app.agent.runner dev
   ```

6. Start the embedding worker only after Vertex credentials and the vector
   migration are available:

   ```powershell
   python -m app.workers.embeddings
   ```

   To queue a controlled embedding backfill, run the server-only command and
   then keep the worker running. `--force` is only for an approved model change:

   ```powershell
   python -m app.workers.reindex --owner-id 123
   ```

## Verification

Run unit and contract tests locally:

```powershell
python -m pytest -q
```

The checked-in tests require no cloud credentials. Provider and end-to-end tests
must use a separate Supabase project and non-production LiveKit/GCP credentials.
See `../IMPLEMENTATION_PLAN.md` for the current status and outstanding live
integration acceptance criteria.
