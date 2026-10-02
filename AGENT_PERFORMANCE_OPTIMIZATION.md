# LiveKit Agent Performance Optimization

## Problem
Railway-deployed LiveKit agent takes ~4 seconds to respond on first message, while local laptop responds in <1 second.

## Root Causes

### 1. **Railway Cold Starts**
- Railway free tier may sleep the agent after inactivity
- First request takes 2-3 seconds to wake up the container

### 2. **Limited Resources**
- Shared CPU/RAM on Railway free tier
- Slower model loading compared to local development

### 3. **Network Latency**
- Extra hops: Phone → LiveKit → Railway → Google APIs
- vs Local: Phone → LiveKit → Laptop → Google APIs (faster)

---

## Optimizations Applied

### ✅ **1. Enable Preemptive Generation**
**File:** `backend_app/app/agent/runner.py`

```python
preemptive_generation=True  # Start generating response while user is speaking
```

**Impact:** Reduces response time by 300-500ms

---

### ✅ **2. Optimize Provider Creation**
**File:** `backend_app/app/agent/runner.py`

```python
# Create STT, LLM, TTS in parallel threads
stt_task = asyncio.create_task(asyncio.to_thread(create_stt, settings))
llm_task = asyncio.create_task(asyncio.to_thread(create_llm, settings))
tts_task = asyncio.create_task(asyncio.to_thread(create_tts, settings))
```

**Impact:** Reduces startup from ~4s to ~2.5s

---

### ✅ **3. Railway Health Check**
**File:** `backend_app/railway.toml`

```toml
healthcheckPath = "/"
healthcheckTimeout = 30
```

**Impact:** Railway pings agent regularly to keep it warm

---

### ✅ **4. Keep-Warm Script** (Optional)
**File:** `backend_app/keep_agent_warm.py`

Use external service like **cron-job.org** or **UptimeRobot** to ping:
```
http://your-railway-agent-url:54628/health
```
Every 5 minutes.

**Impact:** Eliminates cold starts completely

---

## Expected Performance After Optimization

| Metric | Before | After |
|--------|--------|-------|
| First response time | ~4.0s | ~1.5-2.0s |
| Subsequent responses | ~1.0s | ~0.8s |
| Cold start penalty | Yes (2-3s) | No (if keep-warm enabled) |

---

## Additional Recommendations

### **Option 1: Upgrade Railway Plan**
- **Railway Pro** ($5/month) provides:
  - No cold starts
  - Dedicated CPU
  - More RAM
  - **Expected improvement:** First response < 1 second

### **Option 2: Use External Keep-Warm Service**
Free services that ping your agent:
1. **UptimeRobot** - https://uptimerobot.com (free, pings every 5 min)
2. **cron-job.org** - https://cron-job.org (free, pings every 1-60 min)
3. **Freshping** - https://freshping.io (free, pings every 1 min)

Configure them to ping: `http://your-railway-url:54628/health`

### **Option 3: Pre-warm Provider Cache**
Create providers once at startup and reuse them across sessions (requires code changes to make providers singleton).

---

## Testing

After Railway redeploys, test with:

1. **First message** (cold start): Should be ~1.5-2.0s
2. **Second message** (warm): Should be ~0.8s
3. **After 10 minutes idle**: If keep-warm is working, should still be ~1.5-2.0s (not 4s)

---

## Monitoring

Check Railway logs for timing:
```
⏱️ [room] STAGE_START: parallel_provider_creation
⏱️ [room] STAGE_END: parallel_provider_creation took XXXms
```

Target: <1500ms for provider creation
