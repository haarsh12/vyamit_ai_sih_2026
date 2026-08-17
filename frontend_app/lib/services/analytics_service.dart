import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config.dart';
import '../models/dashboard.dart';

class AnalyticsService {
  final String baseUrl = ApiConfig.baseUrl;

  Future<DashboardData?> getDashboard(String token, {int days = 30}) async {
    try {
      print('📊 Fetching dashboard from: $baseUrl/analytics/dashboard?days=$days');
      final response = await http.get(
        Uri.parse('$baseUrl/analytics/dashboard?days=$days'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📊 Dashboard response status: ${response.statusCode}');
      print('📊 Dashboard response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return DashboardData.fromJson(data);
        }
      }
      return null;
    } catch (e) {
      print('❌ Error fetching dashboard: $e');
      return null;
    }
  }

  Future<List<BillHistory>> getBills(String token, {int limit = 50, int offset = 0}) async {
    try {
      print('📋 Fetching bills from: $baseUrl/analytics/bills?limit=$limit&offset=$offset');
      final response = await http.get(
        Uri.parse('$baseUrl/analytics/bills?limit=$limit&offset=$offset'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      print('📋 Bills response status: ${response.statusCode}');
      print('📋 Bills response body: ${response.body}');

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
      print('❌ Error fetching bills: $e');
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
      print('💾 Saving bill to database...');
      print('💾 Total: $totalAmount, Items: ${items.length}');
      print('💾 URL: $baseUrl/analytics/bills');
      
      final response = await http.post(
        Uri.parse('$baseUrl/analytics/bills'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'total_amount': totalAmount,
          'items': items,
          'customer_phone': customerPhone,
          'customer_name': customerName,
          'payment_method': paymentMethod,
        }),
      );

      print('💾 Save bill response status: ${response.statusCode}');
      print('💾 Save bill response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final success = data['success'] == true;
        print('💾 Bill saved: $success');
        return success;
      }
      return false;
    } catch (e) {
      print('❌ Error saving bill: $e');
      return false;
    }
  }
}
