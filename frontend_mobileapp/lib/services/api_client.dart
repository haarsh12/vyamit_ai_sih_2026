import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import 'auth_token_store.dart';

class ApiClient {
  static String get baseUrl => ApiConfig.baseUrl;
  final AuthTokenStore _tokenStore = AuthTokenStore();

  Future<dynamic> post(
    String endpoint,
    Map<String, dynamic> data, {
    Map<String, String> extraHeaders = const {},
  }) async {
    final url = Uri.parse('$baseUrl$endpoint');

    final token = await _tokenStore.read();

    try {
      final response = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
          ...extraHeaders,
        },
        body: jsonEncode(data),
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception("Connection Error: Is the Backend Running? ($e)");
    }
  }

  Future<dynamic> get(String endpoint) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final token = await _tokenStore.read();

    try {
      final response = await http.get(
        url,
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
        },
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception("Connection Error: $e");
    }
  }

  // PUT method for profile and item updates
  Future<dynamic> put(String endpoint, Map<String, dynamic> data) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final token = await _tokenStore.read();

    try {
      final response = await http.put(
        url,
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
        },
        body: jsonEncode(data),
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception("Connection Error: $e");
    }
  }

  // NEW: DELETE method for removing items
  Future<dynamic> delete(String endpoint) async {
    final url = Uri.parse('$baseUrl$endpoint');
    final token = await _tokenStore.read();

    try {
      final response = await http.delete(
        url,
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
        },
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception("Connection Error: $e");
    }
  }

  // Helper to handle success/errors
  dynamic _handleResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Handle empty responses (DELETE operations often return no body)
      if (response.body.isEmpty) {
        return {"message": "Success"};
      }
      return jsonDecode(response.body);
    } else {
      throw Exception("Server Error ${response.statusCode}: ${response.body}");
    }
  }
}
