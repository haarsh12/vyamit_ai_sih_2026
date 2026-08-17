import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../models/shop_details.dart';
import '../services/api_client.dart';
import '../services/printer_service.dart';
import '../providers/bill_provider.dart';
import '../features/gst/gst_invoice_preview_screen.dart';
import '../features/gst/models/gst_invoice_draft.dart';
import '../features/gst/providers/gst_provider.dart';
import 'bill_share_modal.dart';

class VoiceAssistantScreen extends StatefulWidget {
  final ShopDetails shopDetails;
  final Function(Map<String, dynamic>) onBillFinalized;
  final bool isPrinterConnected;
  final VoidCallback togglePrinter;

  const VoiceAssistantScreen({
    super.key,
    required this.shopDetails,
    required this.onBillFinalized,
    required this.isPrinterConnected,
    required this.togglePrinter,
  });

  @override
  State<VoiceAssistantScreen> createState() => _VoiceAssistantScreenState();
}

class _VoiceAssistantScreenState extends State<VoiceAssistantScreen> {
  late stt.SpeechToText _speech;
  late FlutterTts _flutterTts;

  // Session & Connection State
  bool _isSessionActive = false; // Toggled by user tapping voice circle
  String _sessionState = "IDLE"; // IDLE, LISTENING, PROCESSING, SPEAKING
  bool _isListening = false; // Tracks microphone listening state
  String _accumulatedText = "";
  String _currentSpeechChunk = "";
  String _aiResponseText = "Tap to Start";
  double _audioLevel = 0.0;
  Timer? _audioLevelTimer;
  final ApiClient _apiClient = ApiClient();

  // WebSocket
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  bool _isWsConnected = false;
  Timer? _reconnectTimer;
  Timer? _silenceTimer;
  Timer? _sttRestartTimer;

  // Streaming Response Buffer
  String _streamingResponse = "";
  bool _isStreaming = false;

  // Edit Mode State
  bool _isEditMode = false;

  // TTS Queue & Streaming State
  final List<String> _ttsQueue = [];
  int _lastSpokenIndex = 0;
  bool _isTtsSpeaking = false; // Whether TTS is currently playing audio
  bool _streamFinished = false; // Whether the complete response has arrived

  // MethodChannel for sound muting
  static const _volumeChannel = MethodChannel('com.vyamit.mykirana/volume');

