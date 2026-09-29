import '../models/customer.dart';
import 'api_client.dart';
import 'cache_service.dart';

class CustomerService {
  final ApiClient _apiClient;
  final CacheService _cacheService = CacheService();

  CustomerService(this._apiClient);

  Future<List<VerifiedCustomer>> getVerifiedCustomers({
    int limit = 100,
    int offset = 0,
    String orderBy = 'name',
  }) async {
    final cacheKey = 'verified_customers_${limit}_${offset}_$orderBy';
    try {
      final data = await _apiClient.get(
        '/customers/?limit=$limit&offset=$offset&order_by=$orderBy',
      );
      await _cacheService.saveData(cacheKey, data);
      return VerifiedCustomerList.fromJson(Map<String, dynamic>.from(data))
          .customers;
    } catch (e) {
      final cached = await _cacheService.getData(cacheKey);
      if (cached is Map) {
        return VerifiedCustomerList.fromJson(Map<String, dynamic>.from(cached))
            .customers;
      }
      throw Exception('Failed to load verified customers: $e');
    }
  }

  Future<VerifiedCustomerList> getVerifiedCustomerList({
    int limit = 100,
    int offset = 0,
    String orderBy = 'name',
  }) async {
    final cacheKey = 'verified_customer_list_${limit}_${offset}_$orderBy';
    try {
      final data = await _apiClient.get(
        '/customers/?limit=$limit&offset=$offset&order_by=$orderBy',
      );
      await _cacheService.saveData(cacheKey, data);
      return VerifiedCustomerList.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      final cached = await _cacheService.getData(cacheKey);
      if (cached is Map) {
        return VerifiedCustomerList.fromJson(Map<String, dynamic>.from(cached));
      }
      throw Exception('Failed to load verified customers: $e');
    }
  }

  Future<Map<String, dynamic>> getCustomerDetails(int customerId) async {
    final cacheKey = 'customer_details_$customerId';
    try {
      final data = await _apiClient.get('/customers/$customerId');
      final mapData = Map<String, dynamic>.from(data as Map);
      await _cacheService.saveData(cacheKey, mapData);
      return mapData;
    } catch (e) {
      final cached = await _cacheService.getData(cacheKey);
      if (cached is Map) {
        return Map<String, dynamic>.from(cached);
      }
      throw Exception('Failed to load customer details: $e');
    }
  }

  Future<Map<String, dynamic>> getCustomerBills(
    int customerId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final cacheKey = 'customer_bills_${customerId}_${limit}_$offset';
    try {
      final data = await _apiClient.get(
        '/customers/$customerId/bills?limit=$limit&offset=$offset',
      );
      await _cacheService.saveData(cacheKey, data);
      return {
        'customer': data['customer'],
        'bills': (data['bills'] as List)
            .map((json) => CustomerBillItem.fromJson(json))
            .toList(),
        'total_bills': data['total_bills'],
      };
    } catch (e) {
      final cached = await _cacheService.getData(cacheKey);
      if (cached is Map) {
        return {
          'customer': cached['customer'],
          'bills': (cached['bills'] as List)
              .map((json) => CustomerBillItem.fromJson(json))
              .toList(),
          'total_bills': cached['total_bills'],
        };
      }
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
    final cacheKey = 'customer_ledger_${customerId}_${limit}_$offset';
    try {
      final data = await _apiClient.get(
        '/customers/$customerId/ledger?limit=$limit&offset=$offset',
      );
      await _cacheService.saveData(cacheKey, data);
      return CustomerLedgerStatement.fromJson(Map<String, dynamic>.from(data));
    } catch (e) {
      final cached = await _cacheService.getData(cacheKey);
      if (cached is Map) {
        return CustomerLedgerStatement.fromJson(Map<String, dynamic>.from(cached));
      }
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
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-$customerId-$draftId';
    final response = await _apiClient.post(
      '/customers/$customerId/ledger-drafts/$draftId/confirm',
      {'expected_version': expectedVersion},
      extraHeaders: {'Idempotency-Key': requestId},
    );
    return Map<String, dynamic>.from(response as Map);
  }
}
