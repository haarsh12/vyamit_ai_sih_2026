import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import 'services/doctor_prescription_service.dart';

class DoctorPatientListScreen extends StatefulWidget {
  const DoctorPatientListScreen({super.key});

  @override
  State<DoctorPatientListScreen> createState() =>
      _DoctorPatientListScreenState();
}

class _DoctorPatientListScreenState extends State<DoctorPatientListScreen> {
  final _service = DoctorPrescriptionService();
  final _search = TextEditingController();
  List<Map<String, dynamic>> _patients = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final patients = await _service.patients(query: _search.text.trim());
      if (mounted) setState(() => _patients = patients);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load the patient list.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deletePatient(Map<String, dynamic> patient) async {
    final patientId = patient['id'] as int?;
    if (patientId == null) return;
    final name = patient['name']?.toString().trim();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete patient?'),
            content: Text(
              'Delete ${name?.isEmpty ?? true ? 'this patient' : name} and all of their saved prescription history? This cannot be undone.',
            ),
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
      await _service.deletePatient(patientId);
      if (!mounted) return;
      setState(() => _patients.removeWhere((item) => item['id'] == patientId));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Patient deleted.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not delete this patient.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final patient in _patients) {
      final name = patient['name']?.toString().trim() ?? '';
      final letter = name.isEmpty ? '#' : name[0].toUpperCase();
      groups.putIfAbsent(letter, () => []).add(patient);
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Patient Directory',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textBlack,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Search Input
            TextField(
              controller: _search,
              onChanged: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search patient by name or phone...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryGreen),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5)),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                  padding: EdgeInsets.all(36),
                  child: Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)))
            else if (_error != null)
              _emptyState(Icons.cloud_off_rounded, _error!, action: _load)
            else if (_patients.isEmpty)
              _emptyState(Icons.person_search_rounded,
                  'No saved patients found.\nPatients are added automatically when you approve after printing.')
            else
              ...groups.entries.expand((entry) => [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 12, 6, 8),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreen,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              entry.key,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Container(height: 1, color: Colors.grey.shade200)),
                        ],
                      ),
                    ),
                    ...entry.value.map((patient) => _patientTile(patient)),
                  ]),
          ],
        ),
      ),
    );
  }

  Widget _patientTile(Map<String, dynamic> patient) {
    final age = patient['age'];
    final gender = patient['gender']?.toString() ?? '';
    final phone = patient['phone']?.toString() ?? '';
    final name = patient['name']?.toString() ?? 'Patient';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        leading: CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.lightGreenBg,
          foregroundColor: AppColors.primaryGreen,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textBlack),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (age != null)
                _chip(Icons.cake_rounded, '$age yrs'),
              if (gender.isNotEmpty)
                _chip(Icons.person_rounded, gender),
              if (phone.isNotEmpty)
                _chip(Icons.phone_rounded, phone),
            ],
          ),
        ),
        children: [
          const Divider(height: 16, thickness: 0.8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DoctorPatientPrescriptionsScreen(
                          patientId: patient['id'] as int),
                    ),
                  ),
                  icon: const Icon(Icons.history_edu_rounded, size: 18),
                  label: const Text('View Prescriptions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Delete Patient',
                onPressed: () => _deletePatient(patient),
                color: Colors.red.shade600,
                style: IconButton.styleFrom(side: BorderSide(color: Colors.red.shade200)),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F8E9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primaryGreen),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF33691E), fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(IconData icon, String message, {VoidCallback? action}) =>
      Padding(
        padding: const EdgeInsets.only(top: 60, bottom: 40),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: AppColors.lightGreenBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: AppColors.primaryGreen),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54, height: 1.4, fontSize: 14),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: action,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryGreen),
              ),
            ],
          ],
        ),
      );
}

class DoctorPatientPrescriptionsScreen extends StatefulWidget {
  final int patientId;
  const DoctorPatientPrescriptionsScreen({super.key, required this.patientId});

  @override
  State<DoctorPatientPrescriptionsScreen> createState() =>
      _DoctorPatientPrescriptionsScreenState();
}

class _DoctorPatientPrescriptionsScreenState
    extends State<DoctorPatientPrescriptionsScreen> {
  final _service = DoctorPrescriptionService();
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _service.patientPrescriptions(widget.patientId);
      if (mounted) setState(() => _data = data);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final patient = _data?['patient'] is Map
        ? Map<String, dynamic>.from(_data!['patient'] as Map)
        : <String, dynamic>{};
    final records = _data?['prescriptions'] is List
        ? (_data!['prescriptions'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
        : <Map<String, dynamic>>[];
    final name = patient['name']?.toString() ?? 'Patient Prescriptions';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textBlack,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (patient.isNotEmpty) _patientHeader(patient),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.history_rounded, color: AppColors.primaryGreen, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Prescription Records (${records.length})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (records.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(30),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: Text(
                        'No printed prescriptions for this patient yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ...records.map(_recordCard),
              ],
            ),
    );
  }

  Widget _patientHeader(Map<String, dynamic> patient) {
    final name = patient['name']?.toString() ?? '';
    final age = patient['age'];
    final gender = patient['gender']?.toString() ?? '';
    final phone = patient['phone']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade800, Colors.green.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            foregroundColor: Colors.white,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'P',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (age != null) '$age yrs old',
                    if (gender.isNotEmpty) gender,
                    if (phone.isNotEmpty) 'Ph: $phone',
                  ].join('  •  '),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordCard(Map<String, dynamic> record) {
    final medications = record['medications'] is List
        ? record['medications'] as List
        : <dynamic>[];
    final date = DateTime.tryParse(record['printed_at']?.toString() ?? '');
    final dateFormatted = date == null
        ? 'Printed prescription'
        : DateFormat('dd MMM yyyy • hh:mm a').format(date.toLocal());
    final diagnosis = record['diagnosis']?.toString().trim() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.event_available_rounded, size: 16, color: AppColors.primaryGreen),
                  const SizedBox(width: 6),
                  Text(
                    dateFormatted,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryGreen),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.lightGreenBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${medications.length} Meds',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                ),
              ),
            ],
          ),
          if (diagnosis.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.medical_information_rounded, size: 15, color: Colors.amber),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Diagnosis: $diagnosis',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Divider(height: 20, thickness: 0.8),
          ...medications.whereType<Map>().map((medicine) {
            final name = medicine['name']?.toString() ?? '';
            final dose = medicine['dose']?.toString().trim() ?? '';
            final freq = medicine['frequency']?.toString().trim() ?? '';
            final duration = medicine['duration']?.toString().trim() ?? '';
            final timing = medicine['timing']?.toString().trim() ?? '';
            final instructions = medicine['instructions']?.toString().trim() ?? '';

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.medication_liquid_rounded, size: 16, color: AppColors.primaryGreen),
                      const SizedBox(width: 6),
                      Text(
                        name,
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
                  if (instructions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 4),
                      child: Text(
                        'Instructions: $instructions',
                        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade700),
                      ),
                    ),
                ],
              ),
            );
          }),
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

