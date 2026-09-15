import 'dart:typed_data';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/prescription_draft.dart';

/// Renders a portrait prescription specifically for 57/58 mm thermal paper.
/// The printable 48 mm width maps to approximately 384 dots at 203 DPI.
class DoctorPrescriptionPrinterService {
  final BlueThermalPrinter _bluetooth = BlueThermalPrinter.instance;

  Future<String> printPrescription(
    PrescriptionDraft draft,
    DoctorProfileSnapshot doctor, {
    Uint8List? signaturePng,
  }) async {
    if (doctor.medicalRegistrationNumber.trim().isEmpty) {
      return 'Medical registration number is required before printing';
    }
    if ((await _bluetooth.isConnected) != true) {
      return 'Printer not connected';
    }

    try {
      final doc = pw.Document();
      const pageFormat = PdfPageFormat(
        48 * PdfPageFormat.mm,
        double.infinity,
        marginAll: 2 * PdfPageFormat.mm,
      );
      final signatureImage = signaturePng == null || signaturePng.isEmpty
          ? null
          : pw.MemoryImage(signaturePng);

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          build: (_) => pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  doctor.clinicName.trim().isEmpty
                      ? 'CLINIC / PRACTICE'
                      : doctor.clinicName.trim().toUpperCase(),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Text(
                  doctor.doctorName.trim().startsWith('Dr.')
                      ? doctor.doctorName.trim()
                      : 'Dr. ${doctor.doctorName.trim().isEmpty ? 'Doctor' : doctor.doctorName.trim()}',
                  textAlign: pw.TextAlign.center,
                  style:
                      pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
              ),
              if (doctor.qualifications.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    doctor.qualifications.trim(),
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 7),
                  ),
                ),
              pw.Center(
                child: pw.Text(
                  'Reg. No: ${doctor.medicalRegistrationNumber.trim()}',
                  style: const pw.TextStyle(fontSize: 7),
                ),
              ),
              if (doctor.address.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text(doctor.address.trim(),
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 6.5)),
                ),
              if (doctor.phone.trim().isNotEmpty)
                pw.Center(
                  child: pw.Text('Ph: ${doctor.phone.trim()}',
                      textAlign: pw.TextAlign.center,
                      style: const pw.TextStyle(fontSize: 6.5)),
                ),
              pw.Divider(thickness: 1.0),
              _line('Date', _dateTime(draft.prescribedAt)),
              _line('Patient', draft.patientName.isEmpty ? 'General Patient' : draft.patientName),
              if (draft.patientAge != null ||
                  draft.patientGender.trim().isNotEmpty)
                _line(
                  'Age / Sex',
                  '${draft.patientAge?.toString() ?? '-'} yrs / ${draft.patientGender.trim().isEmpty ? '-' : draft.patientGender.trim()}',
                ),
              if (draft.patientPhone.trim().isNotEmpty)
                _line('Phone', draft.patientPhone.trim()),
              if (draft.diagnosis.trim().isNotEmpty)
                _line('Diagnosis', draft.diagnosis.trim()),
              pw.Divider(thickness: 1.0),
              pw.Text('Rx (Medications)',
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              ...draft.medications
                  .asMap()
                  .entries
                  .where((entry) => entry.value.name.trim().isNotEmpty)
                  .map(
                (entry) {
                  final medication = entry.value;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '${entry.key + 1}. ${medication.name.trim()}${medication.dose.trim().isEmpty ? '' : ' (${medication.dose.trim()})'}',
                          style: pw.TextStyle(
                              fontSize: 9, fontWeight: pw.FontWeight.bold),
                        ),
                        ..._medicineLines(medication),
                      ],
                    ),
                  );
                },
              ),
              if (draft.additionalNotes.trim().isNotEmpty) ...[
                pw.Divider(thickness: 0.8),
                pw.Text('Advice / Instructions:',
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.Text(draft.additionalNotes.trim(),
                    style: const pw.TextStyle(fontSize: 7)),
              ],
              pw.SizedBox(height: 10),
              if (signatureImage != null)
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Image(signatureImage,
                      width: 65, height: 27, fit: pw.BoxFit.contain),
                ),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                    doctor.doctorName.trim().isEmpty
                        ? 'Doctor\'s Signature'
                        : 'Dr. ${doctor.doctorName.trim()}',
                    style: const pw.TextStyle(fontSize: 7)),
              ),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Text('*** Computer Generated Prescription ***',
                    style: const pw.TextStyle(fontSize: 6)),
              ),
              pw.SizedBox(height: 14),
            ],
          ),
        ),
      );

      var sentToPrinter = false;
      await for (final page
          in Printing.raster(await doc.save(), pages: [0], dpi: 203)) {
        final imageBytes = await page.toPng();
        final source = img.decodeImage(imageBytes);
        if (source == null) break;
        final raster =
            source.width == 384 ? source : img.copyResize(source, width: 384);
        await _bluetooth.writeBytes(Uint8List.fromList([0x1b, 0x40]));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await _bluetooth.writeBytes(Uint8List.fromList(_rasterBytes(raster)));
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await _bluetooth.writeBytes(Uint8List.fromList([0x0a, 0x0a, 0x0a]));
        sentToPrinter = true;
        break;
      }
      return sentToPrinter
          ? 'Success'
          : 'Print Error: prescription could not be rendered';
    } catch (error) {
      return 'Print Error: $error';
    }
  }

  pw.Widget _line(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
                text: '$label: ',
                style:
                    pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
            pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 7.5)),
          ],
        ),
      ),
    );
  }

  List<pw.Widget> _medicineLines(PrescriptionMedication medication) {
    final details = <String>[
      if (medication.dose.trim().isNotEmpty) 'Dose: ${medication.dose.trim()}',
      if (medication.frequency.trim().isNotEmpty) 'Freq: ${medication.frequency.trim()}',
      if (medication.duration.trim().isNotEmpty) 'Duration: ${medication.duration.trim()}',
      if (medication.timing.trim().isNotEmpty) 'When: ${medication.timing.trim()}',
      if (medication.route.trim().isNotEmpty && medication.route.trim().toLowerCase() != 'oral')
        'Route: ${medication.route.trim()}',
    ];
    final widgets = <pw.Widget>[];
    if (details.isNotEmpty) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 6, top: 1),
          child: pw.Text(
            details.join('  |  '),
            style: const pw.TextStyle(fontSize: 7),
          ),
        ),
      );
    }
    if (medication.instructions.trim().isNotEmpty) {
      widgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 6, top: 1),
          child: pw.Text(
            'Instructions: ${medication.instructions.trim()}',
            style: const pw.TextStyle(fontSize: 7),
          ),
        ),
      );
    }
    return widgets;
  }

  String _dateTime(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} $hour:$minute';
  }

  List<int> _rasterBytes(img.Image source) {
    final data = <int>[0x1d, 0x76, 0x30, 0x00];
    final widthBytes = (source.width + 7) ~/ 8;
    data.addAll([
      widthBytes % 256,
      widthBytes ~/ 256,
      source.height % 256,
      source.height ~/ 256
    ]);
    for (var y = 0; y < source.height; y++) {
      for (var xByte = 0; xByte < widthBytes; xByte++) {
        var byte = 0;
        for (var bit = 0; bit < 8; bit++) {
          final x = (xByte * 8) + bit;
          if (x >= source.width) continue;
          final pixel = source.getPixel(x, y);
          if (pixel.a == 0) continue;
          var brightness = img.getLuminance(pixel).toDouble();
          if (brightness <= 1.0) brightness *= 255;
          if (brightness < 128) byte |= 1 << (7 - bit);
        }
        data.add(byte);
      }
    }
    return data;
  }
}
