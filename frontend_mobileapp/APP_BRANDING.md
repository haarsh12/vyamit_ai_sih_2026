# App Branding Configuration

## App Identity

### App Name
**Display Name:** `VyamitAI`
- Used in app launcher, home screen, app switcher
- Configured in Android and iOS manifests

### Logo
**Source:** `assets/vyamitlogo.png`
- Used for all platform launcher icons
- Generated for: Android, iOS, Web, Windows, macOS

---

## Platform-Specific Configuration

### Android
**Location:** `android/app/src/main/AndroidManifest.xml`
```xml
<application
    android:label="VyamitAI"
    android:icon="@mipmap/ic_launcher">
```

**Launcher Icons:**
- `mipmap-hdpi/ic_launcher.png` (72x72)
- `mipmap-mdpi/ic_launcher.png` (48x48)
- `mipmap-xhdpi/ic_launcher.png` (96x96)
- `mipmap-xxhdpi/ic_launcher.png` (144x144)
- `mipmap-xxxhdpi/ic_launcher.png` (192x192)

### iOS
**Location:** `ios/Runner/Info.plist`
```xml
<key>CFBundleDisplayName</key>
<string>VyamitAI</string>
```

**Launcher Icon:**
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/`
- Multiple sizes generated from 20x20 to 1024x1024

### Web
**Launcher Icons:**
- `web/icons/Icon-192.png`
- `web/icons/Icon-512.png`
- `web/icons/Icon-maskable-192.png`
- `web/icons/Icon-maskable-512.png`

### Windows
**Launcher Icon:**
- `windows/runner/resources/app_icon.ico`

### macOS
**Launcher Icon:**
- `macos/Runner/Assets.xcassets/AppIcon.appiconset/`

---

## Flutter App Title

**Location:** `lib/main.dart`
```dart
MaterialApp(
  title: 'VyamitAI',
  // ...
)
```

This title is used:
- In browser tabs (web)
- In task switcher descriptions
- As fallback when no other name is available

---

## Icon Generation Configuration

**Location:** `pubspec.yaml`
```yaml
flutter_launcher_icons:
  android: "ic_launcher"
  ios: true
  image_path: "assets/vyamitlogo.png"
  min_sdk_android: 21
  web:
    generate: true
    image_path: "assets/vyamitlogo.png"
    background_color: "#FFFFFF"
    theme_color: "#C6E377"
  windows:
    generate: true
    image_path: "assets/vyamitlogo.png"
    icon_size: 48
  macos:
    generate: true
    image_path: "assets/vyamitlogo.png"
```

---

## How to Regenerate Icons

If you update the logo (`assets/vyamitlogo.png`), regenerate icons:

```bash
cd d:\manthan_hack\frontend_mobileapp
dart run flutter_launcher_icons
```

---

## Verification Checklist

✅ Android launcher icon shows Vyamit logo  
✅ iOS launcher icon shows Vyamit logo  
✅ App name displays as "VyamitAI" on home screen  
✅ Logo source file: `assets/vyamitlogo.png`  
✅ All platform icons generated successfully  

---

## Before vs After

### Before
- ❌ App icon: Flutter default logo (blue gradient)
- ❌ App name: "Vyamit AI Mobile"

### After
- ✅ App icon: Custom Vyamit logo
- ✅ App name: "VyamitAI"

---

## Notes

- The logo is automatically sized and formatted for each platform
- Icon generation creates adaptive icons for Android
- iOS icons include all required sizes (20x20 to 1024x1024)
- Web icons include maskable variants for PWA support
- Background color for web: White (#FFFFFF)
- Theme color for web: Light green (#C6E377)
