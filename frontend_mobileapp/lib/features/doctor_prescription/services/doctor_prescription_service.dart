import 'package:uuid/uuid.dart';

import '../../../services/api_client.dart';
import '../../../services/cache_service.dart';
import '../models/prescription_draft.dart';

class DoctorPrescriptionService {
  final ApiClient _api = ApiClient();
  final CacheService _cacheService = CacheService();

  Future<PrescriptionDraft> processVoice(String text) async {
    final response =
        await _api.post('/doctor-prescriptions/voice/process', {'text': text});
    return _draftFromResponse(Map<String, dynamic>.from(response));
  }

  /// The legacy doctor WebSocket is intentionally retired.  This temporary
  /// HTTP bridge only formats an editable draft; audio itself moves to the
  /// authenticated LiveKit flow in the focused voice migration.
  Future<PrescriptionDraft> processVoiceStream(String text) async {
    return processVoice(text);
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
      extraHeaders: {'Idempotency-Key': const Uuid().v4()},
    );
  }

  Future<List<Map<String, dynamic>>> patients({String query = ''}) async {
    final cacheKey = 'doctor_patients_$query';
    try {
      final response = await _api.get(
        '/doctor-prescriptions/patients?q=${Uri.encodeQueryComponent(query)}',
      );
      final values = response['patients'] is List
          ? response['patients'] as List
          : <dynamic>[];
      final result = values
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
      await _cacheService.saveData(cacheKey, result);
      return result;
    } catch (e) {
      final cached = await _cacheService.getData(cacheKey);
      if (cached is List) {
        return cached
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> patientPrescriptions(int patientId) async {
    final cacheKey = 'doctor_patient_prescriptions_$patientId';
    try {
      final response = await _api
          .get('/doctor-prescriptions/patients/$patientId/prescriptions');
      final result = Map<String, dynamic>.from(response as Map);
      await _cacheService.saveData(cacheKey, result);
      return result;
    } catch (e) {
      final cached = await _cacheService.getData(cacheKey);
      if (cached is Map) {
        return Map<String, dynamic>.from(cached);
      }
      rethrow;
    }
  }

  Future<void> deletePatient(int patientId) async {
    await _api.delete('/doctor-prescriptions/patients/$patientId');
  }

  Future<List<Map<String, dynamic>>> history() async {
    const cacheKey = 'doctor_history';
    try {
      final response = await _api.get('/doctor-prescriptions/history');
      final values = response['prescriptions'] is List
          ? response['prescriptions'] as List
          : <dynamic>[];
      final result = values
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .toList();
      await _cacheService.saveData(cacheKey, result);
      return result;
    } catch (e) {
      final cached = await _cacheService.getData(cacheKey);
      if (cached is List) {
        return cached
            .whereType<Map>()
            .map((value) => Map<String, dynamic>.from(value))
            .toList();
      }
      rethrow;
    }
  }

  Future<void> deletePrescription(int prescriptionId) async {
    await _api.delete('/doctor-prescriptions/history/$prescriptionId');
  }
}
