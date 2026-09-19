import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart' as stt;

class LongBillSpeechStartResult {
  final bool started;
  final String message;

  const LongBillSpeechStartResult(this.started, this.message);
}

/// Owns device speech recognition for one manually stopped Long Bill recording.
///
/// The recognizer's transient audio remains on the device. This class retains
/// only the recognized text needed to create an editable server-side draft.
class LongBillSpeechService {
  LongBillSpeechService({
    required this.onTranscriptChanged,
    required this.onSoundLevelChanged,
    required this.onStatusChanged,
  });

  final void Function(String transcript) onTranscriptChanged;
  final void Function(double level) onSoundLevelChanged;
  final void Function(String status) onStatusChanged;

  final stt.SpeechToText _speech = stt.SpeechToText();
  Timer? _restartTimer;
  bool _hasInitialised = false;
  bool _isRecording = false;
  bool _manualStop = false;
  String _committedTranscript = '';
  String _currentHypothesis = '';
  String? _localeId;

  bool get isRecording => _isRecording;
  String get transcript => _composeTranscript();

  Future<LongBillSpeechStartResult> start() async {
    _manualStop = false;
    _committedTranscript = '';
    _currentHypothesis = '';
    _restartTimer?.cancel();

    if (!_hasInitialised) {
      final available = await _speech.initialize(
        onStatus: _handleStatus,
        onError: _handleError,
      );
      _hasInitialised = available;
      if (!available) {
        return const LongBillSpeechStartResult(
          false,
          'Speech recognition is unavailable. Enable an on-device language and microphone permission.',
        );
      }
      _localeId = await _findSupportedIndianLocale();
    }

    _isRecording = true;
    onTranscriptChanged('');
    onStatusChanged('Listening on this device…');
    await _listen();
    if (!_speech.isListening) {
      _isRecording = false;
      return const LongBillSpeechStartResult(
        false,
        'Could not start speech recognition. Check microphone permission and an installed language.',
      );
    }
    return const LongBillSpeechStartResult(true, 'Listening…');
  }

  Future<String> stop() async {
    _manualStop = true;
    _isRecording = false;
    _restartTimer?.cancel();
    _commitCurrentHypothesis();
    if (_speech.isListening) {
      await _speech.stop();
    }
    onSoundLevelChanged(0);
    onStatusChanged('Recording stopped');
    return transcript;
  }

  Future<void> dispose() async {
    _isRecording = false;
    _manualStop = true;
    _restartTimer?.cancel();
    if (_speech.isListening) {
      await _speech.cancel();
    }
  }

  Future<void> _listen() async {
    if (!_isRecording || _speech.isListening) return;
    try {
      await _speech.listen(
        onResult: _handleResult,
        onSoundLevelChange: _handleSoundLevel,
        localeId: _localeId,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          partialResults: true,
          cancelOnError: false,
          onDevice: true,
          listenFor: const Duration(minutes: 1),
          pauseFor: const Duration(seconds: 5),
        ),
      );
    } catch (_) {
      _scheduleRestart('Speech recognition paused. Reconnecting…');
    }
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
    } catch (_) {
      // The platform-selected locale is still a safe fallback.
    }
    return null;
  }

  void _handleResult(dynamic result) {
    if (!_isRecording) return;
    try {
      final words = result?.recognizedWords;
      if (words is! String || words.trim().isEmpty) return;
      _currentHypothesis = words.trim();
      if (result?.finalResult == true) {
        _commitCurrentHypothesis();
      }
      onTranscriptChanged(_composeTranscript());
    } catch (_) {
      onStatusChanged('Speech result could not be read. Please continue speaking.');
    }
  }

  void _handleStatus(String status) {
    if (!_isRecording || _manualStop) return;
    if (status == 'listening' || status == 'speech_start') {
      onStatusChanged('Listening…');
      return;
    }
    if (status == 'done' || status == 'notListening' || status == 'stopped') {
      _commitCurrentHypothesis();
      _scheduleRestart('Listening…');
    }
  }

  void _handleError(dynamic error) {
    if (!_isRecording || _manualStop) return;
    final permanent = error?.permanent == true;
    if (permanent) {
      _isRecording = false;
      onStatusChanged('Speech recognition stopped. Check the on-device language setting.');
      return;
    }
    _scheduleRestart('Listening…');
  }

  void _handleSoundLevel(double level) {
    if (!_isRecording) return;
    onSoundLevelChanged(((level + 10) / 30).clamp(.12, 1.0).toDouble());
  }

  void _scheduleRestart(String status) {
    if (!_isRecording || _manualStop) return;
    _restartTimer?.cancel();
    onStatusChanged(status);
    _restartTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_listen());
    });
  }

  void _commitCurrentHypothesis() {
    final hypothesis = _currentHypothesis.trim();
    if (hypothesis.isEmpty) return;
    _committedTranscript = _mergeTranscript(_committedTranscript, hypothesis);
    _currentHypothesis = '';
    onTranscriptChanged(_committedTranscript);
  }

  String _composeTranscript() {
    if (_currentHypothesis.isEmpty) return _committedTranscript;
    if (_committedTranscript.isEmpty) return _currentHypothesis;
    return _mergeTranscript(_committedTranscript, _currentHypothesis);
  }

  String _mergeTranscript(String previous, String next) {
    if (previous.isEmpty) return next;
    final normalPrevious = _normalise(previous);
    final normalNext = _normalise(next);
    if (normalNext == normalPrevious || normalPrevious.endsWith(normalNext)) {
      return previous;
    }
    // Some recognizers return the complete running utterance after a restart.
    if (normalNext.startsWith(normalPrevious)) return next;

    final previousWords = previous.split(RegExp(r'\s+'));
    final nextWords = next.split(RegExp(r'\s+'));
    final maximumOverlap = previousWords.length < nextWords.length
        ? previousWords.length
        : nextWords.length;
    for (var overlap = maximumOverlap; overlap > 0; overlap--) {
      final prior = previousWords.sublist(previousWords.length - overlap).join(' ');
      final upcoming = nextWords.sublist(0, overlap).join(' ');
      if (_normalise(prior) == _normalise(upcoming)) {
        return '${previous.trim()} ${nextWords.sublist(overlap).join(' ')}'.trim();
      }
    }
    return '${previous.trim()} ${next.trim()}';
  }

  String _normalise(String value) => value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}
