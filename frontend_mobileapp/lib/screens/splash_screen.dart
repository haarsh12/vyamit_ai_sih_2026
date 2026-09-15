import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/bill_provider.dart';
import 'home_screen.dart';
import 'auth_selection_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0, end: -20).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _checkLogin();
  }

  Future<void> _checkLogin() async {
    // 1. Wait for animation
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      // 2. Check Auto Login
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final billProvider = Provider.of<BillProvider>(context, listen: false);

      // Initialize BillProvider (load persisted data)
      await billProvider.initialize();

      // We check storage (await is okay here because tryAutoLogin returns a Future)
      bool isLoggedIn = await auth.tryAutoLogin();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => isLoggedIn
                ? const HomeScreen() // REMOVE 'const' if this still errors
                : const AuthSelectionScreen(),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.lightGreenBg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(0, _animation.value),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 20,
                            spreadRadius: 5)
                      ],
                    ),
                    // Use new Vyamit AI logo
                    child: Image.asset(
                      'assets/vyamitlogo.png',
                      width: 100,
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            const Text(
              "Vyamit AI",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryGreen,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "AI Powered Billing Assistant",
              style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 30),
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                  color: AppColors.primaryGreen, strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}
