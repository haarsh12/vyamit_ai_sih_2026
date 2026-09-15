import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'services/doctor_prescription_service.dart';

class DoctorPrescriptionHistoryScreen extends StatefulWidget {
  const DoctorPrescriptionHistoryScreen({super.key});

  @override
  State<DoctorPrescriptionHistoryScreen> createState() =>
      _DoctorPrescriptionHistoryScreenState();
}

class _DoctorPrescriptionHistoryScreenState
    extends State<DoctorPrescriptionHistoryScreen> {
  final _service = DoctorPrescriptionService();
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await _service.history();
      if (mounted) setState(() => _records = records);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to load prescription history.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteRecord(Map<String, dynamic> record) async {
    final prescriptionId = record['id'] as int?;
    if (prescriptionId == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete prescription?'),
            content: const Text(
                'This removes this prescription from history. It cannot be undone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await _service.deletePrescription(prescriptionId);
      if (!mounted) return;
      setState(
          () => _records.removeWhere((item) => item['id'] == prescriptionId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Prescription deleted.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not delete this prescription.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Prescription History',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textBlack,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: _load,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 140),
                    Center(
                      child: Column(
                        children: [
                          Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: Colors.black54)),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Try again'),
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryGreen),
                          ),
                        ],
                      ),
                    ),
                  ])
                : _records.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 120),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: const BoxDecoration(
                                  color: AppColors.lightGreenBg,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.history_edu_rounded,
                                    size: 48, color: AppColors.primaryGreen),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No Printed Prescriptions Yet',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Prescriptions that you format and print will be saved here automatically.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppColors.textGrey, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _records.length,
                        itemBuilder: (_, index) =>
                            _historyCard(_records[index]),
                      ),
      ),
    );
  }

  Widget _historyCard(Map<String, dynamic> record) {
    final patient = record['patient'] is Map
        ? Map<String, dynamic>.from(record['patient'] as Map)
        : <String, dynamic>{};
    final doctor = record['doctor'] is Map
        ? Map<String, dynamic>.from(record['doctor'] as Map)
        : <String, dynamic>{};
    final medications = record['medications'] is List
        ? record['medications'] as List
        : <dynamic>[];
    final date = DateTime.tryParse(record['printed_at']?.toString() ?? '');
    final dateLabel = date == null
        ? 'Printed prescription'
        : DateFormat('dd MMM yyyy • hh:mm a').format(date.toLocal());

    final patientName = patient['name']?.toString().trim() ?? '';
    final age = patient['age'];
    final gender = patient['gender']?.toString().trim() ?? '';
    final diagnosis = record['diagnosis']?.toString().trim() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8F5E9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: const CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.lightGreenBg,
          foregroundColor: AppColors.primaryGreen,
          child: Icon(Icons.receipt_long_rounded, size: 22),
        ),
        title: Text(
          patientName.isEmpty ? 'General Patient' : patientName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textBlack),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(dateLabel,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Delete prescription',
              onPressed: () => _deleteRecord(record),
              color: Colors.red.shade600,
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
            ),
            const Icon(Icons.expand_more_rounded, color: Colors.grey),
          ],
        ),
        children: [
          const Divider(height: 16, thickness: 0.8),
          
          // Patient details chips
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (age != null)
                _chip(Icons.cake_rounded, '$age yrs'),
              if (gender.isNotEmpty)
                _chip(Icons.person_rounded, gender),
              _chip(Icons.medication_rounded, '${medications.length} Medications', isHighlight: true),
            ],
          ),

          if (diagnosis.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medical_information_rounded, size: 16, color: Colors.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Diagnosis: $diagnosis',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'PRESCRIPTION (Rx)',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: AppColors.primaryGreen),
            ),
          ),
          const SizedBox(height: 8),

          ...medications.whereType<Map>().map((medicine) {
            final medName = medicine['name']?.toString() ?? '';
            final dose = medicine['dose']?.toString().trim() ?? '';
            final freq = medicine['frequency']?.toString().trim() ?? '';
            final duration = medicine['duration']?.toString().trim() ?? '';
            final timing = medicine['timing']?.toString().trim() ?? '';
            final instruction = medicine['instructions']?.toString().trim() ?? '';

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FBE7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE6EE9C)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, size: 15, color: AppColors.primaryGreen),
                      const SizedBox(width: 6),
                      Text(
                        medName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      if (dose.isNotEmpty)
                        Text(
                          ' ($dose)',
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black54, fontSize: 13),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (freq.isNotEmpty) _medPill('Freq: $freq'),
                      if (duration.isNotEmpty) _medPill('Duration: $duration', color: Colors.blue),
                      if (timing.isNotEmpty) _medPill('When: $timing', color: Colors.teal),
                    ],
                  ),
                  if (instruction.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        'Instructions: $instruction',
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                      ),
                    ),
                ],
              ),
            );
          }),

          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded, size: 14, color: AppColors.primaryGreen),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Dr. ${doctor['name'] ?? 'Doctor'} • Reg. No: ${doctor['medical_registration_number'] ?? 'N/A'}',
                    style: const TextStyle(color: Colors.black87, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, {bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isHighlight ? AppColors.lightGreenBg : const Color(0xFFF1F8E9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primaryGreen),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                fontSize: 11,
                color: isHighlight ? AppColors.primaryGreen : const Color(0xFF33691E),
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _medPill(String text, {MaterialColor color = Colors.green}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.shade200, width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade800),
      ),
    );
  }
}
