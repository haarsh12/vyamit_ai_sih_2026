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
      id: (json['_id'] ?? json['id'])?.toString() ?? '',
      names: (json['names'] as List? ?? const [])
          .map((name) => name.toString())
          .where((name) => name.isNotEmpty)
          .toList(),
      // PostgreSQL numeric/decimal values are JSON strings in some API
      // serializers. Accept both those strings and regular JSON numbers.
      price: _asDouble(json['price']),
      unit: json['unit']?.toString() ?? 'kg',
      category: json['category']?.toString() ?? 'General',
      shopCategory: json['shop_category'] as String?,
      gstRate: _asDouble(json['gst_rate']),
      hsnCode: json['hsn_code']?.toString(),
      taxCategory: json['tax_category']?.toString(),
    );
  }

  static double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
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
      if (taxCategory != null && taxCategory!.isNotEmpty)
        'tax_category': taxCategory,
    };
  }
}
