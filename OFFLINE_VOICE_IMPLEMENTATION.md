# Offline Voice Implementation Guide

## Overview
Complete offline voice assistant for Vyamit using on-device STT, LLM, and TTS.

## Recommended Approach: Hybrid Mode

```
┌─────────────────────────────────────────────┐
│           User Speaks                        │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│   On-Device STT (Already Available)         │
│   - Android: Speech Recognition API         │
│   - iOS: Speech Framework                   │
└──────────────┬──────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────┐
│        Network Available?                    │
└──────┬──────────────────────┬───────────────┘
       │ YES                  │ NO
       ▼                      ▼
┌─────────────────┐  ┌──────────────────────┐
│  Cloud LLM      │  │  On-Device LLM       │
│  (Gemini)       │  │  (Gemini Nano/Phi-3) │
└────────┬────────┘  └──────────┬───────────┘
         │                      │
         └──────────┬───────────┘
                    ▼
         ┌─────────────────────┐
         │  On-Device TTS      │
         │  (Already Available)│
         └─────────────────────┘
```

## Implementation Options

### Option 1: Gemini Nano (Android) ⭐ RECOMMENDED

**Pros:**
- Native Android integration via AICore
- Optimized for mobile performance
- Smallest memory footprint (1.5-3GB)
- Best latency
- Free (included in Android 14+)

**Cons:**
- Android 14+ only
- Requires device support check

**Implementation:**
```dart
// Add to pubspec.yaml
dependencies:
  google_ai_edge: ^0.1.0  # When available
  
// Or use Flutter plugin
flutter pub add flutter_gemma
```

### Option 2: Phi-3 Mini via ONNX Runtime (Cross-platform)

**Pros:**
- Works on both iOS and Android
- Good quality (3.8B parameters)
- Active community support
- Quantized versions available

**Cons:**
- Larger size (2.3GB)
- Requires ONNX Runtime Mobile

**Implementation:**
```dart
dependencies:
  onnxruntime: ^1.16.0
  
// Download model
// https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx
```

### Option 3: MediaPipe LLM Inference

**Pros:**
- Official Google solution
- Cross-platform
- Easy integration
- Good documentation

**Cons:**
- Limited model selection
- Medium size models

**Implementation:**
```dart
dependencies:
  google_mediapipe: ^0.10.0
```

### Option 4: Qwen2-1.5B (Best for Multilingual)

**Pros:**
- Better Hindi/Marathi support
- Compact size (~1GB)
- Fast inference
- Good reasoning

**Cons:**
- Requires manual integration
- Less documentation

## Recommended Implementation Plan

### Phase 1: Add Network Detection
```dart
// lib/services/network_service.dart
import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkService {
  static Future<bool> isOnline() async {
    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      return false;
    }
    
    // Verify actual connectivity
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
```

### Phase 2: Create LLM Service with Fallback
```dart
// lib/services/llm_service.dart
abstract class LLMService {
  Future<String> generateResponse(String prompt, {required String context});
}

class CloudLLMService implements LLMService {
  @override
  Future<String> generateResponse(String prompt, {required String context}) async {
    // Your existing Gemini API call
    return await callGeminiAPI(prompt, context);
  }
}

class OfflineLLMService implements LLMService {
  late final OnDeviceLLM _model;
  
  Future<void> initialize() async {
    _model = await OnDeviceLLM.load('gemini_nano'); // or phi-3
  }
  
  @override
  Future<String> generateResponse(String prompt, {required String context}) async {
    return await _model.generate(prompt, context);
  }
}

class HybridLLMService implements LLMService {
  final CloudLLMService _cloud = CloudLLMService();
  final OfflineLLMService _offline = OfflineLLMService();
  
  @override
  Future<String> generateResponse(String prompt, {required String context}) async {
    if (await NetworkService.isOnline()) {
      try {
        return await _cloud.generateResponse(prompt, context: context)
            .timeout(Duration(seconds: 5));
      } catch (e) {
        print('Cloud LLM failed, falling back to offline: $e');
      }
    }
    
    return await _offline.generateResponse(prompt, context: context);
  }
}
```

