/// Modes presented in the swipe-only section of the billing voice screen.
enum VoiceMode {
  voiceAgent,
  tokenSaver,
  offlineAgent,
  longBill,
}

extension VoiceModeDetails on VoiceMode {
  String get title => switch (this) {
        VoiceMode.voiceAgent => 'Voice Agent',
        VoiceMode.tokenSaver => 'Token Saver',
        VoiceMode.offlineAgent => 'Offline Agent',
        VoiceMode.longBill => 'Long Bill',
      };

  String get description => switch (this) {
        VoiceMode.voiceAgent => 'LiveKit realtime voice assistant',
        VoiceMode.tokenSaver => 'Offline STT + WebSocket TTS pipeline',
        VoiceMode.offlineAgent => 'Offline voice assistant',
        VoiceMode.longBill => 'Record a complete bill, then review the draft',
      };

  bool get isAvailable => this != VoiceMode.offlineAgent;
}
