import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../models/shop_details.dart';

class BillShareModal extends StatefulWidget {
  final List<Map<String, dynamic>> billItems;
  final double totalAmount;
  final ShopDetails shopDetails;
  final String? customerName;

  const BillShareModal({
    super.key,
    required this.billItems,
    required this.totalAmount,
    required this.shopDetails,
    this.customerName,
  });

  @override
  State<BillShareModal> createState() => _BillShareModalState();
}

class _BillShareModalState extends State<BillShareModal> {
  late final TextEditingController _customerNameController;
  final TextEditingController _mobileController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _customerNameController = TextEditingController(
      text: widget.customerName ?? 'Walk-in'
    );
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
    final date = '${now.day.toString().padLeft(2, '0')}-${now.month.toString().padLeft(2, '0')}-${now.year}';
    final hour = now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final time = '${hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} $ampm';
    
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
    final formattedMobile = cleanMobile.startsWith('91') ? cleanMobile : '91$cleanMobile';

    // Use SMS scheme to open device SMS app
    final smsUrl = 'sms:+$formattedMobile?body=$encodedText';

    try {
      final uri = Uri.parse(smsUrl);
      
      print('🔍 Trying to launch SMS: $smsUrl');
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        if (mounted) {
          Navigator.pop(context);
          _showSuccess('Opening SMS app...');
        }
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
    final formattedMobile = cleanMobile.startsWith('91') ? cleanMobile : '91$cleanMobile';

    // Use whatsapp:// scheme for better app detection
    final whatsappUrl = 'whatsapp://send?phone=$formattedMobile&text=$encodedText';

    try {
      final uri = Uri.parse(whatsappUrl);
      final canLaunch = await canLaunchUrl(uri);
      
      print('🔍 Trying to launch: $whatsappUrl');
      print('🔍 Can launch: $canLaunch');
      
      if (canLaunch) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        
        if (launched && mounted) {
          Navigator.pop(context);
          _showSuccess('Opening WhatsApp...');
        } else {
          _showError('Failed to open WhatsApp');
        }
      } else {
        // Fallback to https URL
        final fallbackUrl = 'https://wa.me/$formattedMobile?text=$encodedText';
        final fallbackUri = Uri.parse(fallbackUrl);
        
        if (await canLaunchUrl(fallbackUri)) {
          await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
          if (mounted) {
            Navigator.pop(context);
            _showSuccess('Opening WhatsApp...');
          }
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
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
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
                                borderSide: BorderSide(color: Colors.grey[300]!),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: BorderSide(color: Colors.grey[300]!),
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
                                isEnabled: true,
                                onTap: _shareViaSMS,
                              ),

                              // WhatsApp
                              _buildShareOption(
                                icon: Icons.chat,
                                label: 'WhatsApp',
                                color: const Color(0xFF25D366),
                                isEnabled: true,
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
