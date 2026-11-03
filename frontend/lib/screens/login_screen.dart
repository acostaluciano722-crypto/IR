import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../ui/ir_auth_layout.dart';
import '../ui/ir_components.dart';
import 'driver_home_screen.dart';
import 'passenger_home_screen.dart';
import 'register_screen.dart';
import 'password_help_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({this.api, super.key});
  final ApiService? api;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final _api = widget.api ?? ApiService();
  final _form = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  String? _error;
  String? _notice;
  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final user = await _api.login(
          _usernameController.text.trim(), _passwordController.text);
      if (!mounted) return;
      TextInput.finishAutofillContext();
      if (_api.usesSupabase) {
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => user['role'] == 'driver'
              ? DriverHomeScreen(api: _api, user: user)
              : PassengerHomeScreen(api: _api, user: user)));
    } on ProfileRequiredException {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on EmailConfirmationRequired catch (error) {
      if (mounted) setState(() => _notice = error.message);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No hay conexión con IR. Revisa tu conexión e inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    if (_loading) return;
    setState(() { _loading = true; _error = null; _notice = null; });
    try {
      await _api.signInWithGoogle();
      if (mounted) setState(() => _notice = 'Completa el acceso en la ventana de Google.');
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ApiException
          ? error.message : 'No pudimos abrir Google. Inténtalo de nuevo.');
      }
    } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _resend() async {
    if (_loading || !_usernameController.text.contains('@')) return;
    setState(() { _loading = true; _error = null; });
    try {
      await _api.resendConfirmation(_usernameController.text);
      if (mounted) setState(() => _notice = 'Revisa tu correo para confirmar tu cuenta.');
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ApiException
          ? error.message : 'No pudimos enviar el correo. Intenta de nuevo.');
      }
    } finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) => IrAuthLayout(
      title: 'Tu viaje empieza aquí.',
      subtitle: 'Entra a IR y mueve tu ciudad a tu manera.',
      child: AutofillGroup(
          child: Form(
              key: _form,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                        controller: _usernameController,
                        enabled: !_loading,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        autocorrect: false,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Escribe tu correo o celular.'
                                : null,
                        decoration: InputDecoration(
                            labelText: _api.usesSupabase ? 'Correo electrónico' : 'Correo o celular',
                            prefixIcon: const Icon(Icons.person_outline))),
                    const SizedBox(height: 16),
                    TextFormField(
                        controller: _passwordController,
                        enabled: !_loading,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        autocorrect: false,
                        enableSuggestions: false,
                        validator: (value) => value == null || value.isEmpty
                            ? 'Escribe tu contraseña.'
                            : null,
                        onFieldSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                            labelText: 'Contraseña',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Mostrar contraseña'
                                    : 'Ocultar contraseña',
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined)))),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      IrInlineMessage(message: _error!, error: true)
                    ],
                    if (_notice != null) ...[
                      const SizedBox(height: 16),
                      IrInlineMessage(message: _notice!),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                        onPressed: _loading ? null : _login,
                        child: _loading
                            ? const IrButtonProgress()
                            : const Text('Iniciar sesión')),
                    if (_api.usesSupabase) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          onPressed: _loading ? null : _google,
                          icon: Image.asset('assets/icons/google_g.png', width: 20, height: 20),
                          label: const Text('Continuar con Google')),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _loading ? null : () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => PasswordHelpScreen(
                          api: _api, email: _usernameController.text.trim()))),
                        child: const Text('Olvidé mi contraseña')),
                      TextButton(onPressed: _loading ? null : _resend,
                        child: const Text('Reenviar confirmación de correo')),
                    ],
                    const SizedBox(height: 12),
                    TextButton(
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => const RegisterScreen())),
                        child: const Text('Crear una cuenta')),
                  ]))));
}
