import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/shop_details.dart';
import '../../services/livekit_voice_service.dart';
import 'models/prescription_draft.dart';
import 'prescription_preview_screen.dart';

/// Doctor dictation through LiveKit; no device STT, local TTS, or text socket.
class LiveKitDoctorVoiceScreen extends StatefulWidget {
  final ShopDetails shopDetails;
  final bool isPrinterConnected;
  final VoidCallback togglePrinter;

  const LiveKitDoctorVoiceScreen({
    super.key,
    required this.shopDetails,
    required this.isPrinterConnected,
    required this.togglePrinter,
  });

  @override
  State<LiveKitDoctorVoiceScreen> createState() =>
      _LiveKitDoctorVoiceScreenState();
}

class _LiveKitDoctorVoiceScreenState extends State<LiveKitDoctorVoiceScreen>
    with SingleTickerProviderStateMixin {
  final LiveKitVoiceService _voice = LiveKitVoiceService();
  late final AnimationController _pulse;
  StreamSubscription<VoiceUiEvent>? _events;
  bool _active = false;
  bool _openingDraft = false;
  String _status = 'TAP TO START';
  String _transcript = '';

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: .88,
      upperBound: 1.12,
    );
    _events = _voice.events.listen(_onVoiceEvent);
  }

  @override
  void dispose() {
    _events?.cancel();
    _pulse.dispose();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_active || _voice.isConnecting) {
      await _stop();
      return;
    }
    setState(() {
      _active = true;
      _status = 'CONNECTING';
      _transcript = '';
    });
    _pulse.repeat(reverse: true);
    try {
      await _voice.connect(participantName: widget.shopDetails.ownerName);
    } catch (_) {
      if (!mounted) return;
      _pulse.stop();
      setState(() {
        _active = false;
        _status = 'VOICE UNAVAILABLE';
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not start the secure dictation session.'),
      ));
    }
  }

  Future<void> _stop() async {
    await _voice.disconnect();
    if (!mounted) return;
    _pulse.stop();
    setState(() {
      _active = false;
      _status = 'TAP TO START';
    });
  }

  void _onVoiceEvent(VoiceUiEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case 'connected':
        setState(() => _status = 'LISTENING');
        break;
      case 'user_transcript':
        final text = event.payload['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) setState(() => _transcript = text);
        break;
      case 'agent_state':
        final state = event.payload['state']?.toString();
        if (state != null && state.isNotEmpty)
          setState(() => _status = state.toUpperCase());
        break;
      case 'prescription_draft':
        _openDraft(event.payload);
        break;
      case 'disconnected':
        if (_active) _stop();
        break;
      case 'error':
        setState(() => _status = 'VOICE ERROR');
        break;
    }
  }

  Future<void> _openDraft(Map<String, dynamic> payload) async {
    if (_openingDraft || !mounted) return;
    final rawDraft = payload['draft'];
    if (rawDraft is! Map) return;
    _openingDraft = true;
    await _stop();
    if (!mounted) return;
    try {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PrescriptionPreviewScreen(
          initialDraft: PrescriptionDraft.fromVoiceJson(
              Map<String, dynamic>.from(rawDraft)),
          shopDetails: widget.shopDetails,
          isPrinterConnected: widget.isPrinterConnected,
          togglePrinter: widget.togglePrinter,
        ),
      ));
    } finally {
      _openingDraft = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _active || _voice.isConnecting;
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
              Text('Secure clinical dictation',
                  style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
            ]),
        actions: [
          IconButton(
            tooltip: widget.isPrinterConnected
                ? 'Printer connected'
                : 'Connect printer',
            onPressed: widget.togglePrinter,
            icon: Icon(Icons.print_rounded,
                color: widget.isPrinterConnected
                    ? AppColors.printerConnected
                    : AppColors.printerDisconnected),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Text(
              'Dictate patient details, diagnosis and medications. An editable preview always opens before printing.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textGrey, height: 1.35),
            ),
            const Spacer(),
            ScaleTransition(
              scale: active ? _pulse : const AlwaysStoppedAnimation(1),
              child: GestureDetector(
                onTap: _openingDraft ? null : _toggle,
                child: Container(
                  height: 148,
                  width: 148,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? Colors.teal.shade600 : Colors.white,
                    border: Border.all(color: Colors.teal.shade600, width: 3),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.teal.withValues(alpha: .2),
                          blurRadius: 28,
                          spreadRadius: 5)
                    ],
                  ),
                  child: Icon(
                      active ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                      size: 62,
                      color: active ? Colors.white : Colors.teal.shade600),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(_status,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, letterSpacing: .8)),
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 130),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAF6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.teal.withValues(alpha: .25)),
              ),
              child: Text(
                _transcript.isEmpty
                    ? 'Your live dictation will appear here.'
                    : _transcript,
                style: TextStyle(
                    color: _transcript.isEmpty
                        ? AppColors.textGrey
                        : AppColors.textBlack,
                    height: 1.4),
              ),
            ),
            const Spacer(),
            Text(
                active ? 'Tap to end dictation' : 'Tap the microphone to start',
                style: const TextStyle(color: AppColors.textGrey)),
          ]),
        ),
      ),
    );
  }
}
