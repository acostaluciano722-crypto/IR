import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../ui/ir_brand.dart';
import '../ui/ir_theme.dart';
import 'driver_home_screen.dart';
import 'passenger_home_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _api = ApiService();
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
    FocusScope.of(context).unfocus();
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    if (_role == 'driver' &&
        (_document.text.trim().isEmpty ||
            _vehicle.text.trim().isEmpty ||
            _plate.text.trim().isEmpty)) {
      setState(() => _error =
          'Completa los datos del conductor y del vehículo.');
      return;
    }
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
      final screen = user['role'] == 'driver'
          ? DriverHomeScreen(api: _api, user: user)
          : PassengerHomeScreen(api: _api, user: user);
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => screen), (route) => false);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'No hay conexión con IR. Revisa el servidor.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = _role == 'driver';
    return Theme(
      data: irDarkTheme(),
      child: Scaffold(
        backgroundColor: IrPalette.surface,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconButton(
                    tooltip: 'Volver',
                    onPressed: () => Navigator.of(context).maybePop(),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.arrow_back,
                        color: IrPalette.text, size: 28)),
                const SizedBox(width: 10),
                const IrLogoMark(size: 46, showWordmark: true),
              ]),
              const SizedBox(height: 34),
              const Text('Únete a IR',
                  style: TextStyle(
                      color: IrPalette.text,
                      fontSize: 31,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text('Crea tu cuenta como pasajero o conductor.',
                  style: TextStyle(color: IrPalette.muted, fontSize: 16)),
              const SizedBox(height: 28),
              const Text('Quiero registrarme como',
                  style: TextStyle(
                      color: IrPalette.text, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'passenger',
                        label: Text('Pasajero'),
                        icon: Icon(Icons.person_outline)),
                    ButtonSegment(
                        value: 'driver',
                        label: Text('Conductor'),
                        icon: Icon(Icons.drive_eta_outlined)),
                  ],
                  selected: {_role},
                  onSelectionChanged: (value) => setState(() {
                        _role = value.first;
                        _error = null;
                      })),
              const SizedBox(height: 20),
              _field(_name, 'Nombre completo', Icons.person_outline),
              const SizedBox(height: 12),
              _field(_identifier, 'Correo electrónico o usuario',
                  Icons.alternate_email,
                  keyboard: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _field(_phone, 'Número de celular', Icons.phone_outlined,
                  keyboard: TextInputType.phone),
              if (driver) ...[
                const SizedBox(height: 22),
                const Text('Datos para validar tu registro de conductor',
                    style: TextStyle(
                        color: IrPalette.text, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                _field(_document, 'Número de documento', Icons.badge_outlined),
                const SizedBox(height: 12),
                _field(_vehicle, 'Tipo de vehículo',
                    Icons.directions_car_outlined),
                const SizedBox(height: 12),
                _field(_plate, 'Placa del vehículo',
                    Icons.confirmation_number_outlined),
              ],
              const SizedBox(height: 18),
              _field(_password, 'Contraseña (mínimo 8 caracteres)',
                  Icons.lock_outline,
                  obscure: _obscure),
              const SizedBox(height: 12),
              _field(_confirm, 'Confirmar contraseña', Icons.lock_reset_outlined,
                  obscure: _obscure,
                  suffix: IconButton(
                      tooltip: _obscure ? 'Mostrar contraseña' : 'Ocultar contraseña',
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                      icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: IrPalette.muted))),
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
              const SizedBox(height: 22),
              SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: _loading ? null : _register,
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
                                  strokeWidth: 2, color: IrPalette.ink))
                          : const Text('Crear cuenta',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800)))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon,
          {TextInputType? keyboard, bool obscure = false, Widget? suffix}) =>
      TextField(
          controller: controller,
          keyboardType: keyboard,
          obscureText: obscure,
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
                      const BorderSide(color: IrPalette.accent, width: 1.5))));
}
