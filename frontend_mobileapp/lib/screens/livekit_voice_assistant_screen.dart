import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/shop_details.dart';
import '../providers/bill_provider.dart';
import '../services/livekit_voice_service.dart';
import '../services/printer_service.dart';
import '../features/gst/gst_invoice_preview_screen.dart';
import '../features/gst/models/gst_invoice_draft.dart';
import '../features/gst/providers/gst_provider.dart';
import '../features/voice/models/voice_mode.dart';
import '../features/voice/services/long_bill_service.dart';
import '../features/voice/services/long_bill_speech_service.dart';
import '../features/voice/services/token_saver_voice_service.dart';
import 'bill_share_modal.dart';

class LiveKitVoiceAssistantScreen extends StatefulWidget {
  final ShopDetails shopDetails;
  final void Function(Map<String, dynamic>) onBillFinalized;
  final bool isPrinterConnected;
  final VoidCallback togglePrinter;

  const LiveKitVoiceAssistantScreen({
    super.key,
    required this.shopDetails,
    required this.onBillFinalized,
    required this.isPrinterConnected,
    required this.togglePrinter,
  });

  @override
  State<LiveKitVoiceAssistantScreen> createState() =>
      _LiveKitVoiceAssistantScreenState();
}

class _LiveKitVoiceAssistantScreenState
    extends State<LiveKitVoiceAssistantScreen> {
  final LiveKitVoiceService _voice = LiveKitVoiceService();
  final PageController _voiceModeController = PageController();
  final LongBillService _longBillService = LongBillService();
  final FlutterTts _longBillTts = FlutterTts();
  StreamSubscription<VoiceUiEvent>? _events;
  late final LongBillSpeechService _longBillSpeech;
  late final TokenSaverVoiceService _tokenSaverVoice;

  // Session & Voice state
  bool _isSessionActive = false;
  String _sessionState = "IDLE"; // IDLE, INITIALIZING, SETUP, READY, LISTENING, THINKING, TOOL_EXECUTING, SPEAKING
  String _stateLabel = "Tap to Start";
  String _transcript = "";
  String _agentResponse = "Tap to Start";
  double _audioLevel = 0.0;
  Timer? _audioLevelTimer;
  double _startupTimeMs = 0.0;

  // The mode selector controls only the upper section.  Billing and the shop
  // header are deliberately outside this state so they remain fixed.
  int _voiceModeIndex = 0;
  bool _isLongBillSubmitting = false;
  String _longBillTranscript = '';
  String _longBillStatus = 'Tap to start a Long Bill recording';
  double _longBillAudioLevel = 0.0;
  TokenSaverSessionState _tokenSaverState = TokenSaverSessionState.idle;
  String _tokenSaverTranscript = '';
  String _tokenSaverMessage = 'Tap to start Token Saver';
  double _tokenSaverAudioLevel = 0.0;

  // Edit Mode & Live Bill State
  bool _isEditMode = false;
  bool _isManualLiveBillOpen = false;
  Map<String, dynamic>? _pendingCustomerVerificationSuggestion;
  final Set<String> _handledBillDraftIds = <String>{};

  @override
  void initState() {
    super.initState();
    _events = _voice.events.listen(_handleVoiceEvent);
    _longBillSpeech = LongBillSpeechService(
      onTranscriptChanged: (transcript) {
        if (!mounted) return;
        setState(() => _longBillTranscript = transcript);
      },
      onSoundLevelChanged: (level) {
        if (!mounted) return;
        setState(() => _longBillAudioLevel = level);
      },
      onStatusChanged: (status) {
        if (!mounted) return;
        setState(() => _longBillStatus = status);
      },
    );
    _tokenSaverVoice = TokenSaverVoiceService(
      onStateChanged: (state, message) {
        if (!mounted) return;
        setState(() {
          _tokenSaverState = state;
          _tokenSaverMessage = message;
        });
      },
      onTranscriptChanged: (transcript) {
        if (!mounted) return;
        setState(() => _tokenSaverTranscript = transcript);
      },
      onAudioLevelChanged: (level) {
        if (!mounted) return;
        setState(() => _tokenSaverAudioLevel = level);
      },
      onResponse: (response) {
        if (!mounted) return;
        final draft = response['draft'];
        if (response['type'] == 'BILL' && draft is Map) {
          _applyBillDraftPayload(Map<String, dynamic>.from(draft));
          setState(() => _isManualLiveBillOpen = true);
        }
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await context.read<GstProvider>().loadConfiguration();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _audioLevelTimer?.cancel();
    _voiceModeController.dispose();
    unawaited(_longBillTts.stop());
    unawaited(_longBillSpeech.dispose());
    unawaited(_tokenSaverVoice.dispose());
    _voice.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_isSessionActive || _voice.isConnecting) {
      await _stopContinuousSession();
    } else {
      await _startContinuousSession();
    }
  }

  Future<void> _startContinuousSession() async {
    setState(() {
      _isSessionActive = true;
      _sessionState = "INITIALIZING";
      _stateLabel = "Initializing";
      _transcript = "";
      _agentResponse = "Setting up voice session...";
      _audioLevel = 0.2;
    });

    _startAudioLevelAnimation();

    try {
      await _voice.connect(participantName: widget.shopDetails.ownerName);
    } catch (_) {
      if (!mounted) return;
      _audioLevelTimer?.cancel();
      setState(() {
        _isSessionActive = false;
        _sessionState = "IDLE";
        _stateLabel = "Offline";
        _agentResponse = "Voice connection error";
        _audioLevel = 0.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not start secure voice session. Please try again."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _stopContinuousSession() async {
    await _voice.disconnect();
    _audioLevelTimer?.cancel();
    if (!mounted) return;

    setState(() {
      _isSessionActive = false;
      _sessionState = "IDLE";
      _stateLabel = "Offline";
      _transcript = "";
      _agentResponse = "Tap to Start";
      _audioLevel = 0.0;
      _startupTimeMs = 0.0;
    });
  }

  /// Release every microphone-backed mode before resetting or finalizing a
  /// bill. Each implementation is guarded so this does not overwrite the UI
  /// state of an inactive mode.
  Future<void> _stopAllVoiceModes() async {
    if (_isSessionActive || _voice.isConnecting) {
      await _stopContinuousSession();
    }
    if (_tokenSaverVoice.isActive) {
      await _tokenSaverVoice.stop();
    }
    if (_longBillSpeech.isRecording) {
      await _longBillSpeech.stop();
    }
  }

  void _onVoiceModeChanged(int index) {
    if (index == _voiceModeIndex) return;
    final previousMode = VoiceMode.values[_voiceModeIndex];
    setState(() => _voiceModeIndex = index);

    // A mode switch must never leave an unseen microphone session running.
    if (previousMode == VoiceMode.voiceAgent &&
        (_isSessionActive || _voice.isConnecting)) {
      unawaited(_stopContinuousSession());
    }
    if (previousMode == VoiceMode.longBill && _longBillSpeech.isRecording) {
      unawaited(_pauseLongBillForModeChange());
    }
    if (previousMode == VoiceMode.tokenSaver && _tokenSaverVoice.isActive) {
      unawaited(_tokenSaverVoice.stop());
    }
  }

  Future<void> _toggleTokenSaver() async {
    if (_tokenSaverVoice.isActive) {
      await _tokenSaverVoice.stop();
      return;
    }
    await _stopAllVoiceModes();
    setState(() {
      _tokenSaverTranscript = '';
      _tokenSaverAudioLevel = 0;
      _tokenSaverMessage = 'Starting Token Saver…';
    });
    await _tokenSaverVoice.start();
  }

  Future<void> _pauseLongBillForModeChange() async {
    await _longBillSpeech.stop();
    if (!mounted) return;
    setState(() {
      _longBillStatus = _longBillTranscript.trim().isEmpty
          ? 'Recording stopped'
          : 'Recording paused. Return to Long Bill to create the draft.';
    });
  }

  Future<void> _toggleLongBillRecording() async {
    if (_isLongBillSubmitting) return;
    if (_longBillSpeech.isRecording) {
      final transcript = await _longBillSpeech.stop();
      if (!mounted) return;
      if (transcript.trim().length < 2) {
        setState(() => _longBillStatus = 'No speech was recognized. Please try again.');
        return;
      }
      await _submitLongBillTranscript(transcript);
      return;
    }

    await _stopAllVoiceModes();
    setState(() {
      _longBillTranscript = '';
      _longBillAudioLevel = 0;
      _longBillStatus = 'Starting device speech recognition…';
    });
    final result = await _longBillSpeech.start();
    if (!mounted) return;
    setState(() => _longBillStatus = result.message);
  }

  Future<void> _speakLongBillResponse(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    try {
      await _longBillTts.stop();
      await _longBillTts.setSpeechRate(0.48);
      await _longBillTts.setPitch(1.0);
      try {
        await _longBillTts.setLanguage('hi-IN');
      } catch (_) {}
      await _longBillTts.speak(clean);
    } catch (_) {}
  }

  Future<void> _submitLongBillTranscript(String transcript) async {
    setState(() {
      _isLongBillSubmitting = true;
      _longBillStatus = 'Creating a secure bill draft…';
    });
    try {
      final response = await _longBillService.createDraft(transcript);
      if (!mounted) return;
      final message = response['message']?.toString() ?? 'Long Bill review is ready.';
      final draft = response['draft'];
      if (response['status'] == 'draft' && draft is Map) {
        _applyBillDraftPayload(
          Map<String, dynamic>.from(draft),
          replaceExistingBill: true,
        );
        setState(() {
          _isManualLiveBillOpen = true;
          _longBillStatus = message;
        });
      } else {
        setState(() => _longBillStatus = message);
      }
      unawaited(_speakLongBillResponse(message));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _longBillStatus = 'Could not create the draft. Check your connection and try again.';
      });
    } finally {
      if (mounted) setState(() => _isLongBillSubmitting = false);
    }
  }

  void _startAudioLevelAnimation() {
    _audioLevelTimer?.cancel();
    int tick = 0;
    _audioLevelTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (timer) {
        if (!_isSessionActive) {
          timer.cancel();
          return;
        }
        tick++;
        setState(() {
          switch (_sessionState) {
            case "INITIALIZING":
            case "SETUP":
              _audioLevel = 0.2 + (0.15 * (tick % 10) / 10);
              break;
            case "READY":
              _audioLevel = 0.4 + (0.1 * (tick % 10) / 10);
              break;
            case "LISTENING":
              if (_transcript.isNotEmpty) {
                _audioLevel = 0.6 + (0.4 * (tick % 10) / 10);
              } else {
                _audioLevel = 0.3 + (0.2 * (tick % 10) / 10);
              }
              break;
            case "THINKING":
              _audioLevel = 0.4 + (0.25 * (tick % 10) / 10);
              break;
            case "TOOL_EXECUTING":
              _audioLevel = 0.45 + (0.3 * (tick % 10) / 10);
              break;
            case "SPEAKING":
              _audioLevel = 0.5 + (0.4 * (tick % 10) / 10);
              break;
            default:
              _audioLevel = 0.3 + (0.2 * (tick % 10) / 10);
          }
        });
      },
    );
  }

  void _handleVoiceEvent(VoiceUiEvent event) {
    if (!mounted) return;
    
    debugPrint('🎤 VOICE EVENT: ${event.type}');
    
    switch (event.type) {
      case 'initializing':
        setState(() {
          _sessionState = "INITIALIZING";
          _stateLabel = "Initializing";
          _agentResponse = event.payload['message']?.toString() ?? "Setting up...";
        });
        break;
      
      case 'setup':
        setState(() {
          _sessionState = "SETUP";
          _stateLabel = "Setting up";
          _agentResponse = event.payload['message']?.toString() ?? "Preparing voice agent...";
        });
        break;

      case 'ready':
        final startupTime = event.payload['startup_time_ms'];
        setState(() {
          _isSessionActive = true;
          _sessionState = "READY";
          _stateLabel = "Ready";
          _agentResponse = "Ready to listen";
          if (startupTime != null) {
            _startupTimeMs = (startupTime is num) ? startupTime.toDouble() : 0.0;
          }
        });
        debugPrint('🎉 VOICE: Session ready in ${_startupTimeMs}ms');
        // Transition to listening after a brief moment
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && _sessionState == "READY") {
            setState(() {
              _sessionState = "LISTENING";
              _stateLabel = "Listening";
              _agentResponse = "Listening...";
            });
          }
        });
        break;

      case 'connected':
        // Legacy event, treat as ready if not already handled
        if (_sessionState == "INITIALIZING" || _sessionState == "SETUP") {
          setState(() {
            _isSessionActive = true;
            _sessionState = "LISTENING";
            _stateLabel = "Listening";
            if (_agentResponse == "Setting up..." || _agentResponse == "Preparing voice agent...") {
              _agentResponse = "Listening...";
            }
          });
        }
        break;

      case 'user_transcript':
        final text = event.payload['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          setState(() {
            _transcript = text;
            _audioLevel = 0.7;
          });
        }
        break;

      case 'agent_transcript':
        final text = event.payload['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) {
          setState(() {
            _agentResponse = text;
          });
        }
        break;

      case 'agent_state':
        final state = event.payload['state']?.toString().toLowerCase() ?? '';
        final label = event.payload['label']?.toString() ?? '';
        setState(() {
          if (state.contains('listening')) {
            _sessionState = "LISTENING";
            _stateLabel = label.isNotEmpty ? label : "Listening";
            if (_agentResponse == "Thinking..." || _agentResponse == "AI Speaking...") {
              _agentResponse = "Listening...";
            }
          } else if (state.contains('thinking') || state.contains('processing')) {
            _sessionState = "THINKING";
            _stateLabel = label.isNotEmpty ? label : "Thinking";
            if (_agentResponse == "Listening...") {
              _agentResponse = "Thinking...";
            }
          } else if (state.contains('speaking')) {
            _sessionState = "SPEAKING";
            _stateLabel = label.isNotEmpty ? label : "AI Speaking";
          } else {
            _sessionState = state.toUpperCase();
            _stateLabel = label.isNotEmpty ? label : state;
          }
        });
        break;
      
      case 'tool_executing':
        final toolName = event.payload['tool']?.toString() ?? 'tool';
        setState(() {
          _sessionState = "TOOL_EXECUTING";
          _stateLabel = "Executing";
          _agentResponse = "Searching inventory...";
        });
        break;

      case 'interruption':
        debugPrint('🚫 VOICE: User interrupted agent');
        setState(() {
          _sessionState = "LISTENING";
          _stateLabel = "Listening";
        });
        break;
      
      case 'speech_interrupted':
        debugPrint('⏹️ VOICE: Agent speech stopped');
        break;

      case 'bill_draft':
        _applyBillDraftPayload(event.payload);
        break;

      case 'disconnected':
        if (_isSessionActive) {
          _stopContinuousSession();
        }
        break;

      case 'error':
        setState(() {
          _sessionState = "IDLE";
          _stateLabel = "Error";
          _agentResponse = "Voice Error";
        });
        break;
    }
  }

  void _applyBillDraftPayload(
    Map<String, dynamic> payload, {
    bool replaceExistingBill = false,
  }) {
    final draftId = (payload['draft_id'] ?? payload['id'])?.toString().trim() ?? '';
    if (draftId.isNotEmpty && _handledBillDraftIds.contains(draftId)) {
      return;
    }
    final rawState = payload['state'];
    if (rawState is! Map) return;
    final state = Map<String, dynamic>.from(rawState);
    final rawItems = state['items'];
    if (rawItems is! List || rawItems.isEmpty) return;

    final billItems = <Map<String, dynamic>>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final parsedQty = _asDouble(item['quantity'] ?? item['qty'] ?? 1);
      final quantity = parsedQty > 0 ? parsedQty : 1.0;
      final rate = _asDouble(item['price'] ?? item['rate']);
      final unit = item['unit']?.toString() ?? 'unit';
      final name = item['name']?.toString().trim();
      if (name == null || name.isEmpty || rate < 0) continue;
      billItems.add({
        'name': name,
        'en': name,
        'hi': name,
        'qty': '$quantity',
        'qty_display': item['qty_display']?.toString() ?? '${_formatNumber(quantity)} $unit',
        'rate': rate,
        // Recalculate on the client so stale transport values cannot alter a bill.
        'total': _roundMoney(rate * quantity),
        'unit': unit,
        'gst_rate': _asDouble(item['gst_rate']),
      });
    }
    if (billItems.isEmpty) return;

    final rawSuggestion = payload['customer_verification_suggestion'];
    _pendingCustomerVerificationSuggestion = rawSuggestion is Map
        ? Map<String, dynamic>.from(rawSuggestion)
        : null;
    final customerName = state['customer_name']?.toString().trim();
    final billProvider = Provider.of<BillProvider>(context, listen: false);
    if (replaceExistingBill) {
      // Long Bill describes a complete bill. It must not silently merge into
      // an earlier Live Bill or Token Saver turn.
      billProvider.clearBill();
    }
    if (customerName != null && customerName.isNotEmpty) {
      billProvider.setCustomerName(customerName);
    }
    billProvider.addBillItems(billItems);
    if (draftId.isNotEmpty) {
      _handledBillDraftIds.add(draftId);
    }
  }

  // Formatting & Calculation Helpers
  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  double _roundMoney(double value) => (value * 100).roundToDouble() / 100;

  String _formatNumber(double value) {
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    return value
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _extractQuantityNumber(String qtyDisplay) {
    final numericPart = qtyDisplay.replaceAll(RegExp(r'[^0-9.]'), '');
    return numericPart.isEmpty ? '1' : numericPart;
  }

  String _extractUnit(String qtyDisplay) {
    final unitPart = qtyDisplay.replaceAll(RegExp(r'[0-9.]'), '').trim();
    return unitPart.isEmpty ? 'kg' : unitPart;
  }

  String _formatRateWithUnit(double rate, String qtyDisplay) {
    final unit = _extractUnit(qtyDisplay);
    return '₹${_formatNumber(rate)}/$unit';
  }

  String _formatQuantityDisplay(String qtyDisplay) {
    String result = qtyDisplay;
    result = result.replaceAll('dozen', 'doz');
    result = result.replaceAll('plate', 'plt');
    result = result.replaceAll('pieces', 'pic');
    result = result.replaceAll('pics', 'pic');
    result = result.replaceAll('litre', 'lit');
    result = result.replaceAll('liter', 'lit');

    final RegExp kgPattern = RegExp(r'(\d+\.?\d*)\s*kg', caseSensitive: false);
    final match = kgPattern.firstMatch(result);

    if (match != null) {
      double kgValue = double.tryParse(match.group(1) ?? '0') ?? 0;
      if (kgValue > 0 && kgValue < 1) {
        int grams = (kgValue * 1000).round();
        result = result.replaceFirst(kgPattern, '${grams}gm');
      } else if (kgValue > 1 && kgValue != kgValue.toInt()) {
        int grams = (kgValue * 1000).round();
        result = result.replaceFirst(kgPattern, '${grams}gm');
      }
    }

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

  void _resetVoicePage() {
    unawaited(_stopAllVoiceModes());
    final billProvider = Provider.of<BillProvider>(context, listen: false);
    billProvider.clearBill();
    Provider.of<GstProvider>(context, listen: false).resetCurrentBill();

    setState(() {
      if (_isEditMode) _isEditMode = false;
      _isManualLiveBillOpen = false;
    });
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
    });
    if (!_isEditMode) {
      FocusScope.of(context).unfocus();
    }
  }

  void _addManualItem(BillProvider billProvider) {
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
    if (index >= items.length) return;
    final item = Map<String, dynamic>.from(items[index]);

    if (field == 'name') {
      item['name'] = value;
      item['en'] = value;
      item['hi'] = value;
    } else if (field == 'qty_display') {
      item['qty_display'] = value;
      final numericQty = value.replaceAll(RegExp(r'[^0-9.]'), '');
      item['qty'] = numericQty;
      final rate = _asDouble(item['rate']);
      final qty = double.tryParse(numericQty) ?? 1.0;
      item['total'] = rate * qty;
    } else if (field == 'rate') {
      final rate = double.tryParse(value) ?? 0.0;
      item['rate'] = rate;
      final qtyStr =
          item['qty_display'].toString().replaceAll(RegExp(r'[^0-9.]'), '');
      final qty = double.tryParse(qtyStr) ?? 1.0;
      item['total'] = rate * qty;
    }

    items[index] = item;
    billProvider.updateBillItems(items);
  }

  void _removeItemAndCheckEmpty(BillProvider billProvider, int index) {
    billProvider.removeBillItem(index);
    if (billProvider.currentBillItems.isEmpty) {
      setState(() {
        _isManualLiveBillOpen = false;
        if (_isEditMode) _isEditMode = false;
      });
    }
  }

  void _finalizeBill() async {
    final billProvider = Provider.of<BillProvider>(context, listen: false);
    final gstProvider = Provider.of<GstProvider>(context, listen: false);

    if (!billProvider.hasBillItems) return;

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
        await _stopAllVoiceModes();
        billProvider.clearBill();
        setState(() {
          _agentResponse = 'GST invoice printed';
          _isManualLiveBillOpen = false;
        });
      }
      return;
    }

    final isConnected = await PrinterService().isConnected();
    if (!isConnected) {
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

    final billNumber = await billProvider.getNextBillNumber();
    final itemsCopy =
        List<Map<String, dynamic>>.from(billProvider.currentBillItems);

    final billData = {
      'id': billNumber,
      'date':
          "${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}",
      'time': "${DateTime.now().hour}:${DateTime.now().minute}",
      'total': billProvider.billTotal,
      'customerName': billProvider.customerName,
      'shopName': widget.shopDetails.shopName,
      'shopAddress': widget.shopDetails.address,
      'shopPhone': widget.shopDetails.phone1,
      'items': itemsCopy,
      if (_pendingCustomerVerificationSuggestion != null)
        'customer_verification_suggestion': _pendingCustomerVerificationSuggestion,
    };

    widget.onBillFinalized(billData);
    await _stopAllVoiceModes();
    billProvider.clearBill();

    setState(() {
      _agentResponse = "Bill Printed!";
      _isManualLiveBillOpen = false;
      _pendingCustomerVerificationSuggestion = null;
    });
  }

  void _openShareModal(BillProvider billProvider) {
    if (!billProvider.hasBillItems) return;
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

  String _getDisplayText() {
    if (_transcript.isNotEmpty) return _transcript;
    switch (_sessionState) {
      case "INITIALIZING":
        return "Initializing voice session...";
      case "SETUP":
        return "Setting up providers...";
      case "READY":
        return "Session ready!";
      case "LISTENING":
        return "Listening...";
      case "THINKING":
        return "Processing speech...";
      case "TOOL_EXECUTING":
        return "Searching...";
      case "SPEAKING":
        return "Vyamit AI Speaking...";
      default:
        return "Tap to Start Call Session";
    }
  }

  String _getTimeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 4 && hour < 12) {
      return 'Good Morning';
    } else if (hour >= 12 && hour < 17) {
      return 'Good Afternoon';
    } else if (hour >= 17 && hour < 22) {
      return 'Good Evening';
    } else {
      return 'Good Night';
    }
  }

  String get _ownerDisplayName {
    final name = widget.shopDetails.ownerName.trim();
    if (name.isNotEmpty && name.toLowerCase() != 'owner') {
      return name;
    }
    final shop = widget.shopDetails.shopName.trim();
    if (shop.isNotEmpty) {
      return shop;
    }
    return 'Owner';
  }

  // Get color based on session state
  Color _getStatusColor(String state) {
    switch (state) {
      case "INITIALIZING":
        return Colors.orange;
      case "SETUP":
        return Colors.orange.shade700;
      case "READY":
        return Colors.green.shade400;
      case "LISTENING":
        return Colors.green;
      case "THINKING":
        return Colors.purple;
      case "TOOL_EXECUTING":
        return Colors.amber.shade700;
      case "SPEAKING":
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  // Get icon based on session state
  IconData _getStatusIcon(String state) {
    switch (state) {
      case "INITIALIZING":
      case "SETUP":
        return Icons.settings;
      case "READY":
        return Icons.check_circle;
      case "LISTENING":
        return Icons.graphic_eq;
      case "THINKING":
        return Icons.psychology;
      case "TOOL_EXECUTING":
        return Icons.search;
      case "SPEAKING":
        return Icons.volume_up;
      default:
        return Icons.mic;
    }
  }

  Widget _buildGreetingView(BuildContext context) {
    final greeting = _getTimeBasedGreeting();
    final ownerName = _ownerDisplayName;
    final userLocation = widget.shopDetails.address.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/vyamitlogo.png',
                  height: 28,
                  width: 28,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryGreen.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: AppColors.primaryGreen,
                      size: 20,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Vyamit AI",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: AppColors.textBlack,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "How can I assist you today?",
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade600,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '$greeting,',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w400,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ownerName,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: AppColors.textBlack,
            ),
          ),
          const SizedBox(height: 10),
          if (userLocation.isNotEmpty)
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 15,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    userLocation,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildVoiceModeOrb({
    required bool active,
    required double audioLevel,
    required Color activeColor,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return Semantics(
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (active)
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 142 + (audioLevel * 20),
                height: 142 + (audioLevel * 20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: activeColor.withOpacity(.22), width: 2),
                ),
              ),
            AnimatedScale(
              scale: active ? 1 + (audioLevel * .1) : 1,
              duration: const Duration(milliseconds: 120),
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? null : Colors.white,
                  gradient: active
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [activeColor.withOpacity(.92), activeColor],
                        )
                      : null,
                  border: Border.all(
                    color: active ? Colors.transparent : Colors.grey.shade300,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: active ? activeColor.withOpacity(.28) : Colors.black12,
                      blurRadius: active ? 24 : 10,
                      spreadRadius: active ? 3 : 1,
                    ),
                  ],
                ),
                child: Icon(icon, size: 46, color: active ? Colors.white : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveKitModePanel() {
    final active = _isSessionActive;
    final color = active ? _getStatusColor(_sessionState) : Colors.teal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const Column(
            children: [
              Text('Voice Agent', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('LiveKit realtime assistant', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          _buildVoiceModeOrb(
            active: active,
            audioLevel: _audioLevel,
            activeColor: color,
            icon: active ? _getStatusIcon(_sessionState) : Icons.mic,
            onTap: _toggleListening,
          ),
          Column(
            children: [
              Text(
                active ? _stateLabel : 'Tap to Start',
                style: TextStyle(fontWeight: FontWeight.w700, color: active ? color : Colors.black87),
              ),
              const SizedBox(height: 4),
              Text(
                active ? _getDisplayText() : _agentResponse,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTokenSaverModePanel() {
    final active = _tokenSaverVoice.isActive;
    final color = switch (_tokenSaverState) {
      TokenSaverSessionState.error => Colors.red,
      TokenSaverSessionState.processing => Colors.orange,
      TokenSaverSessionState.speaking => Colors.teal,
      _ => Colors.indigo,
    };
    final icon = switch (_tokenSaverState) {
      TokenSaverSessionState.processing => Icons.psychology_rounded,
      TokenSaverSessionState.speaking => Icons.volume_up_rounded,
      _ => active ? Icons.graphic_eq_rounded : Icons.mic,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const Column(
            children: [
              Text('Token Saver', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('On-device STT/TTS • secure text socket', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          _buildVoiceModeOrb(
            active: active,
            audioLevel: _tokenSaverAudioLevel,
            activeColor: color,
            icon: icon,
            onTap: _toggleTokenSaver,
          ),
          Column(
            children: [
              Text(
                _tokenSaverMessage,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, color: active ? color : Colors.black87),
              ),
              const SizedBox(height: 5),
              Text(
                _tokenSaverTranscript.isEmpty ? 'Your live transcript will appear here.' : _tokenSaverTranscript,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailableModePanel(VoiceMode mode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(mode.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade200,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: const Icon(Icons.mic_none_rounded, color: Colors.grey, size: 46),
          ),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(99)),
                child: const Text('UNDER DEVELOPMENT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
              ),
              const SizedBox(height: 7),
              Text(mode.description, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLongBillModePanel() {
    final recording = _longBillSpeech.isRecording;
    final active = recording || _isLongBillSubmitting;
    final color = _isLongBillSubmitting ? Colors.orange : Colors.deepPurple;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          const Column(
            children: [
              Text('Long Bill', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Speak the full bill, then stop to review it', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          _buildVoiceModeOrb(
            active: active,
            audioLevel: _longBillAudioLevel,
            activeColor: color,
            icon: _isLongBillSubmitting ? Icons.hourglass_top_rounded : (recording ? Icons.stop_rounded : Icons.mic),
            onTap: _isLongBillSubmitting ? null : _toggleLongBillRecording,
          ),
          Column(
            children: [
              Text(
                _longBillStatus,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w700, color: active ? color : Colors.black87),
              ),
              const SizedBox(height: 5),
              Text(
                _longBillTranscript.isEmpty ? 'Your live transcript will appear here.' : _longBillTranscript,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceModeDots() {
    return Semantics(
      label: '${VoiceMode.values[_voiceModeIndex].title} mode selected. Swipe left or right to change mode.',
      child: ExcludeSemantics(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(VoiceMode.values.length, (index) {
            final selected = index == _voiceModeIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.primaryGreen : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99),
              ),
            );
          }),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gstProvider = context.watch<GstProvider>();
    
    return Consumer<BillProvider>(
      builder: (context, billProvider, child) {
        final currentBill = billProvider.currentBillItems;
        final showLiveBill = currentBill.isNotEmpty || _isManualLiveBillOpen;

        return Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    // 1. Header Top Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          const SizedBox(width: 48),
                          Expanded(
                            child: Text(
                              widget.shopDetails.shopName,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.print,
                              color: widget.isPrinterConnected
                                  ? AppColors.printerConnected
                                  : AppColors.printerDisconnected,
                            ),
                            onPressed: widget.togglePrinter,
                          ),
                        ],
                      ),
                    ),

                    // 2. This is the only swipeable part of the page. The
                    // header and the bill area below remain fixed.
                    if (!_isEditMode)
                      SizedBox(
                        height: 300,
                        child: Column(
                          children: [
                            Expanded(
                              child: PageView(
                                controller: _voiceModeController,
                                onPageChanged: _onVoiceModeChanged,
                                children: [
                                  _buildLiveKitModePanel(),
                                  _buildTokenSaverModePanel(),
                                  _buildUnavailableModePanel(VoiceMode.offlineAgent),
                                  _buildLongBillModePanel(),
                                ],
                              ),
                            ),
                            _buildVoiceModeDots(),
                          ],
                        ),
                      ),

                    // 3. Live Bill Card OR Greeting View
                    if (showLiveBill)
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
                                padding:
                                    const EdgeInsets.fromLTRB(16, 12, 16, 8),
                                child: Row(
                                  children: [
                                    const Text(
                                      'Live Bill',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16),
                                    ),
                                    if (gstProvider.isShopGstEnabled) ...[
                                      const SizedBox(width: 10),
                                      Semantics(
                                        button: true,
                                        label: gstProvider.isCurrentBillGstEnabled
                                            ? 'Turn off GST invoice mode'
                                            : 'Turn on GST invoice mode',
                                        child: GestureDetector(
                                          onTap: () => gstProvider
                                              .setCurrentBillGstEnabled(
                                            !gstProvider.isCurrentBillGstEnabled,
                                          ),
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 160),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: gstProvider
                                                      .isCurrentBillGstEnabled
                                                  ? AppColors.primaryGreen
                                                  : Colors.grey.shade200,
                                              borderRadius:
                                                  BorderRadius.circular(16),
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
                                        backgroundColor: AppColors.primaryGreen
                                            .withOpacity(0.1),
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
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                      color: Colors.grey))),
                                          Expanded(
                                              flex: 2,
                                              child: Text('Qty',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                      color: Colors.grey))),
                                          Expanded(
                                              flex: 2,
                                              child: Text('GST',
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                      color: Colors.grey))),
                                          Expanded(
                                              flex: 3,
                                              child: Text('Total',
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                      color: Colors.grey))),
                                        ]
                                      : const [
                                          Expanded(
                                              flex: 4,
                                              child: Text('Item',
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                      color: Colors.grey))),
                                          Expanded(
                                              flex: 1,
                                              child: Text('Qty',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                      color: Colors.grey))),
                                          Expanded(
                                              flex: 3,
                                              child: Text('Rate',
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                      color: Colors.grey))),
                                          Expanded(
                                              flex: 2,
                                              child: Text('Total',
                                                  textAlign: TextAlign.right,
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                      color: Colors.grey))),
                                        ],
                                ),
                              ),
                              const Divider(height: 1),
                              Expanded(
                                child: currentBill.isEmpty
                                    ? const Center(
                                        child: Text(
                                          "Tap + to add items manually\nor say 'Chawal 1kg'",
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      )
                                    : ListView.separated(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 10),
                                        itemCount: currentBill.length +
                                            (_isEditMode ? 1 : 0),
                                        separatorBuilder: (_, __) =>
                                            const Divider(height: 16),
                                        itemBuilder: (context, index) {
                                          if (_isEditMode &&
                                              index == currentBill.length) {
                                            return GestureDetector(
                                              onTap: () =>
                                                  _addManualItem(billProvider),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
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
                                                        color: AppColors
                                                            .primaryGreen,
                                                        size: 20),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      "Add Item",
                                                      style: TextStyle(
                                                        color: AppColors
                                                            .primaryGreen,
                                                        fontWeight:
                                                            FontWeight.bold,
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
                                            return Row(children: [
                                              GestureDetector(
                                                onTap: () =>
                                                    _removeItemAndCheckEmpty(
                                                        billProvider, index),
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
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 4,
                                                child: TextField(
                                                  controller:
                                                      TextEditingController(
                                                          text: item['name'])
                                                        ..selection =
                                                            TextSelection.collapsed(
                                                                offset: (item['name']
                                                                            ?.toString() ??
                                                                        '')
                                                                    .length),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
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
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                flex: 1,
                                                child: TextFormField(
                                                  initialValue:
                                                      _extractQuantityNumber(
                                                          item['qty_display']
                                                                  ?.toString() ??
                                                              '1kg'),
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
                                                    final unit = _extractUnit(
                                                        item['qty_display']
                                                                ?.toString() ??
                                                            'kg');
                                                    final newQtyDisplay =
                                                        '$value$unit';
                                                    _updateBillItem(
                                                        index,
                                                        'qty_display',
                                                        newQtyDisplay,
                                                        billProvider);
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                flex: 3,
                                                child: TextFormField(
                                                  initialValue: _formatNumber(
                                                      _asDouble(item['rate'])),
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
                                                        '/${_extractUnit(item['qty_display']?.toString() ?? 'kg')}',
                                                  ),
                                                  onChanged: (value) =>
                                                      _updateBillItem(
                                                          index,
                                                          'rate',
                                                          value,
                                                          billProvider),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  "₹${_formatNumber(_asDouble(item['total']))}",
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14),
                                                ),
                                              ),
                                            ]);
                                          } else {
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 12),
                                              child: gstProvider
                                                      .isCurrentBillGstEnabled
                                                  ? Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Row(children: [
                                                          GestureDetector(
                                                            onTap: () =>
                                                                _removeItemAndCheckEmpty(
                                                                    billProvider,
                                                                    index),
                                                            child: Container(
                                                              margin:
                                                                  const EdgeInsets
                                                                      .only(
                                                                      right: 8),
                                                              padding:
                                                                  const EdgeInsets
                                                                      .all(2),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Colors
                                                                    .red[50],
                                                                shape: BoxShape
                                                                    .circle,
                                                              ),
                                                              child: const Icon(
                                                                Icons.remove,
                                                                size: 16,
                                                                color: Colors.red,
                                                              ),
                                                            ),
                                                          ),
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
                                                                          14),
                                                                ),
                                                                Text(
                                                                  _formatRateWithUnit(
                                                                    _asDouble(
                                                                        item['rate']),
                                                                    item['qty_display']
                                                                            ?.toString() ??
                                                                        '1kg',
                                                                  ),
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          10,
                                                                      color: Colors
                                                                          .black54),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                          Expanded(
                                                            flex: 2,
                                                            child: Text(
                                                              _formatQuantityDisplay(
                                                                item['qty_display']
                                                                        ?.toString() ??
                                                                    '1kg',
                                                              ),
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          13),
                                                            ),
                                                          ),
                                                          Expanded(
                                                            flex: 2,
                                                            child: Text(
                                                              '${_formatNumber(_asDouble(item['gst_rate']))}%\nTax Rs ${_formatNumber(_gstLineTax(item))}',
                                                              textAlign:
                                                                  TextAlign.right,
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          10),
                                                            ),
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
                                                                  fontSize:
                                                                      13),
                                                            ),
                                                          ),
                                                        ]),
                                                      ],
                                                    )
                                                  : Row(children: [
                                                      GestureDetector(
                                                        onTap: () =>
                                                            _removeItemAndCheckEmpty(
                                                                billProvider,
                                                                index),
                                                        child: Container(
                                                          margin:
                                                              const EdgeInsets
                                                                  .only(
                                                                  right: 8),
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(2),
                                                          decoration:
                                                              BoxDecoration(
                                                            color:
                                                                Colors.red[50],
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                          child: const Icon(
                                                            Icons.remove,
                                                            size: 16,
                                                            color: Colors.red,
                                                          ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        flex: 4,
                                                        child: Text(
                                                          item['name']
                                                                  ?.toString() ??
                                                              'Item',
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              fontSize: 14),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        flex: 1,
                                                        child: Text(
                                                          _formatQuantityDisplay(
                                                            item['qty_display']
                                                                    ?.toString() ??
                                                                '1kg',
                                                          ),
                                                          textAlign:
                                                              TextAlign.center,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 13),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        flex: 3,
                                                        child: Text(
                                                          _formatRateWithUnit(
                                                            _asDouble(
                                                                item['rate']),
                                                            item['qty_display']
                                                                    ?.toString() ??
                                                                '1kg',
                                                          ),
                                                          textAlign:
                                                              TextAlign.right,
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 11),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        flex: 2,
                                                        child: Text(
                                                          "₹${_formatNumber(_asDouble(item['total']))}",
                                                          textAlign:
                                                              TextAlign.right,
                                                          style: const TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 14),
                                                        ),
                                                      ),
                                                    ]),
                                            );
                                          }
                                        },
                                      ),
                              ),

                              // Live Bill Bottom Total Bar
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 14),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(25),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 110,
                                      height: 44,
                                      child: ElevatedButton.icon(
                                        onPressed: currentBill.isEmpty
                                            ? null
                                            : _finalizeBill,
                                        icon: const Icon(Icons.print,
                                            color: Colors.white, size: 16),
                                        label: const Text(
                                          "PRINT",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Transform.rotate(
                                      angle: -0.5,
                                      child: IconButton(
                                        onPressed: currentBill.isEmpty
                                            ? null
                                            : () =>
                                                _openShareModal(billProvider),
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
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            "TOTAL",
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              "₹${_formatNumber(gstProvider.isCurrentBillGstEnabled ? _gstBillTotal(currentBill) : billProvider.billTotal)}",
                                              style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.textBlack,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: _buildGreetingView(context),
                      ),
                  ],
                ),

                // Floating Action Button for opening Live Bill Box manually
                if (!showLiveBill)
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: FloatingActionButton.small(
                      onPressed: () {
                        setState(() {
                          _isManualLiveBillOpen = true;
                        });
                      },
                      backgroundColor: AppColors.primaryGreen,
                      elevation: 4,
                      child: const Icon(
                        Icons.receipt_long_rounded,
                        color: Colors.white,
                        size: 20,
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
