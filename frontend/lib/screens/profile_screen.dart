import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../ui/ir_theme.dart';

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
  final _picker = ImagePicker();
  XFile? _selection;
  String? _photoUrl;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _photoUrl = widget.photoUrl;
  }

  Future<void> _choosePhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 88,
      );
      if (file != null && mounted) {
        setState(() {
          _selection = file;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo abrir la galería. Revisa los permisos e inténtalo de nuevo.');
    }
  }

  Future<void> _save() async {
    final file = _selection;
    if (file == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final url = await widget.api.uploadProfilePhoto(
        bytes: await file.readAsBytes(),
        filename: file.name,
      );
      if (!mounted) return;
      setState(() {
        _photoUrl = url;
        _selection = null;
      });
      widget.onPhotoChanged?.call(url);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Foto de perfil actualizada.')));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo guardar la imagen. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.deleteProfilePhoto();
      if (!mounted) return;
      setState(() {
        _photoUrl = null;
        _selection = null;
      });
      widget.onPhotoChanged?.call(null);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo quitar la foto. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _avatar() {
    final selected = _selection;
    if (selected != null) {
      return FutureBuilder<Uint8List>(
        future: selected.readAsBytes(),
        builder: (context, snapshot) => CircleAvatar(
          radius: 62,
          backgroundColor: IrPalette.accent,
          backgroundImage: snapshot.hasData ? MemoryImage(snapshot.data!) : null,
          child: snapshot.hasData ? null : const CircularProgressIndicator(),
        ),
      );
    }
    return CircleAvatar(
      radius: 62,
      backgroundColor: IrPalette.accent,
      backgroundImage: _photoUrl == null ? null : NetworkImage(_photoUrl!),
      child: _photoUrl == null
          ? const Icon(Icons.person, color: IrPalette.ink, size: 56)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.irColors;
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil')),
      backgroundColor: colors.surface,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 36),
          children: [
            Center(
              child: GestureDetector(
                onTap: _choosePhoto,
                child: _avatar(),
              ),
            ),
            const SizedBox(height: 18),
            Text(widget.name, textAlign: TextAlign.center, style: TextStyle(color: colors.text, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 5),
            Text(widget.role == 'driver' ? 'Conductor IR' : 'Pasajero IR', textAlign: TextAlign.center, style: TextStyle(color: colors.muted)),
            const SizedBox(height: 26),
            OutlinedButton.icon(
              onPressed: _saving ? null : _choosePhoto,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_photoUrl == null ? 'Elegir foto' : 'Cambiar foto'),
            ),
            if (_selection != null) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                label: Text(_saving ? 'Guardando…' : 'Guardar foto'),
              ),
            ],
            if (_photoUrl != null && _selection == null) ...[
              const SizedBox(height: 10),
              TextButton.icon(onPressed: _saving ? null : _remove, icon: const Icon(Icons.delete_outline), label: const Text('Quitar foto')),
            ],
            if (_error != null) ...[
              const SizedBox(height: 18),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 22),
            Text('Tu foto ayuda a que pasajeros y conductores te reconozcan durante el viaje.', textAlign: TextAlign.center, style: TextStyle(color: colors.muted, height: 1.45)),
          ],
        ),
      ),
    );
  }
}
