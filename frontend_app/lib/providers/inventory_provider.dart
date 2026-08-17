import 'package:flutter/material.dart';
import '../models/item.dart';
import '../services/inventory_service.dart';
import '../features/category_experience/category_experience.dart';
import '../core/shop_categories.dart';

class InventoryProvider with ChangeNotifier {
  final InventoryService _service = InventoryService();

  // Start with empty inventory
  List<Item> _items = [];
  
  // Product groups for the currently active shop category. These are not the
  // same as the profile's shop category / server-side inventory namespace.
  String _shopCategory = kDefaultShopCategory;
  List<String> _categories = List.from(
    CategoryExperience.forCategory(kDefaultShopCategory).inventoryGroups,
  );

  bool _isLoading = false;
  String _selectedCategory = 'Daily Essentials';
  int _fetchVersion = 0;

  List<Item> get items => _items;
  List<String> get categories => _categories;
  bool get isLoading => _isLoading;
  String get selectedCategory => _selectedCategory;
  String get shopCategory => _shopCategory;

  /// Reset local inventory immediately when the profile category changes,
  /// then reload through the API. This prevents old items flashing while the
  /// network request for the new namespace is in flight.
  Future<void> loadForShopCategory(String category) async {
    final canonicalCategory = canonicalShopCategory(category);
    if (_shopCategory != canonicalCategory) {
      _shopCategory = canonicalCategory;
      _categories = List.from(
        CategoryExperience.forCategory(canonicalCategory).inventoryGroups,
      );
      _selectedCategory = _categories.first;
      _items = [];
      notifyListeners();
    }
    await fetchItems(expectedShopCategory: canonicalCategory);
  }

  // Filter Logic for Display
  List<Item> getFilteredItems(String searchQuery) {
    if (searchQuery.isEmpty) {
      return _items.where((i) => i.category == _selectedCategory).toList();
    } else {
      return _items
          .where((i) => i.names
              .any((n) => n.toLowerCase().contains(searchQuery.toLowerCase())))
          .toList();
    }
  }

  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  // Add a new category
  void addCategory(String categoryName) {
    if (!_categories.contains(categoryName)) {
      _categories.add(categoryName);
      notifyListeners();
    }
  }

  // Delete a category and all its items
  Future<void> deleteCategory(String categoryName) async {
    try {
      print("🗑️ Deleting category: $categoryName");
      
      // Get all items in this category
      final itemsToDelete = _items.where((i) => i.category == categoryName).toList();
      
      // Delete all items from backend
      for (var item in itemsToDelete) {
        await _service.deleteItem(item.id);
      }
      
      // Remove items from local list
      _items.removeWhere((i) => i.category == categoryName);
      
      // Remove category
      _categories.remove(categoryName);
      
      // Switch to first available category if current was deleted
      if (_selectedCategory == categoryName && _categories.isNotEmpty) {
        _selectedCategory = _categories.first;
      }
      
      notifyListeners();
      print("✅ Category deleted: $categoryName");
    } catch (e) {
      print("❌ Delete Category Error: $e");
      rethrow;
    }
  }

  // Fetch items from backend
  Future<void> fetchItems({String? expectedShopCategory}) async {
    final requestedCategory = canonicalShopCategory(
      expectedShopCategory ?? _shopCategory,
    );
    final requestVersion = ++_fetchVersion;
    _isLoading = true;
    notifyListeners();

    try {
      print("📥 Fetching items from backend...");
      final backendItems = await _service.getItems();
      print("✅ Fetched ${backendItems.length} items from backend");

      // A profile switch may have started a new load while this request was
      // in flight. Do not paint an old category's response into the newly
      // selected category, even momentarily.
      if (requestVersion != _fetchVersion || requestedCategory != _shopCategory) {
        return;
      }

      // The API returns the server-owned namespace with every item. Discard a
      // malformed or stale response instead of risking cross-category data.
      _items = backendItems
          .where(
            (item) =>
                item.shopCategory != null &&
                canonicalShopCategory(item.shopCategory) == requestedCategory,
          )
          .toList();
      
      // Add any custom categories from backend items that aren't in predefined list
      for (var item in _items) {
        if (!_categories.contains(item.category)) {
          _categories.add(item.category);
        }
      }
    } catch (e) {
      print("❌ Error fetching items: $e");
    }

    if (requestVersion == _fetchVersion && requestedCategory == _shopCategory) {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Add or Update item
  Future<void> addItem(Item newItem) async {
    final requestedCategory = _shopCategory;
    try {
      print("💾 Saving item: ${newItem.id} (${newItem.names[0]}) - ₹${newItem.price}");
      print("   Category: ${newItem.category}, Unit: ${newItem.unit}");

      // Call backend (POST endpoint handles upsert based on ID)
      final savedItem = await _service.addItem(newItem);
      if (requestedCategory != _shopCategory ||
          savedItem.shopCategory == null ||
          canonicalShopCategory(savedItem.shopCategory) != requestedCategory) {
        return;
      }
      print("✅ Backend saved item with ID: ${savedItem.id}");

      // Update local state - find by ID
      final index = _items.indexWhere((i) => i.id == newItem.id);
      if (index != -1) {
        _items[index] = savedItem;
        print("✅ Updated local item at index $index: ${savedItem.names[0]}");
      } else {
        _items.add(savedItem);
        print("✅ Added new local item: ${savedItem.names[0]}");
      }

      // Add category if it's new
      if (!_categories.contains(newItem.category)) {
        _categories.add(newItem.category);
      }

      notifyListeners();
    } catch (e) {
      print("❌ Save Error: $e");
      await fetchItems(expectedShopCategory: requestedCategory);
    }
  }

  // Delete item
  Future<void> deleteItem(String id) async {
    final requestedCategory = _shopCategory;
    try {
      print("🗑️ Deleting item: $id");

      // Delete from backend
      await _service.deleteItem(id);
      if (requestedCategory != _shopCategory) {
        return;
      }
      
      // Remove from local list
      _items.removeWhere((i) => i.id == id);
      
      notifyListeners();
      print("✅ Deleted from backend");
    } catch (e) {
      print("❌ Delete Error: $e");
      rethrow;
    }
  }
}
