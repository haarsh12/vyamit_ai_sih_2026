# Running Two Vyamit Apps on Same Phone

## ✅ Changes Made

Your current `frontend_app` is now configured as **"Vyamit DEV"** version.

### What Changed:
1. **Package Name**: `com.vyamit.mykirana` → `com.vyamit.mykirana.dev`
2. **App Display Name**: `Vyamit AI` → `Vyamit DEV`
3. **Method Channel**: Updated to match new package

## 📱 How It Works

Now you can have **BOTH apps** on your phone:

| App | Package Name | Display Name | Icon |
|-----|--------------|--------------|------|
| **Original** | `com.vyamit.mykirana` | Vyamit AI | Same icon |
| **Development** | `com.vyamit.mykirana.dev` | Vyamit DEV | Same icon |

Android treats them as completely separate apps because they have different package names!

## 🚀 Build & Install

### Option 1: Debug Build (Fast)
```powershell
cd frontend_app
flutter clean
flutter pub get
flutter run
```

This will install **"Vyamit DEV"** on your phone.

### Option 2: Release Build (Production Quality)
```powershell
cd frontend_app
flutter clean
flutter pub get
flutter build apk --release
```

Then install the APK from:
`frontend_app\build\app\outputs\flutter-apk\app-release.apk`

## 🎯 Testing Scenario

1. **Keep your working app** - Already installed as "Vyamit AI"
2. **Install dev version** - Run `flutter run` to install "Vyamit DEV"
3. **Use both simultaneously**:
   - Test new features in **Vyamit DEV**
   - Keep stable version in **Vyamit AI**
   - They have separate data (different package = different storage)

## 📝 Important Notes

### ⚠️ Separate Data
Each app has its own:
- ✅ Local storage (SharedPreferences)
- ✅ Secure storage (auth tokens)
- ✅ App permissions
- ✅ Cache

They do NOT share data!

### 🔄 Backend Configuration
Both apps can connect to:
- **Production backend** - Update `config.dart` baseUrl
- **Local development backend** - Use `http://10.0.2.2:8000` for emulator
- **Same backend** - Both apps can connect to the same backend

### 🎨 Distinguishing the Apps

On your phone home screen, you'll see:
- **Vyamit AI** (original version)
- **Vyamit DEV** (development version)

Both have the same icon, but different names!

## 🔧 If You Want Different Icons

To make them more distinguishable, you can:

1. Create a different icon for DEV version
2. Save it as `assets/vyamitlogo_dev.png`
3. Update `pubspec.yaml`:
   ```yaml
   flutter_launcher_icons:
     android: "ic_launcher"
     ios: true
     image_path: "assets/vyamitlogo_dev.png"  # Different icon
   ```
4. Run: `flutter pub run flutter_launcher_icons`

## 🧪 Testing Workflow

### Recommended Usage:
1. **Vyamit AI** (Original):
   - Stable version
   - Connected to production backend
   - For normal operations

2. **Vyamit DEV** (Development):
   - Testing new features
   - Connected to local/development backend
   - For experiments

### Quick Switch:
Just tap the app you want to use! No need to uninstall/reinstall anymore.

## 🐛 Troubleshooting

### Both Apps Show Same Name?
- Clear cache: `flutter clean`
- Rebuild: `flutter build apk --release`
- Reinstall

### Can't Install DEV Version?
- Check if package name changed: Look for `applicationId = "com.vyamit.mykirana.dev"` in `build.gradle.kts`
- Uninstall any conflicting versions
- Restart phone

### Apps Share Data?
- They shouldn't! Each package has isolated storage
- If they do, check if you're logged into the same backend account

## ✨ Benefits

✅ **No more overwriting** - Both apps coexist peacefully  
✅ **Quick testing** - Switch between stable and dev instantly  
✅ **Safe experiments** - Break dev version, stable still works  
✅ **Compare behavior** - Run both side-by-side  

---

**Status**: ✅ Configured and ready!

**Next**: Run `flutter run` to install "Vyamit DEV" on your phone.
