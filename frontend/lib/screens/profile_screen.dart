import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/face_verification.dart';
import '../ui/ir_auth_layout.dart';
import '../ui/ir_components.dart';
import '../ui/ir_theme.dart';
import 'face_verification_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.api,
    required this.name,
    required this.role,
    this.photoUrl,
    this.onPhotoChanged,
    super.key,
  });

  final ApiService api;
  final String name;
  final String role;
  final String? photoUrl;
  final ValueChanged<String?>? onPhotoChanged;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  FaceVerificationStatus? _status;
  String? _photoUrl;
  String? _error;
  bool _loading = true;
  bool _removing = false;

  @override
  void initState() {
    super.initState();
    _photoUrl = widget.photoUrl;
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final status = await widget.api.getFaceVerificationStatus();
      if (!mounted) return;
      final changed = _photoUrl != status.photoUrl;
      setState(() {
        _status = status;
        _photoUrl = status.photoUrl;
        _loading = false;
        _error = null;
      });
      if (changed) widget.onPhotoChanged?.call(status.photoUrl);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is ApiException
            ? error.message
            : 'No pudimos consultar la comprobación de tu perfil.';
      });
    }
  }

  Future<void> _openFacialCheck() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          FaceVerificationScreen(api: widget.api, initialStatus: _status),
    ));
    if (mounted) await _reload();
  }

  Future<void> _removePhoto() async {
    if (_removing) return;
    setState(() => _removing = true);
    try {
      await widget.api.deleteProfilePhoto();
      if (!mounted) return;
      setState(() => _photoUrl = null);
      widget.onPhotoChanged?.call(null);
      await _reload();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is ApiException
            ? error.message
            : 'No pudimos quitar la foto. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.irColors;
    final status = _status;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
              children: [
                Center(
                    child: ClipOval(
                        child: ColoredBox(
                  color: colors.input,
                  child: SizedBox.square(
                    dimension: 112,
                    child: _photoUrl == null
                        ? Icon(Icons.person_outline_rounded,
                            size: 56, color: colors.muted)
                        : Image.network(_photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.person_outline_rounded,
                                size: 56,
                                color: colors.muted)),
                  ),
                ))),
                const SizedBox(height: 20),
                Text(widget.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: colors.text,
                        fontSize: 26,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(widget.role == 'driver' ? 'Conductor IR' : 'Pasajero IR',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.muted)),
                const SizedBox(height: 32),
                if (_loading)
                  const IrLoadingState(label: 'Consultando tu comprobación')
                else if (_error != null)
                  IrInlineMessage(
                      message: _error!, error: true, onRetry: _reload),
                if (status != null) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(
                        status.hasCurrentVerification
                            ? Icons.verified_user_outlined
                            : Icons.schedule_outlined,
                        color: status.hasCurrentVerification
                            ? colors.accent
                            : colors.muted),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              status.hasCurrentVerification
                                  ? 'Comprobación facial vigente'
                                  : 'Comprobación facial pendiente',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text(
                              status.verificationDueAt == null
                                  ? 'Compara tu documento con una selfie para crear tu foto.'
                                  : 'Renovación: ${MaterialLocalizations.of(context).formatMediumDate(status.verificationDueAt!.toLocal())}',
                              style:
                                  TextStyle(color: colors.muted, height: 1.5)),
                        ])),
                  ]),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _removing ? null : _openFacialCheck,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(status.enrolled
                        ? 'Actualizar foto con una selfie'
                        : 'Comprobar mi rostro'),
                  ),
                  if (_photoUrl != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                        onPressed: _removing ? null : _removePhoto,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(_removing
                            ? 'Quitando foto…'
                            : 'Quitar foto de perfil')),
                  ],
                  const SizedBox(height: 24),
                  Text(
                      'Tu foto se obtiene de una selfie que coincide con tu referencia facial. La comprobación se renueva cada dos meses.',
                      style: TextStyle(color: colors.muted, height: 1.5)),
                  const SizedBox(height: 12),
                  Text(
                      'Puedes consultar o eliminar tu referencia facial desde la pantalla de comprobación.',
                      style: TextStyle(
                          color: colors.muted, fontSize: 13, height: 1.5)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
