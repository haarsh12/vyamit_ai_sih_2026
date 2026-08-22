import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/shop_details.dart';
import '../providers/bill_provider.dart';
import '../services/livekit_voice_service.dart';
import '../services/workflow_draft_service.dart';
import '../services/printer_service.dart';
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

  // Manual toggle state for Live Bill Box
  bool _isManualLiveBillOpen = false;
  bool _isEditMode = false;

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not start the secure voice session. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
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
        // Extract items and update BillProvider if present
        if (event.payload['state'] != null &&
            event.payload['state']['items'] != null) {
          final rawItems = event.payload['state']['items'];
          if (rawItems is List) {
            final billItems = rawItems.map((item) {
              final map = Map<String, dynamic>.from(item as Map);
              final qty = map['quantity'] ?? map['qty'] ?? 1;
              final rate = (map['price'] ?? map['rate'] ?? 0).toDouble();
              final total = (map['total'] ?? (rate * qty)).toDouble();
              final unit = map['unit']?.toString() ?? 'pcs';
              return {
                'name': map['name']?.toString() ?? 'Item',
                'qty_display': '$qty $unit',
                'rate': rate,
                'total': total,
                'unit': unit,
              };
            }).toList();
            
            final billProvider = Provider.of<BillProvider>(context, listen: false);
            billProvider.updateBillItems(billItems);
          }
        }
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  )),
              const Divider(),
              Text('Total: ₹${state['total_amount'] ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.primaryGreen)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Keep editing'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
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
      
      // Clear bill & reset manual toggle state
      Provider.of<BillProvider>(context, listen: false).clearBill();
      setState(() {
        _isManualLiveBillOpen = false;
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

  void _resetBill(BillProvider billProvider) {
    billProvider.clearBill();
    setState(() {
      _isManualLiveBillOpen = false;
      _isEditMode = false;
    });
  }

  void _finalizeCurrentBill(BillProvider billProvider) async {
    final isConnected = await PrinterService().isConnected();
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("⚠️ Connect Printer First!",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    if (billProvider.currentBillItems.isEmpty) return;

    final billNumber = await billProvider.getNextBillNumber();

    final billData = {
      'id': billNumber,
      'date': DateFormat('dd-MM-yyyy').format(DateTime.now()),
      'time': DateFormat('hh:mm:ss a').format(DateTime.now()),
      'total': billProvider.billTotal,
      'customerName': billProvider.customerName,
      'shopName': widget.shopDetails.shopName,
      'shopAddress': widget.shopDetails.address,
      'shopPhone': widget.shopDetails.phone1,
      'items': billProvider.currentBillItems,
    };

    widget.onBillFinalized(billData);
    _resetBill(billProvider);
  }

  void _openShareModal(BillProvider billProvider) {
    if (billProvider.currentBillItems.isEmpty) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => BillShareModal(
          billItems: billProvider.currentBillItems,
          totalAmount: billProvider.billTotal,
          shopDetails: widget.shopDetails,
          customerName: billProvider.customerName,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  String _formatNumber(double value) {
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  Widget _buildGreetingView(BuildContext context) {
    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 12) {
      greeting = "Good Morning";
    } else if (hour < 17) {
      greeting = "Good Afternoon";
    } else {
      greeting = "Good Evening";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront_rounded,
              size: 42,
              color: AppColors.primaryGreen,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "$greeting, ${widget.shopDetails.ownerName.isNotEmpty ? widget.shopDetails.ownerName : 'Partner'}!",
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textBlack,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            widget.shopDetails.shopName.isNotEmpty ? widget.shopDetails.shopName : "Vyamit AI Smart Billing",
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryGreen,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_outline_rounded, size: 18, color: AppColors.primaryGreen),
                    SizedBox(width: 8),
                    Text(
                      "Voice Commands Tip",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textBlack),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  "Say 'Add 2 kg sugar and 1 packet milk' or ask for catalog items in English, Hindi, or Marathi.",
                  style: TextStyle(fontSize: 12, color: AppColors.textGrey, height: 1.35),
                  textAlign: TextAlign.start,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _active || _voice.isConnecting;
    final billProvider = Provider.of<BillProvider>(context);
    final currentBill = billProvider.currentBillItems;
    
    // Auto-toggle / manual logic for Live Bill Box
    final bool showLiveBill = currentBill.isNotEmpty || _isManualLiveBillOpen;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textBlack,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vyamit Voice Assistant', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            Text('Hindi, Marathi & English Supported', style: TextStyle(fontSize: 12, color: AppColors.textGrey)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: widget.isPrinterConnected ? 'Printer connected' : 'Connect printer',
            onPressed: widget.togglePrinter,
            icon: Icon(
              Icons.print_rounded,
              color: widget.isPrinterConnected ? AppColors.printerConnected : AppColors.printerDisconnected,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Top Voice Control Area
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: Column(
                    children: [
                      // Circular Voice Mic Button
                      ScaleTransition(
                        scale: active ? _pulse : const AlwaysStoppedAnimation(1),
                        child: GestureDetector(
                          onTap: _confirming ? null : _toggleVoice,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: active ? AppColors.primaryGreen : Colors.white,
                              border: Border.all(color: AppColors.primaryGreen, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryGreen.withOpacity(active ? 0.3 : 0.1),
                                  blurRadius: 20,
                                  spreadRadius: 4,
                                )
                              ],
                            ),
                            child: Icon(
                              active ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                              size: 46,
                              color: active ? Colors.white : AppColors.primaryGreen,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _status,
                        style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      // Transcription Banner
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 50, maxHeight: 70),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7FAF6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.primaryGreen.withOpacity(0.2)),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            _transcript.isEmpty
                                ? 'Tap the mic and speak naturally...'
                                : _transcript,
                            style: TextStyle(
                              color: _transcript.isEmpty ? AppColors.textGrey : AppColors.textBlack,
                              fontSize: 13,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Main Content Area: Live Bill Box OR Greeting View
                if (showLiveBill)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Column(
                        children: [
                          // Live Bill Header
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.receipt_long, color: AppColors.primaryGreen, size: 20),
                                    SizedBox(width: 8),
                                    Text("Live Bill Box",
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  ],
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(_isEditMode ? Icons.check : Icons.edit, size: 20),
                                      onPressed: () => setState(() => _isEditMode = !_isEditMode),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _resetBill(billProvider),
                                      icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                                      label: const Text("Clear",
                                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Table Column Headers
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: Row(
                              children: [
                                Expanded(flex: 4, child: Text("Item", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey))),
                                Expanded(flex: 2, child: Text("Qty", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey))),
                                Expanded(flex: 3, child: Text("Rate", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey))),
                                Expanded(flex: 3, child: Text("Total", textAlign: TextAlign.right, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey))),
                              ],
                            ),
                          ),
                          const Divider(height: 1),

                          // Bill Items List
                          Expanded(
                            child: currentBill.isEmpty
                                ? const Center(
                                    child: Text(
                                      "No items in live bill.\nSpeak to add items or type below.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.grey, fontSize: 13),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    itemCount: currentBill.length,
                                    separatorBuilder: (_, __) => const Divider(height: 12),
                                    itemBuilder: (context, index) {
                                      final item = currentBill[index];
                                      final rate = (item['rate'] as num?)?.toDouble() ?? 0.0;
                                      final total = (item['total'] as num?)?.toDouble() ?? (rate * 1);
                                      final qtyDisplay = item['qty_display']?.toString() ?? '${item['qty'] ?? 1}';

                                      return Row(
                                        children: [
                                          if (_isEditMode)
                                            GestureDetector(
                                              onTap: () => billProvider.removeBillItem(index),
                                              child: Container(
                                                margin: const EdgeInsets.only(right: 8),
                                                padding: const EdgeInsets.all(2),
                                                decoration: const BoxDecoration(color: Color(0xFFFFEBEB), shape: BoxShape.circle),
                                                child: const Icon(Icons.remove, size: 14, color: Colors.red),
                                              ),
                                            ),
                                          Expanded(
                                            flex: 4,
                                            child: Text(
                                              item['name']?.toString() ?? 'Item',
                                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 2,
                                            child: Text(
                                              qtyDisplay,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              "₹${_formatNumber(rate)}",
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              "₹${_formatNumber(total)}",
                                              textAlign: TextAlign.right,
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                          ),

                          // Live Bill Footer Controls
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("TOTAL AMOUNT", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                                    Text(
                                      "₹${_formatNumber(billProvider.billTotal)}",
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textBlack),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Transform.rotate(
                                      angle: -0.5,
                                      child: IconButton(
                                        onPressed: currentBill.isEmpty ? null : () => _openShareModal(billProvider),
                                        icon: Icon(
                                          Icons.send,
                                          color: currentBill.isEmpty ? Colors.grey : AppColors.primaryGreen,
                                          size: 22,
                                        ),
                                        style: IconButton.styleFrom(
                                          backgroundColor: currentBill.isEmpty
                                              ? Colors.grey[200]
                                              : AppColors.primaryGreen.withOpacity(0.1),
                                          padding: const EdgeInsets.all(10),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: currentBill.isEmpty ? null : () => _finalizeCurrentBill(billProvider),
                                        icon: const Icon(Icons.print, color: Colors.white, size: 18),
                                        label: const Text(
                                          "PRINT & SAVE",
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.textBlack,
                                          minimumSize: const Size(0, 48),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                                        ),
                                      ),
                                    ),
                                  ],
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

            // Floating Action Button to manually trigger Live Bill Box when closed
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
  }
}
