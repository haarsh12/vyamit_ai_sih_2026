# Deploying Vyamit Backend to Render

This guide walks you through deploying the Vyamit backend application to Render cloud platform.

## Prerequisites

1. **GitHub Repository**: Your code must be in a GitHub repository (or GitLab/Bitbucket)
2. **Render Account**: Sign up at [render.com](https://render.com)
3. **Supabase Database**: You need a Supabase PostgreSQL database set up
4. **Third-party API Keys**: Collect all required API keys (listed below)

## Required Environment Variables & Secrets

Before deployment, gather these credentials:

### 🔐 Critical Secrets (MUST be set)

1. **JWT_SECRET_KEY**: Generate a strong random 32+ character secret
   ```bash
   # Generate with Python:
   python -c "import secrets; print(secrets.token_urlsafe(32))"
   ```

2. **DATABASE_URL**: Your Supabase PostgreSQL connection string
   - Format: `postgresql://USER:PASSWORD@HOST:PORT/postgres?sslmode=require`
   - Get from Supabase Dashboard → Settings → Database → Connection String
   - **Important**: Use the **Transaction Pooler** or **Session Pooler** URL for production

3. **SUPABASE_URL**: Your Supabase project URL
   - Format: `https://YOUR-PROJECT.supabase.co`

4. **Google Cloud Credentials**:
   - **GOOGLE_CREDENTIALS_JSON**: Copy the **entire content** of your service account JSON file
   - **GOOGLE_CLOUD_PROJECT**: Your GCP project ID
   - **VERTEX_GEMINI_MODEL**: e.g., `gemini-1.5-pro` or `gemini-1.5-flash`

5. **LiveKit Configuration**:
   - **LIVEKIT_URL**: Your LiveKit server URL (e.g., `wss://your-project.livekit.cloud`)
   - **LIVEKIT_API_KEY**: Your LiveKit API key
   - **LIVEKIT_API_SECRET**: Your LiveKit API secret

6. **Voice/TTS Configuration**:
   - **CARTESIA_API_KEY**: Cartesia API key for text-to-speech
   - **CARTESIA_VOICE_ID**: Voice ID to use
   - **MISTRAL_API_KEY**: Mistral AI API key (fallback LLM)
   - **MISTRAL_MODEL**: e.g., `mistral-large-latest`

### ⚙️ Optional Secrets

- **SUPABASE_SERVICE_ROLE_KEY**: Only if you need server-side admin access
- **FAST2SMS_API_KEY**: Only if using SMS OTP (set `OTP_DEMO_MODE=true` to skip)

### 🌐 Public Configuration

- **CORS_ORIGINS**: Comma-separated list of allowed frontend URLs
  - Example: `https://your-app.com,https://www.your-app.com`
  - **Must be HTTPS in production**

## Deployment Methods

### Method 1: Deploy via Render Dashboard (Recommended for first-time)

1. **Push your code to GitHub**:
   ```bash
   git add .
   git commit -m "Prepare for Render deployment"
   git push origin main
   ```

2. **Sign in to Render**: Go to [dashboard.render.com](https://dashboard.render.com)

3. **Create New Web Service**:
   - Click **"New +"** → **"Web Service"**
   - Connect your GitHub account if not already connected
   - Select your repository

4. **Configure the Service**:
   - **Name**: `vyamit-backend-api` (or your choice)
   - **Region**: Choose closest to your users (e.g., Singapore, Oregon, Frankfurt)
   - **Branch**: `main` (or your default branch)
   - **Runtime**: Select **"Python 3"**
   - **Build Command**: `pip install -r requirements.txt`
   - **Start Command**: `bash start.sh`
   - **Plan**: Choose your plan (Free tier available, but has limitations)

5. **Set Health Check** (in Advanced settings):
   - **Health Check Path**: `/health`

6. **Add Environment Variables**:
   Click "Advanced" → "Add Environment Variable" and add **all** the variables listed above.

   For **GOOGLE_CREDENTIALS_JSON**:
   - Open your Google service account JSON file
   - Copy the **entire file content** (it's a multi-line JSON)
   - Paste it as the value for `GOOGLE_CREDENTIALS_JSON`

7. **Deploy**: Click **"Create Web Service"**

8. **Monitor Deployment**: Watch the logs for any errors. First deployment takes 5-10 minutes.

### Method 2: Deploy via Blueprint (Infrastructure as Code)

1. **Ensure `render.yaml` is in your repo** (already created in this guide)

2. **Push to GitHub**:
   ```bash
   git add .
   git commit -m "Add Render Blueprint"
   git push origin main
   ```

3. **Create Blueprint in Render**:
   - Go to [dashboard.render.com](https://dashboard.render.com)
   - Click **"New +"** → **"Blueprint"**
   - Connect your repository
   - Render will detect `render.yaml` automatically

4. **Review and Configure**:
   - Review the detected services
   - Add all the **secret environment variables** marked with `sync: false`
   - Click **"Apply"**

5. **Deploy**: Render will create and deploy your services

## Post-Deployment Steps

### 1. Run Database Migrations

After first deployment, you need to run Alembic migrations:

```bash
# SSH into your Render shell (available in the dashboard)
# Or use Render's "Shell" tab
alembic upgrade head
```

**Alternative**: Add migration to start script (not recommended for production):
- This can be risky if multiple instances start simultaneously

### 2. Verify Deployment

Check these endpoints:
- `https://your-app.onrender.com/` - Should return `{"status": "active"}`
- `https://your-app.onrender.com/health` - Should return `{"status": "ok"}`
- `https://your-app.onrender.com/docs` - FastAPI interactive documentation

### 3. Update Frontend Configuration

Update your mobile app configuration to point to the Render URL:
```dart
// lib/core/config.dart
static const String baseUrl = 'https://your-app.onrender.com';
```

### 4. Configure Custom Domain (Optional)

1. Go to your service → Settings → Custom Domains
2. Add your domain
3. Configure DNS records as instructed by Render
4. Update `CORS_ORIGINS` to include your custom domain

## Deploying the LiveKit Agent Worker

The LiveKit agent should run as a separate **Background Worker**:

1. **Create Background Worker**:
   - Click **"New +"** → **"Background Worker"**
   - Select same repository
   - **Build Command**: `pip install -r requirements.txt`
   - **Start Command**: `python -m app.agent.runner dev`

2. **Add Same Environment Variables**: Copy all environment variables from the web service

3. **Deploy**: The worker will run continuously to handle LiveKit voice sessions

## Environment-Specific Configuration

### Development vs Production

The app automatically detects production mode from `APP_ENV=production`. In production:
- OTP demo mode is forbidden
- OTP code logging is forbidden
- CORS must use HTTPS origins
- JWT secret key is required

### Scaling Considerations

- **Free Tier**: Limited to 750 hours/month, spins down after inactivity
- **Starter Tier**: Always-on, better for production
- **Horizontal Scaling**: Use Render's scaling options for high traffic

## Troubleshooting

### Common Issues

1. **"Database connection failed"**
   - Verify `DATABASE_URL` is correct
   - Use Supabase **Pooler URL**, not direct connection
   - Ensure URL has `?sslmode=require` or `?ssl=require`

2. **"Google credentials not found"**
   - Ensure `GOOGLE_CREDENTIALS_JSON` is set with **complete** JSON content
   - Check that `start.sh` has execute permissions
   - Verify the JSON is valid (use a JSON validator)

3. **"Port binding failed"**
   - Don't modify `PORT` environment variable - Render sets this automatically
   - Ensure start command uses `--port ${PORT:-10000}`

4. **"Module not found" errors**
   - Check that all dependencies are in `requirements.txt`
   - Try clearing Render's build cache (Settings → "Clear build cache & deploy")

5. **"CORS errors from frontend"**
   - Verify `CORS_ORIGINS` includes your frontend URL
   - Ensure URL format is correct (no trailing slashes)
   - Check browser console for exact error

### Viewing Logs

- **Real-time logs**: Service page → "Logs" tab
- **Deploy logs**: Service page → "Deploys" tab → Click specific deploy
- **Shell access**: Service page → "Shell" tab (for debugging)

### Render-Specific Gotchas

1. **Build time**: First build can take 5-10 minutes
2. **Free tier spin-down**: Apps sleep after 15 minutes of inactivity (takes ~30s to wake)
3. **Build cache**: Sometimes needs clearing if dependencies don't update
4. **Environment variable changes**: Require redeployment to take effect

## Cost Estimation

### Free Tier
- **Web Services**: 750 hours/month (shared across all services)
- **Good for**: Development, testing, demos
- **Limitations**: Spins down after inactivity, limited resources

### Starter Plan (~$7/month per service)
- Always-on
- 512 MB RAM, 0.5 CPU
- **Good for**: Small production apps

### Standard Plan (~$25/month per service)
- Always-on
- 2 GB RAM, 1 CPU
- **Good for**: Production apps with moderate traffic

## Security Best Practices

1. ✅ Never commit `.env` files or secrets to Git
2. ✅ Use Render's secret environment variables for all credentials
3. ✅ Enable HTTPS only for production (`CORS_ORIGINS` should be HTTPS)
4. ✅ Rotate JWT secrets and API keys periodically
5. ✅ Use Supabase Row Level Security (RLS) policies
6. ✅ Monitor Render logs for suspicious activity
7. ✅ Set up Render's IP restrictions if needed (Enterprise feature)

## Continuous Deployment

Render automatically deploys when you push to your configured branch:

```bash
git add .
git commit -m "Update feature"
git push origin main
# Render automatically starts deploying
```

To disable auto-deploy:
- Go to Service Settings → "Auto-Deploy" → Toggle off

## Monitoring & Maintenance

1. **Health Checks**: Render pings `/health` endpoint regularly
2. **Metrics**: View CPU, Memory, and Request metrics in dashboard
3. **Alerts**: Set up email/Slack alerts for deployment failures
4. **Logs**: Keep production logs for debugging issues

## Additional Resources

- [Render Documentation](https://render.com/docs)
- [Render FastAPI Guide](https://render.com/docs/deploy-fastapi)
- [Supabase Connection Pooling](https://supabase.com/docs/guides/database/connecting-to-postgres#connection-pooler)
- [LiveKit Deployment Guide](https://docs.livekit.io/home/server/deployment/)

## Support

- **Render Support**: [render.com/support](https://render.com/support)
- **Community Forum**: [community.render.com](https://community.render.com)
- **Status Page**: [status.render.com](https://status.render.com)

---

**Ready to deploy!** 🚀

Follow the steps above and your backend will be live on Render in minutes.
