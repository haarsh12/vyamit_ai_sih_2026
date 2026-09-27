class VerifiedCustomer {
  final int id;
  final String name;
  final String? phoneNumber;
  final int totalBills;
  final double totalSpent;
  final double ledgerBalance;
  final DateTime? lastPurchaseDate;
  final DateTime createdAt;

  VerifiedCustomer({
    required this.id,
    required this.name,
    this.phoneNumber,
    required this.totalBills,
    required this.totalSpent,
    required this.ledgerBalance,
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
      ledgerBalance: (json['ledger_balance'] ?? 0).toDouble(),
      lastPurchaseDate: json['last_purchase_date'] != null 
          ? DateTime.parse(json['last_purchase_date'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class VerifiedCustomerList {
  final List<VerifiedCustomer> customers;
  final int total;
  final double totalOutstandingLedger;

  const VerifiedCustomerList({
    required this.customers,
    required this.total,
    required this.totalOutstandingLedger,
  });

  factory VerifiedCustomerList.fromJson(Map<String, dynamic> json) {
    final rawCustomers = json['customers'] as List? ?? const [];
    return VerifiedCustomerList(
      customers: rawCustomers
          .whereType<Map>()
          .map((value) => VerifiedCustomer.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      totalOutstandingLedger:
          (json['total_outstanding_ledger'] as num?)?.toDouble() ?? 0,
    );
  }
}

class CustomerLedgerEntry {
  final int id;
  final int? billId;
  final String entryType;
  final double amount;
  final double balanceAfter;
  final String source;
  final String? note;
  final DateTime occurredAt;

  const CustomerLedgerEntry({
    required this.id,
    this.billId,
    required this.entryType,
    required this.amount,
    required this.balanceAfter,
    required this.source,
    this.note,
    required this.occurredAt,
  });

  bool get increasesBalance => entryType == 'udhaar';

  factory CustomerLedgerEntry.fromJson(Map<String, dynamic> json) {
    return CustomerLedgerEntry(
      id: (json['id'] as num).toInt(),
      billId: (json['bill_id'] as num?)?.toInt(),
      entryType: json['entry_type']?.toString() ?? 'udhaar',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      balanceAfter: (json['balance_after'] as num?)?.toDouble() ?? 0,
      source: json['source']?.toString() ?? 'manual',
      note: json['note']?.toString(),
      occurredAt: DateTime.parse(json['occurred_at'].toString()),
    );
  }
}

class CustomerLedgerStatement {
  final int customerId;
  final String customerName;
  final double currentBalance;
  final List<CustomerLedgerEntry> entries;

  const CustomerLedgerStatement({
    required this.customerId,
    required this.customerName,
    required this.currentBalance,
    required this.entries,
  });

  factory CustomerLedgerStatement.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as List? ?? const [];
    return CustomerLedgerStatement(
      customerId: (json['customer_id'] as num).toInt(),
      customerName: json['customer_name']?.toString() ?? 'Customer',
      currentBalance: (json['current_balance'] as num?)?.toDouble() ?? 0,
      entries: rawEntries
          .whereType<Map>()
          .map((value) => CustomerLedgerEntry.fromJson(Map<String, dynamic>.from(value)))
          .toList(),
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
  final String billingSource;
  final DateTime billDate;
  final DateTime createdAt;

  CustomerBillItem({
    required this.id,
    required this.totalAmount,
    required this.totalItems,
    required this.items,
    required this.paymentMethod,
    required this.billType,
    required this.billingSource,
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
      billingSource: json['billing_source'] ?? 'voice',
      billDate: DateTime.parse(json['bill_date']),
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
