import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/api_service.dart';
import '../services/app_auth.dart';
import '../ui/ir_auth_layout.dart';
import '../ui/ir_components.dart';

class PasswordHelpScreen extends StatefulWidget {
  const PasswordHelpScreen({required this.api, this.email = '', super.key});
  final ApiService api;
  final String email;

  @override
  State<PasswordHelpScreen> createState() => _PasswordHelpScreenState();
}

class _PasswordHelpScreenState extends State<PasswordHelpScreen> {
  final _form = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.email);
  bool _busy = false;
  String? _message;
  bool _failed = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.api.resetPassword(_email.text);
      if (mounted) {
        setState(() {
          _failed = false;
          _message =
              'Si hay una cuenta con ese correo, recibirás un enlace para cambiar tu contraseña.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _message = error is ApiException
              ? error.message
              : 'No pudimos enviar el enlace. Intenta de nuevo.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IrAuthLayout(
        title: 'Recupera tu acceso',
        subtitle:
            'Te enviaremos un enlace a tu correo para crear una nueva contraseña.',
        child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration:
                        const InputDecoration(labelText: 'Correo electrónico'),
                    validator: (value) => value != null && value.contains('@')
                        ? null
                        : 'Escribe un correo válido.'),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: _busy ? null : _send,
                    child: _busy
                        ? const IrButtonProgress()
                        : const Text('Enviar enlace')),
                if (_message != null) ...[
                  const SizedBox(height: 20),
                  IrInlineMessage(message: _message!, error: _failed),
                ],
              ],
            )),
      );
}

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({required this.onSaved, super.key});
  final VoidCallback onSaved;
  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppAuth.client!.auth
          .updateUser(UserAttributes(password: _password.text));
      if (mounted) widget.onSaved();
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = AppAuth.errorMessage(error));
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No pudimos cambiar la contraseña. Solicita un nuevo enlace.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IrAuthLayout(
        title: 'Nueva contraseña',
        subtitle: 'Elige una contraseña que solo uses para IR.',
        child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: true,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration:
                        const InputDecoration(labelText: 'Nueva contraseña'),
                    validator: (value) => (value?.length ?? 0) >= 8
                        ? null
                        : 'Usa al menos 8 caracteres.'),
                const SizedBox(height: 16),
                TextFormField(
                    controller: _confirm,
                    enabled: !_busy,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Confirma tu contraseña'),
                    validator: (value) => value == _password.text
                        ? null
                        : 'Las contraseñas no coinciden.'),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  IrInlineMessage(message: _error!, error: true),
                ],
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const IrButtonProgress()
                        : const Text('Guardar contraseña')),
              ],
            )),
      );
}
