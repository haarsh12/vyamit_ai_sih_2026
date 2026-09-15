# Data Flow and Pipelines Documentation

## Overview
This document provides a comprehensive overview of all data pipelines and flows in the Vyamit application - a multi-tenant shop billing and voice assistant system.

---

## Table of Contents
1. [Authentication Pipeline](#1-authentication-pipeline)
2. [Voice Session Pipeline](#2-voice-session-pipeline)
3. [Inventory Management Pipeline](#3-inventory-management-pipeline)
4. [Billing Pipeline](#4-billing-pipeline)
5. [Customer Management Pipeline](#5-customer-management-pipeline)
6. [Analytics Pipeline](#6-analytics-pipeline)
7. [Background Workers Pipeline](#7-background-workers-pipeline)
8. [Search and Retrieval Pipeline](#8-search-and-retrieval-pipeline)
9. [GST Calculation Pipeline](#9-gst-calculation-pipeline)
10. [Workflow Draft Pipeline](#10-workflow-draft-pipeline)

---

## 1. Authentication Pipeline

### Flow: OTP-based Registration/Login

```
Mobile App
    ↓
[POST /api/v1/auth/send-otp]
    ↓
Rate Limiter (3 requests/5 min)
    ↓
Check User Exists?
    ↓
Generate OTP Code
    ↓
Store in Database
    ↓
SMS Service Integration (External)
    ↓
User Receives OTP
    ↓
[POST /api/v1/auth/verify-otp]
    ↓
Rate Limiter (8 requests/5 min)
    ↓
Validate OTP from Database
    ↓
Create/Fetch User Record
    ↓
Generate JWT Access Token
    ↓
Return Token + User Profile
```

### Data Models Involved:
- **User**: Stores phone_number, shop_name, owner_name, address, shop_category
- **OTP**: Temporary verification codes with expiration

### Key Components:
- `app/api/v1/auth.py` - REST endpoints
- `app/domain/otp.py` - OTP generation/verification logic
- `app/integrations/sms.py` - External SMS delivery
- `app/core/security.py` - JWT token creation
- `app/core/rate_limit.py` - Rate limiting

---

## 2. Voice Session Pipeline

### Flow: Real-time Voice Assistant Connection

```
Mobile App (Voice Button Pressed)
    ↓
[POST /api/v1/voice/token]
    ↓
Authenticate User (JWT)
    ↓
Resolve Tenant Context
    ↓
Create VoiceSession Record
    ↓
Generate LiveKit Token
    ↓
Return Connection Details
    ↓
Mobile Connects to LiveKit
    ↓
Agent Server Receives Connection
    ↓
Verify Participant Identity
    ↓
Initialize STT, LLM, TTS Providers (Parallel)
    ↓
Start Agent Session
    ↓
Publish "ready" Event to UI
    ↓
[CONVERSATION LOOP]
    ↓
User Speech → STT (Speech-to-Text)
    ↓
Transcript → LLM (Language Model)
    ↓
LLM Decision: Text Response or Tool Call
    ↓
Tool Execution (if needed)
    ↓
LLM Response → TTS (Text-to-Speech)
    ↓
Audio → Mobile App
    ↓
UI State Updates (listening/thinking/speaking)
    ↓
[LOOP CONTINUES]
    ↓
Session End → Close Database Session
```

### Data Models Involved:
- **VoiceSession**: room_name, participant_identity, expires_at
- **TenantContext**: owner_id, session_id, shop_category

### Key Components:
- `app/api/v1/voice.py` - Token issuance endpoint
- `app/domain/voice_sessions.py` - Session management service
- `app/agent/runner.py` - LiveKit agent server
- `app/agent/tools.py` - Agent tool functions
- `app/agent/providers.py` - STT/LLM/TTS provider creation
- `app/agent/instructions.py` - System prompts

### Performance Tracking:
- Session initialization timing
- Stage-by-stage latency measurement
- STT → LLM → TTS timing
- Tool execution duration

---

## 3. Inventory Management Pipeline

### Flow: CRUD Operations on Shop Inventory

```
Mobile App
    ↓
[GET /api/v1/items] - List Items
    ↓
Authenticate User
    ↓
Get Tenant Context
    ↓
Query Items by owner_id + shop_category
    ↓
Return Item List
```

```
Mobile App
    ↓
[POST /api/v1/items] - Create Item
    ↓
Validate Payload (ItemCreate schema)
    ↓
Create Item Record
    ↓
Trigger Embedding Job (Async)
    ↓
Return Item Response
```

```
Mobile App
    ↓
[PUT /api/v1/items/{item_id}] - Update Item
    ↓
Fetch Existing Item
    ↓
Update Fields
    ↓
Trigger Embedding Job (if name/category changed)
    ↓
Return Updated Item
```

```
Mobile App
    ↓
[DELETE /api/v1/items/{item_id}] - Delete Item
    ↓
Soft Delete (is_active = False)
    ↓
Trigger Embedding Job (delete operation)
    ↓
Return 204 No Content
```

### Data Models Involved:
- **Item**: master_id, names[], category, price, unit, embedding, owner_id
- **EmbeddingJob**: entity_type, entity_id, operation, status

### Key Components:
- `app/api/v1/items.py` - REST endpoints
- `app/domain/inventory.py` - Business logic
- `app/repositories/inventory.py` - Data access
- `app/schemas/inventory.py` - Request/response schemas

---

## 4. Billing Pipeline

### Flow: Bill Creation and Storage

```
Mobile App (Bill Confirmation)
    ↓
[POST /api/v1/analytics/bills]
    ↓
Require Idempotency-Key Header
    ↓
Check Duplicate by Idempotency Key
    ↓
Validate Bill Items
    ↓
Calculate GST (if applicable)
    ↓
Create Bill Record
    ↓
Update Customer Stats (if customer_phone provided)
    ↓
Commit Transaction
    ↓
Return Bill Summary
```

### Alternative Flow: Draft-to-Bill Workflow

```
Voice Agent Tool Call
    ↓
[create_bill_draft]
    ↓
Create BillDraft in "pending" state
    ↓
Generate Customer Verification Suggestion
    ↓
Publish to Mobile UI
    ↓
User Reviews in "Live Bill Box"
    ↓
[POST /api/v1/workflows/bill-drafts/{draft_id}/confirm]
    ↓
Validate Draft State
    ↓
Check Expected Version (Optimistic Locking)
    ↓
Convert Draft to Permanent Bill
    ↓
Link to Verified Customer (if provided)
    ↓
Update Draft Status to "confirmed"
    ↓
Return Bill ID and Confirmation
```

### Data Models Involved:
- **Bill**: items[], total_amount, customer_phone, customer_name, payment_method, bill_date, idempotency_key
- **BillDraft**: state (pending/confirmed/cancelled), version, expires_at
- **Customer**: Aggregated stats (total_bills, last_purchase_date)

### Key Components:
- `app/api/v1/analytics.py` - Bill creation endpoint
- `app/api/v1/workflows.py` - Draft workflow endpoints
- `app/domain/analytics.py` - Bill business logic
- `app/domain/workflows.py` - Draft management
- `app/domain/billing_source.py` - Source detection (voice/manual/typed)

---

## 5. Customer Management Pipeline

### Flow: Customer Verification and Tracking

```
Automatic Customer Tracking (Anonymous)
    ↓
Bill Created with customer_phone
    ↓
Upsert Customer Record
    ↓
Increment total_bills
    ↓
Update last_purchase_date
```

```
Customer Verification Flow
    ↓
[POST /api/v1/customers/verify]
    ↓
Check for Existing Verified Customer
    ↓
Merge or Create New VerifiedCustomer
    ↓
Link Bill to Verified Customer
    ↓
Trigger Embedding Job (name embedding)
    ↓
Return Verified Customer ID
```

```
Customer Search Flow
    ↓
[GET /api/v1/customers/verification-suggestion]
    ↓
Query Recent Bills by Name
    ↓
Check Existing Verified Customers
    ↓
Generate Merge Suggestions
    ↓
Return Suggestion or null
```

```
Customer Bill History
    ↓
[GET /api/v1/customers/{customer_id}/bills]
    ↓
Fetch Verified Customer
    ↓
Query Associated Bills
    ↓
Return Bill History with Items
```

### Data Models Involved:
- **Customer**: Anonymous customer stats tracked by phone
- **VerifiedCustomer**: Explicitly verified with name, name_embedding
- **Bill**: Links to customer via customer_phone or verified_customer_id
- **EmbeddingJob**: For customer name embeddings

### Key Components:
- `app/api/v1/customers.py` - Customer endpoints
- `app/domain/customers.py` - Customer service logic
- `app/repositories/verified_customers.py` - Data access
- `app/schemas/customers.py` - Request/response schemas

---

## 6. Analytics Pipeline

### Flow: Dashboard and Reporting

```
Mobile App Dashboard
    ↓
[GET /api/v1/analytics/dashboard?days=30]
    ↓
Calculate Date Range
    ↓
Query Bills in Range
    ↓
Aggregate:
    - Total Revenue
    - Bill Count
    - Average Bill Value
    - Top Items
    - Payment Method Distribution
    ↓
Return Dashboard Metrics
```

```
Mobile App Overview
    ↓
[GET /api/v1/analytics/overview?days=7]
    ↓
Query Recent Bills
    ↓
Calculate:
    - Daily Revenue Trend
    - Total Sales
    - Growth Percentage
    ↓
Return Overview Data
```

```
Bill History
    ↓
[GET /api/v1/analytics/bills?limit=50&offset=0]
    ↓
Query Bills with Pagination
    ↓
Order by bill_date DESC
    ↓
Return Bill List
```

### Data Models Involved:
- **Bill**: Source for all analytics
- **Analytics aggregations**: Computed on-the-fly

### Key Components:
- `app/api/v1/analytics.py` - Analytics endpoints
- `app/domain/analytics.py` - Aggregation logic
- `app/repositories/analytics.py` - Optimized queries

---

## 7. Background Workers Pipeline

### Flow: Asynchronous Embedding Generation

```
[Trigger] Item Created/Updated or Customer Verified
    ↓
Insert EmbeddingJob Record
    - entity_type: "item" or "verified_customer"
    - entity_id: ID
    - operation: "upsert" or "delete"
    - status: "pending"
    ↓
[Embedding Worker Process - Separate Container]
    ↓
Poll Database for Pending Jobs
    ↓
Lock Job with FOR UPDATE SKIP LOCKED
    ↓
Update status: "processing"
    ↓
Fetch Entity (Item or VerifiedCustomer)
    ↓
Generate Embedding Text
    - Item: Join names + category + unit
    - Customer: Customer name
    ↓
Call Vertex AI Embedding API
    ↓
Store Vector in Entity
    - Item.embedding
    - VerifiedCustomer.name_embedding
    ↓
Update Metadata:
    - embedding_source_hash
    - embedding_model
    - embedding_updated_at
    ↓
Update Job status: "completed"
    ↓
Commit Transaction
    ↓
[Loop continues - sleep 0.25s if processed, 2s if idle]
```

### Retry Logic:
- Exponential backoff on failures
- Max 5 attempts
- Failed jobs marked "failed" after exhaustion

### Data Models Involved:
- **EmbeddingJob**: Outbox pattern for async processing
- **Item**: embedding field (vector)
- **VerifiedCustomer**: name_embedding field (vector)

### Key Components:
- `app/workers/embeddings.py` - Worker implementation
- `app/retrieval/embeddings.py` - Embedding service
- `app/retrieval/vertex.py` - Vertex AI integration

---

## 8. Search and Retrieval Pipeline

### Flow: Hybrid Search (Exact + Fuzzy + Semantic)

#### Inventory Search

```
Voice Agent or API Call
    ↓
[search_inventory tool or search endpoint]
    ↓
Clean and Normalize Query
    ↓
[Step 1] Exact Match Search
    - Lowercase comparison on item names
    - Alias matching
    ↓
[Step 2] Fuzzy Match (if needed)
    - Trigram similarity (pg_trgm)
    - Levenshtein distance
    ↓
[Step 3] Semantic Search (if available)
    - Generate query embedding
    - Vector similarity search (pgvector)
    - Cosine distance threshold
    ↓
Merge and Deduplicate Results
    ↓
Score and Rank
    ↓
Return Top Matches (limit 10)
```

#### Customer Search

```
Voice Agent or API Call
    ↓
[search_verified_customers tool]
    ↓
Clean Query
    ↓
[Step 1] Exact Name Match
    - Case-insensitive ILIKE
    ↓
[Step 2] Fuzzy Name Match
    - Trigram similarity
    ↓
[Step 3] Semantic Embedding Search
    - Generate query embedding
    - Vector cosine similarity
    ↓
[Step 4] Phone Number Match (if query looks like phone)
    ↓
Merge Results by Priority:
    1. Exact matches
    2. High fuzzy score (>0.6)
    3. Semantic matches (>0.7)
    4. Phone matches
    ↓
Deduplicate and Sort
    ↓
Return Top 5 Matches
```

### Data Models Involved:
- **Item**: names[], embedding, pg_trgm indexes
- **VerifiedCustomer**: name, name_embedding, phone_number
- Vector similarity functions (pgvector extension)

### Key Components:
- `app/retrieval/inventory.py` - Inventory search service
- `app/retrieval/customers.py` - Customer search service
- `app/retrieval/embeddings.py` - Embedding generation
- `app/retrieval/vertex.py` - Google Vertex AI integration

---

## 9. GST Calculation Pipeline

### Flow: Tax Calculation for Bills

```
Bill Creation Request
    ↓
Check Shop GST Configuration
    ↓
[IF GST Registered]
    ↓
For Each Bill Item:
    ↓
    Determine HSN Code (if available)
    ↓
    Apply GST Rate by Category:
        - Essential Foods: 5%
        - Processed Foods: 12%
        - Standard Goods: 18%
        - Luxury Items: 28%
    ↓
    Calculate CGST (Central GST)
    ↓
    Calculate SGST (State GST)
    ↓
    Calculate Total with Tax
    ↓
Aggregate Total GST
    ↓
Generate GST Breakup
    ↓
Return Bill with Tax Details
```

```
GST Configuration Endpoint
    ↓
[GET /api/v1/gst/configuration]
    ↓
Fetch Shop GST Settings
    ↓
Return:
    - is_gst_registered
    - gstin_number
    - gst_rates by category
    - default_rate
```

### Data Models Involved:
- **User**: gstin_number, is_gst_registered
- **GSTConfiguration**: Rate mappings
- **Bill**: GST breakup in items

### Key Components:
- `app/gst/calculation.py` - GST computation logic
- `app/gst/constants.py` - Tax rate definitions
- `app/gst/validation.py` - GSTIN validation
- `app/domain/gst.py` - GST service
- `app/api/v1/gst.py` - Configuration endpoints

---

## 10. Workflow Draft Pipeline

### Flow: Asynchronous Draft Review System

#### Bill Draft Lifecycle

```
Voice Agent Creates Draft
    ↓
[POST /api/v1/workflows/bill-drafts]
    ↓
Create BillDraft:
    - state: {"items": [...], "total_amount": ...}
    - status: "pending"
    - version: 1
    - expires_at: now + 15 minutes
    ↓
Generate Customer Verification Suggestion
    - Check if customer_name matches existing verified customer
    - Return merge suggestion if found
    ↓
Publish to Mobile UI via LiveKit Data Channel
    ↓
[User Reviews in App]
    ↓
User Edits Items
    ↓
[PUT /api/v1/workflows/bill-drafts/{draft_id}]
    ↓
Optimistic Locking Check (expected_version)
    ↓
Update Draft State
    ↓
Increment version
    ↓
Return Updated Draft
    ↓
[User Confirms]
    ↓
[POST /api/v1/workflows/bill-drafts/{draft_id}/confirm]
    ↓
Validate Draft:
    - Check version match
    - Ensure not expired
    - Verify status is "pending"
    ↓
Create Permanent Bill Record
    ↓
Link to Verified Customer (if selected)
    ↓
Update Draft status: "confirmed"
    ↓
Return Bill ID
```

#### Prescription Draft (Doctor Mode)

```
Voice Agent Formats Prescription
    ↓
[format_prescription_dictation tool]
    ↓
Parse Dictation Text
    ↓
Extract:
    - Patient name
    - Medications
    - Dosages
    - Instructions
    ↓
Format into Structured Prescription
    ↓
Publish to Mobile UI
    ↓
[User Reviews and Prints]
```

#### Inventory Draft

```
Voice Agent Parses Inventory Changes
    ↓
[parse_inventory_changes tool]
    ↓
Parse Dictation
    ↓
Extract:
    - Item additions
    - Price updates
    - Category changes
    ↓
Match Against Existing Catalog
    ↓
Generate Change Proposal
    ↓
Publish to Mobile UI
    ↓
[User Reviews and Confirms in App]
```

### Data Models Involved:
- **BillDraft**: Full bill state, version tracking
- **Draft expiration**: 15-minute TTL
- **Optimistic locking**: version field

### Key Components:
- `app/api/v1/workflows.py` - Draft endpoints
- `app/domain/workflows.py` - Draft orchestration
- `app/domain/doctor_prescriptions.py` - Prescription formatting
- `app/domain/voice_inventory.py` - Inventory parsing

---

## Cross-Cutting Concerns

### Multi-Tenancy

All data is isolated by:
- **owner_id**: User/shop identifier
- **shop_category**: Business type ("Grocery", "Doctor Prescription", etc.)

Every query includes these filters to ensure data isolation.

### Tenant Context Resolution

```
JWT Token → User ID
    ↓
Fetch User Record
    ↓
Extract:
    - owner_id
    - shop_category
    ↓
Create TenantContext
    ↓
Pass to All Services/Repositories
```

### Idempotency

Bill creation requires `Idempotency-Key` header:
- Prevents duplicate bill creation
- Safe to retry on network failures
- Stored in database for deduplication

### Rate Limiting

Sliding window rate limiters protect:
- OTP generation (3 requests / 5 minutes)
- OTP verification (8 requests / 5 minutes)

### Database Sessions

- **Web API**: Per-request session from `get_db_session()`
- **Voice Agent**: Separate session pool from `get_agent_db_session()`
- **Workers**: Independent session factory

### Logging and Observability

All pipelines include:
- Structured logging with context fields
- Performance timing measurements
- Error tracking with exc_info
- Request correlation via X-Request-Id header

---

## Technology Stack

### Backend Framework
- **FastAPI**: REST API framework
- **SQLAlchemy**: ORM and database access
- **Alembic**: Database migrations
- **Pydantic**: Schema validation

### Database
- **PostgreSQL**: Primary data store
- **pgvector**: Vector similarity search
- **pg_trgm**: Fuzzy text search

### Real-time Voice
- **LiveKit**: WebRTC infrastructure
- **LiveKit Agents SDK**: Voice agent framework
- **STT Providers**: Deepgram, Google Speech-to-Text
- **LLM Providers**: OpenAI GPT-4, Google Gemini, Groq
- **TTS Providers**: ElevenLabs, Google Text-to-Speech
- **AI Coustics**: Noise cancellation

### External Services
- **Google Vertex AI**: Text embeddings
- **SMS Gateway**: OTP delivery
- **Google Cloud**: Hosting and services

### Mobile
- **Flutter**: Cross-platform mobile app
- **LiveKit Flutter SDK**: Real-time voice
- **HTTP Client**: REST API communication

---

## Deployment Architecture

```
Mobile App (Flutter)
    ↓
    ↓ [HTTPS/WSS]
    ↓
Load Balancer
    ↓
    ├─→ FastAPI Backend (Multiple Instances)
    │       - REST API Endpoints
    │       - JWT Authentication
    │       - Database Sessions
    │
    ├─→ LiveKit Server
    │       - WebRTC Media
    │       - Room Management
    │       - Data Channels
    │
    ├─→ Agent Server (Python Worker)
    │       - Voice Agent Runtime
    │       - STT/LLM/TTS Pipeline
    │       - Tool Execution
    │
    ├─→ Embedding Worker (Python Worker)
    │       - Background Job Processing
    │       - Vector Generation
    │       - Retry Logic
    │
    └─→ PostgreSQL Database
            - User Data
            - Bills
            - Inventory
            - Embeddings
```

---

## Summary

This system implements:
1. **Authentication**: Secure OTP-based login with JWT
2. **Voice AI**: Real-time conversational billing assistant
3. **Inventory**: Multi-modal search with semantic understanding
4. **Billing**: Draft-review-confirm workflow with GST support
5. **Customers**: Verification and history tracking with embeddings
6. **Analytics**: Real-time dashboards and reporting
7. **Background Processing**: Async embedding generation
8. **Multi-tenancy**: Complete data isolation per shop

All pipelines are designed for:
- **Scalability**: Async workers, connection pooling
- **Reliability**: Retry logic, idempotency, optimistic locking
- **Performance**: Parallel processing, caching, indexes
- **Security**: JWT auth, rate limiting, tenant isolation
- **Observability**: Structured logging, performance tracking