### Phase 3: Implement On-Device LLM

#### For Gemini Nano (Android):
```dart
// lib/services/gemini_nano_service.dart
import 'package:flutter/services.dart';

class GeminiNanoService {
  static const platform = MethodChannel('com.vyamit/gemini_nano');
  
  Future<bool> isAvailable() async {
    try {
      return await platform.invokeMethod('isAvailable');
    } catch (e) {
      return false;
    }
  }
  
  Future<String> generate(String prompt, String systemPrompt) async {
    try {
      final result = await platform.invokeMethod('generate', {
        'prompt': prompt,
        'systemPrompt': systemPrompt,
      });
      return result as String;
    } catch (e) {
      throw Exception('Gemini Nano generation failed: $e');
    }
  }
}

// Android implementation: android/app/src/main/kotlin/MainActivity.kt
import com.google.ai.client.generativeai.GenerativeModel
import com.google.ai.client.generativeai.type.generationConfig

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.vyamit/gemini_nano"
    private var geminiModel: GenerativeModel? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> {
                        result.success(isGeminiNanoAvailable())
                    }
                    "generate" -> {
                        val prompt = call.argument<String>("prompt")
                        val systemPrompt = call.argument<String>("systemPrompt")
                        generateResponse(prompt, systemPrompt, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }
    
    private fun isGeminiNanoAvailable(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE
    }
    
    private fun generateResponse(
        prompt: String?,
        systemPrompt: String?,
        result: MethodChannel.Result
    ) {
        if (prompt == null) {
            result.error("INVALID_ARGS", "Prompt is required", null)
            return
        }
        
        CoroutineScope(Dispatchers.IO).launch {
            try {
                if (geminiModel == null) {
                    geminiModel = GenerativeModel(
                        modelName = "gemini-nano",
                        generationConfig = generationConfig {
                            temperature = 0.7f
                            maxOutputTokens = 256
                        }
                    )
                }
                
                val fullPrompt = if (systemPrompt != null) {
                    "$systemPrompt\n\nUser: $prompt"
                } else {
                    prompt
                }
                
                val response = geminiModel!!.generateContent(fullPrompt)
                result.success(response.text)
            } catch (e: Exception) {
                result.error("GENERATION_ERROR", e.message, null)
            }
        }
    }
}
```

#### For Phi-3 via ONNX (Cross-platform):
```dart
// lib/services/phi3_service.dart
import 'package:onnxruntime/onnxruntime.dart';

class Phi3Service {
  late OrtSession _session;
  bool _isInitialized = false;
  
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Load quantized Phi-3 model
    const modelPath = 'assets/models/phi-3-mini-4k-instruct-q4.onnx';
    OrtEnv.instance.init();
    
    final sessionOptions = OrtSessionOptions()
      ..setIntraOpNumThreads(4)
      ..setSessionGraphOptimizationLevel(GraphOptimizationLevel.ortEnableAll);
    
    _session = OrtSession.fromFile(modelPath, sessionOptions);
    _isInitialized = true;
  }
  
  Future<String> generate(String prompt, String systemPrompt) async {
    if (!_isInitialized) await initialize();
    
    // Tokenize and run inference
    final tokens = await _tokenize("$systemPrompt\n\n$prompt");
    final inputTensor = OrtValueTensor.createTensorWithDataList(
      [tokens],
      [1, tokens.length],
    );
    
    final outputs = await _session.runAsync(
      OrtRunOptions(),
      {'input_ids': inputTensor},
    );
    
    final outputTokens = outputs[0]?.value as List<List<int>>;
    return await _detokenize(outputTokens[0]);
  }
  
  Future<List<int>> _tokenize(String text) async {
    // Use tiktoken or sentencepiece tokenizer
    // Implementation depends on your tokenizer choice
    throw UnimplementedError();
  }
  
  Future<String> _detokenize(List<int> tokens) async {
    // Decode tokens back to text
    throw UnimplementedError();
  }
}
```

### Phase 4: Update Voice Service

