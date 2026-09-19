import 'dart:async';
import 'dart:convert';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/config.dart';
import '../../../services/api_client.dart';
import 'android_aec_speech_capture.dart';

enum TokenSaverSessionState { idle, connecting, listening, processing, speaking, error }

extension TokenSaverSessionStateLabel on TokenSaverSessionState {
  String get label => switch (this) {
        TokenSaverSessionState.idle => 'Tap to Start',
        TokenSaverSessionState.connecting => 'Connecting securely…',
        TokenSaverSessionState.listening => 'Listening on this device…',
        TokenSaverSessionState.processing => 'Processing text…',
        TokenSaverSessionState.speaking => 'Responding…',
        TokenSaverSessionState.error => 'Connection issue',
      };
}

/// On-device STT/TTS with a text-only WebSocket for the low-token voice mode.
///
/// No microphone samples are written to disk or sent to the backend.  The
/// service sends only one final device transcript per turn and restarts the
/// recognizer after local TTS playback has completed.
class TokenSaverVoiceService {
  TokenSaverVoiceService({
    required this.onStateChanged,
    required this.onTranscriptChanged,
    required this.onAudioLevelChanged,
    required this.onResponse,
  }) {
    _aecCapture = AndroidAecSpeechCapture(
      onResult: _handleNativeRecognitionResult,
      onStatus: _handleNativeSpeechStatus,
      onError: _handleNativeSpeechError,
      onSoundLevel: _handleNativeSoundLevel,
    );
  }

  final void Function(TokenSaverSessionState state, String message) onStateChanged;
  final void Function(String transcript) onTranscriptChanged;
  final void Function(double level) onAudioLevelChanged;
  final void Function(Map<String, dynamic> response) onResponse;

  final ApiClient _api = ApiClient();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  late final AndroidAecSpeechCapture _aecCapture;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _dispatchTimer;
  Timer? _restartTimer;
  Timer? _reconnectTimer;

  bool _isActive = false;
  bool _isSocketConnected = false;
  bool _speechInitialised = false;
  String _partialTranscript = '';
  String _lastDispatchedTranscript = '';
  DateTime? _lastDispatchedAt;
  String? _activeRequestId;
  int _requestSequence = 0;
  String? _localeId;
  bool _usesNativeAec = false;
  bool _nativeAecUnavailable = false;
  bool _preferOnDeviceRecognition = true;

  bool get isActive => _isActive;
  bool get isListening => _speech.isListening;

