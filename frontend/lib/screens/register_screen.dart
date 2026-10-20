import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../ui/ir_auth_layout.dart';
import '../ui/ir_components.dart';
import '../ui/ir_motion.dart';
import '../ui/ir_theme.dart';
import 'driver_home_screen.dart';
import 'passenger_home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({this.api, super.key});
  final ApiService? api;
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late final _api = widget.api ?? ApiService();
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _identifier = TextEditingController();
  final _phone = TextEditingController();
  final _document = TextEditingController();
  final _vehicle = TextEditingController();
  final _plate = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String _role = 'passenger';
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  @override
  void dispose() {
    for (final controller in [
      _name,
      _identifier,
      _phone,
      _document,
      _vehicle,
      _plate,
      _password,
      _confirm
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _register() async {
    if (_loading || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await _api.register(
          name: _name.text.trim(),
          identifier: _identifier.text.trim(),
          phone: _phone.text.trim(),
          role: _role,
          password: _password.text,
          documentNumber: _document.text.trim(),
          vehicleType: _vehicle.text.trim(),
          vehiclePlate: _plate.text.trim());
      if (!mounted) return;
      TextInput.finishAutofillContext();
      final screen = user['role'] == 'driver'
          ? DriverHomeScreen(api: _api, user: user)
          : PassengerHomeScreen(api: _api, user: user);
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => screen), (_) => false);
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

  @override
  Widget build(BuildContext context) => IrAuthLayout(
      title: 'Únete a IR',
      subtitle: 'Crea tu cuenta como pasajero o conductor.',
      child: AutofillGroup(
          child: Form(
              key: _form,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Quiero registrarme como',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _RoleSelector(
                        value: _role,
                        enabled: !_loading,
                        onChanged: (value) => setState(() {
                              _role = value;
                              _error = null;
                            })),
                    const SizedBox(height: 24),
                    _field(_name, 'Nombre completo', Icons.person_outline,
                        autofill: AutofillHints.name, maxLength: 150),
                    const SizedBox(height: 16),
                    _field(
                        _identifier, 'Correo o usuario', Icons.alternate_email,
                        keyboard: TextInputType.emailAddress,
                        autofill: AutofillHints.username,
                        maxLength: 255),
                    const SizedBox(height: 16),
                    _field(_phone, 'Número de celular', Icons.phone_outlined,
                        keyboard: TextInputType.phone,
                        autofill: AutofillHints.telephoneNumber,
                        maxLength: 20),
                    AnimatedSize(
                        duration:
                            IrMotion.duration(context, IrMotion.transition),
                        curve: Curves.easeOutCubic,
                        child: _role == 'driver'
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                    const SizedBox(height: 24),
                                    const Text(
                                        'Datos del conductor y del vehículo',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 16),
                                    _field(_document, 'Número de documento',
                                        Icons.badge_outlined,
                                        maxLength: 20),
                                    const SizedBox(height: 16),
                                    _field(_vehicle, 'Tipo de vehículo',
                                        Icons.directions_car_outlined,
                                        maxLength: 30),
                                    const SizedBox(height: 16),
                                    _field(_plate, 'Placa del vehículo',
                                        Icons.confirmation_number_outlined,
                                        maxLength: 10,
                                        capitalization:
                                            TextCapitalization.characters),
                                  ])
                            : const SizedBox.shrink()),
                    const SizedBox(height: 24),
                    _field(_password, 'Contraseña', Icons.lock_outline,
                        obscure: _obscure,
                        autofill: AutofillHints.newPassword,
                        validator: (value) => (value?.length ?? 0) < 8
                            ? 'Usa al menos 8 caracteres.'
                            : null,
                        helper: 'Mínimo 8 caracteres',
                        suffix: IconButton(
                            tooltip: _obscure
                                ? 'Mostrar contraseña'
                                : 'Ocultar contraseña',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined))),
                    const SizedBox(height: 16),
                    _field(_confirm, 'Confirmar contraseña',
                        Icons.lock_reset_outlined,
                        obscure: _obscure,
                        validator: (value) => value == null || value.isEmpty
                            ? 'Confirma tu contraseña.'
                            : value != _password.text
                                ? 'Las contraseñas no coinciden.'
                                : null,
                        done: true),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      IrInlineMessage(message: _error!, error: true)
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                        onPressed: _loading ? null : _register,
                        child: _loading
                            ? const IrButtonProgress()
                            : const Text('Crear cuenta')),
                  ]))));
  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
    String? autofill,
    String? helper,
    int? maxLength,
    String? Function(String?)? validator,
    bool done = false,
    TextCapitalization capitalization = TextCapitalization.none,
  }) =>
      TextFormField(
          controller: controller,
          enabled: !_loading,
          keyboardType: keyboard,
          obscureText: obscure,
          textCapitalization: capitalization,
          textInputAction: done ? TextInputAction.done : TextInputAction.next,
          onFieldSubmitted: done ? (_) => _register() : null,
          autofillHints: autofill == null ? null : [autofill],
          autocorrect: false,
          enableSuggestions: controller != _password && controller != _confirm,
          maxLength: maxLength,
          validator: validator ??
              (value) => value == null || value.trim().isEmpty
                  ? 'Completa este campo.'
                  : null,
          decoration: InputDecoration(
              labelText: label,
              helperText: helper,
              counterText: '',
              prefixIcon: Icon(icon),
              suffixIcon: suffix));
}

class _RoleSelector extends StatelessWidget {
  const _RoleSelector(
      {required this.value, required this.enabled, required this.onChanged});

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => Row(children: [
          _option(context, 'passenger', 'Pasajero', Icons.person_outline,
              constraints.maxWidth),
          const SizedBox(width: 8),
          _option(context, 'driver', 'Conductor', Icons.local_taxi_outlined,
              constraints.maxWidth),
        ]),
      );

  Widget _option(BuildContext context, String key, String label, IconData icon,
      double totalWidth) {
    final selected = value == key;
    final available = totalWidth - 8;
    final width = available * (selected ? .58 : .42);
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        width: width,
        height: 72,
        duration: IrMotion.duration(context, IrMotion.transition),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? IrPalette.accent : context.irColors.input,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? IrPalette.accent : context.irColors.border),
        ),
        child: InkWell(
          onTap: enabled ? () => onChanged(key) : null,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(children: [
              Icon(icon,
                  size: 22,
                  color: selected ? IrPalette.ink : context.irColors.muted),
              const SizedBox(width: 7),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: selected ? IrPalette.ink : context.irColors.text,
                        fontWeight: FontWeight.w800)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
