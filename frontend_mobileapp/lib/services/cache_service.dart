import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized local cache service for fast, offline-first data access.
/// Stores application data in local storage with timestamps and automatic serialization.
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  static const String _prefix = 'app_cache_';

  /// Save raw serializable data (Map or List) into local storage
  Future<bool> saveData(String key, dynamic data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fullKey = '$_prefix$key';
      final payload = jsonEncode({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'data': data,
      });
      return await prefs.setString(fullKey, payload);
    } catch (e) {
      debugPrint('CacheService error saving key "$key": $e');
      return false;
    }
  }

  /// Retrieve cached data synchronously if possible or asynchronously
  Future<dynamic> getData(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fullKey = '$_prefix$key';
      final rawJson = prefs.getString(fullKey);
      if (rawJson == null || rawJson.isEmpty) return null;

      final Map<String, dynamic> decoded = jsonDecode(rawJson);
      return decoded['data'];
    } catch (e) {
      debugPrint('CacheService error reading key "$key": $e');
      return null;
    }
  }

  /// Get cached timestamp
  Future<int?> getCacheTimestamp(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final fullKey = '$_prefix$key';
      final rawJson = prefs.getString(fullKey);
      if (rawJson == null) return null;
      final Map<String, dynamic> decoded = jsonDecode(rawJson);
      return decoded['timestamp'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// Check if cache exists
  Future<bool> hasData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_prefix$key');
  }

  /// Clear specific key
  Future<bool> removeData(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return await prefs.remove('$_prefix$key');
  }

  /// Clear all app caches
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}
