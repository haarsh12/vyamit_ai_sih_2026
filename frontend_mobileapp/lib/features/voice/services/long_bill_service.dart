import '../../../services/api_client.dart';

/// Creates a reviewable bill draft from the final device transcript.
class LongBillService {
  LongBillService({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<Map<String, dynamic>> createDraft(String transcript) async {
    final response = await _api.post('/voice/long-bill/drafts', {
      'transcript': transcript.trim(),
    });
    if (response is! Map) {
      throw StateError('Long Bill service returned an invalid response.');
    }
    return Map<String, dynamic>.from(response);
  }
}
