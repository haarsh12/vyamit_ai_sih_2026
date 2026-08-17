import 'api_client.dart';
import '../screens/voice_inventory_screen.dart';

class VoiceInventoryService {
  final ApiClient _api = ApiClient();

  Future<List<ParsedCategory>> parseVoiceInventory(String rawText) async {
    try {
      final response = await _api.post('/inventory/voice-parse', {
        'raw_text': rawText,
      });

      // Parse response
      final categories = response['categories'] as List;
      
      return categories.map((catData) {
        final items = (catData['items'] as List).map((itemData) {
          return ParsedItem(
            name: itemData['name'] ?? '',
            price: (itemData['price'] ?? 0).toDouble(),
            unit: itemData['unit'] ?? 'kg',
            isExisting: itemData['is_existing'] ?? false,
            oldPrice: itemData['old_price']?.toDouble(),
            oldUnit: itemData['old_unit'],
            existingId: itemData['existing_id'],
            aliases: List<String>.from(itemData['aliases'] ?? []),
          );
        }).toList();

        return ParsedCategory(
          name: catData['name'] ?? 'Other',
          items: items,
        );
      }).toList();
    } catch (e) {
      print('❌ Voice inventory service error: $e');
      rethrow;
    }
  }
}
