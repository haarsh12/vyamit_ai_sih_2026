# Render Deployment Checklist ✅

## Pre-Deployment Preparation

### 📋 Gather Required Credentials

- [ ] **JWT_SECRET_KEY** - Generate with: `python -c "import secrets; print(secrets.token_urlsafe(32))"`
- [ ] **DATABASE_URL** - Supabase connection string (use Pooler URL)
- [ ] **SUPABASE_URL** - Your Supabase project URL
- [ ] **GOOGLE_CREDENTIALS_JSON** - Full JSON content of service account key
- [ ] **GOOGLE_CLOUD_PROJECT** - GCP project ID
- [ ] **VERTEX_GEMINI_MODEL** - Model name (e.g., `gemini-1.5-pro`)
- [ ] **LIVEKIT_URL** - LiveKit server WebSocket URL
- [ ] **LIVEKIT_API_KEY** - LiveKit API key
- [ ] **LIVEKIT_API_SECRET** - LiveKit API secret
- [ ] **CARTESIA_API_KEY** - Cartesia TTS API key
- [ ] **CARTESIA_VOICE_ID** - Voice ID for TTS
- [ ] **MISTRAL_API_KEY** - Mistral AI API key
- [ ] **MISTRAL_MODEL** - Mistral model name
- [ ] **CORS_ORIGINS** - Your frontend URLs (HTTPS in production)

### 📝 Update Configuration

- [ ] Review and update `CORS_ORIGINS` with your actual frontend URLs
- [ ] Confirm `APP_ENV=production` for production deployment
- [ ] Set `OTP_DEMO_MODE=true` if not using SMS (or provide FAST2SMS_API_KEY)
- [ ] Verify all file paths in code are production-ready

### 🔧 Repository Setup

- [ ] Ensure `requirements.txt` exists
- [ ] Ensure `.python-version` exists (specifies Python 3.11)
- [ ] Ensure `start.sh` exists and is committed
- [ ] Ensure `render.yaml` exists (optional, for Blueprint deployment)
- [ ] Commit all changes to Git
- [ ] Push to GitHub/GitLab/Bitbucket

## Deployment Steps

### 🚀 Render Dashboard Setup

