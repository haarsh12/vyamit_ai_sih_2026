import 'package:flutter/services.dart';

typedef NativeSpeechResult = void Function(String text, bool isFinal);
typedef NativeSpeechStatus = void Function(String status);
typedef NativeSpeechError = void Function(int code, bool isFatal);
typedef NativeSoundLevel = void Function(double level);

/// Android 13+ device-STT bridge with verifiable AEC/NS/AGC capture effects.
///
/// It has a strict fallback contract: callers may treat the native path as
/// active only when both `started` and `aec_attached` are true. The Flutter
/// platform recognizer remains the safe fallback on unsupported devices.
class AndroidAecSpeechCapture {
  AndroidAecSpeechCapture({
    required NativeSpeechResult onResult,
    required NativeSpeechStatus onStatus,
    required NativeSpeechError onError,
    required NativeSoundLevel onSoundLevel,
  })  : _onResult = onResult,
        _onStatus = onStatus,
        _onError = onError,
        _onSoundLevel = onSoundLevel {
    _channel.setMethodCallHandler(_handleNativeEvent);
  }

  static const MethodChannel _channel =
      MethodChannel('com.vyamit.mykirana/aec_speech_capture');

  final NativeSpeechResult _onResult;
  final NativeSpeechStatus _onStatus;
  final NativeSpeechError _onError;
  final NativeSoundLevel _onSoundLevel;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  Future<Map<String, dynamic>> support() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getAecCaptureSupport',
      );
      return _toStringMap(result);
    } on MissingPluginException {
      return const {'supported': false};
    } on PlatformException {
      return const {'supported': false};
    }
  }

  Future<Map<String, dynamic>> start() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startAecCapture',
      );
      final settings = _toStringMap(result);
      _isRunning = settings['started'] == true;
      return settings;
    } on MissingPluginException {
      _isRunning = false;
      return const {'started': false};
    } on PlatformException {
      _isRunning = false;
      return const {'started': false};
    }
  }

  Future<void> stop() async {
    _isRunning = false;
    try {
      await _channel.invokeMethod<void>('stopAecCapture');
    } on MissingPluginException {
      // Unsupported platform.
    } on PlatformException {
      // Native capture is already closed.
    }
  }

  Future<void> dispose() async {
    await stop();
    _channel.setMethodCallHandler(null);
  }

  Future<void> _handleNativeEvent(MethodCall call) async {
    final arguments = call.arguments is Map
        ? Map<dynamic, dynamic>.from(call.arguments as Map)
        : const <dynamic, dynamic>{};
    switch (call.method) {
      case 'speechResult':
        final text = arguments['recognizedWords'];
        if (text is String && text.trim().isNotEmpty) {
          _onResult(text, arguments['finalResult'] == true);
        }
        return;
      case 'speechStatus':
        final status = arguments['status']?.toString() ?? '';
        _isRunning = status == 'listening' || status == 'speech_start';
        _onStatus(status);
        return;
      case 'speechError':
        _isRunning = false;
        final code = arguments['code'];
        _onError(code is int ? code : -1, arguments['fatal'] == true);
        return;
      case 'soundLevel':
        final value = arguments['level'];
        if (value is num) _onSoundLevel(value.toDouble());
        return;
    }
  }

  Map<String, dynamic> _toStringMap(Map<dynamic, dynamic>? value) =>
      value == null ? <String, dynamic>{} : Map<String, dynamic>.from(value);
}
