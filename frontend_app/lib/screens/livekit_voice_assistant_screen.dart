import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/shop_details.dart';
import '../services/livekit_voice_service.dart';
import '../services/workflow_draft_service.dart';

/// Retail voice surface backed by the authenticated LiveKit room.
///
/// It deliberately keeps financial confirmation in the app: the agent can
/// create a proposal but this screen is the only path that confirms it.
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
    extends State<LiveKitVoiceAssistantScreen>
    with SingleTickerProviderStateMixin {
  final LiveKitVoiceService _voice = LiveKitVoiceService();
  final WorkflowDraftService _drafts = WorkflowDraftService();
  late final AnimationController _pulse;
  StreamSubscription<VoiceUiEvent>? _events;
  bool _active = false;
  bool _confirming = false;
  String _status = 'TAP TO START';
  String _transcript = '';
  String? _shownDraftId;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: .88,
      upperBound: 1.12,
    );
    _events = _voice.events.listen(_handleVoiceEvent);
  }

  @override
  void dispose() {
    _events?.cancel();
    _pulse.dispose();
    _voice.dispose();
    super.dispose();
  }

  Future<void> _toggleVoice() async {
    if (_active || _voice.isConnecting) {
      await _stopVoice();
      return;
    }
    setState(() {
      _active = true;
      _status = 'CONNECTING';
      _transcript = '';
      _shownDraftId = null;
    });
    _pulse.repeat(reverse: true);
    try {
      await _voice.connect(participantName: widget.shopDetails.ownerName);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _active = false;
        _status = 'VOICE UNAVAILABLE';
      });
      _pulse.stop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not start the secure voice session. Please try again.'),
      ));
    }
  }

  Future<void> _stopVoice() async {
    await _voice.disconnect();
    if (!mounted) return;
    _pulse.stop();
    setState(() {
      _active = false;
      _confirming = false;
      _status = 'TAP TO START';
    });
  }

  void _handleVoiceEvent(VoiceUiEvent event) {
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
        final state = event.payload['state']?.toString().trim();
        if (state != null && state.isNotEmpty) {
          setState(() => _status = state.toUpperCase());
        }
        break;
      case 'bill_draft':
        final draftId = event.payload['draft_id']?.toString();
        if (draftId != null && draftId.isNotEmpty && draftId != _shownDraftId) {
          _shownDraftId = draftId;
          _showBillReview(event.payload);
        }
        break;
      case 'disconnected':
        if (_active) _stopVoice();
        break;
      case 'error':
        setState(() => _status = 'VOICE ERROR');
        break;
    }
  }

  Future<void> _showBillReview(Map<String, dynamic> payload) async {
    final rawState = payload['state'];
    if (rawState is! Map) return;
    final state = Map<String, dynamic>.from(rawState);
    final rawItems = state['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map>().map((item) => Map<String, dynamic>.from(item)).toList()
        : <Map<String, dynamic>>[];
    final draftId = payload['draft_id']?.toString();
    final version = payload['version'] is num
        ? (payload['version'] as num).toInt()
        : int.tryParse('${payload['version']}');
    if (draftId == null || version == null || items.isEmpty || !mounted) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Review bill draft',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              const SizedBox(height: 6),
              const Text('Check every item and total before confirming.'),
              const SizedBox(height: 16),
              ...items.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${item['name'] ?? 'Item'}  •  ${item['quantity'] ?? item['qty'] ?? 1} ${item['unit'] ?? ''}  •  ₹${item['total'] ?? 0}',
                    ),
                  )),
              const Divider(),
              Text('Total: ₹${state['total_amount'] ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep editing'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm bill'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (confirmed == true) await _confirmBill(draftId, version, state, items);
  }

  Future<void> _confirmBill(
    String draftId,
    int version,
    Map<String, dynamic> state,
    List<Map<String, dynamic>> items,
  ) async {
    if (_confirming) return;
    setState(() {
      _confirming = true;
      _status = 'SAVING BILL';
    });
    try {
      await _drafts.confirmBillDraft(draftId: draftId, version: version);
      if (!mounted) return;
      final total = double.tryParse('${state['total_amount'] ?? 0}') ?? 0;
      widget.onBillFinalized({
        'id': draftId,
        'date': DateTime.now().toIso8601String(),
        'time': TimeOfDay.now().format(context),
        'total': total,
        'customerName': state['customer_name']?.toString() ?? 'Walk-in',
        'shopName': widget.shopDetails.shopName,
        'shopAddress': widget.shopDetails.address,
        'shopPhone': widget.shopDetails.phone1,
        'server_saved': true,
        'items': items.map((item) => {
              'name': item['name'],
              'qty': item['quantity'] ?? item['qty'],
              'unit': item['unit'],
              'rate': item['price'] ?? item['rate'],
              'price': item['price'] ?? item['rate'],
              'total': item['total'],
            }).toList(),
      });
      await _stopVoice();
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'REVIEW REQUIRED');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('The bill was not confirmed. Refresh the draft and try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
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
        title: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Vyamit Voice', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          Text('Hindi, Marathi and English', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
        ]),
        actions: [
          IconButton(
            tooltip: widget.isPrinterConnected ? 'Printer connected' : 'Connect printer',
            onPressed: widget.togglePrinter,
            icon: Icon(Icons.print_rounded,
                color: widget.isPrinterConnected ? AppColors.printerConnected : AppColors.printerDisconnected),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Text('Speak naturally. Vyamit will ask before creating a bill draft.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textGrey)),
            const Spacer(),
            ScaleTransition(
              scale: active ? _pulse : const AlwaysStoppedAnimation(1),
              child: GestureDetector(
                onTap: _confirming ? null : _toggleVoice,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? AppColors.primaryGreen : Colors.white,
                    border: Border.all(color: AppColors.primaryGreen, width: 3),
                    boxShadow: [BoxShadow(color: AppColors.primaryGreen.withValues(alpha: .22), blurRadius: 28, spreadRadius: 6)],
                  ),
                  child: Icon(active ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                      size: 64, color: active ? Colors.white : AppColors.primaryGreen),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(_status, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .8)),
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 130),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAF6),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primaryGreen.withValues(alpha: .25)),
              ),
              child: Text(
                _transcript.isEmpty ? 'Your secure live transcription will appear here.' : _transcript,
                style: TextStyle(color: _transcript.isEmpty ? AppColors.textGrey : AppColors.textBlack, height: 1.4),
              ),
            ),
            const Spacer(),
            Text(active ? 'Tap to end the secure voice session' : 'Tap the microphone to start',
                style: const TextStyle(color: AppColors.textGrey)),
          ]),
        ),
      ),
    );
  }
}
