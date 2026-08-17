import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/shop_categories.dart';
import '../providers/auth_provider.dart';
import 'otp_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _shopNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _selectedShopCategory;

  void _checkUserAndSendOtp() async {
    String phone = _phoneController.text.trim();
    if (phone.length < 10 ||
        _shopNameController.text.isEmpty ||
        _ownerNameController.text.isEmpty ||
        _addressController.text.isEmpty ||
        _selectedShopCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                "Please fill all fields and select your shop type (category)")),
      );
      return;
    }

    if (!phone.startsWith("+91")) phone = "+91$phone";

    setState(() => _isLoading = true);

    try {
      // NEW LOGIC: Call Backend to Send OTP (isLogin = false)
      await Provider.of<AuthProvider>(context, listen: false)
          .sendOtp(phone, false);

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtpScreen(
              phoneNumber: phone,
              isLogin: false,
              shopName: _shopNameController.text.trim(),
              ownerName: _ownerNameController.text.trim(),
              address: _addressController.text.trim(),
              shopCategory: _selectedShopCategory!,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text("Error: ${e.toString().replaceAll('Exception:', '')}")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Create Account"),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Enter your shop details",
                style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 30),
            const Text("Shop Name",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _shopNameController,
              decoration: const InputDecoration(
                hintText: "e.g. Sharma Kirana",
                prefixIcon: Icon(Icons.store, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Owner Name",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _ownerNameController,
              decoration: const InputDecoration(
                hintText: "Your Name",
                prefixIcon: Icon(Icons.person, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Address",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                hintText: "City, State",
                prefixIcon: Icon(Icons.location_on, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Shop type",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text(
              "Required — helps billing AI understand your business",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedShopCategory,
              decoration: const InputDecoration(
                hintText: "Select category",
                prefixIcon: Icon(Icons.category_outlined, color: Colors.grey),
              ),
              items: kShopCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedShopCategory = v),
            ),
            const SizedBox(height: 20),
            const Text("Mobile Number",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: "10 digit number",
                prefixIcon: Icon(Icons.phone_android, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _checkUserAndSendOtp,
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Get OTP"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
