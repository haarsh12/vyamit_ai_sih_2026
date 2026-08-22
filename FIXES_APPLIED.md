# Issues Fixed - August 21, 2026

## Issue 1: Inventory Items Not Showing - Type Casting Error

### Problem
Flutter app showed error: `type 'String' is not a subtype of type 'num?' in type cast`
- Items were added to inventory but not displaying
- Backend was returning HTTP 200 OK with data, but Flutter couldn't parse it

### Root Cause
Pydantic v2 serializes `Decimal` fields as strings by default in JSON responses. The Flutter app expected numeric types (float/num) for `price` and `gst_rate` fields.

### Solution
Added `@field_serializer` decorators to convert `Decimal` to `float` during JSON serialization in:
- `backend_app/app/schemas/inventory.py` - ItemBase class (price, gst_rate)
- `backend_app/app/schemas/gst.py` - GstConfigurationInput (allowed_gst_rates) and GstInvoiceItemInput (quantity, rate, gst_rate)
- `backend_app/app/schemas/analytics.py` - BillItemInput (quantity, price, total) and BillCreate (total_amount)

This ensures all numeric values are returned as JSON numbers instead of strings, matching Flutter's expectations.

## Issue 2: Voice Service Unavailable

### Problem
Frontend showing "VOICE UNAVAILABLE" status when attempting to use voice features.

### Investigation Results
✅ Backend API is working - successfully issues LiveKit tokens (`POST /voice/token 201 Created`)  
✅ LiveKit connection credentials are configured in `.env`  
✅ Flutter app successfully requests tokens  
❌ **LiveKit agent process is not running** - This is the root cause

### Root Cause
The voice feature requires **two separate processes**:
1. **API Server** (uvicorn) - ✅ Running - Issues tokens and handles HTTP requests
2. **LiveKit Agent** (agent runner) - ❌ Not Running - Processes voice, runs LLM, sends responses

The agent failed to start due to missing AI provider credentials:

**Missing Configuration in `.env`:**
```env
GOOGLE_CLOUD_PROJECT=           # Empty - required
VERTEX_GEMINI_MODEL=            # Empty - required
MISTRAL_MODEL=                  # Empty - required
GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/google-service-account.json  # File doesn't exist
```

### Solution Steps

**Step 1: Get Google Cloud Credentials**

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create or select a project
3. Enable these APIs:
   - Cloud Speech-to-Text API
   - Vertex AI API
4. Create a service account:
   - IAM & Admin → Service Accounts → Create Service Account
   - Grant roles: "Vertex AI User" and "Speech-to-Text Client"
5. Create and download JSON key
6. Save the file in `backend_app/` directory (e.g., `google-credentials.json`)

**Step 2: Update `.env` File**

```env
# Update these lines in backend_app/.env:
GOOGLE_APPLICATION_CREDENTIALS=google-credentials.json  # or full path
GOOGLE_CLOUD_PROJECT=your-gcp-project-id  # from Google Cloud Console
VERTEX_GEMINI_MODEL=gemini-2.0-flash-exp  # or gemini-1.5-pro
MISTRAL_MODEL=mistral-large-latest  # or mistral-medium-latest
```

**Step 3: Start the LiveKit Agent**

Open a **new terminal** in the `backend_app` directory and run:

```powershell
python -m app.agent.runner dev
```

Keep this terminal running alongside your API server.

**Step 4: Verify**

Once the agent starts successfully, you should see:
- Agent logs showing it connected to LiveKit
- Flutter voice circle becomes responsive
- Voice transcription and responses work

### Architecture Note

The Vyamit voice system uses this architecture:

```
Flutter App
    ↓ (requests token)
FastAPI Server → LiveKit Cloud ← LiveKit Agent
    ↓               ↓                  ↓
Database      WebRTC Room      AI Services (Google, Mistral, Cartesia)
```

1. Flutter requests a token from FastAPI
2. FastAPI creates a LiveKit room and returns credentials
3. Flutter joins the LiveKit room
4. **The Agent must be running** to join the same room and process voice
5. Agent uses Google STT, Gemini LLM, and Cartesia TTS to respond

## Additional Issues Found

### setState() Called After dispose()
Flutter logs show memory leak warnings in HistoryScreenState:
```
E/flutter: setState() called after dispose(): _HistoryScreenState
```

**Recommendation**: Add `mounted` checks before setState calls in `frontend_app/lib/screens/history_screen.dart`:
```dart
if (mounted) {
  setState(() { ... });
}
```

### Missing Image File
```
PathNotFoundException: Cannot retrieve length of file, path='/data/user/0/com.vyamit.mykirana/cache/.../20260818_085700.jpg'
```

This suggests image cache cleanup issues. Consider implementing proper cache validation before accessing cached images.

## Testing
After applying these fixes:
1. Restart the backend server
2. Clear Flutter app cache/reinstall if needed
3. Test adding inventory items - they should now display correctly
4. Voice features will remain unavailable until LiveKit is properly configured
