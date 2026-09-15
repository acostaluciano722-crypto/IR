import 'package:flutter/material.dart';

import '../services/api_service.dart';
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
    for (final controller in [_name, _identifier, _phone, _document, _vehicle, _plate, _password, _confirm]) { controller.dispose(); }
    super.dispose();
  }

  Future<void> _register() async {
    FocusScope.of(context).unfocus();
    if (_password.text != _confirm.text) { setState(() => _error = 'Las contraseñas no coinciden.'); return; }
    if (_role == 'driver' && (_document.text.trim().isEmpty || _vehicle.text.trim().isEmpty || _plate.text.trim().isEmpty)) { setState(() => _error = 'Completa los datos del conductor y del vehículo.'); return; }
    setState(() { _loading = true; _error = null; });
    try {
      final user = await _api.register(name: _name.text.trim(), identifier: _identifier.text.trim(), phone: _phone.text.trim(), role: _role, password: _password.text, documentNumber: _document.text.trim(), vehicleType: _vehicle.text.trim(), vehiclePlate: _plate.text.trim());
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => PassengerHomeScreen(api: _api, user: user)), (route) => false);
    } on ApiException catch (error) { setState(() => _error = error.message); }
    catch (_) { setState(() => _error = 'No hay conexión con IR. Revisa el servidor.'); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    final driver = _role == 'driver';
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta'), backgroundColor: Colors.transparent),
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 32), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Únete a IR', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Crea tu cuenta como pasajero o conductor.', style: TextStyle(color: Colors.black54, fontSize: 16)),
        const SizedBox(height: 24),
        const Text('Quiero registrarme como', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'passenger', label: Text('Pasajero'), icon: Icon(Icons.person_outline)), ButtonSegment(value: 'driver', label: Text('Conductor'), icon: Icon(Icons.drive_eta_outlined))], selected: {_role}, onSelectionChanged: (value) => setState(() { _role = value.first; _error = null; })),
        const SizedBox(height: 20),
        _field(_name, 'Nombre completo', Icons.person_outline),
        const SizedBox(height: 12),
        _field(_identifier, 'Correo electrónico o usuario', Icons.alternate_email, keyboard: TextInputType.emailAddress),
        const SizedBox(height: 12),
        _field(_phone, 'Número de celular', Icons.phone_outlined, keyboard: TextInputType.phone),
        if (driver) ...[
          const SizedBox(height: 20),
          const Text('Datos para validar tu registro de conductor', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _field(_document, 'Número de documento', Icons.badge_outlined),
          const SizedBox(height: 12),
          _field(_vehicle, 'Tipo de vehículo', Icons.directions_car_outlined),
          const SizedBox(height: 12),
          _field(_plate, 'Placa del vehículo', Icons.confirmation_number_outlined),
        ],
        const SizedBox(height: 20),
        _field(_password, 'Contraseña (mínimo 8 caracteres)', Icons.lock_outline, obscure: _obscure),
        const SizedBox(height: 12),
        TextField(controller: _confirm, obscureText: _obscure, decoration: InputDecoration(labelText: 'Confirmar contraseña', prefixIcon: const Icon(Icons.lock_reset_outlined), suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined)))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: const TextStyle(color: Color(0xFFB3261E)))),
        const SizedBox(height: 22),
        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _loading ? null : _register, child: _loading ? const CircularProgressIndicator(color: Colors.white) : const Text('Crear cuenta'))),
      ]))),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon, {TextInputType? keyboard, bool obscure = false}) => TextField(controller: controller, keyboardType: keyboard, obscureText: obscure, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)));
}
