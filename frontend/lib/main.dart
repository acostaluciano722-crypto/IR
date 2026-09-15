import 'package:flutter/material.dart';

import 'screens/welcome_screen.dart';

void main() {
  runApp(const IrApp());
}

class IrApp extends StatelessWidget {
  const IrApp({super.key});

  static const lemonTonic = Color(0xFFE8F044);
  static const ink = Color(0xFF171B1D);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IR',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7F2),
        colorScheme: ColorScheme.fromSeed(
          seedColor: lemonTonic,
          brightness: Brightness.light,
          surface: const Color(0xFFF7F7F2),
        ),
        fontFamily: 'Arial',
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: ink, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: ink,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      home: const WelcomeScreen(),
    );
  }
}
