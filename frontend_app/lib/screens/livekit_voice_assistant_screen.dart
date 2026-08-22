import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../models/shop_details.dart';
import '../providers/bill_provider.dart';
import '../services/livekit_voice_service.dart';
import '../services/workflow_draft_service.dart';
import '../services/printer_service.dart';
import '../features/gst/gst_invoice_preview_screen.dart';
import '../features/gst/models/gst_invoice_draft.dart';
import '../features/gst/providers/gst_provider.dart';
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
  final WorkflowDraftService _drafts = WorkflowDraftService();
  StreamSubscription<VoiceUiEvent>? _events;

  // Session & Voice state
  bool _isSessionActive = false;
  String _sessionState = "IDLE"; // IDLE, LISTENING, PROCESSING, SPEAKING
  String _transcript = "";
  String _agentResponse = "Tap to Start";
  double _audioLevel = 0.0;
  Timer? _audioLevelTimer;

  // Edit Mode & Live Bill State
  bool _isEditMode = false;
  bool _isManualLiveBillOpen = false;

  @override
  void initState() {
    super.initState();
    _events = _voice.events.listen(_handleVoiceEvent);
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
      _sessionState = "LISTENING";
      _transcript = "";
      _agentResponse = "Listening...";
      _audioLevel = 0.3;
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
      _transcript = "";
      _agentResponse = "Tap to Start";
      _audioLevel = 0.0;
    });
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
          if (_sessionState == "SPEAKING") {
            _audioLevel = 0.5 + (0.4 * (tick % 10) / 10);
          } else if (_sessionState == "PROCESSING") {
            _audioLevel = 0.4 + (0.2 * (tick % 10) / 10);
          } else if (_transcript.isNotEmpty) {
            _audioLevel = 0.6 + (0.4 * (tick % 10) / 10);
          } else {
            _audioLevel = 0.3 + (0.2 * (tick % 10) / 10);
          }
        });
      },
    );
  }

  void _handleVoiceEvent(VoiceUiEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case 'connected':
        setState(() {
          _isSessionActive = true;
          _sessionState = "LISTENING";
          if (_agentResponse == "Tap to Start") {
            _agentResponse = "Listening...";
          }
        });
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
        final rawState = event.payload['state']?.toString().toLowerCase() ?? '';
        setState(() {
          if (rawState.contains('speaking')) {
            _sessionState = "SPEAKING";
          } else if (rawState.contains('thinking') || rawState.contains('processing')) {
            _sessionState = "PROCESSING";
            if (_agentResponse == "Listening...") {
              _agentResponse = "Thinking...";
            }
          } else {
            _sessionState = "LISTENING";
            if (_agentResponse == "Thinking...") {
              _agentResponse = "Listening...";
            }
          }
        });
        break;

      case 'bill_draft':
        if (event.payload['state'] != null &&
            event.payload['state']['items'] != null) {
          final rawItems = event.payload['state']['items'];
          if (rawItems is List) {
            final billItems = rawItems.map((item) {
              final map = Map<String, dynamic>.from(item as Map);
              final qty = map['quantity'] ?? map['qty'] ?? 1;
              final rate = _asDouble(map['price'] ?? map['rate']);
              final total = _asDouble(map['total'] ?? (rate * _asDouble(qty)));
              final unit = map['unit']?.toString() ?? 'kg';
              var qtyDisplay = map['qty_display']?.toString() ?? '${_formatNumber(_asDouble(qty))}$unit';

              return <String, dynamic>{
                'name': map['name']?.toString() ?? 'Item',
                'en': map['name']?.toString() ?? 'Item',
                'hi': map['name']?.toString() ?? 'Item',
                'qty': '$qty',
                'qty_display': qtyDisplay,
                'rate': rate,
                'total': total,
                'unit': unit,
                'gst_rate': _asDouble(map['gst_rate']),
              };
            }).toList();

            final billProvider = Provider.of<BillProvider>(context, listen: false);
            billProvider.updateBillItems(billItems);
          }
        }
        break;

      case 'disconnected':
        if (_isSessionActive) {
          _stopContinuousSession();
        }
        break;

      case 'error':
        setState(() {
          _sessionState = "IDLE";
          _agentResponse = "Voice Error";
        });
        break;
    }
  }

  // Formatting & Calculation Helpers
  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _formatNumber(double value) {
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
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
    _stopContinuousSession();
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
        await _stopContinuousSession();
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
    };

    widget.onBillFinalized(billData);
    await _stopContinuousSession();
    billProvider.clearBill();

    setState(() {
      _agentResponse = "Bill Printed!";
      _isManualLiveBillOpen = false;
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
    if (_sessionState == "LISTENING") return "Listening...";
    if (_sessionState == "PROCESSING") return "Processing speech...";
    if (_sessionState == "SPEAKING") return "Vyamit AI Speaking...";
    return "Tap to Start Call Session";
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

  @override
  Widget build(BuildContext context) {
    final gstProvider = context.watch<GstProvider>();
    final statusColor = !_isSessionActive
        ? Colors.grey
        : (_sessionState == "LISTENING"
            ? Colors.green
            : (_sessionState == "PROCESSING"
                ? Colors.blue
                : Colors.teal));

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

                    // 2. Voice Circle & Mic Animations
                    if (!_isEditMode)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                if (_isSessionActive) ...[
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 500),
                                    height: 160 + (_audioLevel * 20),
                                    width: 160 + (_audioLevel * 20),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: statusColor.withOpacity(0.2),
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
                                        color: statusColor.withOpacity(0.3),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
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
                                                colors: _sessionState ==
                                                        "LISTENING"
                                                    ? [
                                                        Colors.green.shade700,
                                                        Colors.green.shade500
                                                      ]
                                                    : (_sessionState ==
                                                            "PROCESSING"
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
                                        color: _isSessionActive
                                            ? null
                                            : Colors.white,
                                        border: Border.all(
                                          color: _isSessionActive
                                              ? Colors.transparent
                                              : Colors.grey.shade300,
                                          width: 2,
                                        ),
                                        boxShadow: [
                                          if (_isSessionActive)
                                            BoxShadow(
                                              color: statusColor.withOpacity(0.4),
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
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: statusColor.withOpacity(0.2),
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
                                      color: statusColor,
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
                                          : (statusColor is MaterialColor
                                              ? statusColor.shade700
                                              : statusColor),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Speech Display
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

                            // AI Response Display
                            SizedBox(
                              height: 24,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _agentResponse,
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
