class ApiConfig {
  // ============================================
  // ENVIRONMENT CONFIGURATION
  // ============================================
  
  // Production URL (Render deployment - ACTIVE)
  static const String _productionUrl = "https://manthan4yuva-hackathon.onrender.com";
  
  // Development URL (Local backend - comment out for production)
  // static const String _developmentUrl = "http://10.40.209.207:8000";
  
  static const String _configuredUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _productionUrl,  // Production mode (Render)
    // defaultValue: _developmentUrl,     // Development mode (Local)
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