  Future<bool> start() async {
    if (_isActive) return true;
    _isActive = true;
    _partialTranscript = '';
    _activeRequestId = null;
    _setState(TokenSaverSessionState.connecting, 'Preparing device voice services…');

    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(.48);
      await _tts.setPitch(1.0);
      // The platform uses its locally installed voice. Failure to select Hindi
      // does not prevent the default device voice from reading a response.
      try {
        await _tts.setLanguage('hi-IN');
      } catch (_) {}

      if (!_speechInitialised) {
        final available = await _speech.initialize(
          onStatus: _handleSpeechStatus,
          onError: _handleSpeechError,
        );
        _speechInitialised = available;
        if (!available) {
          _isActive = false;
          _setState(TokenSaverSessionState.error, 'Enable microphone permission and an on-device speech language.');
          return false;
        }
        _localeId = await _findSupportedIndianLocale();
      }
      await _openSocket();
      return true;
    } catch (_) {
      _isActive = false;
      _setState(TokenSaverSessionState.error, 'Could not start Token Saver. Check your connection and try again.');
      return false;
    }
  }

  Future<void> stop() async {
    _isActive = false;
    _isSocketConnected = false;
    _dispatchTimer?.cancel();
    _restartTimer?.cancel();
    _reconnectTimer?.cancel();
    _activeRequestId = null;
    if (_speech.isListening) await _speech.stop();
    await _aecCapture.stop();
    _usesNativeAec = false;
    await _tts.stop();
    final subscription = _socketSubscription;
    final channel = _channel;
    _socketSubscription = null;
    _channel = null;
    await subscription?.cancel();
    await channel?.sink.close();
    _setState(TokenSaverSessionState.idle, TokenSaverSessionState.idle.label);
  }

  Future<void> dispose() async {
    await stop();
    await _aecCapture.dispose();
  }

  Future<void> _openSocket() async {
    final ticketResponse = await _api.post('/voice/token-saver/ticket', {});
    if (ticketResponse is! Map || ticketResponse['ticket'] is! String) {
      throw StateError('Token Saver did not receive a connection ticket.');
    }
    final uri = Uri.parse('${ApiConfig.wsUrl}/voice/token-saver/ws');
    final channel = WebSocketChannel.connect(
      uri,
      // Keep the short-lived credential out of URLs, browser history, and
      // ordinary request-query logging. The server negotiates only the named
      // application protocol, never echoes this ticket.
      protocols: ['vyamit-token-saver', ticketResponse['ticket'].toString()],
    );
    _channel = channel;
    _socketSubscription = channel.stream.listen(
      _handleSocketMessage,
      onError: (_) => _handleSocketClosed(),
      onDone: _handleSocketClosed,
      cancelOnError: false,
    );
  }

  void _handleSocketMessage(dynamic rawMessage) {
    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(rawMessage.toString());
      if (decoded is! Map) return;
      message = Map<String, dynamic>.from(decoded);
    } catch (_) {
      _setState(TokenSaverSessionState.error, 'Received an invalid server response.');
      return;
    }

    final type = message['type']?.toString();
    if (type == 'connected') {
      _isSocketConnected = true;
      _setState(TokenSaverSessionState.listening, TokenSaverSessionState.listening.label);
      unawaited(_startDeviceRecognition());
      return;
    }
    if (!_belongsToActiveRequest(message)) return;
    if (type == 'processing') {
      _setState(TokenSaverSessionState.processing, message['message']?.toString() ?? 'Processing text…');
      return;
    }
    if (type == 'complete') {
      final response = message['response'];
      if (response is! Map) {
        _setState(TokenSaverSessionState.error, 'Token Saver returned an invalid response.');
        _scheduleRecognizerRestart();
        return;
      }
      _activeRequestId = null;
      final result = Map<String, dynamic>.from(response);
      onResponse(result);
      unawaited(_speakThenListen(result['message']?.toString() ?? 'Ready for the next item.'));
      return;
    }
    if (type == 'error') {
      _activeRequestId = null;
      _setState(TokenSaverSessionState.error, message['message']?.toString() ?? 'Token Saver could not process that request.');
      _scheduleRecognizerRestart();
    }
  }

  bool _belongsToActiveRequest(Map<String, dynamic> message) {
    final requestId = _activeRequestId;
    if (requestId == null || requestId.isEmpty) return false;
    final received = message['request_id'];
    return received == null || received.toString() == requestId;
  }

  void _handleSocketClosed() {
    _isSocketConnected = false;
    if (!_isActive) return;
    _setState(TokenSaverSessionState.connecting, 'Reconnecting securely…');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_isActive && !_isSocketConnected) {
        unawaited(_reconnect());
      }
    });
  }

  Future<void> _reconnect() async {
    try {
      await _openSocket();
    } catch (_) {
      if (_isActive) _handleSocketClosed();
    }
  }

  Future<void> _startDeviceRecognition() async {
    if (!_isActive || !_isSocketConnected || _activeRequestId != null) return;
    if (!_nativeAecUnavailable && !_aecCapture.isRunning) {
      final support = await _aecCapture.support();
      if (support['supported'] == true) {
        final settings = await _aecCapture.start();
        _usesNativeAec = settings['started'] == true && settings['aec_attached'] == true;
        if (_usesNativeAec) {
          _setState(TokenSaverSessionState.listening, TokenSaverSessionState.listening.label);
          return;
        }
        await _aecCapture.stop();
      }
      _nativeAecUnavailable = true;
    }
    await _startFallbackRecognizer();
  }

  Future<void> _startFallbackRecognizer() async {
    if (!_isActive || !_isSocketConnected || _speech.isListening || _activeRequestId != null) return;
    try {
      await _speech.listen(
        onResult: _handleRecognitionResult,
        onSoundLevelChange: (level) {
          if (_isActive) {
            onAudioLevelChanged(((level + 10) / 30).clamp(.12, 1.0).toDouble());
          }
        },
        localeId: _localeId,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          // Keep offline recognition as the first choice. Some Android phones
          // have no downloaded offline language model; use the platform's
          // normal recognizer only after that capability reports a permanent
          // failure, rather than leaving the mode silent.
          onDevice: _preferOnDeviceRecognition,
          listenFor: const Duration(minutes: 1),
          pauseFor: const Duration(seconds: 4),
        ),
      );
      _setState(TokenSaverSessionState.listening, TokenSaverSessionState.listening.label);
    } catch (_) {
      _scheduleRecognizerRestart();
    }
  }

  void _handleRecognitionResult(dynamic result) {
    if (!_isActive || _activeRequestId != null) return;
    try {
      final words = result?.recognizedWords;
      if (words is! String || words.trim().isEmpty) return;
      _acceptRecognitionResult(words, result?.finalResult == true);
    } catch (_) {
      _setState(TokenSaverSessionState.error, 'Speech recognition returned an invalid result.');
    }
  }

  void _handleNativeRecognitionResult(String words, bool isFinal) {
    _acceptRecognitionResult(words, isFinal);
  }

  void _acceptRecognitionResult(String words, bool isFinal) {
    if (!_isActive || _activeRequestId != null || words.trim().isEmpty) return;
    _partialTranscript = words.trim();
    onTranscriptChanged(_partialTranscript);
    _dispatchTimer?.cancel();
    _dispatchTimer = Timer(
      isFinal ? const Duration(milliseconds: 350) : const Duration(milliseconds: 1600),
      _dispatchCurrentTranscript,
    );
  }

  Future<void> _dispatchCurrentTranscript() async {
    final transcript = _partialTranscript.trim();
    if (!_isActive || !_isSocketConnected || transcript.isEmpty || _activeRequestId != null) return;
    if (_isRecentDuplicate(transcript)) {
      _partialTranscript = '';
      return;
    }
    _lastDispatchedTranscript = _normalise(transcript);
    _lastDispatchedAt = DateTime.now();
    _partialTranscript = '';
    onTranscriptChanged(transcript);
    if (_usesNativeAec) {
      await _aecCapture.stop();
      _usesNativeAec = false;
    }
    if (_speech.isListening) await _speech.stop();
    onAudioLevelChanged(0);
    final requestId = '${DateTime.now().microsecondsSinceEpoch}-${++_requestSequence}';
    _activeRequestId = requestId;
    _setState(TokenSaverSessionState.processing, TokenSaverSessionState.processing.label);
    try {
      _channel?.sink.add(jsonEncode({
        'action': 'process',
        'request_id': requestId,
        'text': transcript,
      }));
    } catch (_) {
      _activeRequestId = null;
      _handleSocketClosed();
    }
  }

  Future<void> _speakThenListen(String message) async {
    if (!_isActive) return;
    final response = message.trim();
    if (response.isEmpty) {
      _scheduleRecognizerRestart();
      return;
    }
    _setState(TokenSaverSessionState.speaking, response);
    try {
      await _tts.speak(response);
    } catch (_) {
      // Local playback is optional; the visible response is still delivered.
    } finally {
      _scheduleRecognizerRestart();
    }
  }

  void _handleSpeechStatus(String status) {
    if (!_isActive || _activeRequestId != null || _usesNativeAec) return;
    if (status == 'done' || status == 'notListening' || status == 'stopped') {
      _scheduleRecognizerRestart();
    }
  }

  void _handleNativeSpeechStatus(String status) {
    if (!_isActive || _activeRequestId != null) return;
    if (status == 'listening' || status == 'speech_start') {
      _setState(TokenSaverSessionState.listening, TokenSaverSessionState.listening.label);
      return;
    }
    if (status == 'done' || status == 'stopped') {
      _usesNativeAec = false;
      _scheduleRecognizerRestart();
    }
  }

  void _handleNativeSpeechError(int _, bool isFatal) {
    if (!_isActive) return;
    _usesNativeAec = false;
    if (isFatal) _nativeAecUnavailable = true;
    _scheduleRecognizerRestart();
  }

  void _handleNativeSoundLevel(double level) {
    if (_isActive) {
      onAudioLevelChanged(((level + 10) / 30).clamp(.12, 1.0).toDouble());
    }
  }

  void _handleSpeechError(dynamic error) {
    if (!_isActive) return;
    if (error?.permanent == true) {
      if (_preferOnDeviceRecognition) {
        _preferOnDeviceRecognition = false;
        _setState(
          TokenSaverSessionState.connecting,
          'Offline speech is unavailable. Starting device recognition…',
        );
        _scheduleRecognizerRestart();
        return;
      }
      _setState(TokenSaverSessionState.error, 'Speech recognition stopped. Check the installed on-device language.');
      return;
    }
    _scheduleRecognizerRestart();
  }

  void _scheduleRecognizerRestart() {
    if (!_isActive || !_isSocketConnected || _activeRequestId != null) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_startDeviceRecognition());
    });
  }

  Future<String?> _findSupportedIndianLocale() async {
    try {
      final locales = await _speech.locales();
      for (final preferred in const ['hi_IN', 'mr_IN', 'en_IN']) {
        for (final locale in locales) {
          if (locale.localeId.replaceAll('-', '_').toLowerCase() == preferred) {
            return locale.localeId;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  bool _isRecentDuplicate(String value) {
    final previous = _lastDispatchedAt;
    return previous != null &&
        DateTime.now().difference(previous) < const Duration(seconds: 4) &&
        _normalise(value) == _lastDispatchedTranscript;
  }

  String _normalise(String value) => value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  void _setState(TokenSaverSessionState state, String message) {
    if (_isActive || state == TokenSaverSessionState.error || state == TokenSaverSessionState.idle) {
      onStateChanged(state, message);
    }
  }
}
