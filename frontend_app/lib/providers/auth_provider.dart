import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import '../models/shop_details.dart';
import '../core/shop_categories.dart';

class AuthProvider with ChangeNotifier {
  String? _token;
  ShopDetails? _shopDetails;
  final ApiClient _apiClient = ApiClient();

  bool get isLoggedIn => _token != null;
  String? get token => _token;
  ShopDetails? get shopDetails => _shopDetails;

  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('user_token')) return false;

    _token = prefs.getString('user_token');

    // Load saved shop details if available
    if (prefs.containsKey('user_data')) {
      final data = jsonDecode(prefs.getString('user_data')!);
      final cat = data['shop_category'] as String?;
      _shopDetails = ShopDetails(
        shopName: data['shop_name'] ?? "My Kirana",
        ownerName: data['owner_name'] ?? "Owner",
        address: data['address'] ?? "India",
        phone1: data['phone_number'] ?? "",
        phone2: data['phone2'] ?? "", // Load phone2 from storage
        shopCategory: canonicalShopCategory(cat),
        medicalRegistrationNumber: data['medical_registration_number'] ?? '',
        qualifications: data['qualifications'] ?? '',
      );

      print("DEBUG: Auto-login loaded phone2: ${_shopDetails?.phone2}");
    }

    notifyListeners();
    return true;
  }

  Future<bool> verifyOtp({
    required String phone,
    required String otp,
    String? shopName,
    String? ownerName,
    String? address,
    String? shopCategory,
  }) async {
    try {
      // 1. Send Request
      final response = await _apiClient.post('/auth/verify-otp', {
        "phone_number": phone,
        "otp_code": otp,
        if (shopName != null) "shop_name": shopName,
        if (ownerName != null) "owner_name": ownerName,
        if (address != null) "address": address,
        if (shopCategory != null) "shop_category": shopCategory,
      });

      // DEBUG LOG: Check this in your Flutter Terminal!
      print("SERVER RESPONSE: $response");

      // 2. Extract Token
      _token = response['access_token'];

      // 3. Extract Data (Prioritize Backend Data)
      String finalShopName = response['shop_name'] ?? shopName ?? "My Shop";
      String finalOwnerName = response['owner_name'] ?? ownerName ?? "Owner";
      String finalAddress = response['address'] ?? address ?? "India";
      String finalPhone2 = response['phone2'] ?? ""; // Get phone2 from response
      int userId = response['user_id'] ?? 0;
      final String finalCategory = canonicalShopCategory(
        response['shop_category'] as String? ?? shopCategory,
      );
      final String medicalRegistrationNumber =
          response['medical_registration_number'] ?? '';
      final String qualifications = response['qualifications'] ?? '';

      print("DEBUG: Received phone2 from backend: $finalPhone2");
      print("DEBUG: shop_category: $finalCategory");

      // 4. Save to Storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_token', _token!);

      final userData = {
        'user_id': userId,
        'shop_name': finalShopName,
        'owner_name': finalOwnerName,
        'address': finalAddress,
        'phone_number': phone,
        'phone2': finalPhone2, // Save phone2 to storage
        'shop_category': finalCategory,
        'medical_registration_number': medicalRegistrationNumber,
        'qualifications': qualifications,
      };
      await prefs.setString('user_data', jsonEncode(userData));

      // 5. Update State
      _shopDetails = ShopDetails(
        shopName: finalShopName,
        ownerName: finalOwnerName,
        address: finalAddress,
        phone1: phone,
        phone2: finalPhone2, // Set phone2 in state
        shopCategory: finalCategory,
        medicalRegistrationNumber: medicalRegistrationNumber,
        qualifications: qualifications,
      );

      notifyListeners();
      return true;
    } catch (e) {
      print("LOGIN ERROR: $e");
      rethrow;
    }
  }

  Future<void> sendOtp(String phone, bool isLogin) async {
    try {
      await _apiClient
          .post('/auth/send-otp', {"phone_number": phone, "is_login": isLogin});
    } catch (e) {
      rethrow;
    }
  }

  // Update Profile Method
  Future<bool> updateProfile({
    required String shopName,
    required String ownerName,
    required String address,
    String? phone2,
    required String shopCategory,
    String? medicalRegistrationNumber,
    String? qualifications,
  }) async {
    try {
      print(
          "Updating profile: Shop=$shopName, Owner=$ownerName, Address=$address, Phone2=$phone2, Category=$shopCategory");

      // 1. Send Update Request to Backend
      final response = await _apiClient.put('/auth/update-profile', {
        "shop_name": shopName,
        "owner_name": ownerName,
        "address": address,
        "shop_category": shopCategory,
        if (phone2 != null && phone2.isNotEmpty) "phone2": phone2,
        if (medicalRegistrationNumber != null)
          "medical_registration_number": medicalRegistrationNumber,
        if (qualifications != null) "qualifications": qualifications,
      });

      print("UPDATE RESPONSE: $response");

      // 2. Extract Updated Data
      String updatedShopName = response['shop_name'] ?? shopName;
      String updatedOwnerName = response['owner_name'] ?? ownerName;
      String updatedAddress = response['address'] ?? address;
      String updatedPhone2 =
          response['phone2'] ?? phone2 ?? ""; // Get phone2 from response
      final String updatedCategory = canonicalShopCategory(
        response['shop_category'] as String? ?? shopCategory,
      );
      final String updatedMedicalRegistrationNumber =
          response['medical_registration_number'] ??
              medicalRegistrationNumber ??
              _shopDetails?.medicalRegistrationNumber ??
              '';
      final String updatedQualifications = response['qualifications'] ??
          qualifications ??
          _shopDetails?.qualifications ??
          '';

      // Keep phone1 unchanged (it's read-only)
      String currentPhone1 = _shopDetails?.phone1 ?? "";

      print("DEBUG: Updated phone2 from backend: $updatedPhone2");

      // 3. Save to Local Storage
      final prefs = await SharedPreferences.getInstance();

      // Get existing user data to preserve user_id
      String? existingData = prefs.getString('user_data');
      int userId = 0;
      if (existingData != null) {
        final data = jsonDecode(existingData);
        userId = data['user_id'] ?? 0;
      }

      final userData = {
        'user_id': userId,
        'shop_name': updatedShopName,
        'owner_name': updatedOwnerName,
        'address': updatedAddress,
        'phone_number': currentPhone1,
        'phone2': updatedPhone2, // Save updated phone2
        'shop_category': updatedCategory,
        'medical_registration_number': updatedMedicalRegistrationNumber,
        'qualifications': updatedQualifications,
      };
      await prefs.setString('user_data', jsonEncode(userData));

      // 4. Update State
      _shopDetails = ShopDetails(
        shopName: updatedShopName,
        ownerName: updatedOwnerName,
        address: updatedAddress,
        phone1: currentPhone1,
        phone2: updatedPhone2, // Update phone2 in state
        shopCategory: updatedCategory,
        medicalRegistrationNumber: updatedMedicalRegistrationNumber,
        qualifications: updatedQualifications,
      );

      notifyListeners();
      return true;
    } catch (e) {
      print("UPDATE PROFILE ERROR: $e");
      rethrow;
    }
  }

  Future<void> logout() async {
    _token = null;
    _shopDetails = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    notifyListeners();
  }
}
