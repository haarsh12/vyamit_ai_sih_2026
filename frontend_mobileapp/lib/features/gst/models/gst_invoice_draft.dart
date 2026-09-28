class GstInvoiceDraft {
  final Map<String, dynamic> customer;
  final Map<String, dynamic>? sellerOverride;
  final List<Map<String, dynamic>> items;
  final String? issueDate;
  final String? dueDate;
  final String paymentMethod;
  final int? verifiedCustomerId;
  final String paymentStatus;
  final String? referenceNumber;
  final Map<String, dynamic>? bankDetails;

  const GstInvoiceDraft({
    required this.customer,
    required this.items,
    this.sellerOverride,
    this.issueDate,
    this.dueDate,
    this.paymentMethod = 'cash',
    this.verifiedCustomerId,
    this.paymentStatus = 'PAID',
    this.referenceNumber,
    this.bankDetails,
  });

  factory GstInvoiceDraft.fromLiveBill({
    required List<Map<String, dynamic>> billItems,
    required String customerName,
    String? customerGstin,
    String? customerStateCode,
    String paymentMethod = 'cash',
    int? verifiedCustomerId,
  }) {
    String quantityOf(Map<String, dynamic> item) {
      final value = item['qty'] ?? item['quantity'];
      if (value != null && value.toString().trim().isNotEmpty)
        return value.toString();
      return (item['qty_display']?.toString() ?? '1')
          .replaceAll(RegExp(r'[^0-9.]'), '');
    }

    // Validate and normalize state code - default to '27' (Maharashtra) if invalid
    String normalizedStateCode = '27'; // Default to Maharashtra
    if (customerStateCode != null && customerStateCode.trim().isNotEmpty) {
      final code = customerStateCode.trim().padLeft(2, '0');
      // Check if it's a valid state code (01-38, excluding some)
      final validCodes = [
        '01',
        '02',
        '03',
        '04',
        '05',
        '06',
        '07',
        '08',
        '09',
        '10',
        '11',
        '12',
        '13',
        '14',
        '15',
        '16',
        '17',
        '18',
        '19',
        '20',
        '21',
        '22',
        '23',
        '24',
        '26',
        '27',
        '29',
        '30',
        '31',
        '32',
        '33',
        '34',
        '35',
        '36',
        '37',
        '38',
        '97'
      ];
      if (validCodes.contains(code)) {
        normalizedStateCode = code;
      }
    }

    return GstInvoiceDraft(
      customer: {
        'name': customerName.trim().isEmpty
            ? 'Walk-in customer'
            : customerName.trim(),
        if (customerGstin != null && customerGstin.trim().isNotEmpty)
          'gstin': customerGstin.trim(),
        'state_code': normalizedStateCode,
      },
      items: billItems
          .map((item) => <String, dynamic>{
                'name': item['name'] ?? item['en'] ?? 'Item',
                'quantity': quantityOf(item).isEmpty ? '1' : quantityOf(item),
                'unit': item['unit']?.toString() ?? 'unit',
                'rate': item['rate'] ?? item['price'] ?? 0,
                'gst_rate': item['gst_rate'] ?? item['gstRate'] ?? 0,
                if (item['hsn_code'] != null) 'hsn_code': item['hsn_code'],
                if (item['tax_category'] != null)
                  'tax_category': item['tax_category'],
              })
          .toList(),
      paymentMethod: paymentMethod,
      paymentStatus:
          paymentMethod.toLowerCase() == 'udhaar' ? 'UNPAID' : 'PAID',
      verifiedCustomerId: verifiedCustomerId,
    );
  }

  Map<String, dynamic> toJson() {
    // Helper to extract date-only string from ISO datetime
    String? _extractDateOnly(String? isoString) {
      if (isoString == null || isoString.isEmpty) return null;
      // Extract YYYY-MM-DD from datetime string (removes time component)
      return isoString.split('T').first;
    }

    return {
      'is_gst_invoice': true,
      'customer': customer,
      if (sellerOverride != null) 'seller_override': sellerOverride,
      'items': items,
      if (issueDate != null) 'issue_date': _extractDateOnly(issueDate),
      if (dueDate != null) 'due_date': _extractDateOnly(dueDate),
      'payment_method': paymentMethod,
      if (verifiedCustomerId != null)
        'verified_customer_id': verifiedCustomerId,
      'payment_status': paymentStatus,
      if (referenceNumber != null && referenceNumber!.trim().isNotEmpty)
        'reference_number': referenceNumber,
      if (bankDetails?['bank_name']?.toString().trim().isNotEmpty == true)
        'bank_name': bankDetails!['bank_name'],
      if (bankDetails?['account_name']?.toString().trim().isNotEmpty == true)
        'account_name': bankDetails!['account_name'],
      if (bankDetails?['account_number']?.toString().trim().isNotEmpty == true)
        'account_number': bankDetails!['account_number'],
      if (bankDetails?['ifsc']?.toString().trim().isNotEmpty == true)
        'ifsc': bankDetails!['ifsc'],
    };
  }

  GstInvoiceDraft copyWith({
    Map<String, dynamic>? customer,
    Map<String, dynamic>? sellerOverride,
    List<Map<String, dynamic>>? items,
    String? issueDate,
    String? dueDate,
    String? paymentMethod,
    int? verifiedCustomerId,
    String? paymentStatus,
    String? referenceNumber,
    Map<String, dynamic>? bankDetails,
  }) {
    return GstInvoiceDraft(
      customer: customer ?? this.customer,
      sellerOverride: sellerOverride ?? this.sellerOverride,
      items: items ?? this.items,
      issueDate: issueDate ?? this.issueDate,
      dueDate: dueDate ?? this.dueDate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      verifiedCustomerId: verifiedCustomerId ?? this.verifiedCustomerId,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      bankDetails: bankDetails ?? this.bankDetails,
    );
  }
}
