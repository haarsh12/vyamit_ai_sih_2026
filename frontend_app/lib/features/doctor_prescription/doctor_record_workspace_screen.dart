import 'package:flutter/material.dart';

import '../../core/theme.dart';

enum DoctorRecordWorkspaceType { patientHistory, pastRecords }

/// A privacy-safe placeholder for the Doctor Prescription mode.
///
/// It intentionally contains no patient records and performs no network call.
/// Clinical data requires a separate consent, access-control, audit, and
/// retention design before it can be introduced here.
class DoctorRecordWorkspaceScreen extends StatelessWidget {
  final DoctorRecordWorkspaceType type;

  const DoctorRecordWorkspaceScreen.patientHistory({super.key})
      : type = DoctorRecordWorkspaceType.patientHistory;

  const DoctorRecordWorkspaceScreen.pastRecords({super.key})
      : type = DoctorRecordWorkspaceType.pastRecords;

  @override
  Widget build(BuildContext context) {
    final isPatientHistory = type == DoctorRecordWorkspaceType.patientHistory;
    final title = isPatientHistory ? 'Patient History' : 'Past Records';
    final subtitle = isPatientHistory
        ? 'Patient history will appear here when the clinical module is enabled.'
        : 'Previous prescriptions and records will appear here when enabled.';
    final icon = isPatientHistory
        ? Icons.people_alt_rounded
        : Icons.folder_copy_rounded;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textBlack,
        elevation: 0.5,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: AppColors.lightGreenBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: AppColors.primaryGreen),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 18),
              const Text(
                'No patient data is stored or displayed in this layout-only release.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
