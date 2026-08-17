import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import 'home_screen.dart';

class OtpScreen extends StatefulWidget {
  final String phoneNumber;
  final bool isLogin;
  // Optional data for Registration
  final String? shopName;
  final String? ownerName;
  final String? address;
  final String? shopCategory;

  const OtpScreen({
    super.key,
    required this.phoneNumber,
    required this.isLogin,
    this.shopName,
    this.ownerName,
    this.address,
    this.shopCategory,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  // 6 separate controllers for each OTP digit
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    6,
    (index) => FocusNode(),
  );

  Timer? _timer;
  int _secondsRemaining = 45;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    // Auto-focus first box
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  void _startTimer() {
    setState(() => _secondsRemaining = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      } else {
        _timer?.cancel();
      }
    });
  }

  void _resendOtp() async {
    try {
      await Provider.of<AuthProvider>(context, listen: false)
          .sendOtp(widget.phoneNumber, widget.isLogin);
      _startTimer();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("OTP Resent!")));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Resend Failed: $e")));
    }
  }

  void _verifyAndLogin() async {
    // Combine all 6 digits
    String otp = _otpControllers.map((controller) => controller.text).join();

    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter complete 6-digit OTP',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Provider.of<AuthProvider>(context, listen: false).verifyOtp(
          phone: widget.phoneNumber,
          otp: otp,
          shopName: widget.shopName,
          ownerName: widget.ownerName,
          address: widget.address,
          shopCategory: widget.shopCategory);

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      
      // Parse error message
      String errorMessage = 'Verification failed';
      final errorStr = e.toString();
      
      if (errorStr.contains('Invalid OTP') || errorStr.contains('incorrect')) {
        errorMessage = 'Incorrect OTP. Please try again.';
      } else if (errorStr.contains('expired')) {
        errorMessage = 'OTP has expired. Please request a new one.';
      } else if (errorStr.contains('not found') || errorStr.contains('does not exist')) {
        errorMessage = 'Phone number not registered.';
      } else if (errorStr.contains('Connection') || errorStr.contains('network')) {
        errorMessage = 'Network error. Please check your connection.';
      } else if (errorStr.contains('Server') || errorStr.contains('500')) {
        errorMessage = 'Server error. Please try again later.';
      } else if (errorStr.contains('timeout')) {
        errorMessage = 'Request timeout. Please try again.';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: () {
                // Clear OTP fields
                for (var controller in _otpControllers) {
                  controller.clear();
                }
                _focusNodes[0].requestFocus();
              },
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  Widget _buildOtpBox(int index) {
    return Container(
      width: 50,
      height: 60,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focusNodes[index].hasFocus
              ? AppColors.primaryGreen
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: TextField(
        controller: _otpControllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        maxLength: 1,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
        decoration: const InputDecoration(
          counterText: "",
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onChanged: (value) {
          if (value.isNotEmpty && index < 5) {
            // Move to next field
            _focusNodes[index + 1].requestFocus();
          } else if (value.isEmpty && index > 0) {
            // Move to previous field on backspace
            _focusNodes[index - 1].requestFocus();
          }

          // Auto-submit when all 6 digits are entered
          if (index == 5 && value.isNotEmpty) {
            String fullOtp = _otpControllers.map((c) => c.text).join();
            if (fullOtp.length == 6) {
              _verifyAndLogin();
            }
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Top illustration image
            Image.asset(
              'assets/images/undraw_two-factor-authentication_ofho__1_.png',
              width: double.infinity,
              height: 220,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 40),
            Text(
              "OTP Sent to ${widget.phoneNumber}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.textBlack,
              ),
            ),
            const SizedBox(height: 30),
            // 6 separate OTP boxes
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(
                6,
                (index) => _buildOtpBox(index),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyAndLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        "Verify",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            if (_secondsRemaining > 0)
              Text(
                "Resend OTP in 00:${_secondsRemaining.toString().padLeft(2, '0')}",
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              )
            else
              TextButton(
                onPressed: _resendOtp,
                child: const Text(
                  "Resend OTP",
                  style: TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
