import 'package:flutter/material.dart';

import '../services/api_service.dart';
import 'passenger_home_screen.dart';
import 'driver_home_screen.dart';
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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DriverHomeScreen(api: _api, user: user),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => PassengerHomeScreen(api: _api, user: user),
          ),
        );
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'No hay conexion con IR. Revisa el servidor.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 44, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _LogoMark(),
              const SizedBox(height: 64),
              Text('Tu viaje empieza aqui.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF171B1D))),
              const SizedBox(height: 10),
              Text('Entra a IR y mueve tu ciudad a tu manera.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54)),
              const SizedBox(height: 36),
              TextField(controller: _usernameController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo o usuario', prefixIcon: Icon(Icons.person_outline))),
              const SizedBox(height: 14),
              TextField(controller: _passwordController, obscureText: _obscurePassword, onSubmitted: (_) => _login(), decoration: InputDecoration(labelText: 'Contraseña', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => _obscurePassword = !_obscurePassword), icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
              ],
              const SizedBox(height: 26),
              ElevatedButton(onPressed: _loading ? null : _login, child: _loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Entrar')),
              const SizedBox(height: 18),
              Center(child: TextButton(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())), child: const Text('¿Aún no tienes cuenta? Crear cuenta'))),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFE8F044), borderRadius: BorderRadius.circular(14)), alignment: Alignment.center, child: const Text('IR', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, letterSpacing: -2))),
      const SizedBox(width: 12),
      const Text('IR', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -1)),
    ]);
  }
}
