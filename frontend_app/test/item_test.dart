import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_app/models/item.dart';

void main() {
  test('reads PostgreSQL decimal values serialized as JSON strings', () {
    final item = Item.fromJson({
      'id': 'rice-1',
      'names': ['Rice', 'Chawal'],
      'price': '45.50',
      'unit': 'kg',
      'category': 'Daily Essentials',
      'shop_category': 'Kirana',
      'gst_rate': '5.0',
    });

    expect(item.id, 'rice-1');
    expect(item.price, 45.5);
    expect(item.gstRate, 5.0);
    expect(item.shopCategory, 'Kirana');
  });

  test('keeps compatibility with ordinary JSON numeric values', () {
    final item = Item.fromJson({
      'id': 7,
      'names': ['Soap'],
      'price': 30,
      'gst_rate': 18,
    });

    expect(item.id, '7');
    expect(item.price, 30.0);
    expect(item.gstRate, 18.0);
  });
}
