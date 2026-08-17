import '../core/config.dart';
import 'api_client.dart';
import '../models/item.dart';

class InventoryService {
  final ApiClient _api = ApiClient();

  // 1. Get All Items - ADD TRAILING SLASH
  Future<List<Item>> getItems() async {
    final response = await _api.get('/items/'); // ← Added /
    // Assuming backend returns a list: [ {item1}, {item2} ]
    return (response as List).map((e) => Item.fromJson(e)).toList();
  }

  // 2. Add Item - ADD TRAILING SLASH
  Future<Item> addItem(Item item) async {
    final response = await _api.post('/items/', item.toJson()); // ← Added /
    return Item.fromJson(response);
  }

  // 3. Update Item - ALREADY HAS TRAILING SLASH
  Future<Item> updateItem(Item item) async {
    final response =
        await _api.put('/items/${item.id}/', item.toJson()); // ← Added /
    return Item.fromJson(response);
  }

  // 4. Delete Item - ADD TRAILING SLASH
  Future<void> deleteItem(String id) async {
    await _api.delete('/items/$id/'); // ← Added /
  }
}
