import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class BillProvider with ChangeNotifier {
  // Live bill items (persists across screens)
  List<Map<String, dynamic>> _currentBillItems = [];
  
  // Customer name for current bill
  String _customerName = "Walk-in";
  
  // Sequential bill number
  int _lastBillNumber = 0;
  
  // QR Code persistence
  String? _qrCodePath;

  // Getters
  List<Map<String, dynamic>> get currentBillItems => _currentBillItems;
  String get customerName => _customerName;
  int get nextBillNumber => _lastBillNumber + 1;
  String? get qrCodePath => _qrCodePath;
  bool get hasBillItems => _currentBillItems.isNotEmpty;

  // Initialize provider - load persisted data
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Load last bill number
    _lastBillNumber = prefs.getInt('last_bill_number') ?? 0;
    
    // Load QR code path
    _qrCodePath = prefs.getString('qr_code_path');
    
    // Load customer name
    _customerName = prefs.getString('current_customer_name') ?? "Walk-in";
    
    // Load current bill items (if app was closed with items)
    final billItemsJson = prefs.getString('current_bill_items');
    if (billItemsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(billItemsJson);
        _currentBillItems = decoded.cast<Map<String, dynamic>>();
      } catch (e) {
        print("Error loading bill items: $e");
        _currentBillItems = [];
      }
    }
    
    notifyListeners();
  }

  // Set customer name
  void setCustomerName(String name) {
    _customerName = name.trim().isEmpty ? "Walk-in" : name.trim();
    _saveCustomerNameToStorage();
    notifyListeners();
  }

  // Add item to current bill
  void addBillItem(Map<String, dynamic> item) {
    _currentBillItems.add(item);
    _saveBillItemsToStorage();
    notifyListeners();
  }

  // Add multiple items to current bill
  void addBillItems(List<Map<String, dynamic>> items) {
    _currentBillItems.addAll(items);
    _saveBillItemsToStorage();
    notifyListeners();
  }

  // Remove item from current bill
  void removeBillItem(int index) {
    if (index >= 0 && index < _currentBillItems.length) {
      _currentBillItems.removeAt(index);
      _saveBillItemsToStorage();
      notifyListeners();
    }
  }

  // Clear current bill (Cancel Bill button)
  void clearBill() {
    _currentBillItems.clear();
    _customerName = "Walk-in"; // Reset customer name
    _saveBillItemsToStorage();
    _saveCustomerNameToStorage();
    notifyListeners();
  }

  // Update bill items (for frequent page)
  void updateBillItems(List<Map<String, dynamic>> items) {
    _currentBillItems = items;
    _saveBillItemsToStorage();
    notifyListeners();
  }

  // Get next bill number and increment
  Future<String> getNextBillNumber() async {
    _lastBillNumber++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_bill_number', _lastBillNumber);
    notifyListeners();
    return _lastBillNumber.toString();
  }

  // Save QR code path
  Future<void> saveQrCode(String path) async {
    _qrCodePath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('qr_code_path', path);
    notifyListeners();
  }

  // Remove QR code
  Future<void> removeQrCode() async {
    _qrCodePath = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('qr_code_path');
    notifyListeners();
  }

  // Private: Save bill items to storage
  Future<void> _saveBillItemsToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentBillItems.isEmpty) {
      await prefs.remove('current_bill_items');
    } else {
      final jsonString = jsonEncode(_currentBillItems);
      await prefs.setString('current_bill_items', jsonString);
    }
  }

  // Private: Save customer name to storage
  Future<void> _saveCustomerNameToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('current_customer_name', _customerName);
  }

  // Calculate total
  double get billTotal {
    return _currentBillItems.fold<double>(
      0,
      (sum, item) => sum + ((item['total'] as num?)?.toDouble() ?? 0),
    );
  }
}
