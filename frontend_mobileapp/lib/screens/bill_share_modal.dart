import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../models/shop_details.dart';
import '../models/customer.dart';
import '../widgets/udhaar_bill_confirmation_dialog.dart';
import '../widgets/customer_verification_dialog.dart';
import '../services/customer_service.dart';
import '../services/api_client.dart';
import '../services/analytics_service.dart';
import '../services/auth_token_store.dart';

class BillShareModal extends StatefulWidget {
  final List<Map<String, dynamic>> billItems;
  final double totalAmount;
  final ShopDetails shopDetails;
  final String? customerName;
  final String paymentMethod;
  final int? verifiedCustomerId;
  final String billingSource;

  const BillShareModal({
    super.key,
    required this.billItems,
    required this.totalAmount,
    required this.shopDetails,
    this.customerName,
    this.paymentMethod = 'cash',
    this.verifiedCustomerId,
    this.billingSource = 'voice',
  });

  @override
  State<BillShareModal> createState() => _BillShareModalState();
}

class _BillShareModalState extends State<BillShareModal> {
  late final TextEditingController _customerNameController;
  final TextEditingController _mobileController = TextEditingController();
  late final CustomerService _customerService;
  final AnalyticsService _analyticsService = AnalyticsService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _customerService = CustomerService(ApiClient());
    _customerNameController = TextEditingController(
        text:
            widget.customerName != null && !_isGenericName(widget.customerName!)
                ? widget.customerName
                : 'Walk-in');
  }

  bool _isGenericName(String name) {
    final generic = [
      'customer',
      'guest',
      'user',
      'anonymous',
      'unknown',
      'unnamed',
      'walk-in',
      'walkin',
      'walk in',
      'retail',
      'cash',
      'n/a',
      'na',
    ];
    return generic.contains(name.toLowerCase().trim());
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  String _generateBillText() {
    // Helper function to format rows with proper alignment
    String formatRow(String name, String qty, String rate, String amount) {
      // Pad strings to fixed widths for alignment
      final namePad = name.padRight(15);
      final qtyPad = qty.padRight(6);
      final ratePad = rate.padRight(7);
      final amtPad = amount.padLeft(7);
      return '$namePad$qtyPad$ratePad$amtPad';
    }

    final buffer = StringBuffer();

    // Header with real shop details
    buffer.writeln('🧾 *VYAMIT AI RECEIPT*');
    buffer.writeln('');
    buffer.writeln('*${widget.shopDetails.shopName.toUpperCase()}*');
    buffer.writeln(widget.shopDetails.address);
    buffer.writeln('📞 ${widget.shopDetails.phone1}');
    if (widget.shopDetails.phone2.isNotEmpty) {
      buffer.writeln('📞 ${widget.shopDetails.phone2}');
    }
    buffer.writeln('');
    buffer.writeln('Customer: ${_customerNameController.text}');

    // Date and Time
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    final hour =
        now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final time =
        '${hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} $ampm';

    buffer.writeln('Date: $date');
    buffer.writeln('Time: $time');
    buffer.writeln('--------------------------------');

    // Column Headers
    buffer.writeln(formatRow('Item', 'Qty', 'Rate', 'Amt'));
    buffer.writeln('--------------------------------');

    // Items
    for (var item in widget.billItems) {
      final name = item['name'] ?? item['en'] ?? 'Item';
      final qtyDisplay = item['qty_display'] ?? item['qty'] ?? '1';
      final rate = (item['rate'] ?? 0.0).toStringAsFixed(0);
      final total = (item['total'] ?? 0.0).toStringAsFixed(0);

      buffer.writeln(formatRow(
        name.length > 15 ? name.substring(0, 15) : name,
        qtyDisplay,
        rate,
        total,
      ));
    }

    buffer.writeln('--------------------------------');
    buffer.writeln('*TOTAL:* ₹${widget.totalAmount.toStringAsFixed(0)}');
    buffer.writeln('--------------------------------');
    buffer.writeln('');
    buffer.writeln('🙏 Thank you! Visit Again');
    buffer.writeln('⚡ Powered by Vyamit AI');

    return buffer.toString();
  }

  String get _finalCustomerName {
    final name = _customerNameController.text.trim();
    return name.isEmpty ? 'Walk-in' : name;
  }

  double _asNumber(dynamic value) {
    if (value is num) return value.toDouble();
    final text = value?.toString() ?? '';
    return double.tryParse(text) ??
        double.tryParse(text.replaceAll(RegExp(r'[^0-9.]'), '')) ??
        0;
  }

  List<Map<String, dynamic>> _billItemsForApi() {
    return widget.billItems.map((item) {
      final quantity =
          _asNumber(item['quantity'] ?? item['qty'] ?? item['qty_display']);
      final safeQuantity = quantity > 0 ? quantity : 1.0;
      final price = _asNumber(item['price'] ?? item['rate']);
      final total = double.parse((safeQuantity * price).toStringAsFixed(2));
      return {
        'name': (item['name'] ?? item['en'] ?? 'Item').toString(),
        'quantity': safeQuantity,
        'unit': (item['unit'] ?? 'unit').toString(),
        'price': double.parse(price.toStringAsFixed(2)),
        'total': total,
      };
    }).toList();
  }

  Future<int?> _saveVirtualBill() async {
    final token = await AuthTokenStore().read();
    if (token == null) {
      throw const AnalyticsRequestException(
        'Your session has expired. Please sign in again.',
      );
    }

    final items = _billItemsForApi();
    final total = items.fold<double>(
      0,
      (sum, item) => sum + (item['total'] as double),
    );
    final result = await _analyticsService.saveBill(
      token,
      totalAmount: double.parse(total.toStringAsFixed(2)),
      items: items,
      customerPhone: _mobileController.text.trim(),
      customerName: _finalCustomerName,
      paymentMethod: widget.paymentMethod,
      verifiedCustomerId: widget.verifiedCustomerId,
      billType: 'virtual',
      billingSource: widget.billingSource,
    );
    final billId = result['bill_id'];
    return billId is num ? billId.toInt() : null;
  }

  Future<bool> _verifyAndLinkCustomer(
    CustomerVerificationSuggestion suggestion,
    int billId,
  ) async {
    try {
      final result = await _customerService.verifyCustomer(
        customerName: suggestion.customerName!,
        phoneNumber: _mobileController.text.trim(),
        mergeWithExistingId:
            suggestion.isDuplicate ? suggestion.existingCustomerId : null,
        linkBillId: billId,
      );
      if (mounted) {
        _showSuccess(result['message']?.toString() ?? 'Customer saved');
      }
      return true;
    } catch (error) {
      if (mounted) {
        _showError(
            'Virtual bill saved, but customer verification failed: $error');
      }
      return false;
    }
  }

  Future<void> _showCustomerVerification(
    CustomerVerificationSuggestion suggestion,
    int billId,
  ) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => CustomerVerificationDialog(
        suggestion: suggestion,
        onNo: () => Navigator.of(dialogContext).pop(),
        onYes: () async {
          if (await _verifyAndLinkCustomer(suggestion, billId) &&
              dialogContext.mounted) {
            Navigator.of(dialogContext).pop();
          }
        },
      ),
    );
  }

  Future<void> _completeVirtualShare(
    Future<bool> Function() openShareApp,
    String channel,
  ) async {
    if (_isLoading) return;
    if (widget.paymentMethod == 'udhaar') {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => UdhaarBillConfirmationDialog(
          customerName: _finalCustomerName,
          amount: widget.totalAmount,
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _isLoading = true);

    try {
      if (!await openShareApp()) {
        _showError('Failed to open $channel');
        return;
      }

      final billId = await _saveVirtualBill();
      if (billId == null) {
        _showError(
            'The $channel bill was opened but could not be saved to history.');
        return;
      }

      CustomerVerificationSuggestion? suggestion;
      try {
        suggestion = await _customerService.getVerificationSuggestion(
          _finalCustomerName,
        );
      } catch (_) {
        if (mounted) {
          setState(() => _isLoading = false);
          _showError(
            'Virtual bill was saved to history, but customer verification is unavailable.',
          );
          Navigator.of(context).pop(true);
        }
        return;
      }
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (suggestion != null && suggestion.shouldVerify) {
        await _showCustomerVerification(suggestion, billId);
      } else {
        _showSuccess('Virtual bill saved to history.');
      }

      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) _showError('Failed to save virtual bill: $error');
    } finally {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    }
  }

  Future<void> _shareViaSMS() async {
    final mobile = _mobileController.text.trim();

    if (mobile.isEmpty || mobile.length < 10) {
      _showError('Please enter a valid 10-digit mobile number');
      return;
    }

    final billText = _generateBillText();
    final encodedText = Uri.encodeComponent(billText);

    // Format: sms:<number>?body=<message>
    final cleanMobile = mobile.replaceAll('+', '').replaceAll(' ', '');
    final formattedMobile =
        cleanMobile.startsWith('91') ? cleanMobile : '91$cleanMobile';

    // Use SMS scheme to open device SMS app
    final smsUrl = 'sms:+$formattedMobile?body=$encodedText';

    try {
      final uri = Uri.parse(smsUrl);

      print('🔍 Trying to launch SMS: $smsUrl');

      if (await canLaunchUrl(uri)) {
        await _completeVirtualShare(
          () => launchUrl(uri),
          'SMS',
        );
      } else {
        _showError('SMS app not available');
      }
    } catch (e) {
      print('❌ SMS launch error: $e');
      _showError('Failed to open SMS app: $e');
    }
  }

  Future<void> _shareViaWhatsApp() async {
    final mobile = _mobileController.text.trim();

    if (mobile.isEmpty || mobile.length < 10) {
      _showError('Please enter a valid 10-digit mobile number');
      return;
    }

    final billText = _generateBillText();
    final encodedText = Uri.encodeComponent(billText);

    // Format: Remove +91 prefix, WhatsApp handles it
    final cleanMobile = mobile.replaceAll('+', '').replaceAll(' ', '');
    final formattedMobile =
        cleanMobile.startsWith('91') ? cleanMobile : '91$cleanMobile';

    // Use whatsapp:// scheme for better app detection
    final whatsappUrl =
        'whatsapp://send?phone=$formattedMobile&text=$encodedText';

    try {
      final uri = Uri.parse(whatsappUrl);
      final canLaunch = await canLaunchUrl(uri);

      print('🔍 Trying to launch: $whatsappUrl');
      print('🔍 Can launch: $canLaunch');

      if (canLaunch) {
        await _completeVirtualShare(
          () => launchUrl(uri, mode: LaunchMode.externalApplication),
          'WhatsApp',
        );
      } else {
        // Fallback to https URL
        final fallbackUrl = 'https://wa.me/$formattedMobile?text=$encodedText';
        final fallbackUri = Uri.parse(fallbackUrl);

        if (await canLaunchUrl(fallbackUri)) {
          await _completeVirtualShare(
            () => launchUrl(fallbackUri, mode: LaunchMode.externalApplication),
            'WhatsApp',
          );
        } else {
          _showError('WhatsApp is not installed');
        }
      }
    } catch (e) {
      print('❌ WhatsApp launch error: $e');
      _showError('Failed to open WhatsApp: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primaryGreen,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Grey semi-transparent background (like Edit Item)
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              color: Colors.black.withOpacity(0.5),
            ),
          ),

          // Centered modal (like Edit Item dialog)
          Center(
            child: Container(
              width: screenWidth * 0.85,
              constraints: BoxConstraints(
                maxHeight: screenHeight * 0.7,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Share Bill',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.grey),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Customer Name
                          const Text(
                            'Customer Name',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _customerNameController,
                            decoration: InputDecoration(
                              hintText: 'Enter customer name',
                              filled: true,
                              fillColor: Colors.grey[50],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey[300]!),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Mobile Number
                          const Text(
                            'Mobile Number',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _mobileController,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            decoration: InputDecoration(
                              hintText: 'Enter 10-digit mobile number',
                              prefixText: '+91 ',
                              filled: true,
                              fillColor: Colors.grey[50],
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide:
                                    BorderSide(color: Colors.grey[300]!),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              counterText: '',
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Share Options
                          const Text(
                            'Share Via',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Three circles for sharing options
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // SMS (Opens device SMS app)
                              _buildShareOption(
                                icon: Icons.sms,
                                label: 'SMS',
                                color: const Color(0xFF2196F3),
                                isEnabled: !_isLoading,
                                onTap: _shareViaSMS,
                              ),

                              // WhatsApp
                              _buildShareOption(
                                icon: Icons.chat,
                                label: 'WhatsApp',
                                color: const Color(0xFF25D366),
                                isEnabled: !_isLoading,
                                onTap: _shareViaWhatsApp,
                              ),
                            ],
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareOption({
    required IconData icon,
    required String label,
    required Color color,
    required bool isEnabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isEnabled ? color.withOpacity(0.1) : Colors.grey[200],
              border: Border.all(
                color: isEnabled ? color : Colors.grey,
                width: 2,
              ),
            ),
            child: Icon(
              icon,
              size: 35,
              color: isEnabled ? color : Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isEnabled ? Colors.black : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
