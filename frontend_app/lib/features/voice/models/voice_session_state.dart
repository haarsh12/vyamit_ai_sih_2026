/// The durable states used by the retail voice turn controller.
///
/// Keeping these states explicit avoids mixing microphone, network and playback
/// lifecycles in unrelated booleans.  The UI may choose its own labels, but all
/// turn-changing code should use this enum.
enum VoiceSessionState {
  idle,
  listening,
  userSpeaking,
  possibleEnd,
  processing,
  agentSpeaking,
  interrupting,
  error,
  disconnected,
}

extension VoiceSessionStateLabel on VoiceSessionState {
  String get label => switch (this) {
        VoiceSessionState.idle => 'Tap to start',
        VoiceSessionState.listening => 'Listening...',
        VoiceSessionState.userSpeaking => 'Listening...',
        VoiceSessionState.possibleEnd => 'Finishing your sentence...',
        VoiceSessionState.processing => 'Thinking...',
        VoiceSessionState.agentSpeaking => 'Vyamit AI speaking...',
        VoiceSessionState.interrupting => 'Interrupted',
        VoiceSessionState.error => 'Voice session error',
        VoiceSessionState.disconnected => 'Reconnecting...',
      };

  bool get acceptsSpeech => switch (this) {
        VoiceSessionState.listening ||
        VoiceSessionState.userSpeaking ||
        VoiceSessionState.possibleEnd ||
        VoiceSessionState.processing ||
        VoiceSessionState.agentSpeaking ||
        VoiceSessionState.interrupting ||
        VoiceSessionState.disconnected =>
          true,
        _ => false,
      };
}

/// Guards legal voice-turn transitions and makes unexpected lifecycle jumps
/// visible in development instead of silently changing one of many booleans.
class VoiceStateMachine {
  VoiceStateMachine([this._state = VoiceSessionState.idle]);

  VoiceSessionState _state;

  VoiceSessionState get state => _state;

  static const Map<VoiceSessionState, Set<VoiceSessionState>> _transitions = {
    VoiceSessionState.idle: {
      VoiceSessionState.listening,
      VoiceSessionState.error,
      VoiceSessionState.disconnected,
    },
    VoiceSessionState.listening: {
      VoiceSessionState.userSpeaking,
      VoiceSessionState.processing,
      VoiceSessionState.agentSpeaking,
      VoiceSessionState.idle,
      VoiceSessionState.error,
      VoiceSessionState.disconnected,
    },
    VoiceSessionState.userSpeaking: {
      VoiceSessionState.possibleEnd,
      VoiceSessionState.processing,
      VoiceSessionState.listening,
      VoiceSessionState.interrupting,
      VoiceSessionState.idle,
      VoiceSessionState.error,
    },
    VoiceSessionState.possibleEnd: {
      VoiceSessionState.userSpeaking,
      VoiceSessionState.processing,
      VoiceSessionState.listening,
      VoiceSessionState.idle,
      VoiceSessionState.error,
    },
    VoiceSessionState.processing: {
      VoiceSessionState.agentSpeaking,
      VoiceSessionState.interrupting,
      VoiceSessionState.listening,
      VoiceSessionState.idle,
      VoiceSessionState.error,
      VoiceSessionState.disconnected,
    },
    VoiceSessionState.agentSpeaking: {
      VoiceSessionState.userSpeaking,
      VoiceSessionState.interrupting,
      VoiceSessionState.listening,
      VoiceSessionState.idle,
      VoiceSessionState.error,
    },
    VoiceSessionState.interrupting: {
      VoiceSessionState.userSpeaking,
      VoiceSessionState.processing,
      VoiceSessionState.listening,
      VoiceSessionState.idle,
      VoiceSessionState.error,
    },
    VoiceSessionState.error: {
      VoiceSessionState.listening,
      VoiceSessionState.idle,
      VoiceSessionState.disconnected,
    },
    VoiceSessionState.disconnected: {
      VoiceSessionState.listening,
      VoiceSessionState.userSpeaking,
      VoiceSessionState.processing,
      VoiceSessionState.idle,
      VoiceSessionState.error,
    },
  };

  bool canTransitionTo(VoiceSessionState next) =>
      next == _state || (_transitions[_state]?.contains(next) ?? false);

  bool transitionTo(VoiceSessionState next) {
    if (!canTransitionTo(next)) return false;
    _state = next;
    return true;
  }

  /// Used only for terminal clean-up where the underlying platform may have
  /// already torn down the recognizer or WebSocket.
  void reset() => _state = VoiceSessionState.idle;
}
