import '../../core/master_list.dart';
import '../../core/shop_categories.dart';
import '../../models/item.dart';

/// Initial shortcut data for the categories that expose Frequent Billing.
///
/// These are device-local shortcuts only; inventory, voice matching, and AI
/// retrieval always use the category-scoped API inventory instead. HomeScreen
/// copies this list per category, so edits never spill into another category.
List<Item> defaultFrequentItemsForCategory(String category) {
  switch (canonicalShopCategory(category)) {
    case 'Kirana':
    case 'Fast Food':
      // Preserve the existing frequent-billing catalogue and layout for the
      // two business flows that use it today.
      return List<Item>.from(masterFrequentList);
    case 'Dairy':
      return [
        Item(id: 'dairy-milk-500ml', names: ['Milk 500 ml'], price: 30, unit: 'pkt', category: 'Milk & Dairy'),
        Item(id: 'dairy-milk-1l', names: ['Milk 1 litre'], price: 60, unit: 'pkt', category: 'Milk & Dairy'),
        Item(id: 'dairy-curd-400g', names: ['Curd 400 g'], price: 45, unit: 'pkt', category: 'Milk & Dairy'),
        Item(id: 'dairy-paneer-200g', names: ['Paneer 200 g'], price: 90, unit: 'pkt', category: 'Milk & Dairy'),
        Item(id: 'dairy-butter-100g', names: ['Butter 100 g'], price: 58, unit: 'pkt', category: 'Milk & Dairy'),
      ];
    default:
      return <Item>[];
  }
}
