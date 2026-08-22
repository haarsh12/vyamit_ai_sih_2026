# Voice Agent Setup Guide

## Current Status

✅ **Working:**
- Backend API server is running
- LiveKit connection credentials configured
- Backend successfully issues voice tokens (`POST /voice/token → 201 Created`)
- Flutter app can request tokens

❌ **Not Working:**
- LiveKit Agent process is not running
- Voice circle shows "VOICE UNAVAILABLE" in Flutter app

## Why Voice Isn't Working

The Vyamit voice feature requires **TWO separate processes**:

1. **API Server** (`uvicorn app.main:app`) - ✅ Currently Running
   - Handles HTTP requests
   - Issues LiveKit tokens
   - Manages database

2. **LiveKit Agent** (`python -m app.agent.runner dev`) - ❌ Not Running
   - Joins LiveKit rooms
   - Processes voice input (Speech-to-Text)
   - Runs AI/LLM logic
   - Generates voice responses (Text-to-Speech)

**The agent is failing to start due to missing AI provider credentials.**

## Required Configuration

The agent needs these environment variables in `backend_app/.env`:

### Currently Missing:
```env
GOOGLE_APPLICATION_CREDENTIALS=  # Must point to Google Cloud JSON key file
GOOGLE_CLOUD_PROJECT=            # Your GCP project ID
VERTEX_GEMINI_MODEL=             # e.g., gemini-2.0-flash-exp
MISTRAL_MODEL=                   # e.g., mistral-large-latest
```

### Already Configured (no changes needed):
```env
LIVEKIT_URL=wss://vyamit-ai-a8uemv7n.livekit.cloud  ✅
LIVEKIT_API_KEY=APIcEZbBwAmQkVF                     ✅
LIVEKIT_API_SECRET=KfRB2R4fyVfcqbUmDyPZXZSDUNCx...  ✅
CARTESIA_API_KEY=sk_car_gaoeJQiHmRfG5Wphcvdi9H      ✅
MISTRAL_API_KEY=Ayxh9usCRXMNSgXD7fMoWdBI7sgMOrX7   ✅
```

## Step-by-Step Setup

### Step 1: Google Cloud Setup

1. **Go to Google Cloud Console**: https://console.cloud.google.com/

