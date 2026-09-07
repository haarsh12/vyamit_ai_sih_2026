import 'dart:io';
import 'package:flutter/foundation.dart';

class ApiConfig {
  // 🚀 PRODUCTION - Render Backend
  static const String _productionUrl = "https://ideathon-vyamit.onrender.com";
  
  // 🧪 LOCAL DEVELOPMENT URLs
  static const String _emulatorUrl = "http://10.0.2.2:8000";
  static const String _realDeviceUrl = "http://10.147.4.207:8000";  // Replace with your laptop's local IP
  static const String _localUrl = "http://localhost:8000";

  static String get baseUrl {
    // 🧪 ACTIVE: DEVELOPMENT MODE - Real Device via USB
    if (kReleaseMode) {
      return _productionUrl;  // Use production in release mode
    }
    
    if (Platform.isAndroid) {
      return _realDeviceUrl;  // Real phone connected via USB
      // return _emulatorUrl;  // Uncomment for emulator
    }
    
    return _localUrl;  // Web/Windows
    
    // 🚀 TO SWITCH TO PRODUCTION: Comment above code and uncomment below
    /*
    return _productionUrl;
    */
  }

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