```dart
// lib/services/voice_llm_service.dart
class VoiceLLMService {
  final HybridLLMService _llmService = HybridLLMService();
  bool _isOfflineMode = false;
  
  Future<void> initialize() async {
    // Initialize offline model
    await _llmService._offline.initialize();
    
    // Check network status
    _isOfflineMode = !(await NetworkService.isOnline());
  }
  
  Future<String> processVoiceCommand(
    String userSpeech, {
    required String shopCategory,
    required Map<String, dynamic> context,
  }) async {
    // Build prompt based on your existing instructions
    final systemPrompt = _buildSystemPrompt(shopCategory);
    final prompt = _buildPrompt(userSpeech, context);
    
    // Generate response (auto-fallback to offline if needed)
    final response = await _llmService.generateResponse(
      prompt,
      context: systemPrompt,
    );
    
    return _parseAndExecute(response, context);
  }
  
  String _buildSystemPrompt(String shopCategory) {
    if (shopCategory == 'Doctor Prescription') {
      return '''You are a medical assistant helping doctors create prescriptions.
Extract: patient name, medicines, dosage, diagnosis.
Keep responses brief and structured.''';
    } else {
      return '''You are a billing assistant for a $shopCategory shop.
Extract: items, quantities, prices.
Keep responses brief and actionable.''';
    }
  }
  
  String _buildPrompt(String userSpeech, Map<String, dynamic> context) {
    return '''Current context: ${context['currentBill'] ?? 'New bill'}
User said: "$userSpeech"

What action should be taken?''';
  }
  
  String _parseAndExecute(String response, Map<String, dynamic> context) {
    // Parse LLM response and execute tools
    // This replaces your current LiveKit agent tools with local processing
    return response;
  }
}
```

## Deployment Steps

### Step 1: Add Dependencies
```yaml
# pubspec.yaml
dependencies:
  connectivity_plus: ^5.0.0
  # Choose one:
  # flutter_gemma: ^0.1.0  # For Gemini Nano
  # onnxruntime: ^1.16.0   # For Phi-3
  
assets:
  - assets/models/  # For storing model files
```

### Step 2: Download Model
```bash
# For Phi-3 Mini (recommended for cross-platform)
# Download from: https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx

# Place in: frontend_app/assets/models/phi-3-mini-4k-instruct-q4.onnx
# Size: ~2.3GB (will be bundled with app)

# For Gemini Nano: No download needed, uses AICore
```

### Step 3: Update Permissions
```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
```

### Step 4: Test Offline Mode
```dart
// Add to your voice screen
void _testOfflineMode() async {
  // Force offline mode
  final service = VoiceLLMService();
  await service.initialize();
  
  final response = await service.processVoiceCommand(
    "Add 2 paracetamol tablets",
    shopCategory: "Pharmacy",
    context: {"currentBill": []},
  );
  
  print("Offline response: $response");
}
```

## Storage Requirements

| Model | Size | Quality | Speed | Multilingual |
|-------|------|---------|-------|--------------|
| Gemini Nano | 1.5-3GB | Excellent | Fast | Good |
| Phi-3 Mini | 2.3GB | Very Good | Medium | Medium |
| TinyLlama | 637MB | Good | Very Fast | Limited |
| Qwen2-1.5B | ~1GB | Very Good | Fast | Excellent |

## Performance Considerations

1. **First-time load**: 2-5 seconds (model initialization)
2. **Subsequent calls**: 100-500ms (depending on model)
3. **Memory usage**: 1.5-3GB RAM
4. **Battery impact**: Moderate (similar to video playback)

## Fallback Strategy

```
1. Try cloud LLM (best quality, requires network)
   └─ Timeout or failure after 5s
      └─ Fall back to on-device LLM (good quality, always works)
         └─ If model not loaded
            └─ Use template-based responses (basic but instant)
```

## Next Steps

1. **Choose your LLM**: I recommend Gemini Nano for Android, Phi-3 for iOS
2. **Implement network detection**: Use connectivity_plus
3. **Create hybrid service**: Cloud-first with offline fallback
4. **Test offline mode**: Airplane mode testing
5. **Optimize prompts**: Keep prompts short for faster inference

Would you like me to implement any of these options for you?
