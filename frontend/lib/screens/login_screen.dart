import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../ui/ir_brand.dart';
import '../ui/ir_theme.dart';
import 'driver_home_screen.dart';
import 'passenger_home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _api = ApiService();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await _api.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      if (user['role'] == 'driver') {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => DriverHomeScreen(api: _api, user: user)));
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
            builder: (_) => PassengerHomeScreen(api: _api, user: user)));
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'No hay conexión con IR. Revisa el servidor.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: irDarkTheme(),
        child: Scaffold(
          backgroundColor: IrPalette.surface,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                      tooltip: 'Volver',
                      onPressed: () => Navigator.of(context).maybePop(),
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      icon: const Icon(Icons.arrow_back,
                          color: IrPalette.text, size: 28)),
                  const SizedBox(height: 28),
                  const IrLogoMark(size: 64, showWordmark: true),
                  const SizedBox(height: 54),
                  const Text('Tu viaje empieza aquí.',
                      style: TextStyle(
                          color: IrPalette.text,
                          fontSize: 31,
                          height: 1.05,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  const Text('Entra a IR y mueve tu ciudad a tu manera.',
                      style: TextStyle(
                          color: IrPalette.muted, fontSize: 16, height: 1.4)),
                  const SizedBox(height: 34),
                  _field(
                      controller: _usernameController,
                      label: 'Correo o usuario',
                      icon: Icons.person_outline,
                      keyboard: TextInputType.emailAddress),
                  const SizedBox(height: 14),
                  _field(
                      controller: _passwordController,
                      label: 'Contraseña',
                      icon: Icons.lock_outline,
                      obscure: _obscurePassword,
                      suffix: IconButton(
                          tooltip: _obscurePassword
                              ? 'Mostrar contraseña'
                              : 'Ocultar contraseña',
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                          icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: IrPalette.muted)),
                      onSubmitted: (_) => _login()),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFF351D20),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF7D3F45))),
                        child: Text(_error!,
                            style: const TextStyle(color: Color(0xFFFFB4AB)))),
                  ],
                  const SizedBox(height: 28),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: _loading ? null : _login,
                          style: FilledButton.styleFrom(
                              backgroundColor: IrPalette.accent,
                              foregroundColor: IrPalette.ink,
                              minimumSize: const Size.fromHeight(58),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16))),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: IrPalette.ink))
                              : const Text('Entrar',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800)))),
                  const SizedBox(height: 18),
                  Center(
                      child: TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const RegisterScreen())),
                          child: const Text('¿Aún no tienes cuenta? Crear cuenta',
                              style: TextStyle(color: IrPalette.accent)))),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
    ValueChanged<String>? onSubmitted,
  }) => TextField(
        controller: controller,
        keyboardType: keyboard,
        obscureText: obscure,
        onSubmitted: onSubmitted,
        style: const TextStyle(color: IrPalette.text, fontSize: 16),
        decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: IrPalette.muted),
            prefixIcon: Icon(icon, color: IrPalette.muted),
            suffixIcon: suffix,
            filled: true,
            fillColor: IrPalette.raised,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: IrPalette.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              borderSide:
                const BorderSide(color: IrPalette.accent, width: 1.5))),
          );
}
