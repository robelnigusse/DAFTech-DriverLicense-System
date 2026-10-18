import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final loggedIn = await AuthService.isLoggedIn();
  runApp(LicenseScannerApp(initialLoggedIn: loggedIn));
}

class LicenseScannerApp extends StatelessWidget {
  final bool initialLoggedIn;

  const LicenseScannerApp({
    super.key,
    required this.initialLoggedIn,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DAFTech Driver Licence',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF176B57),
        ),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: initialLoggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}
