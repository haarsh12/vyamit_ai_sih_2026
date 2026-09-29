/// One source of truth for the API origin used by HTTP and WebSocket services.
///
/// Override this at build time instead of editing source, for example:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000`.
class ApiConfig {
  const ApiConfig._();

  static const String _productionUrl =
      'https://manthan4yuva-hackathon.onrender.com';

  static const String _configuredUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _productionUrl,
  );

  static String get baseUrl =>
      _configuredUrl.replaceFirst(RegExp(r'/+$'), '');

  /// Converts the configured HTTP(S) origin to the matching WS(S) origin.
  static String get wsUrl {
    final base = baseUrl;
    if (base.startsWith('https://')) {
      return base.replaceFirst('https://', 'wss://');
    }
    if (base.startsWith('http://')) {
      return base.replaceFirst('http://', 'ws://');
    }
    return 'ws://$base';
  }
}
