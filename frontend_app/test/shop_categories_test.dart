import 'package:flutter_test/flutter_test.dart';

import 'package:frontend_app/core/shop_categories.dart';

void main() {
  group('canonicalShopCategory', () {
    test('keeps canonical category names unchanged', () {
      expect(canonicalShopCategory('Doctor Prescription'), 'Doctor Prescription');
      expect(canonicalShopCategory('Kirana'), 'Kirana');
    });

    test('maps legacy and formatting variants to the API contract', () {
      expect(canonicalShopCategory(' stationary '), 'Stationery');
      expect(canonicalShopCategory('FAST FOOD'), 'Fast Food');
      expect(canonicalShopCategory('doctor'), 'Doctor Prescription');
    });

    test('fails safely to the general category for unknown input', () {
      expect(canonicalShopCategory(null), kDefaultShopCategory);
      expect(canonicalShopCategory('not-a-real-category'), kDefaultShopCategory);
    });
  });
}
