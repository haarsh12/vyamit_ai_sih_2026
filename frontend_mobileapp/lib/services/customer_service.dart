import '../models/customer.dart';
import 'api_client.dart';

class CustomerService {
  final ApiClient _apiClient;

  CustomerService(this._apiClient);

  Future<List<VerifiedCustomer>> getVerifiedCustomers({
    int limit = 100,
    int offset = 0,
    String orderBy = 'name',
  }) async {
    try {
      final data = await _apiClient.get(
        '/customers/?limit=$limit&offset=$offset&order_by=$orderBy',
      );

      return VerifiedCustomerList.fromJson(Map<String, dynamic>.from(data)).customers;
    } catch (e) {
      throw Exception('Failed to load verified customers: $e');
    }
  }

  Future<VerifiedCustomerList> getVerifiedCustomerList({
    int limit = 100,
    int offset = 0,
    String orderBy = 'name',
  }) async {
    try {
      final data = await _apiClient.get(
        '/customers/?limit=$limit&offset=$offset&order_by=$orderBy',
      );
      return VerifiedCustomerList.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      throw Exception('Failed to load verified customers: $e');
    }
  }

  Future<Map<String, dynamic>> getCustomerDetails(int customerId) async {
    try {
      final data = await _apiClient.get('/customers/$customerId');
      return data as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to load customer details: $e');
    }
  }

  Future<Map<String, dynamic>> getCustomerBills(
    int customerId, {
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final data = await _apiClient.get(
        '/customers/$customerId/bills?limit=$limit&offset=$offset',
      );

      return {
        'customer': data['customer'],
        'bills': (data['bills'] as List)
            .map((json) => CustomerBillItem.fromJson(json))
            .toList(),
        'total_bills': data['total_bills'],
      };
    } catch (e) {
      throw Exception('Failed to load customer bills: $e');
    }
  }

  Future<Map<String, dynamic>> verifyCustomer({
    required String customerName,
    String? phoneNumber,
    int? mergeWithExistingId,
    int? linkBillId,
  }) async {
    final data = {
      'customer_name': customerName,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (mergeWithExistingId != null)
        'merge_with_existing_id': mergeWithExistingId,
      if (linkBillId != null) 'link_bill_id': linkBillId,
    };

    final response = await _apiClient.post(
      '/customers/verify',
      data,
    );

    return response as Map<String, dynamic>;
  }

  Future<CustomerVerificationSuggestion?> getVerificationSuggestion(
    String customerName,
  ) async {
    final trimmedName = customerName.trim();
    if (trimmedName.isEmpty) return null;

    try {
      final data = await _apiClient.get(
        '/customers/verification-suggestion?customer_name=${Uri.encodeQueryComponent(trimmedName)}',
      );
      if (data is! Map) return null;
      return CustomerVerificationSuggestion.fromJson(
        Map<String, dynamic>.from(data),
      );
    } catch (error) {
      throw Exception('Failed to check customer name: $error');
    }
  }

  Future<void> removeCustomer(int customerId) async {
    try {
      await _apiClient.delete('/customers/$customerId');
    } catch (e) {
      throw Exception('Failed to remove customer: $e');
    }
  }

  Future<CustomerLedgerStatement> getCustomerLedger(
    int customerId, {
    int limit = 100,
    int offset = 0,
  }) async {
    try {
      final data = await _apiClient.get(
        '/customers/$customerId/ledger?limit=$limit&offset=$offset',
      );
      return CustomerLedgerStatement.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      throw Exception('Failed to load customer ledger: $e');
    }
  }

  Future<Map<String, dynamic>> createLedgerDraft(
    int customerId, {
    required String entryType,
    required double amount,
    String? note,
  }) async {
    final response = await _apiClient.post(
      '/customers/$customerId/ledger-drafts',
      {
        'entry_type': entryType,
        'amount': double.parse(amount.toStringAsFixed(2)),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> confirmLedgerDraft(
    int customerId,
    String draftId,
    int expectedVersion,
  ) async {
    final requestId = '${DateTime.now().microsecondsSinceEpoch}-$customerId-$draftId';
    final response = await _apiClient.post(
      '/customers/$customerId/ledger-drafts/$draftId/confirm',
      {'expected_version': expectedVersion},
      extraHeaders: {'Idempotency-Key': requestId},
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