  @override
  void initState() {
    super.initState();

    _speech = stt.SpeechToText();
    _flutterTts = FlutterTts();
    _initTts();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await context.read<GstProvider>().loadConfiguration();
      } catch (_) {
        // The existing voice billing flow remains available offline; a GST
        // action will still be rejected by the backend unless configured.
      }
    });
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _sttRestartTimer?.cancel();
    _speech.stop();
    _flutterTts.stop();
    _audioLevelTimer?.cancel();
    _reconnectTimer?.cancel();
    _wsSubscription?.cancel();
    _wsChannel?.sink.close();
    _unmuteSystemSounds();
    super.dispose();
  }

  /// Mute system sounds via MethodChannel to silence native speech beeps
  Future<void> _muteSystemSounds() async {
    try {
      await _volumeChannel.invokeMethod('muteSystemSounds');
      debugPrint('🔇 System sounds muted');
    } catch (e) {
      debugPrint('⚠️ Failed to mute system sounds: $e');
    }
  }

  /// Unmute system sounds via MethodChannel to restore volumes
  Future<void> _unmuteSystemSounds() async {
    try {
      await _volumeChannel.invokeMethod('unmuteSystemSounds');
      debugPrint('🔊 System sounds unmuted');
    } catch (e) {
      debugPrint('⚠️ Failed to unmute system sounds: $e');
    }
  }

  void _initTts() async {
    await _flutterTts.setLanguage("hi-IN");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.awaitSpeakCompletion(true);

    _flutterTts.setCompletionHandler(() {
      debugPrint('🔊 TTS sentence completed');
      _onSentenceCompleted();
    });

    _flutterTts.setErrorHandler((msg) {
      debugPrint('🔊 TTS error: $msg');
      _onSentenceCompleted();
    });
  }

  void _onSentenceCompleted() {
    if (!mounted) return;
    _isTtsSpeaking = false;

    // If more sentences in queue, continue
    if (_ttsQueue.isNotEmpty) {
      _processTtsQueue();
    } else {
      // All TTS finished, add delay to avoid echo pickup, then resume
      debugPrint('🔊 TTS queue empty, resuming listening after delay...');
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_isTtsSpeaking) {
          _processTtsQueue();
        }
      });
    }
  }

  Future<void> _processTtsQueue() async {
    if (!mounted || _isTtsSpeaking) return;

    if (_ttsQueue.isNotEmpty) {
      // STOP LISTENING to prevent feedback loop
      await _pauseListeningForTts();

      setState(() {
        _isTtsSpeaking = true;
        _sessionState = "SPEAKING";
      });
      String nextSentence = _ttsQueue.removeAt(0);
      debugPrint('🔊 Speaking sentence: "$nextSentence"');
      await _flutterTts.speak(nextSentence);
    } else if (_streamFinished) {
      debugPrint(
          '🔊 Queue finished and stream complete. Resuming listening...');
      _resumeListeningAfterTts();
    }
  }

  void _resumeListeningAfterTts() {
    if (!mounted || !_isSessionActive) return;

    // Add delay to avoid picking up residual TTS echo
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted || !_isSessionActive) return;

      setState(() {
        _sessionState = "LISTENING";
        _isTtsSpeaking = false;
        _accumulatedText = "";
        _currentSpeechChunk = "";
        _aiResponseText = "Listening...";
        _audioLevel = 0.3;
      });
      _startSpeechRecognition();
      _startAudioLevelAnimation();
    });
  }

  /// Pause speech recognition during TTS to prevent feedback loop
  Future<void> _pauseListeningForTts() async {
    if (_isListening) {
      debugPrint('🔇 Pausing STT for TTS playback');
      await _speech.stop();
      setState(() {
        _isListening = false;
      });
    }
  }

  /// Connect to backend Voice AI WebSocket stream
  Future<void> _connectWebSocket() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('user_token');

      final String wsEndpoint = '${ApiConfig.wsUrl}/voice/ws/stream';
      final Uri uri = Uri.parse(wsEndpoint).replace(
        queryParameters: {
          if (token != null) 'token': token,
        },
      );

      debugPrint('🔌 Connecting to Streaming Voice WebSocket: $uri');
      _wsChannel = WebSocketChannel.connect(uri);

      _wsSubscription?.cancel();
      _wsSubscription = _wsChannel!.stream.listen(
        (data) {
          _handleWebSocketMessage(data);
        },
        onError: (error) {
          debugPrint('❌ Voice WS Error: $error');
          if (mounted) setState(() => _isWsConnected = false);
          _scheduleWsReconnect();
        },
        onDone: () {
          debugPrint('🔌 Voice WS Connection Closed');
          if (mounted) setState(() => _isWsConnected = false);
          _scheduleWsReconnect();
        },
      );
    } catch (e) {
      debugPrint('❌ WS Connection exception: $e');
      _scheduleWsReconnect();
    }
  }

  void _scheduleWsReconnect() {
    if (!mounted || !_isSessionActive) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_isWsConnected && _isSessionActive) {
        debugPrint('🔄 Attempting Voice WS Reconnect...');
        _connectWebSocket();
      }
    });
  }

  void _handleWebSocketMessage(dynamic messageData) async {
    try {
      final Map<String, dynamic> data = jsonDecode(messageData.toString());
      final String type = data['type'] ?? '';

      debugPrint('📥 WS Message: type=$type');

      if (type == 'connected') {
        debugPrint('✅ Streaming Voice WS connected!');
        if (mounted) {
          setState(() {
            _isWsConnected = true;
            if (_sessionState == "IDLE") {
              _sessionState = "LISTENING";
              _aiResponseText = "Listening...";
            }
          });
        }
        return;
      }

      if (type == 'processing') {
        debugPrint('⏳ Backend processing...');
        if (mounted) {
          setState(() {
            _sessionState = "PROCESSING";
            _aiResponseText = data['msg'] ?? "Thinking...";
            _isStreaming = false;
            _streamingResponse = "";
          });
        }
        return;
      }

      if (type == 'stream_token') {
        final String token = data['token'] ?? '';
        final String accumulated = data['accumulated'] ?? '';

        if (mounted) {
          setState(() {
            _isStreaming = true;
            _streamingResponse = accumulated;
          });

          final partialMsg = _extractStreamingMsg(accumulated);
          if (partialMsg != null && partialMsg.isNotEmpty) {
            final newSentences = _getNewSentences(partialMsg, _lastSpokenIndex);
            for (var sentence in newSentences) {
              _ttsQueue.add(sentence);
              _lastSpokenIndex += sentence.length;
            }
            if (newSentences.isNotEmpty) {
              _processTtsQueue();
            }

            setState(() {
              _aiResponseText = partialMsg.length > 100
                  ? partialMsg.substring(0, 100) + '...'
                  : partialMsg;
            });
          }
        }
        return;
      }

      if (type == 'complete') {
        debugPrint('✅ Stream complete');
        final Map<String, dynamic> response = data['response'] ?? {};
        String customerName = response['customer_name'] ?? "Walk-in";
        final billProvider = Provider.of<BillProvider>(context, listen: false);
        final gstProvider = Provider.of<GstProvider>(context, listen: false);
        final customer = response['customer'] is Map
            ? Map<String, dynamic>.from(response['customer'] as Map)
            : const <String, dynamic>{};

        if (customerName != "Walk-in") {
          billProvider.setCustomerName(customerName);
          debugPrint("👤 Customer name set: $customerName");
        }
        if (gstProvider.isCurrentBillGstEnabled) {
          gstProvider.setCustomerTaxDetails(
            gstin: customer['gstin']?.toString(),
            stateCode: customer['state_code']?.toString(),
          );
        }

        if (response['type'] == 'BILL') {
          List<dynamic> newItems = response['items'] ?? [];
          debugPrint("🎤 VOICE WS returned ${newItems.length} items");

          for (var item in newItems) {
            String qtyDisplay = item['qty_display']?.toString() ?? '1kg';
            String qty = item['qty']?.toString() ?? '1';
            String unit = item['unit']?.toString() ?? 'kg';

            if (qtyDisplay == '1kg' && (qty != '1' || unit != 'kg')) {
              qtyDisplay = '$qty$unit';
            }

            final normalizedItem = {
              'name':
                  item['name'] ?? item['en'] ?? item['item_name'] ?? 'Unknown',
              'en':
                  item['en'] ?? item['name'] ?? item['item_name'] ?? 'Unknown',
              'hi':
                  item['hi'] ?? item['name'] ?? item['item_name'] ?? 'Unknown',
              'qty': qty,
              'qty_display': qtyDisplay,
              'rate': _asDouble(
                  item['rate'] ?? item['price'] ?? item['unit_price']),
              'total': _asDouble(item['total'] ?? item['line_total']),
              'unit': unit,
              'gst_rate': _asDouble(item['gst_rate'] ?? item['gstRate']),
              if (item['hsn_code'] != null) 'hsn_code': item['hsn_code'],
              if (item['tax_category'] != null)
                'tax_category': item['tax_category'],
            };

            billProvider.addBillItem(normalizedItem);
          }
        }

        final String finalMsg = response['msg'] ?? '';
        setState(() {
          _streamFinished = true;
          _isStreaming = false;
          _streamingResponse = "";
        });

        if (finalMsg.isNotEmpty) {
          if (_lastSpokenIndex < finalMsg.length) {
            String remainingText = finalMsg.substring(_lastSpokenIndex).trim();
            if (remainingText.isNotEmpty) {
              _ttsQueue.add(remainingText);
            }
          }
          setState(() {
            _aiResponseText = finalMsg;
          });
          _processTtsQueue();
        } else {
          _resumeListeningAfterTts();
        }

        return;
      }

      if (type == 'error') {
        debugPrint('❌ WS Error: ${data['message']}');
        if (mounted) {
          setState(() {
            _aiResponseText = "Error: ${data['message']}";
            _isStreaming = false;
            _streamingResponse = "";
          });
        }
        _resumeListeningAfterTts();
        return;
      }
    } catch (e) {
      debugPrint("❌ Error parsing WS message: $e");
      _resumeListeningAfterTts();
    }
  }

  /// Helper: Extract the `"msg"` string from a partial or full JSON string
  String? _extractStreamingMsg(String partialJson) {
    // Look for closed "msg" field
    final regExp = RegExp(r'"msg"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)"?');
    final matches = regExp.allMatches(partialJson);
    if (matches.isNotEmpty) {
      final match = matches.last;
      String val = match.group(1) ?? '';
      val = val.replaceAll(r'\"', '"').replaceAll(r'\n', '\n');
      return val;
    }

    // Look for open "msg" field
    final openRegExp = RegExp(r'"msg"\s*:\s*"([^"\\]*(?:\\.[^"\\]*)*)$');
    final openMatch = openRegExp.firstMatch(partialJson);
    if (openMatch != null) {
      String val = openMatch.group(1) ?? '';
      val = val.replaceAll(r'\"', '"').replaceAll(r'\n', '\n');
      return val;
    }

    return null;
  }

  /// Helper: Split text into completed sentences starting from startIndex
  List<String> _getNewSentences(String text, int startIndex) {
    List<String> sentences = [];
    int currentPos = startIndex;

    while (currentPos < text.length) {
      int nextDelim = -1;
      int delimLen = 1;

      for (int i = currentPos; i < text.length; i++) {
        String char = text[i];
        if (char == '।' || char == '?' || char == '!' || char == '\n') {
          nextDelim = i;
          break;
        } else if (char == '.') {
          // Ignore decimal points in numbers
          bool isDecimal = false;
          if (i > 0 && i < text.length - 1) {
            bool isPrevDigit = _isDigit(text[i - 1]);
            bool isNextDigit = _isDigit(text[i + 1]);
            if (isPrevDigit && isNextDigit) {
              isDecimal = true;
            }
          }
          if (!isDecimal) {
            nextDelim = i;
            break;
          }
        }
      }

      if (nextDelim != -1) {
        String sentence =
            text.substring(currentPos, nextDelim + delimLen).trim();
        if (sentence.isNotEmpty) {
          sentences.add(sentence);
        }
        currentPos = nextDelim + delimLen;
      } else {
        break;
      }
    }
    return sentences;
  }

  bool _isDigit(String s) {
    if (s.isEmpty) return false;
    return s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;
  }

  /// Interrupt active TTS playback (mute TTS speaking for this time)
  Future<void> _interruptTts() async {
    if (!_isTtsSpeaking &&
        _sessionState != "PROCESSING" &&
        _sessionState != "SPEAKING") return;

    debugPrint("🎙️ Interruption triggered - muting/stopping TTS playback");

    _ttsQueue.clear();
    _lastSpokenIndex = 0;
    _isTtsSpeaking = false;
    _streamFinished = false;

    await _flutterTts.stop();

    setState(() {
      _sessionState = "LISTENING";
      _isListening = true;
      _accumulatedText = "";
      _currentSpeechChunk = "";
      _aiResponseText = "Listening...";
      _isStreaming = false;
      _streamingResponse = "";
      _audioLevel = 0.3;
    });

    _startSpeechRecognition();
  }

  /// Reset entire voice page
  void _resetVoicePage() {
    _stopContinuousSession();

    final billProvider = Provider.of<BillProvider>(context, listen: false);
    billProvider.clearBill();
    Provider.of<GstProvider>(context, listen: false).resetCurrentBill();

    setState(() {
      if (_isEditMode) {
        _isEditMode = false;
      }
    });

    debugPrint('🔄 Voice page reset');
  }

  /// Get display text for current speech chunk
  String _getDisplayText() {
    final fullText = (_accumulatedText + ' ' + _currentSpeechChunk).trim();

    if (fullText.isEmpty) {
      if (_sessionState == "LISTENING") return "Listening...";
      if (_sessionState == "PROCESSING") return "Processing speech...";
      if (_sessionState == "SPEAKING") return "Vyamit AI Speaking...";
      return "Tap to Start Call Session";
    }

    final words = fullText.split(' ');
    if (words.length <= 15) {
      return fullText;
    }

    final lastWords = words.sublist(words.length - 15);
    return lastWords.join(' ');
  }

  /// Toggle continuous conversation call session

  void _toggleListening() async {
    if (_isSessionActive) {
      await _stopContinuousSession();
    } else {
      await _startContinuousSession();
    }
  }

  /// Start Continuous Hands-Free Call Session
  Future<void> _startContinuousSession() async {
    await _muteSystemSounds();
    await _connectWebSocket();

    bool available = await _speech.initialize(
      onError: (val) {
        debugPrint('🎤 STT Error: ${val.errorMsg}');
        final isTransient =
            val.errorMsg.contains('busy') || val.errorMsg.contains('timeout');
        if (_isSessionActive &&
            _sessionState == "LISTENING" &&
            !val.errorMsg.toLowerCase().contains('permission') &&
            !isTransient) {
          _scheduleSttRestart();
        } else if (val.errorMsg.toLowerCase().contains('permission')) {
          _stopContinuousSession();
          setState(() {
            _aiResponseText = "Microphone permission denied";
          });
        }
      },
      onStatus: (status) {
        debugPrint('🎤 STT Status: $status');
        if (_isSessionActive &&
            _sessionState == "LISTENING" &&
            (status == 'done' || status == 'notListening')) {
          _scheduleSttRestart();
        }
      },
    );

    if (available) {
      setState(() {
        _isSessionActive = true;
        _sessionState = "LISTENING";
        _isListening = true;
        _accumulatedText = "";
        _currentSpeechChunk = "";
        _aiResponseText = "Listening...";
        _audioLevel = 0.3;

        _ttsQueue.clear();
        _lastSpokenIndex = 0;
        _isTtsSpeaking = false;
        _streamFinished = false;
        _streamingResponse = "";
        _isStreaming = false;
      });

      await _startSpeechRecognition();
      _startAudioLevelAnimation();
      debugPrint('🎙️ Continuous Hands-Free Session Started');
    } else {
      debugPrint('❌ Speech recognition not available');
      setState(() {
        _aiResponseText = "Speech recognition not available";
      });
      await _unmuteSystemSounds();
    }
  }

  /// Schedule seamless STT restart — only when in LISTENING state
  void _scheduleSttRestart() {
    if (!_isSessionActive || !mounted) return;
    if (_sessionState != "LISTENING") return;
    _sttRestartTimer?.cancel();
    _sttRestartTimer = Timer(const Duration(milliseconds: 600), () {
      if (_isSessionActive && mounted && _sessionState == "LISTENING") {
        debugPrint('🔄 Auto-restarting continuous STT...');
        _startSpeechRecognition();
      }
    });
  }

  /// Internal speech recognition start — guarded by LISTENING state
  Future<void> _startSpeechRecognition() async {
    if (!_isSessionActive || !mounted) return;
    if (_sessionState != "LISTENING") return;

    if (_speech.isListening) return;

    try {
      if (!_speech.isAvailable) {
        await _speech.initialize();
      }

      await _speech.listen(
        onResult: _handleSpeechResult,
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        localeId: 'hi_IN',
        cancelOnError: false,
        listenFor: const Duration(minutes: 10),
        pauseFor: const Duration(
            seconds: 10), // Keep active longer to avoid stop-start beeps
      );

      debugPrint('`✅ Speech recognition listening continuously...');
    } catch (e) {
      debugPrint('❌ Listen error: $e');
      if (_sessionState == "LISTENING") _scheduleSttRestart();
    }
  }

  /// Audio level animation for orb
  void _startAudioLevelAnimation() {
    _audioLevelTimer?.cancel();

    _audioLevelTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (timer) {
        if (!_isListening) {
          timer.cancel();
          return;
        }

        setState(() {
          if (_currentSpeechChunk.isNotEmpty) {
            _audioLevel = 0.6 + (0.4 * (timer.tick % 10) / 10);
          } else {
            _audioLevel = 0.3 + (0.2 * (timer.tick % 10) / 10);
          }
        });
      },
    );
  }

  /// Handle speech results with silence boundary auto-dispatch & barge-in check
  void _handleSpeechResult(result) {
    if (!_isSessionActive || !mounted) return;

    final recognizedWords = result.recognizedWords.trim();
    if (recognizedWords.isEmpty) return;

    // Check for barge-in (interruption) during processing or playback
    if (_isTtsSpeaking ||
        _sessionState == "PROCESSING" ||
        _sessionState == "SPEAKING") {
      if (recognizedWords.length >= 2) {
        _interruptTts();
        return;
      }
    }

    setState(() {
      _currentSpeechChunk = recognizedWords;
      _audioLevel = 0.7;
    });

    _silenceTimer?.cancel();

    // Dispatch speech after 1.5s of silence
    _silenceTimer = Timer(const Duration(milliseconds: 1500), () {
      final fullText = (_accumulatedText + ' ' + _currentSpeechChunk).trim();
      if (fullText.isNotEmpty &&
          _isSessionActive &&
          _sessionState == "LISTENING") {
        _dispatchSpeechUtterance(fullText);
      }
    });
  }

  /// Auto-dispatch speech utterance over WebSocket
  Future<void> _dispatchSpeechUtterance(String text) async {
    if (text.trim().isEmpty || !_isSessionActive) return;

    _silenceTimer?.cancel();
    _sttRestartTimer?.cancel();

    setState(() {
      _sessionState = "PROCESSING";
      _isListening = false;
      _accumulatedText = text;
      _currentSpeechChunk = "";
      _aiResponseText = "Thinking...";
      _audioLevel = 0.0;
    });

    debugPrint('🚀 Auto-Dispatched Utterance: "$text"');
    await _processAiRequest(text);
  }

  /// Stop Continuous Hands-Free Session
  Future<void> _stopContinuousSession() async {
    _silenceTimer?.cancel();
    _sttRestartTimer?.cancel();
    _reconnectTimer?.cancel();
    await _speech.stop();
    await _flutterTts.stop();
    _audioLevelTimer?.cancel();

    _wsSubscription?.cancel();
    await _wsChannel?.sink.close();
    _wsChannel = null;
    _isWsConnected = false;

    await _unmuteSystemSounds();

    setState(() {
      _isSessionActive = false;
      _sessionState = "IDLE";
      _isListening = false;
      _isTtsSpeaking = false;
      _accumulatedText = "";
      _currentSpeechChunk = "";
      _aiResponseText = "Tap to Start";
      _audioLevel = 0.0;

      _ttsQueue.clear();
      _lastSpokenIndex = 0;
      _streamFinished = false;
      _streamingResponse = "";
      _isStreaming = false;
    });

    debugPrint('🛑 Continuous Call Session Stopped');
  }

  Future<void> _processAiRequest(String text) async {
    if (text.trim().isEmpty) return;

    setState(() {
      _aiResponseText = "Thinking...";
      _isStreaming = false;
      _streamingResponse = "";
      _ttsQueue.clear();
      _lastSpokenIndex = 0;
      _streamFinished = false;
    });

    if (_wsChannel != null && _isWsConnected) {
      try {
        final payload = jsonEncode({
          "action": "process",
          "text": text,
          "gst_mode": Provider.of<GstProvider>(context, listen: false)
              .isCurrentBillGstEnabled,
        });
        debugPrint("📤 Sending Voice Command: $text");

        _wsChannel!.sink.add(payload);
        return;
      } catch (e) {
        debugPrint("❌ Failed to send over WS: $e");
      }
    }

    debugPrint("⚠️ WS disconnected, falling back to HTTP POST");
    await _processAiRequestHttpFallback(text);
  }

  Future<void> _processAiRequestHttpFallback(String text) async {
    try {
      final data = await _apiClient.post('/voice/process', {
        "text": text,
        "shop_category": widget.shopDetails.shopCategory,
        "gst_mode": Provider.of<GstProvider>(context, listen: false)
            .isCurrentBillGstEnabled,
      });

      String customerName = data['customer_name'] ?? "Walk-in";
      final billProvider = Provider.of<BillProvider>(context, listen: false);
      final gstProvider = Provider.of<GstProvider>(context, listen: false);
      final customer = data['customer'] is Map
          ? Map<String, dynamic>.from(data['customer'] as Map)
          : const <String, dynamic>{};

      if (customerName != "Walk-in") {
        billProvider.setCustomerName(customerName);
        debugPrint("👤 Customer name set: $customerName");
      }
      if (gstProvider.isCurrentBillGstEnabled) {
        gstProvider.setCustomerTaxDetails(
          gstin: customer['gstin']?.toString(),
          stateCode: customer['state_code']?.toString(),
        );
      }

      String? msg = data['msg'];
      if (msg != null && msg.isNotEmpty) {
        setState(() {
          _sessionState = "SPEAKING";
          _aiResponseText = msg;
          _ttsQueue.clear();
          _lastSpokenIndex = 0;
          _streamFinished = true;
        });
        _ttsQueue.add(msg);
        _processTtsQueue();
      } else {
        _resumeListeningAfterTts();
      }

      if (data['type'] == 'BILL') {
        List<dynamic> newItems = data['items'] ?? [];
        debugPrint("🎤 VOICE API returned ${newItems.length} items");

        for (var item in newItems) {
          String qtyDisplay = item['qty_display']?.toString() ?? '1kg';
          String qty = item['qty']?.toString() ?? '1';
          String unit = item['unit']?.toString() ?? 'kg';

          if (qtyDisplay == '1kg' && (qty != '1' || unit != 'kg')) {
            qtyDisplay = '$qty$unit';
          }

          final normalizedItem = {
            'name':
                item['name'] ?? item['en'] ?? item['item_name'] ?? 'Unknown',
            'en': item['en'] ?? item['name'] ?? item['item_name'] ?? 'Unknown',
            'hi': item['hi'] ?? item['name'] ?? item['item_name'] ?? 'Unknown',
            'qty': qty,
            'qty_display': qtyDisplay,
            'rate':
                _asDouble(item['rate'] ?? item['price'] ?? item['unit_price']),
            'total': _asDouble(item['total'] ?? item['line_total']),
            'unit': unit,
            'gst_rate': _asDouble(item['gst_rate'] ?? item['gstRate']),
            if (item['hsn_code'] != null) 'hsn_code': item['hsn_code'],
            if (item['tax_category'] != null)
              'tax_category': item['tax_category'],
          };

          billProvider.addBillItem(normalizedItem);
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
      setState(() => _aiResponseText = "Server Error");
      _resumeListeningAfterTts();
    }
  }

  void _finalizeBill() async {
    final billProvider = Provider.of<BillProvider>(context, listen: false);
    final gstProvider = Provider.of<GstProvider>(context, listen: false);

    // DEBUG: Check if bill has items
    if (!billProvider.hasBillItems) {
      debugPrint("❌ VOICE BILL: Bill is empty - cannot print");
      return;
    }

    if (gstProvider.isCurrentBillGstEnabled) {
      final printed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => GstInvoicePreviewScreen(
            initialDraft: GstInvoiceDraft.fromLiveBill(
              billItems: List<Map<String, dynamic>>.from(
                billProvider.currentBillItems,
              ),
              customerName: billProvider.customerName,
              customerGstin: gstProvider.customerGstin,
              customerStateCode: gstProvider.customerStateCode,
            ),
            shopDetails: widget.shopDetails,
            isPrinterConnected: widget.isPrinterConnected,
            togglePrinter: widget.togglePrinter,
          ),
        ),
      );
      if (printed == true && mounted) {
        await _stopContinuousSession();
        billProvider.clearBill();
        setState(() => _aiResponseText = 'GST invoice printed');
      }
      return;
    }

    debugPrint(
        "✅ VOICE BILL: Has ${billProvider.currentBillItems.length} items");
    debugPrint("👤 Customer: ${billProvider.customerName}");

    // DEBUG: Print each item structure
    for (var item in billProvider.currentBillItems) {
      debugPrint("VOICE ITEM: $item");
    }

    // Check printer connection in real-time
    final isConnected = await PrinterService().isConnected();
    if (!isConnected) {
      _flutterTts.speak("Printer connected nahi hai"); // Speak warning
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ Connect Printer First!"),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      widget.togglePrinter();
      return;
    }

    // Speak confirmation
    _flutterTts.speak("Bill print ho raha hai");

    // Get next bill number
    final billNumber = await billProvider.getNextBillNumber();

    // CRITICAL: Create a COPY of items before clearing
    final itemsCopy =
        List<Map<String, dynamic>>.from(billProvider.currentBillItems);

    final billData = {
      'id': billNumber,
      'date':
          "${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}",

      'time': "${DateTime.now().hour}:${DateTime.now().minute}",
      'total': billProvider.billTotal,
      'customerName': billProvider.customerName, // Add customer name
      'shopName': widget.shopDetails.shopName,
      'shopAddress': widget.shopDetails.address,
      'shopPhone': widget.shopDetails.phone1,
      'items': itemsCopy, // Use the copy, not the reference
    };

    debugPrint("✅ VOICE BILL DATA: $billData");
    final itemsList = billData['items'] as List;
    debugPrint("✅ VOICE BILL ITEMS COUNT: ${itemsList.length}");

    widget.onBillFinalized(billData);

    // Stop session when bill is printed (off automatically)
    await _stopContinuousSession();

    // Clear bill after printing
    billProvider.clearBill();
    setState(() {
      _aiResponseText = "Bill Printed!";
    });
  }

  void _openShareModal(BillProvider billProvider) {
    if (!billProvider.hasBillItems) return;

    // Get current bill items
    final billItems =
        List<Map<String, dynamic>>.from(billProvider.currentBillItems);
    final totalAmount = billProvider.billTotal;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BillShareModal(
          billItems: billItems,
          totalAmount: totalAmount,
          shopDetails: widget.shopDetails,
          customerName: billProvider.customerName,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  // Helper: Format number without .0 for whole numbers
  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatNumber(double value) {
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  // Helper: Extract numeric quantity from qtyDisplay (e.g., "2kg" -> "2")
  String _extractQuantityNumber(String qtyDisplay) {
    final numericPart = qtyDisplay.replaceAll(RegExp(r'[^0-9.]'), '');
    return numericPart.isEmpty ? '1' : numericPart;
  }

  // Helper: Extract unit from qtyDisplay (e.g., "2kg" -> "kg")
  String _extractUnit(String qtyDisplay) {
    final unitPart = qtyDisplay.replaceAll(RegExp(r'[0-9.]'), '').trim();
    return unitPart.isEmpty ? 'kg' : unitPart;
  }

  // Helper: Format rate with unit (e.g., rate=30, qtyDisplay="2plt" -> "₹30/plt")
  String _formatRateWithUnit(double rate, String qtyDisplay) {
    final unit = _extractUnit(qtyDisplay);
    return '₹${_formatNumber(rate)}/$unit';
  }

  // Helper: Format quantity display with smart kg/gm conversion
  String _formatQuantityDisplay(String qtyDisplay) {
    // First apply short unit names
    String result = qtyDisplay;

    result = result.replaceAll('dozen', 'doz');
    result = result.replaceAll('plate', 'plt');
    result = result.replaceAll('pieces', 'pic');
    result = result.replaceAll('pics', 'pic');
    result = result.replaceAll('litre', 'lit');
    result = result.replaceAll('liter', 'lit');

    // Smart kg/gm conversion
    // Extract number and unit from string like "0.4kg" or "1.2 kg"
    final RegExp kgPattern = RegExp(r'(\d+\.?\d*)\s*kg', caseSensitive: false);
    final match = kgPattern.firstMatch(result);

    if (match != null) {
      double kgValue = double.tryParse(match.group(1) ?? '0') ?? 0;

      // If < 1kg, convert to grams
      if (kgValue > 0 && kgValue < 1) {
        int grams = (kgValue * 1000).round();
        result = result.replaceFirst(kgPattern, '${grams}gm');
      }
      // If > 1kg but has decimal, convert fully to grams
      else if (kgValue > 1 && kgValue != kgValue.toInt()) {
        int grams = (kgValue * 1000).round();
        result = result.replaceFirst(kgPattern, '${grams}gm');
      }
      // If whole kg, keep as is
    }

    // Convert large grams to kg (e.g., 2000gm -> 2kg)
    final RegExp gmPattern = RegExp(r'(\d+)\s*gm', caseSensitive: false);
    final gmMatch = gmPattern.firstMatch(result);

    if (gmMatch != null) {
      int gmValue = int.tryParse(gmMatch.group(1) ?? '0') ?? 0;
      if (gmValue >= 1000 && gmValue % 1000 == 0) {
        int kgValue = gmValue ~/ 1000;
        result = result.replaceFirst(gmPattern, '${kgValue}kg');
      }
    }

    return result;
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
    });
    if (!_isEditMode) {
      // Close keyboard when exiting edit mode
      FocusScope.of(context).unfocus();
    }
  }

  void _addManualItem(BillProvider billProvider) {
    // Add empty item and enter edit mode
    final newItem = {
      'name': 'New Item',
      'en': 'New Item',
      'hi': 'New Item',
      'qty': '1',
      'qty_display': '1kg',
      'rate': 0.0,
      'total': 0.0,
      'unit': 'kg',
      'gst_rate': 0.0,
    };

    billProvider.addBillItem(newItem);

    if (!_isEditMode) {
      setState(() {
        _isEditMode = true;
      });
    }
  }

  void _updateBillItem(
      int index, String field, String value, BillProvider billProvider) {
    final items =
        List<Map<String, dynamic>>.from(billProvider.currentBillItems);
    final item = Map<String, dynamic>.from(items[index]);

    if (field == 'name') {
      item['name'] = value;
      item['en'] = value;
      item['hi'] = value;
    } else if (field == 'qty_display') {
      item['qty_display'] = value;
      // Extract numeric part for qty field
      final numericQty = value.replaceAll(RegExp(r'[^0-9.]'), '');
      item['qty'] = numericQty;
      // Recalculate total
      final rate = (item['rate'] as num).toDouble();
      final qty = double.tryParse(numericQty) ?? 1.0;
      item['total'] = rate * qty;
    } else if (field == 'rate') {
      final rate = double.tryParse(value) ?? 0.0;
      item['rate'] = rate;
      // Recalculate total
      final qtyStr =
          item['qty_display'].toString().replaceAll(RegExp(r'[^0-9.]'), '');
      final qty = double.tryParse(qtyStr) ?? 1.0;
      item['total'] = rate * qty;
    }

    items[index] = item;
    billProvider.updateBillItems(items);
  }

  // Computed total - always derived from items
  double _computeTotal(List<Map<String, dynamic>> items) {
    return items.fold<double>(
      0,
      (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0),
    );
  }

  double _gstTaxableValue(Map<String, dynamic> item) {
    final quantity = _asDouble(item['qty']);
    final safeQuantity = quantity > 0 ? quantity : 1;
    return _asDouble(item['rate']) * safeQuantity;
  }

  double _gstLineTax(Map<String, dynamic> item) =>
      _gstTaxableValue(item) *
      _asDouble(item['gst_rate']).clamp(0, 40).toDouble() /
      100;

  double _gstLineTotal(Map<String, dynamic> item) =>
      _gstTaxableValue(item) + _gstLineTax(item);

  double _gstBillTotal(List<Map<String, dynamic>> items) =>
      items.fold<double>(0, (sum, item) => sum + _gstLineTotal(item));

  @override
  Widget build(BuildContext context) {
    final gstProvider = context.watch<GstProvider>();
    return Consumer<BillProvider>(
      builder: (context, billProvider, child) {
        final currentBill = billProvider.currentBillItems;

        return Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Column(
              children: [
                // 1. Header - Fixed overflow
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    const SizedBox(width: 48),
                    Expanded(
                      child: Text(widget.shopDetails.shopName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                        icon: Icon(Icons.print,
                            color: widget.isPrinterConnected
                                ? AppColors.printerConnected
                                : AppColors.printerDisconnected),
                        onPressed: widget.togglePrinter),
                  ]),
                ),

                // 2. Voice Circle - Premium interactive design
                if (!_isEditMode)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Interactive voice circle stack
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Dynamic ripples when active
                            if (_isSessionActive) ...[
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 500),
                                height: 160 + (_audioLevel * 20),
                                width: 160 + (_audioLevel * 20),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: (_sessionState == "LISTENING"
                                            ? Colors.green
                                            : (_sessionState == "PROCESSING"
                                                ? Colors.blue
                                                : Colors.teal))
                                        .withOpacity(0.2),
                                    width: 2,
                                  ),
                                ),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                height: 140 + (_audioLevel * 10),
                                width: 140 + (_audioLevel * 10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: (_sessionState == "LISTENING"
                                            ? Colors.green
                                            : (_sessionState == "PROCESSING"
                                                ? Colors.blue
                                                : Colors.teal))
                                        .withOpacity(0.3),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ],

                            // Main interactive circle
                            AnimatedScale(
                              scale: _isSessionActive
                                  ? 1.0 + (_audioLevel * 0.12)
                                  : 1.0,
                              duration: const Duration(milliseconds: 100),
                              child: GestureDetector(
                                onTap: _toggleListening,
                                child: Container(
                                  height: 120,
                                  width: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: _isSessionActive
                                        ? LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: _sessionState == "LISTENING"
                                                ? [
                                                    Colors.green.shade700,
                                                    Colors.green.shade500
                                                  ]
                                                : (_sessionState == "PROCESSING"
                                                    ? [
                                                        Colors.blue.shade700,
                                                        Colors.blue.shade500
                                                      ]
                                                    : [
                                                        Colors.teal.shade700,
                                                        Colors.teal.shade500
                                                      ]),
                                          )
                                        : null,
                                    color:
                                        _isSessionActive ? null : Colors.white,
                                    border: Border.all(
                                      color: _isSessionActive
                                          ? Colors.transparent
                                          : Colors.grey.shade300,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      if (_isSessionActive)
                                        BoxShadow(
                                          color: (_sessionState == "LISTENING"
                                                  ? Colors.green
                                                  : (_sessionState ==
                                                          "PROCESSING"
                                                      ? Colors.blue
                                                      : Colors.teal))
                                              .withOpacity(0.4),
                                          blurRadius: 30,
                                          spreadRadius: 4,
                                        )
                                      else
                                        const BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                    ],
                                  ),
                                  child: Icon(
                                    !_isSessionActive
                                        ? Icons.mic
                                        : (_sessionState == "LISTENING"
                                            ? Icons.graphic_eq
                                            : (_sessionState == "PROCESSING"
                                                ? Icons.insights
                                                : Icons.volume_up)),
                                    size: 50,
                                    color: _isSessionActive
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 15),

                        // Status Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: (!_isSessionActive
                                    ? Colors.grey
                                    : (_sessionState == "LISTENING"
                                        ? Colors.green
                                        : (_sessionState == "PROCESSING"
                                            ? Colors.blue
                                            : Colors.teal)))
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: (!_isSessionActive
                                      ? Colors.grey
                                      : (_sessionState == "LISTENING"
                                          ? Colors.green
                                          : (_sessionState == "PROCESSING"
                                              ? Colors.blue
                                              : Colors.teal)))
                                  .withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: !_isSessionActive
                                      ? Colors.grey
                                      : (_sessionState == "LISTENING"
                                          ? Colors.green
                                          : (_sessionState == "PROCESSING"
                                              ? Colors.blue
                                              : Colors.teal)),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                !_isSessionActive
                                    ? 'Offline'
                                    : (_sessionState == "LISTENING"
                                        ? 'Listening...'
                                        : (_sessionState == "PROCESSING"
                                            ? 'Thinking...'
                                            : 'AI Speaking...')),
                                style: TextStyle(
                                  color: !_isSessionActive
                                      ? Colors.grey.shade700
                                      : (_sessionState == "LISTENING"
                                          ? Colors.green.shade700
                                          : (_sessionState == "PROCESSING"
                                              ? Colors.blue.shade700
                                              : Colors.teal.shade700)),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),

// Speech Text - SINGLE LINE with fixed height
                        SizedBox(
                          height: 20,
                          child: Text(
                            _getDisplayText(),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ),

                        // Response Text - SINGLE LINE with fixed height and streaming indicator
                        SizedBox(
                          height: 24,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (_isStreaming)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          AppColors.primaryGreen),
                                    ),
                                  ),
                                ),
                              Flexible(
                                child: Text(
                                  _aiResponseText,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                // Live Bill retains the established white card, colours, shadow,
                // add/edit affordance, and footer. GST is an additive toggle only.
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 20,
                          offset: Offset(0, -5),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          child: Row(
                            children: [
                              const Text(
                                'Live Bill',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              if (gstProvider.isShopGstEnabled) ...[
                                const SizedBox(width: 10),
                                Semantics(
                                  button: true,
                                  label: gstProvider.isCurrentBillGstEnabled
                                      ? 'Turn off GST invoice mode'
                                      : 'Turn on GST invoice mode',
                                  child: GestureDetector(
                                    onTap: () =>
                                        gstProvider.setCurrentBillGstEnabled(
                                      !gstProvider.isCurrentBillGstEnabled,
                                    ),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 160),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            gstProvider.isCurrentBillGstEnabled
                                                ? AppColors.primaryGreen
                                                : Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: gstProvider
                                                  .isCurrentBillGstEnabled
                                              ? AppColors.primaryGreen
                                              : Colors.grey.shade300,
                                        ),
                                      ),
                                      child: Text(
                                        'GST',
                                        style: TextStyle(
                                          color: gstProvider
                                                  .isCurrentBillGstEnabled
                                              ? Colors.white
                                              : Colors.grey.shade700,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const Spacer(),
                              // Keep the original short Cancel action visible on
                              // narrow phones, followed by the existing Add/Edit control.
                              TextButton.icon(
                                onPressed: _resetVoicePage,
                                icon: const Icon(Icons.refresh,
                                    size: 16, color: Colors.red),
                                label: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12),
                                ),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                onPressed: () {
                                  if (currentBill.isEmpty) {
                                    _addManualItem(billProvider);
                                  } else {
                                    _toggleEditMode();
                                  }
                                },
                                icon: Icon(
                                  currentBill.isEmpty
                                      ? Icons.add
                                      : (_isEditMode
                                          ? Icons.close
                                          : Icons.edit),
                                  size: 18,
                                  color: AppColors.primaryGreen,
                                ),
                                style: IconButton.styleFrom(
                                  backgroundColor:
                                      AppColors.primaryGreen.withOpacity(0.1),
                                  padding: const EdgeInsets.all(6),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                tooltip: currentBill.isEmpty
                                    ? 'Add item'
                                    : (_isEditMode
                                        ? 'Close editing'
                                        : 'Edit bill'),
                              ),
                            ],
                          ),
                        ),

                        // GST mode retains readable columns on a narrow phone
                        // screen while showing the tax-aware line total.
                        Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 5),
                            child: Row(
                                children: gstProvider.isCurrentBillGstEnabled
                                    ? const [
                                        Expanded(
                                            flex: 4,
                                            child: Text('Item',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: Colors.grey))),
                                        Expanded(
                                            flex: 2,
                                            child: Text('Qty',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: Colors.grey))),
                                        Expanded(
                                            flex: 2,
                                            child: Text('GST',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: Colors.grey))),
                                        Expanded(
                                            flex: 3,
                                            child: Text('Total',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: Colors.grey))),
                                      ]
                                    : const [
                                        Expanded(
                                            flex: 4,
                                            child: Text('Item',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: Colors.grey))),
                                        Expanded(
                                            flex: 1,
                                            child: Text('Qty',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: Colors.grey))),
                                        Expanded(
                                            flex: 3,
                                            child: Text('Rate',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: Colors.grey))),
                                        Expanded(
                                            flex: 2,
                                            child: Text('Total',
                                                textAlign: TextAlign.right,
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: Colors.grey))),
                                      ])),
                        const Divider(height: 1),

                        // List Items
                        Expanded(
                            child: currentBill.isEmpty
                                ? const Center(
                                    child: Text(
                                        "Tap + to add items manually\nor say 'Chawal 1kg'",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey)))
                                : ListView.separated(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 10),
                                    itemCount: currentBill.length +
                                        (_isEditMode ? 1 : 0),
                                    separatorBuilder: (_, __) =>
                                        const Divider(height: 16),
                                    itemBuilder: (context, index) {
                                      // Add Item Button at the end in Edit Mode
                                      if (_isEditMode &&
                                          index == currentBill.length) {
                                        return GestureDetector(
                                          onTap: () =>
                                              _addManualItem(billProvider),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryGreen
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: AppColors.primaryGreen
                                                    .withOpacity(0.3),
                                                style: BorderStyle.solid,
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.add,
                                                    color:
                                                        AppColors.primaryGreen,
                                                    size: 20),
                                                SizedBox(width: 8),
                                                Text(
                                                  "Add Item",
                                                  style: TextStyle(
                                                    color:
                                                        AppColors.primaryGreen,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }

                                      final item = currentBill[index];

                                      if (_isEditMode) {
                                        // Editable Mode
                                        return Row(children: [
                                          GestureDetector(
                                              onTap: () => billProvider
                                                  .removeBillItem(index),
                                              child: Container(
                                                  margin: const EdgeInsets.only(
                                                      right: 8),
                                                  padding:
                                                      const EdgeInsets.all(2),
                                                  decoration: BoxDecoration(
                                                      color: Colors.red[50],
                                                      shape: BoxShape.circle),
                                                  child: const Icon(
                                                      Icons.remove,
                                                      size: 16,
                                                      color: Colors.red))),
                                          Expanded(
                                              flex: 4,
                                              child: TextField(
                                                controller:
                                                    TextEditingController(
                                                        text: item['name'])
                                                      ..selection = TextSelection
                                                          .collapsed(
                                                              offset:
                                                                  item['name']
                                                                      .length),
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14),
                                                decoration:
                                                    const InputDecoration(
                                                  isDense: true,
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                          vertical: 8,
                                                          horizontal: 4),
                                                  border: OutlineInputBorder(),
                                                ),
                                                onChanged: (value) =>
                                                    _updateBillItem(
                                                        index,
                                                        'name',
                                                        value,
                                                        billProvider),
                                              )),
                                          const SizedBox(width: 4),
                                          Expanded(
                                              flex: 1,
                                              child: TextFormField(
                                                initialValue:
                                                    _extractQuantityNumber(
                                                        item['qty_display']),
                                                textAlign: TextAlign.center,
                                                keyboardType:
                                                    TextInputType.number,
                                                style: const TextStyle(
                                                    fontSize: 13),
                                                decoration:
                                                    const InputDecoration(
                                                  isDense: true,
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                          vertical: 8,
                                                          horizontal: 2),
                                                  border: OutlineInputBorder(),
                                                ),
                                                onChanged: (value) {
                                                  // Update quantity keeping the unit
                                                  final unit = _extractUnit(
                                                      item['qty_display']);
                                                  final newQtyDisplay =
                                                      '$value$unit';
                                                  _updateBillItem(
                                                      index,
                                                      'qty_display',
                                                      newQtyDisplay,
                                                      billProvider);
                                                },
                                              )),
                                          const SizedBox(width: 4),
                                          Expanded(
                                              flex: 3,
                                              child: TextFormField(
                                                initialValue: _formatNumber(
                                                    (item['rate'] as num)
                                                        .toDouble()),
                                                textAlign: TextAlign.right,
                                                keyboardType:
                                                    TextInputType.number,
                                                style: const TextStyle(
                                                    fontSize: 11),
                                                decoration: InputDecoration(
                                                  isDense: true,
                                                  contentPadding:
                                                      const EdgeInsets
                                                          .symmetric(
                                                          vertical: 8,
                                                          horizontal: 4),
                                                  border:
                                                      const OutlineInputBorder(),
                                                  prefixText: '₹',
                                                  suffixText:
                                                      '/${_extractUnit(item['qty_display'])}',
                                                ),
                                                onChanged: (value) =>
                                                    _updateBillItem(
                                                        index,
                                                        'rate',
                                                        value,
                                                        billProvider),
                                              )),
                                          const SizedBox(width: 4),
                                          Expanded(
                                              flex: 2,
                                              child: Text(
                                                  "₹${_formatNumber((item['total'] as num).toDouble())}",
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14))),
                                        ]);
                                      } else {
                                        // Display Mode
                                        return Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: gstProvider
                                                  .isCurrentBillGstEnabled
                                              ? Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(children: [
                                                      GestureDetector(
                                                          onTap: () =>
                                                              billProvider
                                                                  .removeBillItem(
                                                                      index),
                                                          child: Container(
                                                              margin:
                                                                  const EdgeInsets.only(
                                                                      right: 8),
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                      2),
                                                              decoration: BoxDecoration(
                                                                  color: Colors
                                                                      .red[50],
                                                                  shape: BoxShape
                                                                      .circle),
                                                              child: const Icon(
                                                                  Icons.remove,
                                                                  size: 16,
                                                                  color: Colors
                                                                      .red))),
                                                      Expanded(
                                                        flex: 4,
                                                        child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                  item['name']
                                                                          ?.toString() ??
                                                                      'Item',
                                                                  style: const TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      fontSize:
                                                                          14)),
                                                              Text(
                                                                  _formatRateWithUnit(
                                                                      _asDouble(
                                                                          item[
                                                                              'rate']),
                                                                      item['qty_display']
                                                                              ?.toString() ??
                                                                          '1unit'),
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      color: Colors
                                                                          .black54)),
                                                            ]),
                                                      ),
                                                      Expanded(
                                                          flex: 2,
                                                          child: Text(
                                                              _formatQuantityDisplay(
                                                                  item['qty_display']
                                                                          ?.toString() ??
                                                                      '1unit'),
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          13))),
                                                      Expanded(
                                                        flex: 2,
                                                        child: Text(
                                                            '${_formatNumber(_asDouble(item['gst_rate']))}%\nTax Rs ${_formatNumber(_gstLineTax(item))}',
                                                            textAlign: TextAlign
                                                                .right,
                                                            style:
                                                                const TextStyle(
                                                                    fontSize:
                                                                        10)),
                                                      ),
                                                      Expanded(
                                                        flex: 3,
                                                        child: Text(
                                                            'Rs ${_formatNumber(_gstLineTotal(item))}',
                                                            textAlign:
                                                                TextAlign.right,
                                                            style: const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 13)),
                                                      ),
                                                    ]),
                                                  ],
                                                )
                                              : Row(children: [
                                                  GestureDetector(
                                                      onTap: () => billProvider
                                                          .removeBillItem(
                                                              index),
                                                      child: Container(
                                                          margin:
                                                              const EdgeInsets.only(
                                                                  right: 8),
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(2),
                                                          decoration: BoxDecoration(
                                                              color: Colors
                                                                  .red[50],
                                                              shape: BoxShape
                                                                  .circle),
                                                          child: const Icon(
                                                              Icons.remove,
                                                              size: 16,
                                                              color:
                                                                  Colors.red))),
                                                  Expanded(
                                                      flex: 4,
                                                      child: Text(item['name'],
                                                          style:
                                                              const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontSize:
                                                                      14))),
                                                  Expanded(
                                                      flex: 1,
                                                      child: Text(
                                                          _formatQuantityDisplay(
                                                              item['qty_display'] ??
                                                                  '1kg'),
                                                          textAlign:
                                                              TextAlign.center,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize:
                                                                      13))),
                                                  Expanded(
                                                      flex: 3,
                                                      child: Text(
                                                          _formatRateWithUnit(
                                                              (item['rate']
                                                                      as num)
                                                                  .toDouble(),
                                                              item['qty_display'] ??
                                                                  '1kg'),
                                                          textAlign:
                                                              TextAlign.right,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize:
                                                                      11))),
                                                  Expanded(
                                                      flex: 2,
                                                      child: Text(
                                                          "₹${_formatNumber((item['total'] as num).toDouble())}",
                                                          textAlign:
                                                              TextAlign.right,
                                                          style:
                                                              const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize:
                                                                      14))),
                                                ]),
                                        );
                                      }
                                    })),

                        // Footer Total - Fixed overflow with tighter spacing
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(25))),
                            child: Row(children: [
                              // Print Button - Smaller fixed width
                              SizedBox(
                                width: 110,
                                height: 44,
                                child: ElevatedButton.icon(
                                    onPressed: _finalizeBill,
                                    icon: const Icon(Icons.print,
                                        color: Colors.white, size: 16),
                                    label: const Text("PRINT",
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8))),
                              ),

                              const SizedBox(width: 6),

                              // Share Icon - Smaller
                              Transform.rotate(
                                angle: -0.5,
                                child: IconButton(
                                  onPressed: currentBill.isEmpty
                                      ? null
                                      : () => _openShareModal(billProvider),
                                  icon: Icon(
                                    Icons.send,
                                    color: currentBill.isEmpty
                                        ? Colors.grey
                                        : AppColors.primaryGreen,
                                    size: 22,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: currentBill.isEmpty
                                        ? Colors.grey[200]
                                        : AppColors.primaryGreen
                                            .withOpacity(0.1),
                                    padding: const EdgeInsets.all(8),
                                  ),
                                ),
                              ),

                              const SizedBox(width: 4),

                              // Total - Flexible with constraints
                              Expanded(
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text("TOTAL",
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey,
                                              fontWeight: FontWeight.w600)),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                            "₹${_formatNumber(gstProvider.isCurrentBillGstEnabled ? _gstBillTotal(currentBill) : billProvider.billTotal)}",
                                            style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.textBlack)),
                                      ),
                                    ]),
                              ),
                            ])),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
