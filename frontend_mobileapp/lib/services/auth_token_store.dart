import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores only the bearer token in platform-protected storage.
///
/// A one-time migration reads the legacy SharedPreferences value and removes
/// it after a successful secure write. Non-secret user display data remains in
/// SharedPreferences so the current offline UI contract is preserved.
class AuthTokenStore {
  static const _key = 'user_token';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  Future<String?> read() async {
    final secureToken = await _secureStorage.read(key: _key);
    if (secureToken != null && secureToken.isNotEmpty) return secureToken;

    final preferences = await SharedPreferences.getInstance();
    final legacyToken = preferences.getString(_key);
    if (legacyToken == null || legacyToken.isEmpty) return null;
    await _secureStorage.write(key: _key, value: legacyToken);
    await preferences.remove(_key);
    return legacyToken;
  }

  Future<void> write(String token) =>
      _secureStorage.write(key: _key, value: token);

  Future<void> delete() => _secureStorage.delete(key: _key);
}
