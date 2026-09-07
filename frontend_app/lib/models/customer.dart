class VerifiedCustomer {
  final int id;
  final String name;
  final String? phoneNumber;
  final int totalBills;
  final double totalSpent;
  final DateTime? lastPurchaseDate;
  final DateTime createdAt;

  VerifiedCustomer({
    required this.id,
    required this.name,
    this.phoneNumber,
    required this.totalBills,
    required this.totalSpent,
    this.lastPurchaseDate,
    required this.createdAt,
  });

  factory VerifiedCustomer.fromJson(Map<String, dynamic> json) {
    return VerifiedCustomer(
      id: json['id'],
      name: json['name'],
      phoneNumber: json['phone_number'],
      totalBills: json['total_bills'] ?? 0,
      totalSpent: (json['total_spent'] ?? 0).toDouble(),
      lastPurchaseDate: json['last_purchase_date'] != null 
          ? DateTime.parse(json['last_purchase_date'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class CustomerVerificationSuggestion {
  final bool shouldVerify;
  final String? customerName;
  final int? existingCustomerId;
  final String? existingCustomerName;
  final bool isDuplicate;
  final String message;

  CustomerVerificationSuggestion({
    required this.shouldVerify,
    this.customerName,
    this.existingCustomerId,
    this.existingCustomerName,
    required this.isDuplicate,
    required this.message,
  });

  factory CustomerVerificationSuggestion.fromJson(Map<String, dynamic> json) {
    return CustomerVerificationSuggestion(
      shouldVerify: json['should_verify'] ?? false,
      customerName: json['customer_name'],
      existingCustomerId: json['existing_customer_id'],
      existingCustomerName: json['existing_customer_name'],
      isDuplicate: json['is_duplicate'] ?? false,
      message: json['message'] ?? '',
    );
  }
}

class CustomerBillItem {
  final int id;
  final double totalAmount;
  final int totalItems;
  final List<Map<String, dynamic>> items;
  final String paymentMethod;
  final String billType;
  final DateTime billDate;
  final DateTime createdAt;

  CustomerBillItem({
    required this.id,
    required this.totalAmount,
    required this.totalItems,
    required this.items,
    required this.paymentMethod,
    required this.billType,
    required this.billDate,
    required this.createdAt,
  });

  factory CustomerBillItem.fromJson(Map<String, dynamic> json) {
    return CustomerBillItem(
      id: json['id'],
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      totalItems: json['total_items'] ?? 0,
      items: List<Map<String, dynamic>>.from(json['items'] ?? []),
      paymentMethod: json['payment_method'] ?? 'cash',
      billType: json['bill_type'] ?? 'printed',
      billDate: DateTime.parse(json['bill_date']),
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