2. **Create or Select a Project**
   - Click project dropdown → "New Project"
   - Name it (e.g., "vyamit-voice")
   - Note the Project ID (you'll need this)

3. **Enable Required APIs**
   - Go to "APIs & Services" → "Enable APIs and Services"
   - Search and enable:
     - ✅ Cloud Speech-to-Text API
     - ✅ Vertex AI API

4. **Create Service Account**
   - Go to "IAM & Admin" → "Service Accounts"
   - Click "Create Service Account"
   - Name: `vyamit-agent`
   - Grant roles:
     - ✅ Vertex AI User
     - ✅ Speech-to-Text Client
   - Click "Create and Continue" → "Done"

5. **Download JSON Key**
   - Click on the service account you just created
   - Go to "Keys" tab
   - Click "Add Key" → "Create new key"
   - Select "JSON" → Click "Create"
   - Save the downloaded file as `backend_app/google-credentials.json`

### Step 2: Update .env File

Edit `backend_app/.env` and update these lines:

```env
# Google Cloud Configuration
GOOGLE_APPLICATION_CREDENTIALS=google-credentials.json
GOOGLE_CLOUD_PROJECT=your-project-id-from-step-2
VERTEX_GEMINI_MODEL=gemini-2.0-flash-exp
MISTRAL_MODEL=mistral-large-latest
```

**Note:** Replace `your-project-id-from-step-2` with the actual Project ID from Google Cloud Console.

### Step 3: Verify Google Credentials

Test if the credentials work:

```powershell
# From backend_app directory
python -c "from google.cloud import aiplatform; print('Google Cloud credentials OK!')"
```

If you see an error, double-check:
- The JSON file exists at the path specified
- The file is valid JSON
- The service account has the correct roles

### Step 4: Start the LiveKit Agent

**Open a NEW terminal/PowerShell window** (keep your API server running in the other one):

```powershell
cd D:\manthan_hack\backend_app
python -m app.agent.runner dev
```

### Step 5: Verify Agent is Running

You should see logs like:
```
{"timestamp": "...", "level": "INFO", "message": "agent_started", ...}
```

If you see errors:
- Check all environment variables are set
- Verify Google credentials file exists
- Ensure all API keys are valid

### Step 6: Test Voice in Flutter

1. Open the Vyamit app
2. Navigate to voice features
3. Tap the microphone circle
4. You should see "CONNECTING" → "LISTENING"
5. Speak into the microphone
6. The agent should transcribe and respond

## Troubleshooting

### Error: "agent_configuration_error"
**Problem:** Missing or invalid environment variables  
**Solution:** Check all required variables in `.env` are set and not empty

### Error: "GOOGLE_APPLICATION_CREDENTIALS must point to a mounted credential file"
**Problem:** JSON key file not found  
**Solution:** 
- Verify the file exists: `ls backend_app/google-credentials.json`
- Use full path if needed: `GOOGLE_APPLICATION_CREDENTIALS=D:/manthan_hack/backend_app/google-credentials.json`

### Error: "Permission denied" or "403 Forbidden" from Google
**Problem:** Service account doesn't have required permissions  
**Solution:** 
- Go back to IAM & Admin → Service Accounts
- Edit the service account
- Add roles: "Vertex AI User" and "Speech-to-Text Client"

### Voice connects but doesn't respond
**Problem:** Agent started but crashed, or model configuration invalid  
**Solution:**
- Check agent logs for errors
- Verify model names are correct (no typos)
- Check Mistral API key is valid

### "Room not found" errors
**Problem:** Agent and API are using different LiveKit configurations  
**Solution:**
- Restart both API and Agent after changing `.env`
- Verify both processes read the same `.env` file

## Architecture Diagram

```
┌─────────────────┐
│  Flutter App    │
│  (Mobile)       │
└────────┬────────┘
         │ 1. Request Token
         ↓
┌─────────────────────┐
│  FastAPI Server     │ ←──── 2. Create Room & Token
│  (uvicorn)          │
└─────────────────────┘
         │ 3. Return Token
         ↓
┌─────────────────────┐
│  LiveKit Cloud      │ ←──── 4. Join Room (Flutter)
│  (WebRTC Rooms)     │
└─────────────────────┘
         │ 5. Join Same Room
         ↓
┌─────────────────────┐
│  LiveKit Agent      │ ←──── 6. Process Voice
│  (agent runner)     │
└─────────┬───────────┘
          │
          ├─→ Google STT (Speech Recognition)
          ├─→ Vertex AI Gemini (Understand & Decide)
          ├─→ Mistral (Fallback LLM)
          └─→ Cartesia TTS (Voice Response)
```

## Quick Reference Commands

### Start API Server
```powershell
cd backend_app
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

### Start Agent (in separate terminal)
```powershell
cd backend_app
python -m app.agent.runner dev
```

### Check Agent Logs
Look for these log messages:
- ✅ `agent_session_started` - Agent connected to room
- ✅ `stt_transcript` - Speech recognized
- ✅ `agent_state` - Agent is processing
- ❌ `agent_configuration_error` - Missing credentials
- ❌ `agent_rejected_*` - Room/participant validation failed

## Cost Considerations

Running the voice agent will incur costs from:
- **Google Cloud**: Speech-to-Text + Vertex AI API calls
- **LiveKit Cloud**: WebRTC room usage (generous free tier)
- **Cartesia**: Text-to-Speech API calls
- **Mistral**: LLM API calls (only when used as fallback)

**Recommendation for testing:**
- Use the free tiers initially
- Monitor usage in each provider's dashboard
- Consider setting up billing alerts

## Need Help?

Check the logs for specific error messages:
- API logs: In the terminal running `uvicorn`
- Agent logs: In the terminal running `app.agent.runner`
- Flutter logs: In the terminal running `flutter run` or in Android Studio

Common error patterns and solutions are documented above in the Troubleshooting section.
