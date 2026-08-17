import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../core/config.dart';
import '../../../services/api_client.dart';
import '../models/prescription_draft.dart';

class DoctorPrescriptionService {
  final ApiClient _api = ApiClient();

  Future<PrescriptionDraft> processVoice(String text) async {
    final response =
        await _api.post('/doctor-prescriptions/voice/process', {'text': text});
    return _draftFromResponse(Map<String, dynamic>.from(response));
  }

  /// Uses the doctor-only WebSocket first. The separate HTTP endpoint remains
  /// a reliable fallback for restrictive networks and older Android devices.
  Future<PrescriptionDraft> processVoiceStream(String text) async {
    WebSocketChannel? channel;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('user_token');
      if (token == null || token.isEmpty) return processVoice(text);
      final uri = Uri.parse(
        '${ApiConfig.wsUrl}/doctor-prescriptions/voice/ws/stream?token=${Uri.encodeQueryComponent(token)}',
      );
      channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(const Duration(seconds: 8));
      channel.sink.add(jsonEncode({'action': 'process', 'text': text}));
      await for (final event
          in channel.stream.timeout(const Duration(seconds: 30))) {
        final decoded = jsonDecode(event.toString());
        if (decoded is! Map) continue;
        final message = Map<String, dynamic>.from(decoded);
        if (message['type'] == 'complete' && message['response'] is Map) {
          return _draftFromResponse(
              Map<String, dynamic>.from(message['response'] as Map));
        }
        if (message['type'] == 'error') {
          throw Exception(message['message'] ?? 'Voice processing failed');
        }
      }
      throw Exception('Voice stream closed before a draft was returned');
    } catch (_) {
      return processVoice(text);
    } finally {
      await channel?.sink.close();
    }
  }

  PrescriptionDraft _draftFromResponse(Map<String, dynamic> response) {
    final rawDraft = response['draft'];
    if (response['type'] != 'PRESCRIPTION_DRAFT' || rawDraft is! Map) {
      throw Exception(
          response['message'] ?? 'Unable to create prescription draft');
    }
    return PrescriptionDraft.fromVoiceJson(Map<String, dynamic>.from(rawDraft));
  }

  Future<Map<String, dynamic>> profileReadiness() async {
    final response = await _api.get('/doctor-prescriptions/profile-readiness');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> recordPrintedPrescription(
    PrescriptionDraft draft, {
    required List<List<List<double>>> signatureStrokes,
    required bool savePatient,
  }) async {
    await _api.post(
      '/doctor-prescriptions/printed',
      draft.toPrintedJson(
        signatureStrokes: signatureStrokes,
        savePatient: savePatient,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> patients({String query = ''}) async {
    final response = await _api.get(
      '/doctor-prescriptions/patients?q=${Uri.encodeQueryComponent(query)}',
    );
    final values = response['patients'] is List
        ? response['patients'] as List
        : <dynamic>[];
    return values
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
  }

  Future<Map<String, dynamic>> patientPrescriptions(int patientId) async {
    final response = await _api
        .get('/doctor-prescriptions/patients/$patientId/prescriptions');
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> deletePatient(int patientId) async {
    await _api.delete('/doctor-prescriptions/patients/$patientId');
  }

  Future<List<Map<String, dynamic>>> history() async {
    final response = await _api.get('/doctor-prescriptions/history');
    final values = response['prescriptions'] is List
        ? response['prescriptions'] as List
        : <dynamic>[];
    return values
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
  }

  Future<void> deletePrescription(int prescriptionId) async {
    await _api.delete('/doctor-prescriptions/history/$prescriptionId');
  }
}