- [ ] Sign up/Login to [render.com](https://render.com)
- [ ] Click **"New +"** → **"Web Service"**
- [ ] Connect your GitHub account
- [ ] Select your repository
- [ ] Select branch (usually `main` or `master`)

### ⚙️ Service Configuration

- [ ] **Name**: Set service name (e.g., `vyamit-backend-api`)
- [ ] **Region**: Choose region closest to users
- [ ] **Runtime**: Select **"Python 3"**
- [ ] **Build Command**: `pip install -r requirements.txt`
- [ ] **Start Command**: `bash start.sh`
- [ ] **Instance Type**: Choose plan (Free/Starter/Standard)

### 🔐 Environment Variables

Add these in Render Dashboard → Environment section:

**Application:**
- [ ] `APP_ENV=production`
- [ ] `APP_NAME=Vyamit Backend`
- [ ] `CORS_ORIGINS=<your-frontend-urls>`

**Security:**
- [ ] `JWT_SECRET_KEY=<secret>`
- [ ] `JWT_ACCESS_TOKEN_MINUTES=10080`

**Database:**
- [ ] `DATABASE_URL=<supabase-url>`
- [ ] `SUPABASE_URL=<supabase-url>`

**Google Cloud:**
- [ ] `GOOGLE_CREDENTIALS_JSON=<entire-json-content>`
- [ ] `GOOGLE_APPLICATION_CREDENTIALS=/etc/secrets/google-service-account.json`
- [ ] `GOOGLE_CLOUD_PROJECT=<project-id>`
- [ ] `GOOGLE_CLOUD_LOCATION=global`
- [ ] `VERTEX_GEMINI_MODEL=<model-name>`

**LiveKit:**
- [ ] `LIVEKIT_URL=<livekit-url>`
- [ ] `LIVEKIT_API_KEY=<api-key>`
- [ ] `LIVEKIT_API_SECRET=<api-secret>`

**Voice/TTS:**
- [ ] `CARTESIA_API_KEY=<api-key>`
- [ ] `CARTESIA_VOICE_ID=<voice-id>`
- [ ] `MISTRAL_API_KEY=<api-key>`
- [ ] `MISTRAL_MODEL=<model-name>`

**Optional:**
- [ ] `FAST2SMS_API_KEY=<api-key>` (or set `OTP_DEMO_MODE=true`)
- [ ] `OTP_DEMO_MODE=false` (set to `true` for testing without SMS)

### 🏥 Advanced Settings

- [ ] Set **Health Check Path** to `/health`
- [ ] Review auto-deploy settings (enabled by default)

### 🎬 Deploy

- [ ] Click **"Create Web Service"** or **"Deploy"**
- [ ] Monitor build logs for errors
- [ ] Wait for "Deploy succeeded" message (~5-10 minutes for first deploy)

## Post-Deployment

### ✅ Verification

- [ ] Visit `https://your-app.onrender.com/` - Check for `{"status": "active"}`
- [ ] Visit `https://your-app.onrender.com/health` - Check for `{"status": "ok"}`
- [ ] Visit `https://your-app.onrender.com/docs` - Verify API documentation loads
- [ ] Check Render logs for any warnings or errors

### 🗄️ Database Setup

- [ ] Open Render Shell (from dashboard)
- [ ] Run migrations: `alembic upgrade head`
- [ ] Verify tables created in Supabase

### 📱 Update Frontend

- [ ] Update mobile app `baseUrl` to Render URL
- [ ] Update any hardcoded API endpoints
- [ ] Test authentication flow
- [ ] Test LiveKit voice sessions
- [ ] Test all critical features

### 🔧 Optional: LiveKit Agent Worker

- [ ] Create separate Background Worker for agent
- [ ] Use same environment variables
- [ ] Start command: `python -m app.agent.runner dev`
- [ ] Verify agent connects to LiveKit

### 🌐 Optional: Custom Domain

- [ ] Add custom domain in Render settings
- [ ] Configure DNS records
- [ ] Update `CORS_ORIGINS` with custom domain
- [ ] Wait for SSL certificate provisioning

## Testing & Monitoring

### 🧪 Test All Features

- [ ] User registration/login
- [ ] JWT token generation
- [ ] Database queries
- [ ] LiveKit room creation
- [ ] Voice agent functionality
- [ ] GST calculations
- [ ] Inventory management
- [ ] OTP delivery (or demo mode)

### 📊 Monitor Performance

- [ ] Check response times in Render metrics
- [ ] Monitor memory usage
- [ ] Check CPU usage
- [ ] Review error rates in logs
- [ ] Set up alerts for failures

### 🔒 Security Review

- [ ] Verify HTTPS is enforced
- [ ] Check CORS settings allow only intended origins
- [ ] Ensure no secrets in logs
- [ ] Verify JWT tokens expire correctly
- [ ] Test rate limiting (if implemented)

## Troubleshooting

If deployment fails, check:

- [ ] Build logs for Python/dependency errors
- [ ] All required environment variables are set
- [ ] Database connection string is correct
- [ ] Google credentials JSON is valid
- [ ] `start.sh` has correct permissions
- [ ] No syntax errors in code

## Maintenance

### Regular Tasks

- [ ] Monitor Render dashboard for alerts
- [ ] Review logs periodically
- [ ] Keep dependencies updated
- [ ] Rotate secrets/API keys quarterly
- [ ] Review and optimize database queries
- [ ] Monitor costs and usage

### When Making Changes

- [ ] Test locally first
- [ ] Commit to Git
- [ ] Push to GitHub
- [ ] Render auto-deploys (if enabled)
- [ ] Monitor deployment in Render dashboard
- [ ] Verify changes in production

---

## Quick Commands Reference

### Generate JWT Secret
```bash
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

### Test Local Before Deploy
```bash
# Set environment variables from .env
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000

# Run tests
python -m pytest -q
```

### View Render Logs (via CLI)
```bash
# Install Render CLI
npm install -g @render/cli

# Login
render login

# View logs
render logs <service-id>
```

---

## Support Resources

- 📖 [Full Deployment Guide](./RENDER_DEPLOYMENT.md)
- 📖 [Backend README](./readme.md)
- 🌐 [Render Docs](https://render.com/docs)
- 💬 [Render Community](https://community.render.com)

---

**Once all boxes are checked, your app is production-ready!** 🎉
