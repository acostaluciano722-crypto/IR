import 'package:flutter/material.dart';

import '../ui/ir_brand.dart';
import '../ui/ir_theme.dart';
import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Theme(
        data: irDarkTheme(),
        child: Scaffold(
          backgroundColor: IrPalette.surface,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  const Center(child: IrLogoMark(size: 188)),
                  const SizedBox(height: 30),
                  const Center(
                      child: Text('Viaja para ganar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: IrPalette.text,
                              fontSize: 31,
                              height: 1.05,
                              fontWeight: FontWeight.w800))),
                  const SizedBox(height: 12),
                  const Center(
                      child: Text(
                          'Viajes simples, claros y pensados para tu ciudad.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: IrPalette.muted,
                              fontSize: 16,
                              height: 1.45))),
                  const Spacer(),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const RegisterScreen())),
                          style: FilledButton.styleFrom(
                              backgroundColor: IrPalette.accent,
                              foregroundColor: IrPalette.ink,
                              minimumSize: const Size.fromHeight(58),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          child: const Text('Crear cuenta',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)))),
                  const SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const LoginScreen())),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: IrPalette.text,
                              minimumSize: const Size.fromHeight(58),
                              side: const BorderSide(color: Color(0xFF55585A)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          child: const Text('Iniciar sesión',
                              style: TextStyle(fontWeight: FontWeight.w700)))),
                ],
              ),
            ),
          ),
        ),
      );
}
