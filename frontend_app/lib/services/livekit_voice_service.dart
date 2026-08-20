import 'dart:async';
import 'dart:convert';

import 'package:livekit_client/livekit_client.dart';

import 'api_client.dart';

/// A typed event published by the server-side Vyamit LiveKit agent.
///
/// It is intentionally limited to UI state. Business writes remain normal
/// authenticated HTTP calls, with server-side validation and idempotency.
class VoiceUiEvent {
  final String type;
  final Map<String, dynamic> payload;

  const VoiceUiEvent(this.type, this.payload);
}

/// Owns one server-authorised LiveKit voice connection.
///
/// The mobile app never constructs a room name, participant identity, or
/// LiveKit JWT. Those are minted by POST /voice/token after app-JWT
/// authentication, which keeps tenant selection out of the client.
class LiveKitVoiceService {
  final ApiClient _api;
  final StreamController<VoiceUiEvent> _uiEvents =
      StreamController<VoiceUiEvent>.broadcast();

  Room? _room;
  EventsListener<RoomEvent>? _listener;
  bool _initialised = false;
  bool _connecting = false;

  LiveKitVoiceService({ApiClient? api}) : _api = api ?? ApiClient();

  Stream<VoiceUiEvent> get events => _uiEvents.stream;
  bool get isConnected => _room?.connectionState == ConnectionState.connected;
  bool get isConnecting => _connecting;

  Future<void> connect({String? participantName}) async {
    if (_connecting || isConnected) return;
    _connecting = true;
    try {
      final credentials = await _api.post('/voice/token', {
        if (participantName != null && participantName.trim().isNotEmpty)
          'participant_name': participantName.trim(),
      });
      final url = credentials['server_url']?.toString() ?? '';
      final token = credentials['participant_token']?.toString() ?? '';
      if (url.isEmpty || token.isEmpty) {
        throw StateError('Voice service returned incomplete connection credentials.');
      }

      if (!_initialised) {
        await LiveKitClient.initialize();
        _initialised = true;
      }
      await disconnect();
      final room = Room();
      final listener = room.createListener();
      listener
        ..on<DataReceivedEvent>(_onDataReceived)
        ..on<RoomDisconnectedEvent>((_) {
          _uiEvents.add(const VoiceUiEvent('disconnected', {}));
        });
      _room = room;
      _listener = listener;
      await room.connect(url, token);
      final participant = room.localParticipant;
      if (participant == null) {
        throw StateError('Voice connection did not create a local participant.');
      }
      await participant.setMicrophoneEnabled(true);
      _uiEvents.add(VoiceUiEvent('connected', {
        'room_name': credentials['room_name']?.toString(),
        'session_id': credentials['session_id']?.toString(),
      }));
    } catch (error) {
      _uiEvents.add(VoiceUiEvent('error', {'message': 'Could not start voice session.'}));
      await disconnect();
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    final participant = _room?.localParticipant;
    if (participant == null || !isConnected) return;
    await participant.setMicrophoneEnabled(enabled);
  }

  Future<void> disconnect() async {
    final listener = _listener;
    final room = _room;
    _listener = null;
    _room = null;
    if (listener != null) await listener.dispose();
    if (room != null) {
      await room.disconnect();
      await room.dispose();
    }
  }

  void _onDataReceived(DataReceivedEvent event) {
    if (event.topic != 'vyamit.ui') return;
    try {
      final decoded = jsonDecode(utf8.decode(event.data));
      if (decoded is! Map) return;
      final payload = Map<String, dynamic>.from(decoded);
      final type = payload.remove('type')?.toString();
      if (type == null || type.isEmpty) return;
      _uiEvents.add(VoiceUiEvent(type, payload));
    } on FormatException {
      // Ignore malformed data instead of allowing a remote participant to
      // crash the voice UI. The server publishes only this namespaced topic.
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _uiEvents.close();
  }
}
