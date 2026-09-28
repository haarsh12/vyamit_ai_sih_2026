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

class _OtpScreenState extends State<OtpScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  Timer? _timer;
  int _secondsRemaining = 45;
  bool _isLoading = false;

  late AnimationController _cursorAnimationController;

  @override
  void initState() {
    super.initState();
    _startTimer();

    // Blinking cursor animation for active box
    _cursorAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _cursorAnimationController.reverse();
        } else if (status == AnimationStatus.dismissed) {
          _cursorAnimationController.forward();
        }
      });
    _cursorAnimationController.forward();

    _focusNode.addListener(() {
      if (mounted) setState(() {});
    });

    // Auto-focus input box when screen builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsRemaining = 45);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        if (mounted) setState(() => _secondsRemaining--);
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
      _otpController.clear();
      _focusNode.requestFocus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("OTP Resent successfully!"),
            backgroundColor: AppColors.primaryGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Resend Failed: $e"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _verifyAndLogin() async {
    String otp = _otpController.text.trim();

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
        shopCategory: widget.shopCategory,
      );

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);

        // Parse error message for user friendly feedback
        String errorMessage = 'Verification failed';
        final errorStr = e.toString();

        if (errorStr.contains('Invalid OTP') ||
            errorStr.contains('incorrect')) {
          errorMessage = 'Incorrect OTP. Please try again.';
        } else if (errorStr.contains('expired')) {
          errorMessage = 'OTP has expired. Please request a new one.';
        } else if (errorStr.contains('not found') ||
            errorStr.contains('does not exist')) {
          errorMessage = 'Phone number not registered.';
        } else if (errorStr.contains('Connection') ||
            errorStr.contains('network')) {
          errorMessage = 'Network error. Please check your connection.';
        } else if (errorStr.contains('Server') || errorStr.contains('500')) {
          errorMessage = 'Server error. Please try again later.';
        } else if (errorStr.contains('timeout')) {
          errorMessage = 'Request timeout. Please try again.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              errorMessage,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'RETRY',
              textColor: Colors.white,
              onPressed: () {
                _otpController.clear();
                _focusNode.requestFocus();
              },
            ),
          ),
        );
      }
    }
  }

  void _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData != null && clipboardData.text != null) {
      final text = clipboardData.text!.replaceAll(RegExp(r'\D'), '');
      if (text.length >= 6) {
        _otpController.text = text.substring(0, 6);
        _otpController.selection = TextSelection.fromPosition(
          TextPosition(offset: _otpController.text.length),
        );
        setState(() {});
        if (_otpController.text.length == 6) {
          _verifyAndLogin();
        }
      } else if (text.isNotEmpty) {
        _otpController.text = text;
        _otpController.selection = TextSelection.fromPosition(
          TextPosition(offset: _otpController.text.length),
        );
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cursorAnimationController.dispose();
    _otpController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Widget _buildDigitBox(int index, String currentText) {
    bool isFocused = _focusNode.hasFocus &&
        (index == currentText.length ||
            (index == 5 && currentText.length == 6));
    bool isFilled = index < currentText.length;
    String digit = isFilled ? currentText[index] : '';

    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 56,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isFilled
              ? AppColors.lightGreenBg
              : (isFocused ? Colors.white : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFocused
                ? AppColors.primaryGreen
                : (isFilled ? AppColors.primaryGreen : const Color(0xFFE2E8F0)),
            width: isFocused ? 2.0 : 1.5,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: AppColors.primaryGreen.withAlpha(38),
                    blurRadius: 8,
                    spreadRadius: 1,
                    offset: const Offset(0, 2),
                  )
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withAlpha(5),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Center(
          child: isFilled
              ? Text(
                  digit,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textBlack,
                  ),
                )
              : (isFocused && currentText.length == index
                  ? AnimatedBuilder(
                      animation: _cursorAnimationController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: _cursorAnimationController.value,
                          child: Container(
                            width: 2.5,
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.primaryGreen,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      },
                    )
                  : const SizedBox.shrink()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String currentText = _otpController.text;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: AppColors.textBlack, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.content_paste_rounded,
                color: AppColors.primaryGreen, size: 22),
            tooltip: "Paste OTP",
            onPressed: _pasteFromClipboard,
          )
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              // Top illustration image
              Image.asset(
                'assets/images/undraw_two-factor-authentication_ofho__1_.png',
                width: double.infinity,
                height: 200,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 32),

              // Heading
              const Text(
                "Verification Code",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: AppColors.textBlack,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),

              // Phone subtitle with Edit Option (FittedBox to prevent overflow)
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "We sent a 6-digit code to ",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      widget.phoneNumber,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textBlack,
                      ),
                    ),
                    const SizedBox(width: 4),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(
                        Icons.edit_rounded,
                        size: 16,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),

              // OTP Digits Field Container
              GestureDetector(
                onTap: () {
                  _focusNode.requestFocus();
                },
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  children: [
                    // Invisible real textfield handling keyboard input, copy/paste, SMS autofill
                    Opacity(
                      opacity: 0.0,
                      child: SizedBox(
                        height: 56,
                        child: TextField(
                          controller: _otpController,
                          focusNode: _focusNode,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          autofillHints: const [AutofillHints.oneTimeCode],
                          onChanged: (val) {
                            setState(() {});
                            if (val.length == 6) {
                              _verifyAndLogin();
                            }
                          },
                        ),
                      ),
                    ),
                    // Visual Digit Boxes Row (Fully responsive, no overflow)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        6,
                        (index) => _buildDigitBox(index, currentText),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // Verify Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: (_isLoading || currentText.length < 6)
                      ? null
                      : _verifyAndLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryGreen,
                    disabledBackgroundColor:
                        AppColors.primaryGreen.withAlpha(102),
                    elevation: currentText.length == 6 ? 4 : 0,
                    shadowColor: AppColors.primaryGreen.withAlpha(102),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
                          "Verify & Proceed",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 24),

              // Resend Timer / Action
              if (_secondsRemaining > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer_outlined,
                        size: 16, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(
                      "Resend code in ",
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    ),
                    Text(
                      "00:${_secondsRemaining.toString().padLeft(2, '0')}",
                      style: const TextStyle(
                        color: AppColors.primaryGreen,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Didn't receive code? ",
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    ),
                    TextButton(
                      onPressed: _resendOtp,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 0),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        "Resend OTP",
                        style: TextStyle(
                          color: AppColors.primaryGreen,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
