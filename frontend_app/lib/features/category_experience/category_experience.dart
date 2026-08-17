import 'package:flutter/material.dart';

import '../../core/shop_categories.dart';

/// The category-only pages that can appear before shared application pages.
///
/// Dashboard and Profile are deliberately not included here. HomeScreen adds
/// those shared pages after this policy has been resolved.
enum CategoryPageType {
  voice,
  inventory,
  frequentBilling,
  patientHistory,
  pastRecords,
}

class CategoryPageDefinition {
  final CategoryPageType type;
  final String label;
  final IconData icon;

  const CategoryPageDefinition({
    required this.type,
    required this.label,
    required this.icon,
  });
}

/// One authoritative UI policy for a business category.
///
/// `inventoryGroups` are product groups inside a category-scoped inventory;
/// they are never database namespaces and are never sent as a shop category.
class CategoryExperience {
  final String category;
  final List<String> inventoryGroups;
  final List<CategoryPageDefinition> pages;
  final bool showsSharedDashboard;

  const CategoryExperience({
    required this.category,
    required this.inventoryGroups,
    required this.pages,
    this.showsSharedDashboard = true,
  });

  bool get hasInventory =>
      pages.any((page) => page.type == CategoryPageType.inventory);

  static CategoryExperience forCategory(String? category) =>
      _experiences[canonicalShopCategory(category)] ?? _experiences['Other']!;

  static const _voicePage = CategoryPageDefinition(
    type: CategoryPageType.voice,
    label: 'Voice',
    icon: Icons.mic_rounded,
  );
  static const _inventoryPage = CategoryPageDefinition(
    type: CategoryPageType.inventory,
    label: 'Inventory',
    icon: Icons.inventory_2_rounded,
  );
  static const _frequentBillingPage = CategoryPageDefinition(
    type: CategoryPageType.frequentBilling,
    label: 'Frequent',
    icon: Icons.flash_on_rounded,
  );
  static const _patientHistoryPage = CategoryPageDefinition(
    type: CategoryPageType.patientHistory,
    label: 'Patients',
    icon: Icons.people_alt_rounded,
  );
  static const _pastRecordsPage = CategoryPageDefinition(
    type: CategoryPageType.pastRecords,
    label: 'History',
    icon: Icons.history_rounded,
  );

  static const Map<String, CategoryExperience> _experiences = {
    // The existing five-page Kirana experience is intentionally preserved.
    'Kirana': CategoryExperience(
      category: 'Kirana',
      inventoryGroups: [
        'Anaaj',
        'Atta',
        'Dal',
        'Masale',
        'Tel',
        'Dry Fruits',
        'Upvas',
        'Other'
      ],
      pages: [_voicePage, _inventoryPage, _frequentBillingPage],
    ),
    'Fast Food': CategoryExperience(
      category: 'Fast Food',
      inventoryGroups: [
        'Meals',
        'Snacks',
        'Beverages',
        'Combos',
        'Add-ons',
        'Other'
      ],
      pages: [_voicePage, _inventoryPage, _frequentBillingPage],
    ),
    'Dairy': CategoryExperience(
      category: 'Dairy',
      inventoryGroups: [
        'Milk & Dairy',
        'FMCG',
        'Beverages',
        'Fresh Products',
        'Other'
      ],
      pages: [_voicePage, _inventoryPage, _frequentBillingPage],
    ),
    'Hardware': CategoryExperience(
      category: 'Hardware',
      inventoryGroups: [
        'Tools',
        'Fasteners',
        'Plumbing',
        'Electrical',
        'Paint',
        'Other'
      ],
      pages: [_voicePage, _inventoryPage],
    ),
    'Stationery': CategoryExperience(
      category: 'Stationery',
      inventoryGroups: [
        'Writing',
        'Paper',
        'Notebooks',
        'Office Supplies',
        'Art & Craft',
        'Other'
      ],
      pages: [_voicePage, _inventoryPage],
    ),
    'Pharmacy': CategoryExperience(
      category: 'Pharmacy',
      inventoryGroups: [
        'Medicines',
        'FMCG',
        'Personal Care',
        'First Aid',
        'Wellness',
        'Other'
      ],
      pages: [_voicePage, _inventoryPage],
    ),
    'General': CategoryExperience(
      category: 'General',
      inventoryGroups: [
        'Daily Essentials',
        'FMCG',
        'Household',
        'Snacks',
        'Personal Care',
        'Other'
      ],
      pages: [_voicePage, _inventoryPage],
    ),
    'Clothing': CategoryExperience(
      category: 'Clothing',
      inventoryGroups: [
        'Men',
        'Women',
        'Kids',
        'Accessories',
        'Footwear',
        'Other'
      ],
      pages: [_voicePage, _inventoryPage],
    ),
    'Other': CategoryExperience(
      category: 'Other',
      inventoryGroups: ['Items', 'Other'],
      pages: [_voicePage, _inventoryPage],
    ),
    // Doctor mode deliberately omits retail Dashboard and inventory. It owns
    // a separate voice-to-prescription flow, patient directory, and history.
    'Doctor Prescription': CategoryExperience(
      category: 'Doctor Prescription',
      inventoryGroups: [
        'Prescriptions',
        'Consultation',
        'Lab Tests',
        'Procedures',
        'Other'
      ],
      pages: [_voicePage, _patientHistoryPage, _pastRecordsPage],
      showsSharedDashboard: false,
    ),
  };
}
