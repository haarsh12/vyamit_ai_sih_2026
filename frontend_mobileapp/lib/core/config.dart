class ApiConfig {
  // ============================================
  // ENVIRONMENT CONFIGURATION
  // ============================================
  
  // Production URL (uncomment for production)
  // static const String _productionUrl = "https://ideathon-vyamit.onrender.com";
  
  // Development URL (comment out for production)
  static const String _developmentUrl = "http://192.168.56.207:8000";
  
  static const String _configuredUrl = String.fromEnvironment(
    'API_BASE_URL',
    // defaultValue: _productionUrl,  // Production mode
    defaultValue: _developmentUrl,     // Development mode
  );

  static String get baseUrl => _configuredUrl.replaceFirst(RegExp(r'/+$'), '');

  // For local development, pass a known reachable origin at build/run time:
  // flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000

  /// Convert the HTTP API origin to its matching WebSocket origin.
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
