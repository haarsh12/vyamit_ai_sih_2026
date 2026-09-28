import 'package:flutter/foundation.dart';

import '../models/gst_configuration.dart';
import '../services/gst_service.dart';

class GstProvider with ChangeNotifier {
  final GstService _service;

  GstProvider({GstService? service}) : _service = service ?? GstService();

  GstConfiguration _configuration = const GstConfiguration(isEnabled: false);
  bool _isLoading = false;
  bool _isSaving = false;
  bool _currentBillGstEnabled = false;
  String _customerGstin = '';
  String _customerStateCode = '';

  GstConfiguration get configuration => _configuration;
  bool get isShopGstEnabled =>
      _configuration.isEnabled && _configuration.canIssueTaxInvoice;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isCurrentBillGstEnabled => _currentBillGstEnabled;
  String get customerGstin => _customerGstin;
  String get customerStateCode => _customerStateCode;

  Future<void> loadConfiguration() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      _configuration = await _service.getConfiguration();
      if (!_configuration.isEnabled) _currentBillGstEnabled = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveConfiguration(GstConfiguration configuration) async {
    if (_isSaving) return;
    _isSaving = true;
    notifyListeners();
    try {
      _configuration = await _service.saveConfiguration(configuration);
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> disableConfiguration() async {
    if (_isSaving) return;
    _isSaving = true;
    notifyListeners();
    try {
      await _service.disableConfiguration();
      _configuration = const GstConfiguration(
          isEnabled: false, verificationStatus: 'disabled');
      resetCurrentBill();
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  void setCurrentBillGstEnabled(bool enabled) {
    if (enabled && !_configuration.isEnabled) return;
    _currentBillGstEnabled = enabled;
    if (!enabled) {
      _customerGstin = '';
      _customerStateCode = '';
    }
    notifyListeners();
  }

  void setCustomerTaxDetails({String? gstin, String? stateCode}) {
    if (gstin != null) _customerGstin = gstin;
    if (stateCode != null) _customerStateCode = stateCode;
    notifyListeners();
  }

  void resetCurrentBill() {
    _currentBillGstEnabled = false;
    _customerGstin = '';
    _customerStateCode = '';
    notifyListeners();
  }
}
