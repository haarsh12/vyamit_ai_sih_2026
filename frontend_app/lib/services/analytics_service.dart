import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../core/config.dart';
import '../models/dashboard.dart';

class AnalyticsService {
  final String baseUrl = ApiConfig.baseUrl;

  Future<DashboardData?> getDashboard(String token, {int days = 30}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/analytics/dashboard?days=$days'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return DashboardData.fromJson(data);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<List<BillHistory>> getBills(String token, {int limit = 50, int offset = 0}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/analytics/bills?limit=$limit&offset=$offset'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return (data['bills'] as List)
              .map((bill) => BillHistory.fromJson(bill))
              .toList();
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> saveBill(
    String token, {
    required double totalAmount,
    required List<Map<String, dynamic>> items,
    String? customerPhone,
    String? customerName,
    String paymentMethod = 'cash',
  }) async {
    try {
      final response = await http.post(
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
          'payment_method': paymentMethod,
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}
