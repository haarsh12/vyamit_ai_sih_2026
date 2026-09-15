import '../models/gst_configuration.dart';
import '../../../services/api_client.dart';
import 'package:uuid/uuid.dart';

class GstService {
  final ApiClient _api = ApiClient();

  Future<GstConfiguration> getConfiguration() async {
    final response = await _api.get('/gst/configuration');
    return GstConfiguration.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<GstConfiguration> saveConfiguration(GstConfiguration configuration) async {
    final response = await _api.put('/gst/configuration', configuration.toJson());
    return GstConfiguration.fromJson(Map<String, dynamic>.from(response as Map));
  }

  Future<void> disableConfiguration() => _api.delete('/gst/configuration');

  Future<Map<String, dynamic>> previewInvoice(Map<String, dynamic> draft) async {
    final response = await _api.post('/gst/invoices/preview', draft);
    return Map<String, dynamic>.from(response as Map);
  }

  Future<Map<String, dynamic>> finalizeInvoice(Map<String, dynamic> draft) async {
    final response = await _api.post(
      '/gst/invoices',
      draft,
      extraHeaders: {'Idempotency-Key': const Uuid().v4()},
    );
    return Map<String, dynamic>.from(response as Map);
  }

  Future<void> markInvoicePrinted(int invoiceId) async {
    await _api.post('/gst/invoices/$invoiceId/printed', const {});
  }
}
