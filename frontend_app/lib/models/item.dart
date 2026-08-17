class Item {
  final String id; // Database ID
  final List<String> names; // ["Rice", "Chawal", "Tandul"]
  final double price;
  final String unit; // "kg", "pkt"
  final String category; // "Anaaj", "Masale"
  final String? shopCategory; // Server-assigned inventory namespace
  final double gstRate;
  final String? hsnCode;
  final String? taxCategory;

  Item({
    required this.id,
    required this.names,
    required this.price,
    required this.unit,
    required this.category,
    this.shopCategory,
    this.gstRate = 0,
    this.hsnCode,
    this.taxCategory,
  });

  // Convert JSON from Backend -> Flutter Object
  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['_id'] ??
          json['id']?.toString() ??
          '', // Handle both MongoDB _id and SQL id
      names: List<String>.from(json['names'] ?? []),
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      unit: json['unit'] ?? 'kg',
      category: json['category'] ?? 'General',
      shopCategory: json['shop_category'] as String?,
      gstRate: (json['gst_rate'] as num?)?.toDouble() ?? 0,
      hsnCode: json['hsn_code']?.toString(),
      taxCategory: json['tax_category']?.toString(),
    );
  }

  // Convert Flutter Object -> JSON for Backend
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'names': names,
      'price': price,
      'unit': unit,
      'category': category,
      'gst_rate': gstRate,
      if (hsnCode != null && hsnCode!.isNotEmpty) 'hsn_code': hsnCode,
      if (taxCategory != null && taxCategory!.isNotEmpty) 'tax_category': taxCategory,
    };
  }
}
