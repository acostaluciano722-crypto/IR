import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'register_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const ink = Color(0xFF171B1D);
  static const lemon = Color(0xFFE8F044);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ink,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 38, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(color: lemon, borderRadius: BorderRadius.circular(52)),
                alignment: Alignment.center,
                child: const Text('IR', style: TextStyle(color: ink, fontSize: 72, fontWeight: FontWeight.w900, letterSpacing: -7)),
              ),
              const SizedBox(height: 28),
              const Text('Muévete a tu manera.', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              const Text('Viajes simples, claros y pensados para tu ciudad.', style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
              const Spacer(),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())), style: ElevatedButton.styleFrom(backgroundColor: lemon, foregroundColor: ink), child: const Text('Crear cuenta'))),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: OutlinedButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginScreen())), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), child: const Text('Iniciar sesión'))),
            ],
          ),
        ),
      ),
    );
  }
}
