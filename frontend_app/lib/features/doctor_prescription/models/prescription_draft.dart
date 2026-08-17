class PrescriptionMedication {
  String name;
  String dose;
  String frequency;
  String duration;
  String timing;
  String route;
  String instructions;

  PrescriptionMedication({
    this.name = '',
    this.dose = '',
    this.frequency = '',
    this.duration = '',
    this.timing = '',
    this.route = '',
    this.instructions = '',
  });

  factory PrescriptionMedication.fromJson(Map<String, dynamic> json) {
    return PrescriptionMedication(
      name: json['name']?.toString() ?? '',
      dose: json['dose']?.toString() ?? '',
      frequency: json['frequency']?.toString() ?? '',
      duration: json['duration']?.toString() ?? '',
      timing: json['timing']?.toString() ?? '',
      route: json['route']?.toString() ?? '',
      instructions: json['instructions']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name.trim(),
        'dose': dose.trim(),
        'frequency': frequency.trim(),
        'duration': duration.trim(),
        'timing': timing.trim(),
        'route': route.trim(),
        'instructions': instructions.trim(),
      };
}

class PrescriptionDraft {
  String patientName;
  int? patientAge;
  String patientGender;
  String patientPhone;
  String diagnosis;
  String additionalNotes;
  String englishTranscript;
  DateTime prescribedAt;
  List<PrescriptionMedication> medications;

  PrescriptionDraft({
    this.patientName = '',
    this.patientAge,
    this.patientGender = '',
    this.patientPhone = '',
    this.diagnosis = '',
    this.additionalNotes = '',
    this.englishTranscript = '',
    DateTime? prescribedAt,
    List<PrescriptionMedication>? medications,
  })  : prescribedAt = prescribedAt ?? DateTime.now(),
        medications = medications ?? [PrescriptionMedication()];

  factory PrescriptionDraft.fromVoiceJson(Map<String, dynamic> json) {
    final patient = json['patient'] is Map<String, dynamic>
        ? json['patient'] as Map<String, dynamic>
        : <String, dynamic>{};
    final rawAge = patient['age'];
    final age = rawAge is num ? rawAge.toInt() : int.tryParse('$rawAge');
    final rawMedications = json['medications'] is List
        ? json['medications'] as List<dynamic>
        : <dynamic>[];
    return PrescriptionDraft(
      patientName: patient['name']?.toString() ?? '',
      patientAge: age,
      patientGender: patient['gender']?.toString() ?? '',
      patientPhone: patient['phone']?.toString() ?? '',
      diagnosis: json['diagnosis']?.toString() ?? '',
      additionalNotes: json['additional_notes']?.toString() ?? '',
      englishTranscript: json['english_transcript']?.toString() ?? '',
      medications: rawMedications
          .whereType<Map>()
          .map((item) =>
              PrescriptionMedication.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
    );
  }

  Map<String, dynamic> toPrintedJson({
    required List<List<List<double>>> signatureStrokes,
    required bool savePatient,
  }) =>
      {
        'patient_name': patientName.trim(),
        'patient_age': patientAge,
        'patient_gender': patientGender.trim(),
        'patient_phone': patientPhone.trim(),
        'diagnosis': diagnosis.trim(),
        'medications':
            medications.map((medication) => medication.toJson()).toList(),
        'additional_notes': additionalNotes.trim(),
        'signature_strokes': signatureStrokes,
        'prescribed_at': prescribedAt.toUtc().toIso8601String(),
        'save_patient': savePatient,
      };
}

class DoctorProfileSnapshot {
  final String doctorName;
  final String clinicName;
  final String qualifications;
  final String medicalRegistrationNumber;
  final String address;
  final String phone;

  const DoctorProfileSnapshot({
    required this.doctorName,
    required this.clinicName,
    required this.qualifications,
    required this.medicalRegistrationNumber,
    required this.address,
    required this.phone,
  });
}
