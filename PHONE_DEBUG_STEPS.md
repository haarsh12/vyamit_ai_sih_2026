# Token Saver Voice Mode - Phone Troubleshooting

## Issue
Token Saver offline STT/TTS not working on your phone but works on friends' phones with same app version.

## Root Cause
Device-specific configuration: missing speech recognition language models or TTS voices.

---

## **Quick Fix Steps (Try in Order)**

### Step 1: Download Hindi Speech Recognition Model
1. Open **Settings**
2. Go to **System** → **Languages & Input**
3. Tap **Virtual Keyboard** (or **On-screen keyboard**)
4. Select **Gboard** or **Google voice typing**
5. Tap **Offline speech recognition**
6. Download these language packs:
   - ✅ **Hindi (India)** - `hi-IN`
   - ✅ **English (India)** - `en-IN`
   - ✅ **Marathi (India)** - `mr-IN` (optional)
7. **Wait for full download** (don't just start it - let it complete)
8. **Restart your phone**

### Step 2: Enable Microphone Permission
1. Go to **Settings** → **Apps**
2. Find **Vyamit** or your app name
3. Tap **Permissions**
4. Enable **Microphone** → **Allow all the time**
5. Enable **Storage** (if prompted)

### Step 3: Configure Text-to-Speech
1. Go to **Settings** → **Accessibility**
2. Tap **Text-to-Speech output** (or **TTS**)
3. Select **Preferred engine** → **Google Text-to-Speech Engine**
4. Tap **Settings** gear icon next to it
5. Tap **Install voice data**
6. Download **Hindi (India)** voice pack
7. Go back and set **Speech rate** to **Normal** (middle position)

### Step 4: Update Google Services
1. Open **Google Play Store**
2. Search: **"Google Play Services"**
3. Tap **Update** if available
4. Search: **"Google Text-to-Speech Engine"**
5. Tap **Update** if available
6. Search: **"Speech Services by Google"**
7. Tap **Update** if available

### Step 5: Clear App Cache (Last Resort)
1. Go to **Settings** → **Apps** → **Vyamit**
2. Tap **Storage & cache**
3. Tap **Clear cache** (NOT Clear data - that will delete your login)
4. Force stop the app
5. Reopen the app

---

## **How to Verify It's Fixed**

1. Open Vyamit app
2. Go to Voice Billing → **Token Saver Mode**
3. Tap the microphone button
4. You should see: **"Listening on this device…"** (not "Offline speech is unavailable")
5. Say something in Hindi: "नमस्ते" (Namaste)
6. It should transcribe and respond back in Hindi voice

---

## **Check Your Android Version**
- Settings → About Phone → Android version
- Token Saver works best on **Android 10+**
- AEC (echo cancellation) requires **Android 13+** but is optional

---

## **Compare with Your Friends' Phones**

Ask them to check:
1. **Settings → Languages & Input → Offline speech recognition**
   - What language packs do they have downloaded?
2. **Settings → Accessibility → TTS**
   - Which TTS engine are they using?
3. **Android version**
   - Same version as yours?

The difference is likely in Step 1 or Step 3.

---

## **Technical Details (For Developer)**

The Token Saver mode has this fallback sequence:
1. Try **Android AEC Native Speech** (Android 13+ only)
2. Fall back to **On-Device Speech Recognition** (requires downloaded language models)
3. Fall back to **Online Speech Recognition** (if on-device fails)
4. Show error if all fail

The code at line 111-114 in `token_saver_voice_service.dart` shows:
```dart
if (!available) {
  _setState(TokenSaverSessionState.error,
      'Enable microphone permission and an on-device speech language.');
  return false;
}
```

This means Speech-to-Text initialization completely failed, usually due to:
- Missing microphone permission
- No speech recognition language model installed
- Google Play Services not working

---

## **Still Not Working?**

If none of the above fixes work, check:
1. **Phone brand/model** - Some Chinese phones (Xiaomi, Oppo, Vivo) have restricted Google services
2. **Region settings** - Set phone region to **India**
3. **Google app permissions** - Enable all permissions for Google app
4. **Developer options** - Disable any audio/mic debugging features if enabled
