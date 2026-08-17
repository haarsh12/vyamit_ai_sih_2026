import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme.dart';
import '../../models/shop_details.dart';
import 'models/prescription_draft.dart';
import 'prescription_preview_screen.dart';
import 'services/doctor_prescription_service.dart';

/// The doctor voice surface intentionally follows the main voice-page
/// interaction: one tap starts a live session and the next tap closes it.
/// Unlike retail voice, a completed utterance opens an editable prescription
/// rather than starting a spoken back-and-forth conversation.
class DoctorVoiceScreen extends StatefulWidget {
  final ShopDetails shopDetails;
  final bool isPrinterConnected;
  final VoidCallback togglePrinter;

  const DoctorVoiceScreen({
    super.key,
    required this.shopDetails,
    required this.isPrinterConnected,
    required this.togglePrinter,
  });

  @override
  State<DoctorVoiceScreen> createState() => _DoctorVoiceScreenState();
}

class _DoctorVoiceScreenState extends State<DoctorVoiceScreen>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final DoctorPrescriptionService _service = DoctorPrescriptionService();
  late final AnimationController _pulseController;

  Timer? _silenceTimer;
  Timer? _restartTimer;
  bool _speechReady = false;
  bool _isSessionActive = false;
  bool _isProcessing = false;
  int _draftRequestId = 0;
  String _sessionState = 'IDLE';
  String _transcript = '';
  double _audioLevel = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
      lowerBound: .82,
      upperBound: 1.18,
    );
  }

  Future<void> _toggleSession() async {
    if (_isProcessing) {
      _cancelDraftCreation();
      return;
    }
    if (_isSessionActive) {
      await _finishSession();
    } else {
      await _startSession();
    }
  }

  Future<void> _startSession() async {
    final ready = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: _onSpeechError,
    );
    if (!mounted) return;
    if (!ready) {
      setState(() => _sessionState = 'MICROPHONE PERMISSION NEEDED');
      return;
    }
    setState(() {
      _speechReady = true;
      _isSessionActive = true;
      _sessionState = 'LISTENING';
      _transcript = '';
      _audioLevel = .25;
    });
    _pulseController.repeat(reverse: true);
    await _startListening();
  }

  Future<void> _startListening() async {
    if (!_speechReady ||
        !_isSessionActive ||
        _isProcessing ||
        _speech.isListening) {
      return;
    }
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          localeId: 'en_IN',
          listenMode: stt.ListenMode.dictation,
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 8),
          partialResults: true,
          cancelOnError: false,
        ),
        onSoundLevelChange: (level) {
          if (!mounted || !_isSessionActive) return;
          setState(() {
            _audioLevel = (level.abs() / 30).clamp(.15, 1).toDouble();
          });
        },
        onResult: (result) {
          if (!mounted || !_isSessionActive) return;
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          setState(() {
            _transcript = words;
            _audioLevel = .75;
          });
          _silenceTimer?.cancel();
          // A brief natural pause submits the dictated prescription, just as
          // the main voice screen dispatches its utterance after silence.
          _silenceTimer = Timer(const Duration(milliseconds: 1800), () {
            if (_isSessionActive && !_isProcessing && _transcript.isNotEmpty) {
              _finishSession(submit: true);
            }
          });
          if (result.finalResult && words.isNotEmpty) {
            _finishSession(submit: true);
          }
        },
      );
    } catch (_) {
      _restartListening();
    }
  }

  void _onSpeechStatus(String status) {
    if (!_isSessionActive || _isProcessing || !mounted) return;
    if (status == 'done' || status == 'notListening') {
      _restartListening();
    }
  }

  void _onSpeechError(dynamic error) {
    if (!mounted) return;
    if (error.errorMsg.toLowerCase().contains('permission')) {
      _stopSession(showIdle: false);
      setState(() => _sessionState = 'MICROPHONE PERMISSION NEEDED');
      return;
    }
    if (_isSessionActive && !_isProcessing) _restartListening();
  }

  void _restartListening() {
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 450), () {
      if (_isSessionActive && !_isProcessing && mounted) _startListening();
    });
  }

  Future<void> _finishSession({bool submit = true}) async {
    if (!_isSessionActive && !_isProcessing) return;
    final transcription = _transcript.trim();
    await _stopSession(showIdle: !submit || transcription.isEmpty);
    if (submit && transcription.isNotEmpty) await _createDraft(transcription);
  }

  Future<void> _stopSession({required bool showIdle}) async {
    _silenceTimer?.cancel();
    _restartTimer?.cancel();
    // Flip the session state before stopping STT. Some Android devices emit
    // a final `done` callback from `stop`, which must not restart a session
    // that the doctor explicitly closed by tapping the voice circle.
    if (mounted) {
      setState(() {
        _isSessionActive = false;
        _audioLevel = 0;
        if (showIdle) _sessionState = 'TAP TO START';
      });
    }
    await _speech.stop();
    _pulseController.stop();
  }

  Future<void> _createDraft(String transcription) async {
    if (_isProcessing) return;
    final requestId = ++_draftRequestId;
    setState(() {
      _isProcessing = true;
      _sessionState = 'FORMATTING PRESCRIPTION';
    });
    try {
      final draft = await _service.processVoiceStream(transcription);
      if (!mounted || requestId != _draftRequestId) return;
      await _openPreview(draft);
    } catch (_) {
      if (mounted && requestId == _draftRequestId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Could not format the dictation. You can still use Manual mode.'),
          ),
        );
      }
    } finally {
      if (mounted && requestId == _draftRequestId) {
        setState(() {
          _isProcessing = false;
          _sessionState = 'TAP TO START';
          _transcript = '';
        });
      }
    }
  }

  void _cancelDraftCreation() {
    // The WebSocket service always closes its channel in `finally`. Bumping
    // the request id makes any late response harmless after the doctor taps
    // the orb to close it while formatting is in progress.
    _draftRequestId++;
    setState(() {
      _isProcessing = false;
      _sessionState = 'TAP TO START';
      _transcript = '';
      _audioLevel = 0;
    });
  }

  Future<void> _openPreview(PrescriptionDraft draft) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PrescriptionPreviewScreen(
          initialDraft: draft,
          shopDetails: widget.shopDetails,
          isPrinterConnected: widget.isPrinterConnected,
          togglePrinter: widget.togglePrinter,
        ),
      ),
    );
  }

  Future<void> _openManualMode() async {
    await _stopSession(showIdle: true);
    await _openPreview(PrescriptionDraft());
  }

  Future<void> _clearAll() async {
    await _stopSession(showIdle: true);
    if (!mounted) return;
    setState(() => _transcript = '');
  }

  @override
  void dispose() {
    _silenceTimer?.cancel();
    _restartTimer?.cancel();
    _speech.stop();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = _isSessionActive || _isProcessing;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textBlack,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Prescription Voice',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text('Speak naturally in English or Hinglish',
                style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: widget.isPrinterConnected
                ? 'Printer connected'
                : 'Connect printer',
            onPressed: widget.togglePrinter,
            icon: Icon(
              Icons.print_rounded,
              color: widget.isPrinterConnected
                  ? AppColors.printerConnected
                  : AppColors.printerDisconnected,
            ),
          ),
          IconButton(
            tooltip: 'Clear voice session',
            onPressed: _clearAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              // Header guidance tip card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.lightGreenBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFC8E6C9)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.health_and_safety_rounded,
                        color: AppColors.primaryGreen, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Dictate patient details, diagnosis, medicine, dose, frequency, duration and food instructions. A complete editable preview always opens before printing.',
                        style: TextStyle(
                            height: 1.35,
                            fontSize: 13,
                            color: Color(0xFF28512B)),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Interactive Kirana-identical voice circle stack
              Stack(
                alignment: Alignment.center,
                children: [
                  if (active) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      height: 160 + (_audioLevel * 20),
                      width: 160 + (_audioLevel * 20),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: (_isProcessing
                                  ? Colors.teal
                                  : (_isSessionActive
                                      ? Colors.green
                                      : Colors.grey))
                              .withValues(alpha: 0.2),
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
                          color: (_isProcessing
                                  ? Colors.teal
                                  : (_isSessionActive
                                      ? Colors.green
                                      : Colors.grey))
                              .withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ],
                  AnimatedScale(
                    scale: active ? 1.0 + (_audioLevel * 0.12) : 1.0,
                    duration: const Duration(milliseconds: 100),
                    child: GestureDetector(
                      onTap: _toggleSession,
                      child: Container(
                        height: 120,
                        width: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: active
                              ? LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: _isProcessing
                                      ? [
                                          Colors.teal.shade700,
                                          Colors.teal.shade500
                                        ]
                                      : [
                                          Colors.green.shade700,
                                          Colors.green.shade500
                                        ],
                                )
                              : null,
                          color: active ? null : Colors.white,
                          border: Border.all(
                            color: active
                                ? Colors.transparent
                                : Colors.grey.shade300,
                            width: 2,
                          ),
                          boxShadow: [
                            if (active)
                              BoxShadow(
                                color:
                                    (_isProcessing ? Colors.teal : Colors.green)
                                        .withValues(alpha: 0.4),
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
                          !active
                              ? Icons.mic
                              : (_isProcessing
                                  ? Icons.insights
                                  : Icons.graphic_eq),
                          size: 50,
                          color: active ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Status Badge Pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: (!active
                          ? Colors.grey
                          : (_isProcessing ? Colors.teal : Colors.green))
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (!active
                            ? Colors.grey
                            : (_isProcessing ? Colors.teal : Colors.green))
                        .withValues(alpha: 0.2),
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
                        color: !active
                            ? Colors.grey
                            : (_isProcessing ? Colors.teal : Colors.green),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      !active
                          ? (_sessionState == 'MICROPHONE PERMISSION NEEDED'
                              ? 'Permission Needed'
                              : 'Tap to start')
                          : (_isProcessing
                              ? 'Formatting Prescription...'
                              : 'Listening...'),
                      style: TextStyle(
                        color: !active
                            ? Colors.grey.shade700
                            : (_isProcessing
                                ? Colors.teal.shade700
                                : Colors.green.shade700),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Helper subtitle
              Text(
                _isSessionActive
                    ? 'Tap the voice circle again when finished or pause to submit.'
                    : 'Creates editable prescription draft automatically after you pause.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),

              const SizedBox(height: 20),

              // Live Transcription Box Card
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 100),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(
                    color: _transcript.isNotEmpty
                        ? AppColors.primaryGreen.withValues(alpha: 0.4)
                        : const Color(0xFFE0E0E0),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.record_voice_over_rounded,
                                size: 16,
                                color: _transcript.isNotEmpty
                                    ? AppColors.primaryGreen
                                    : Colors.grey.shade500),
                            const SizedBox(width: 6),
                            Text(
                              'LIVE TRANSCRIPTION',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: _transcript.isNotEmpty
                                    ? AppColors.primaryGreen
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        if (_transcript.isNotEmpty)
                          GestureDetector(
                            onTap: _clearAll,
                            child: const Text(
                              'Clear',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    const Divider(height: 16, thickness: 0.8),
                    Text(
                      _transcript.isEmpty
                          ? 'Your live transcription will appear here as you speak...'
                          : _transcript,
                      style: TextStyle(
                        color: _transcript.isEmpty
                            ? Colors.black38
                            : AppColors.textBlack,
                        fontSize: 14,
                        height: 1.4,
                        fontStyle: _transcript.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Action Buttons Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _clearAll,
                      icon: const Icon(Icons.clear_all_rounded, size: 20),
                      label: const Text('Clear all',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryGreen,
                        side: const BorderSide(
                            color: Color(0xFF81C784), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _openManualMode,
                      icon: const Icon(Icons.edit_note_rounded, size: 20),
                      label: const Text('Manual mode',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

