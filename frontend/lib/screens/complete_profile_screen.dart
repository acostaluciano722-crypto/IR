import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/app_auth.dart';
import '../ui/ir_auth_layout.dart';
import '../ui/ir_components.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen(
      {required this.api,
      required this.onSaved,
      this.needsLegacyLink = false,
      super.key});
  final ApiService api;
  final VoidCallback onSaved;
  final bool needsLegacyLink;

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _document = TextEditingController();
  final _vehicle = TextEditingController();
  final _plate = TextEditingController();
  final _legacyPassword = TextEditingController();
  bool _linkingLegacy = false;
  String _role = 'passenger';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _linkingLegacy = widget.needsLegacyLink;
    final metadata = AppAuth.client?.auth.currentUser?.userMetadata ?? {};
    final draft = metadata['ir_onboarding'];
    final values = draft is Map ? draft : <String, dynamic>{};
    // Metadata only prefills editable fields; the backend owns roles and balances.
    _name.text = (values['name'] ?? metadata['full_name'] ?? '').toString();
    _phone.text = (values['phone'] ?? '').toString();
    _document.text = (values['document_number'] ?? '').toString();
    _vehicle.text = (values['vehicle_type'] ?? '').toString();
    _plate.text = (values['vehicle_plate'] ?? '').toString();
    _role = values['role'] == 'driver' ? 'driver' : 'passenger';
  }

  @override
  void dispose() {
    for (final field in [
      _name,
      _phone,
      _document,
      _vehicle,
      _plate,
      _legacyPassword
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_linkingLegacy) {
        await widget.api.linkLegacyAccount(_legacyPassword.text);
      } else {
        await widget.api.completeProfile({
          'name': _name.text.trim(),
          'phone': _phone.text.trim(),
          'role': _role,
          'document_number': _document.text.trim(),
          'vehicle_type': _vehicle.text.trim(),
          'vehicle_plate': _plate.text.trim(),
        });
      }
      if (mounted) widget.onSaved();
    } on LegacyAccountLinkRequiredException {
      if (mounted) setState(() => _linkingLegacy = true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'No pudimos guardar tu perfil. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController controller, String label,
          {TextInputType? keyboard,
          int maxLength = 100,
          bool obscure = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: TextFormField(
          controller: controller,
          enabled: !_saving,
          obscureText: obscure,
          keyboardType: keyboard,
          maxLength: maxLength,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(labelText: label, counterText: ''),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Completa este campo.'
              : null,
        ),
      );

  @override
  Widget build(BuildContext context) => IrAuthLayout(
        title: _linkingLegacy ? 'Conserva tu cuenta IR' : 'Completa tu perfil',
        subtitle: _linkingLegacy
            ? 'Ya tienes una cuenta con este correo. Confirma tu contraseña anterior para conservar tus viajes, puntos y saldos.'
            : 'Tu correo está verificado. Solo faltan estos datos para empezar.',
        child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_linkingLegacy) ...[
                  _field(_legacyPassword, 'Contraseña anterior de IR',
                      obscure: true, maxLength: 1024),
                ] else ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'passenger', label: Text('Pasajero')),
                      ButtonSegment(value: 'driver', label: Text('Conductor')),
                    ],
                    selected: {_role},
                    onSelectionChanged: _saving
                        ? null
                        : (values) => setState(() => _role = values.single),
                  ),
                  const SizedBox(height: 24),
                  _field(_name, 'Nombre completo', maxLength: 150),
                  _field(_phone, 'Número de celular',
                      keyboard: TextInputType.phone, maxLength: 20),
                  if (_role == 'driver') ...[
                    _field(_document, 'Número de documento', maxLength: 20),
                    _field(_vehicle, 'Tipo de vehículo', maxLength: 30),
                    _field(_plate, 'Placa del vehículo', maxLength: 10),
                  ],
                ],
                if (_error != null) ...[
                  IrInlineMessage(message: _error!, error: true),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const IrButtonProgress()
                        : Text(_linkingLegacy
                            ? 'Vincular mi cuenta'
                            : 'Empezar a usar IR')),
                const SizedBox(height: 12),
                TextButton(
                    onPressed: _saving
                        ? null
                        : () async {
                            try {
                              await widget.api.signOut();
                            } catch (_) {
                              if (mounted) {
                                setState(() => _error =
                                    'No pudimos cerrar la sesión. Intenta de nuevo.');
                              }
                            }
                          },
                    child: const Text('Cerrar sesión')),
              ],
            )),
      );
}
