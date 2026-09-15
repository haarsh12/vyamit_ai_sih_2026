# Frontend Integration with Render Backend

## ✅ Backend Deployed Successfully!

**Backend URL:** `https://manthan4yuva-hackathon.onrender.com`

---

## 📱 Frontend Configuration Updated

The Flutter app is now configured to use the Render backend.

### File Changed:
- `lib/core/config.dart`

### Changes Made:

```dart
// OLD (Local development)
static const String _developmentUrl = "http://10.40.209.207:8000";
defaultValue: _developmentUrl,

// NEW (Render production)
static const String _productionUrl = "https://manthan4yuva-hackathon.onrender.com";
defaultValue: _productionUrl,
```

---

## 🔄 Switching Between Local and Render

### To Use Render Backend (Current - Production):
```dart
// lib/core/config.dart
static const String _productionUrl = "https://manthan4yuva-hackathon.onrender.com";
// static const String _developmentUrl = "http://10.40.209.207:8000";

defaultValue: _productionUrl,  // ← Active
// defaultValue: _developmentUrl,
```

### To Use Local Backend (Development):
```dart
// lib/core/config.dart
static const String _productionUrl = "https://manthan4yuva-hackathon.onrender.com";
static const String _developmentUrl = "http://YOUR_LOCAL_IP:8000";

// defaultValue: _productionUrl,
defaultValue: _developmentUrl,  // ← Active
```

### To Override at Runtime:
```bash
# Use specific URL without changing code
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8000
```

---

## 🧪 Testing the Integration

### 1. Run the Flutter App
```bash
cd frontend_mobileapp
flutter run
```

### 2. Test Authentication
- Open the app
- Try to login with any phone number
- Use OTP: `112233` (demo mode enabled)
- Should successfully authenticate

### 3. Test Voice Features
- Navigate to voice assistant screen
- The app will connect to: `wss://manthan4yuva-hackathon.onrender.com/...`
- Voice features should work with LiveKit integration

---

## 📋 Backend Endpoints Available

| Endpoint | URL |
|----------|-----|
| Root | `https://manthan4yuva-hackathon.onrender.com/` |
| Health Check | `https://manthan4yuva-hackathon.onrender.com/health` |
| API Docs | `https://manthan4yuva-hackathon.onrender.com/docs` |
| Authentication | `https://manthan4yuva-hackathon.onrender.com/api/v1/auth/*` |
| Inventory | `https://manthan4yuva-hackathon.onrender.com/api/v1/inventory/*` |
| Voice Sessions | `https://manthan4yuva-hackathon.onrender.com/api/v1/voice/*` |

---

## 🔧 Configuration Details

### Current Backend Settings:

- **Environment**: `development` (allows OTP demo mode)
- **OTP Demo Mode**: Enabled (any OTP works, e.g., `112233`)
- **Database**: Supabase (Transaction pooler)
- **LiveKit**: Configured for voice features
- **Google Cloud**: Vertex AI for speech and LLM
- **CORS**: Allows all origins (configure for production)

### Security Notes:

⚠️ **For Production Deployment:**
1. Change `APP_ENV=production` in backend
2. Set up real SMS with Fast2SMS
3. Configure specific CORS origins
4. Update JWT secret keys
5. Enable HTTPS only in frontend

---

## 🚀 Next Steps

### Immediate Testing:
1. ✅ Backend is live and running
2. ✅ Frontend is configured to use Render
3. 🔄 Run `flutter run` to test
4. 🔄 Test authentication with demo OTP
5. 🔄 Test voice features

### Production Readiness:
- [ ] Set up proper CORS origins
- [ ] Configure real SMS service
- [ ] Add custom domain (optional)
- [ ] Enable backend security checks
- [ ] Test all features end-to-end

---

## 🆘 Troubleshooting

### App Can't Connect to Backend:

**Check:**
1. Backend is running: Visit `https://manthan4yuva-hackathon.onrender.com/health`
2. Internet connection on device/emulator
3. CORS settings allow your app's origin
4. No typos in URL

### Authentication Fails:

**Check:**
1. OTP demo mode is enabled (`OTP_DEMO_MODE=true`)
2. Using any demo OTP (e.g., `112233`)
3. Backend logs for errors

### Voice Features Don't Work:

**Check:**
1. LiveKit credentials are configured
2. LiveKit room creation endpoint works
3. Device has microphone permissions
4. WebSocket connection is established

---

## 📞 Backend Support

- **Backend Logs**: Check Render dashboard → Logs tab
- **Backend Status**: `https://manthan4yuva-hackathon.onrender.com/health`
- **API Documentation**: `https://manthan4yuva-hackathon.onrender.com/docs`

---

## ✅ Current Status

- ✅ Backend deployed on Render
- ✅ Database connected (Supabase)
- ✅ Google Cloud credentials configured
- ✅ LiveKit integration ready
- ✅ Frontend configured to use Render backend
- 🔄 Ready for testing!

---

**Last Updated:** $(date)
**Backend URL:** https://manthan4yuva-hackathon.onrender.com
**Frontend Config:** Production mode (Render backend)
