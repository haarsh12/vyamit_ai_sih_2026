# 🚀 Vyamit Startup Guide

## Quick Start

### Option 1: Use Startup Scripts (Recommended)

**Terminal 1 - Backend:**
```powershell
.\start_backend.ps1
```

**Terminal 2 - Frontend:**
```powershell
.\start_frontend.ps1
```

---

## Manual Startup Commands

### Backend (FastAPI + Python)

```powershell
# Navigate to backend
cd backend_app

# Activate virtual environment
.\venv\Scripts\Activate.ps1

# Start server
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

**Backend will be available at:** http://localhost:8000

**API Documentation:** http://localhost:8000/docs

**Health Check:** http://localhost:8000/health/live

---

### Frontend (Flutter)

```powershell
# Navigate to frontend
cd frontend_app

# Get dependencies
flutter pub get

# Run app
flutter run
```

**Frontend will connect to backend at:** http://localhost:8000

---

## Available Devices

### Check Connected Devices:
```powershell
flutter devices
```

### Run on Specific Device:
```powershell
# Windows Desktop
flutter run -d windows

# Chrome Browser
flutter run -d chrome

# Android Device/Emulator
flutter run -d <device-id>

# iOS Simulator (macOS only)
flutter run -d <simulator-id>
```

---

## Backend API Endpoints

Once backend is running, these endpoints are available:

### Authentication
- `POST /auth/send-otp` - Send OTP to phone
- `POST /auth/verify-otp` - Verify OTP and login
- `GET /auth/profile` - Get user profile
- `PUT /auth/profile` - Update profile

### Inventory
- `GET /items/` - List all items
- `POST /items/` - Create item
- `PUT /items/{id}` - Update item
- `DELETE /items/{id}` - Delete item

### Analytics
- `POST /analytics/bills` - Create bill
- `GET /analytics/bills` - List bills
- `GET /analytics/dashboard` - Dashboard stats
- `GET /analytics/overview` - Quick overview

### Voice (LiveKit)
- `POST /voice/token` - Get LiveKit token
- `POST /voice-inventory/session` - Create voice session

### GST
- `POST /gst/configure` - Save GST configuration
- `POST /gst/invoice` - Generate GST invoice
- `GET /gst/invoices` - List invoices

### Doctor Prescriptions
- `POST /doctor/prescriptions` - Create prescription
- `GET /doctor/prescriptions` - List prescriptions
- `GET /doctor/patients` - List patients

### Health
- `GET /health/live` - Liveness check
- `GET /health/ready` - Readiness check
- `GET /` - Root status

---

## Troubleshooting

### Backend Issues

**Issue: `ModuleNotFoundError`**
```powershell
cd backend_app
.\venv\Scripts\Activate.ps1
pip install -e .
```

**Issue: Database connection error**
- Check `backend_app/.env` file exists
- Verify `DATABASE_URL` is set correctly
- Test connection: `python -m pytest tests/test_api_health.py`

**Issue: Port 8000 already in use**
```powershell
# Kill process on port 8000
netstat -ano | findstr :8000
taskkill /PID <process-id> /F

# Or use a different port
python -m uvicorn app.main:app --port 8001
```

---

### Frontend Issues

**Issue: `flutter: command not found`**
- Install Flutter: https://flutter.dev/docs/get-started/install
- Add Flutter to PATH

**Issue: No devices found**
```powershell
# For Windows desktop
flutter config --enable-windows-desktop

# For web
flutter config --enable-web

# For Android
# Start Android Studio AVD Manager
```

**Issue: Connection refused to backend**
- Ensure backend is running on port 8000
- Check `frontend_app/lib/core/config.dart`
- Update IP address for real device:
  ```dart
  static const String _realDeviceUrl = "http://YOUR_LAPTOP_IP:8000";
  ```

**Issue: Hot reload not working**
- Press `r` in terminal for hot reload
- Press `R` for hot restart
- Restart app: `flutter run`

---

## Environment Variables

### Backend (.env)

Create `backend_app/.env` from `.env.example`:

```env
# Required
DATABASE_URL=postgresql://postgres.PROJECT:PASSWORD@REGION.pooler.supabase.com:6543/postgres?sslmode=require
JWT_SECRET_KEY=your-secret-key-here

# Optional (for OTP testing)
OTP_DEMO_MODE=true
LOG_OTP_CODES=true

# For production
LIVEKIT_URL=wss://your-project.livekit.cloud
LIVEKIT_API_KEY=your-key
LIVEKIT_API_SECRET=your-secret
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
CARTESIA_API_KEY=your-key
MISTRAL_API_KEY=your-key
```

### Frontend (config.dart)

Edit `frontend_app/lib/core/config.dart`:

```dart
// For local development
static const String _localUrl = "http://localhost:8000";

// For real device via USB
static const String _realDeviceUrl = "http://YOUR_LAPTOP_IP:8000";

// For production
static const String _productionUrl = "https://your-backend.onrender.com";
```

---

## Development Workflow

### 1. Start Backend
```powershell
# Terminal 1
.\start_backend.ps1
```

### 2. Start Frontend
```powershell
# Terminal 2
.\start_frontend.ps1
```

### 3. Test API
Visit http://localhost:8000/docs for interactive API documentation

### 4. Make Changes
- Backend: Edit code → auto-reloads (--reload flag)
- Frontend: Edit code → press `r` for hot reload

### 5. Test Changes
```powershell
# Backend tests
cd backend_app
pytest tests/

# Frontend (once tests are added)
cd frontend_app
flutter test
```

---

## Production Deployment

### Backend (Render/Railway/Fly.io)
```bash
# Build command
pip install -e .

# Start command
uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

### Frontend (Web)
```bash
# Build
flutter build web

# Deploy (serve the build/web folder)
```

### Frontend (Android)
```bash
# Build APK
flutter build apk --release

# Build App Bundle
flutter build appbundle --release
```

### Frontend (iOS)
```bash
# Build IPA
flutter build ipa --release
```

---

## Next Steps

1. ✅ Start backend with `.\start_backend.ps1`
2. ✅ Start frontend with `.\start_frontend.ps1`
3. ✅ Test login flow (OTP demo mode)
4. ✅ Add items to inventory
5. ✅ Create bills
6. ⏳ Configure LiveKit for voice features
7. ⏳ Add production API keys

---

## Support

For issues:
1. Check logs in terminal
2. Visit http://localhost:8000/docs for API docs
3. Run tests: `pytest tests/` (backend)
4. Check GitHub issues

---

**Happy Coding! 🚀**
