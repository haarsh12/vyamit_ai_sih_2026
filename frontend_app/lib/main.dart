import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Import Providers
import 'providers/auth_provider.dart';
import 'providers/inventory_provider.dart';
import 'providers/bill_provider.dart';
import 'features/gst/providers/gst_provider.dart';

// Import Screens
import 'screens/splash_screen.dart';

// Import Theme
import 'core/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. LOCK ORIENTATION (Fixes layout bugs)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]).then((_) {
    runApp(const MyKiranaApp());
  });
}

class MyKiranaApp extends StatelessWidget {
  const MyKiranaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 2. INITIALIZE PROVIDERS (The Brains)
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => BillProvider()),
        ChangeNotifierProvider(create: (_) => GstProvider()),
      ],
      child: MaterialApp(
        title: 'Vyamit AI',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primaryGreen,
            primary: AppColors.primaryGreen,
            surface: AppColors.background,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: AppColors.textBlack),
            titleTextStyle: TextStyle(
              color: AppColors.textBlack,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          // Ensure Cards look like the old app
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.05),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        // 3. START APP
        home: const SplashScreen(),
      ),
    );
  }
}
