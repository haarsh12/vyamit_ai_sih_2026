import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../core/config.dart';
import '../models/dashboard.dart';
import 'cache_service.dart';

class AnalyticsRequestException implements Exception {
  final String message;

  const AnalyticsRequestException(this.message);

  @override
  String toString() => message;
}

class AnalyticsService {
  final String baseUrl = ApiConfig.baseUrl;
  static const _requestTimeout = Duration(seconds: 30);
  final CacheService _cacheService = CacheService();

  Future<DashboardData> getDashboard(String token, {int days = 30}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/analytics/dashboard?days=$days'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          await _cacheService.saveData('analytics_dashboard', data);
          return DashboardData.fromJson(data);
        }
      }
      throw AnalyticsRequestException(
        _serverError('Could not load dashboard', response),
      );
    } on AnalyticsRequestException {
      rethrow;
    } catch (e) {
      final cached = await _cacheService.getData('analytics_dashboard');
      if (cached is Map) {
        return DashboardData.fromJson(Map<String, dynamic>.from(cached));
      }
      throw const AnalyticsRequestException(
        'Cannot reach the billing server. Check your internet connection and sign in again.',
      );
    }
  }

  Future<List<BillHistory>> getBills(String token,
      {int limit = 50, int offset = 0}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/analytics/bills?limit=$limit&offset=$offset'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          await _cacheService.saveData('analytics_bills', data['bills']);
          return (data['bills'] as List)
              .map((bill) => BillHistory.fromJson(bill))
              .toList();
        }
      }
      throw AnalyticsRequestException(
        _serverError('Could not load bill history', response),
      );
    } on AnalyticsRequestException {
      rethrow;
    } catch (e) {
      final cached = await _cacheService.getData('analytics_bills');
      if (cached is List) {
        return cached
            .map((bill) => BillHistory.fromJson(Map<String, dynamic>.from(bill as Map)))
            .toList();
      }
      throw const AnalyticsRequestException(
        'Cannot reach the billing server. Check your internet connection and sign in again.',
      );
    }
  }

  Future<Map<String, dynamic>> saveBill(
    String token, {
    required double totalAmount,
    required List<Map<String, dynamic>> items,
    String? customerPhone,
    String? customerName,
    int? verifiedCustomerId,
    String paymentMethod = 'cash',
    String billType = 'printed',
    String billingSource = 'voice',
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/analytics/bills'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Idempotency-Key': const Uuid().v4(),
            },
            body: json.encode({
              'total_amount': totalAmount,
              'items': items,
              'customer_phone': customerPhone,
              'customer_name': customerName,
              if (verifiedCustomerId != null)
                'verified_customer_id': verifiedCustomerId,
              'payment_method': paymentMethod,
              'bill_type': billType,
              'billing_source': billingSource,
            }),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data is Map && data['success'] == true && data['bill_id'] != null) {
          return Map<String, dynamic>.from(data);
        }
      }
      throw AnalyticsRequestException(
        _serverError('Bill could not be saved', response),
      );
    } on AnalyticsRequestException {
      rethrow;
    } catch (_) {
      throw AnalyticsRequestException(
        'Cannot reach the billing server. Check your internet connection and sign in again.',
      );
    }
  }

  String _serverError(String prefix, http.Response response) {
    String detail = '';
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map) {
        final value = decoded['detail'] ?? decoded['message'];
        if (value != null) detail = value.toString();
      }
    } catch (_) {
      detail = response.body.trim();
    }

    if (response.statusCode == 401) {
      return 'Your session has expired. Please sign in again.';
    }
    return detail.isEmpty
        ? '$prefix (server error ${response.statusCode}).'
        : '$prefix: $detail';
  }
}
