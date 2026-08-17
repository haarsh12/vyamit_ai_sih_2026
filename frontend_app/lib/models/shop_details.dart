import 'dart:typed_data';

class ShopDetails {
  String shopName;
  String ownerName;
  String address;
  String phone1;
  String phone2;

  /// Canonical shop category from `core/shop_categories.dart`.
  String shopCategory;
  String medicalRegistrationNumber;
  String qualifications;
  Uint8List? qrCodeBytes; // Added for Printer Logic

  ShopDetails({
    required this.shopName,
    required this.ownerName,
    required this.address,
    required this.phone1,
    required this.phone2,
    this.shopCategory = 'General',
    this.medicalRegistrationNumber = '',
    this.qualifications = '',
    this.qrCodeBytes,
  });
}
