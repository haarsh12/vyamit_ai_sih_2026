import 'package:uuid/uuid.dart';

import 'api_client.dart';

/// Confirms server-created workflow drafts after an explicit UI action.
class WorkflowDraftService {
  final ApiClient _api;

  WorkflowDraftService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<Map<String, dynamic>> confirmBillDraft({
    required String draftId,
    required int version,
    int? verifiedCustomerId,
  }) async {
    final result = await _api.post(
      '/workflows/bill-drafts/$draftId/confirm',
      {
        'expected_version': version,
        if (verifiedCustomerId != null)
          'verified_customer_id': verifiedCustomerId,
      },
      extraHeaders: {'Idempotency-Key': const Uuid().v4()},
    );
    return Map<String, dynamic>.from(result as Map);
  }
}
