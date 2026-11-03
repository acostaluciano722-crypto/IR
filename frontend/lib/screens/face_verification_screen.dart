import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/face_verification.dart';
import '../services/selfie_camera.dart';
import '../ui/ir_auth_layout.dart';
import '../ui/ir_theme.dart';

class FaceVerificationScreen extends StatefulWidget {
  const FaceVerificationScreen({
    required this.api,
    this.initialStatus,
    this.requiredVerification = false,
    this.onCompleted,
    this.onProfileChanged,
    this.onSignOut,
    this.cameraFactory,
    this.documentPicker,
    super.key,
  });

  final ApiService api;
  final FaceVerificationStatus? initialStatus;
  final bool requiredVerification;
  final VoidCallback? onCompleted;
  final VoidCallback? onProfileChanged;
  final Future<void> Function()? onSignOut;
  final SelfieCameraFactory? cameraFactory;
  final FaceDocumentPicker? documentPicker;

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen>
    with WidgetsBindingObserver {
  FaceVerificationStatus? _status;
  SelfieCamera? _camera;
  FaceCapture? _document;
  FaceCapture? _selfie;
  bool _loading = true;
  bool _cameraStarting = false;
  bool _cameraActive = false;
  bool _capturing = false;
  bool _saving = false;
  bool _deleting = false;
  bool _pickingDocument = false;
  bool _consent = false;
  bool _completed = false;
  String? _error;
  String? _notice;

  bool get _busy => _saving || _deleting || _capturing || _cameraStarting;
  bool get _enrolling => !(_status?.enrolled ?? false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _status = widget.initialStatus;
    if (_status != null) {
      _loading = false;
    } else {
      unawaited(_loadStatus());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_cameraActive && _camera != null) {
        unawaited(_closeCamera());
        if (mounted) {
          setState(() => _notice =
              'La cámara se ha pausado. Ábrela de nuevo cuando estés listo.');
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final camera = _camera;
    _camera = null;
    if (camera != null) unawaited(camera.close());
    _document = null;
    _selfie = null;
    super.dispose();
  }

  Future<void> _loadStatus() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final status = await widget.api.getFaceVerificationStatus();
      if (mounted) setState(() => _status = status);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No pudimos consultar tu comprobación facial. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _selectDocument() async {
    if (_busy || _pickingDocument) return;
    setState(() {
      _pickingDocument = true;
      _error = null;
    });
    try {
      final capture = await (widget.documentPicker ?? pickFaceDocument)();
      if (capture == null || !mounted) return;
      if (capture.bytes.lengthInBytes > 5 * 1024 * 1024) {
        setState(() => _error =
            'La foto del documento es demasiado grande. Usa una imagen de hasta 5 MB.');
        return;
      }
      setState(() {
        _document = capture;
        _notice = null;
      });
    } on PlatformException {
      if (mounted) {
        setState(() => _error =
            'No pudimos abrir tus fotos. Revisa el permiso y vuelve a intentarlo.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No pudimos abrir la foto del documento. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _pickingDocument = false);
    }
  }

  Future<void> _startCamera() async {
    if (_busy || _status?.available != true || (_enrolling && !_consent)) {
      return;
    }
    await _closeCamera();
    if (!mounted) return;
    setState(() {
      _cameraStarting = true;
      _error = null;
      _notice = null;
      _selfie = null;
      _completed = false;
    });
    final camera = (widget.cameraFactory ?? DeviceSelfieCamera.new)();
    _camera = camera;
    try {
      await camera.initialize();
      if (!mounted || _camera != camera) {
        await camera.close();
        return;
      }
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == AppLifecycleState.hidden ||
          lifecycle == AppLifecycleState.paused ||
          lifecycle == AppLifecycleState.detached) {
        await _closeCamera();
        if (mounted) {
          setState(() => _notice =
              'La cámara se ha pausado. Ábrela de nuevo cuando estés listo.');
        }
        return;
      }
      setState(() => _cameraActive = true);
    } on CameraException catch (error) {
      await _closeCamera();
      if (mounted) setState(() => _error = _cameraError(error.code));
    } on MissingPluginException {
      await _closeCamera();
      if (mounted) {
        setState(() => _error =
            'La cámara no está disponible en esta versión. Abre IR en Chrome o en Android.');
      }
    } catch (_) {
      await _closeCamera();
      if (mounted) {
        setState(() => _error =
            'No pudimos abrir la cámara. Comprueba que otra aplicación no la esté usando.');
      }
    } finally {
      if (mounted) setState(() => _cameraStarting = false);
    }
  }

  String _cameraError(String code) => switch (code) {
        'CameraAccessDenied' ||
        'CameraAccessDeniedWithoutPrompt' ||
        'CameraAccessRestricted' ||
        'permissionDenied' =>
          'Permite el acceso a la cámara en tu navegador o en los ajustes del dispositivo. En la web usa HTTPS o localhost.',
        'no_camera' =>
          'No encontramos una cámara. Conecta una o abre IR desde tu teléfono.',
        _ =>
          'No pudimos iniciar la cámara. Comprueba el permiso y vuelve a intentarlo.',
      };

  Future<void> _closeCamera() async {
    final camera = _camera;
    _camera = null;
    if (mounted) setState(() => _cameraActive = false);
    if (camera != null) {
      try {
        await camera.close();
      } catch (_) {/* Camera is already closed. */}
    }
  }

  Future<void> _takeSelfie() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final image = await camera.capture();
      await _closeCamera();
      if (image.bytes.lengthInBytes > 5 * 1024 * 1024) {
        if (mounted) {
          setState(() => _error =
              'La selfie es demasiado grande. Usa una captura de hasta 5 MB.');
        }
        return;
      }
      if (mounted) setState(() => _selfie = image);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No pudimos tomar la selfie. Abre de nuevo la cámara e inténtalo otra vez.');
      }
      await _closeCamera();
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _submit() async {
    final selfie = _selfie;
    final status = _status;
    if (_busy || selfie == null || status == null || !status.available) return;
    if (_enrolling && (_document == null || !_consent)) return;
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      FaceVerificationStatus updated;
      if (_enrolling) {
        final document = _document!;
        updated = await widget.api.enrollFace(
          documentBytes: document.bytes,
          documentFilename: document.filename,
          selfieBytes: selfie.bytes,
          selfieFilename: selfie.filename,
          consentVersion: status.consentVersion,
        );
      } else {
        final result = await widget.api.verifyFace(
            selfieBytes: selfie.bytes, selfieFilename: selfie.filename);
        if (!result.verified) {
          if (mounted) {
            setState(() {
              _status = result.status;
              _error = result.message ??
                  'La selfie no coincide con tu referencia. Toma otra foto e intenta de nuevo.';
            });
          }
          return;
        }
        updated = result.status;
      }
      if (!mounted) return;
      setState(() {
        _status = updated;
        _selfie = null;
        _document = null;
        _consent = false;
        _completed = true;
        _notice =
            'La coincidencia facial se comprobó. Tu selfie ya es tu foto de perfil.';
      });
      widget.onProfileChanged?.call();
      if (widget.requiredVerification) widget.onCompleted?.call();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'No pudimos terminar la comprobación. Tus datos anteriores se conservan. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _revoke() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('¿Eliminar tu referencia facial?'),
              content: const Text(
                  'Retiraremos tu referencia biométrica y la foto de perfil creada con ella. Para volver a comprobar tu rostro necesitarás tu documento y una nueva selfie.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Conservar referencia')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Eliminar referencia')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    await _closeCamera();
    if (!mounted) return;
    setState(() {
      _deleting = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.api.revokeFaceEnrollment();
      widget.onProfileChanged?.call();
      if (!mounted) return;
      setState(() {
        _selfie = null;
        _document = null;
        _consent = false;
        _completed = false;
        _notice = 'Tu referencia facial fue eliminada.';
      });
      await _loadStatus();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'No pudimos eliminar la referencia. Vuelve a intentarlo.');
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String _date(DateTime value) =>
      MaterialLocalizations.of(context).formatMediumDate(value.toLocal());

  @override
  Widget build(BuildContext context) {
    final colors = context.irColors;
    return PopScope(
      canPop: !widget.requiredVerification && !_saving && !_deleting,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.requiredVerification,
          title: const Text('Verificación facial'),
          actions: [
            if (widget.requiredVerification && widget.onSignOut != null)
              TextButton(
                  onPressed: _busy ? null : _signOut,
                  child: const Text('Cerrar sesión')),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          semanticsLabel: 'Consultando tu verificación facial'))
                  : LayoutBuilder(builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 840;
                      final overview = _overview(colors);
                      final task = _task(colors);
                      return SingleChildScrollView(
                        padding: EdgeInsets.all(wide ? 32 : 20),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Expanded(child: overview),
                                    const SizedBox(width: 48),
                                    SizedBox(width: 420, child: task),
                                  ])
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                    overview,
                                    const SizedBox(height: 28),
                                    task
                                  ]),
                      );
                    }),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    await _closeCamera();
    if (mounted) {
      setState(() {
        _document = null;
        _selfie = null;
        _consent = false;
      });
    }
    try {
      await widget.onSignOut?.call();
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'No pudimos cerrar la sesión. Intenta de nuevo.');
      }
    }
  }

  Widget _overview(IrColors colors) {
    final status = _status;
    final title = _completed || status?.hasCurrentVerification == true
        ? 'Tu rostro está comprobado'
        : status?.enrolled == true
            ? 'Es momento de una nueva selfie'
            : 'Tu documento. Tu selfie. Tu perfil.';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.face_retouching_natural_rounded,
          size: 36, color: colors.accent),
      const SizedBox(height: 20),
      Text(title,
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w700, height: 1.12, letterSpacing: -.6)),
      const SizedBox(height: 14),
      Text(
          status?.enrolled == true
              ? 'Comparamos una selfie reciente con tu última referencia comprobada. La renovación corresponde cada dos meses.'
              : 'Comparamos el rostro de tu documento con una selfie tomada ahora. Si coinciden, la selfie se convierte en tu foto de perfil.',
          style: TextStyle(color: colors.muted, fontSize: 16, height: 1.55)),
      const SizedBox(height: 26),
      if (status != null) _statusRow(status, colors),
      const SizedBox(height: 26),
      _fact(
          Icons.lock_outline_rounded,
          'Tu documento no se conserva',
          'La foto del documento se procesa para esta comparación. Conservamos una referencia facial protegida para las siguientes comprobaciones.',
          colors),
      const SizedBox(height: 18),
      _fact(
          Icons.person_outline_rounded,
          'Una comprobación de coincidencia',
          'Este proceso compara rostros; no autentica el documento ni certifica tu identidad legal.',
          colors),
      if (status?.enrolled == true) ...[
        const SizedBox(height: 24),
        TextButton.icon(
            onPressed: _busy ? null : _revoke,
            icon: const Icon(Icons.delete_outline_rounded),
            label: Text(_deleting
                ? 'Eliminando referencia…'
                : 'Eliminar referencia facial')),
      ],
    ]);
  }

  Widget _statusRow(FaceVerificationStatus status, IrColors colors) =>
      Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: colors.raised, borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
                status.hasCurrentVerification
                    ? Icons.check_circle_outline_rounded
                    : Icons.schedule_rounded,
                color: colors.accent,
                size: 22),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      !status.enrolled
                          ? 'Primera comprobación pendiente'
                          : status.verificationDue
                              ? 'Renueva tu comprobación facial'
                              : 'Coincidencia facial comprobada',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (status.verificationDueAt != null) ...[
                    const SizedBox(height: 5),
                    Text(
                        '${status.verificationDue ? 'Venció' : 'Renueva antes del'} ${_date(status.verificationDueAt!)}',
                        style: TextStyle(color: colors.muted, height: 1.4)),
                  ],
                ])),
          ]));

  Widget _fact(IconData icon, String title, String detail, IrColors colors) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 21, color: colors.muted),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w600, height: 1.4)),
          const SizedBox(height: 4),
          Text(detail,
              style: TextStyle(color: colors.muted, fontSize: 14, height: 1.5)),
        ])),
      ]);

  Widget _task(IrColors colors) {
    final status = _status;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error != null) ...[
        IrInlineMessage(message: _error!, error: true),
        const SizedBox(height: 16),
      ],
      if (_notice != null) ...[
        IrInlineMessage(message: _notice!),
        const SizedBox(height: 16),
      ],
      if (status == null) ...[
        OutlinedButton.icon(
            onPressed: _loadStatus,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Volver a consultar')),
      ] else if (!status.available) ...[
        Icon(Icons.cloud_off_outlined, size: 40, color: colors.muted),
        const SizedBox(height: 16),
        const Text('La comprobación facial no está disponible ahora.',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        const SizedBox(height: 8),
        Text('Vuelve a intentarlo en unos minutos.',
            style: TextStyle(color: colors.muted, height: 1.5)),
        const SizedBox(height: 20),
        OutlinedButton.icon(
            onPressed: _loadStatus,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Comprobar disponibilidad')),
      ] else if (_completed) ...[
        if (status.photoUrl != null)
          Center(
              child: ClipOval(
                  child: Image.network(status.photoUrl!,
                      width: 112,
                      height: 112,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.person_outline_rounded, size: 88)))),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: () {
              if (widget.onCompleted != null) {
                widget.onCompleted!();
              } else {
                Navigator.of(context).maybePop();
              }
            },
            child: const Text('Continuar')),
      ] else ...[
        if (_enrolling) ...[
          _stepTitle('1', 'Foto de tu documento', colors),
          const SizedBox(height: 12),
          _documentControl(colors),
          const SizedBox(height: 24),
        ],
        _stepTitle(_enrolling ? '2' : null, 'Selfie en este momento', colors),
        const SizedBox(height: 12),
        Text(
            'Mira de frente, con buena luz y sin cubrir tu rostro. Solo debe aparecer una persona.',
            style: TextStyle(color: colors.muted, height: 1.5)),
        const SizedBox(height: 16),
        if (_enrolling) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            onChanged: _busy
                ? null
                : (value) {
                    setState(() {
                      _consent = value ?? false;
                      if (!_consent) _selfie = null;
                    });
                    if (!_consent) unawaited(_closeCamera());
                  },
            title: const Text('Autorizo la comparación facial',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: const Text(
                'Acepto el procesamiento de estas fotos y el almacenamiento de una referencia facial protegida. Puedo eliminarla desde mi perfil.',
                style: TextStyle(fontSize: 13, height: 1.45)),
          ),
          const SizedBox(height: 16),
        ],
        _selfieControl(colors),
        if (_enrolling && (_document == null || !_consent)) ...[
          const SizedBox(height: 10),
          Text(
              'Selecciona la foto del documento y autoriza la comparación para abrir la cámara.',
              style:
                  TextStyle(color: colors.muted, fontSize: 13, height: 1.45)),
        ],
        if (_selfie != null) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy || (_enrolling && (_document == null || !_consent))
                ? null
                : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.verified_user_outlined),
            label: Text(_saving
                ? 'Comprobando rostro…'
                : _enrolling
                    ? 'Comparar documento y selfie'
                    : 'Comprobar mi selfie'),
          ),
          if (_saving) ...[
            const SizedBox(height: 10),
            Text(
                'La comprobación puede tardar unos segundos. Mantén esta pantalla abierta.',
                style:
                    TextStyle(color: colors.muted, fontSize: 13, height: 1.5)),
          ],
        ],
      ],
    ]);
  }

  Widget _stepTitle(String? number, String title, IrColors colors) =>
      Row(children: [
        if (number != null) ...[
          Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: colors.accent, borderRadius: BorderRadius.circular(8)),
              child: Text(number,
                  style: TextStyle(
                      color: colors.surface, fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
        ],
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600))),
      ]);

  Widget _documentControl(IrColors colors) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_document != null) ...[
          ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(_document!.bytes,
                  height: 160,
                  fit: BoxFit.contain,
                  semanticLabel: 'Documento seleccionado para la comparación',
                  errorBuilder: (_, __, ___) => const SizedBox(
                      height: 80,
                      child: Center(
                          child: Text(
                              'No pudimos mostrar esta imagen. Selecciona otra.'))))),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
            onPressed: _busy || _pickingDocument ? null : _selectDocument,
            icon: const Icon(Icons.badge_outlined),
            label: Text(_pickingDocument
                ? 'Abriendo fotos…'
                : _document == null
                    ? 'Seleccionar foto del documento'
                    : 'Cambiar foto del documento')),
        const SizedBox(height: 8),
        Text(
            'La fotografía del rostro debe verse nítida, sin reflejos. JPG, PNG o WebP; hasta 5 MB.',
            style: TextStyle(color: colors.muted, fontSize: 13, height: 1.45)),
      ]);

  Widget _selfieControl(IrColors colors) {
    final camera = _camera;
    final selfie = _selfie;
    if (selfie != null || (_cameraActive && camera != null)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 4 / 5,
              child: ColoredBox(
                  color: Colors.black,
                  child: selfie != null
                      ? Image.memory(selfie.bytes,
                          fit: BoxFit.cover,
                          semanticLabel:
                              'Selfie tomada para la comprobación facial')
                      : Stack(fit: StackFit.expand, children: [
                          camera!.buildPreview(),
                          IgnorePointer(
                              child: Center(
                                  child: FractionallySizedBox(
                            widthFactor: .64,
                            heightFactor: .70,
                            child: DecoratedBox(
                                decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.all(
                                        Radius.elliptical(160, 210)),
                                    border: Border.all(
                                        color: IrPalette.accent
                                            .withValues(alpha: .8),
                                        width: 2))),
                          ))),
                        ])),
            )),
        const SizedBox(height: 12),
        if (selfie != null)
          OutlinedButton.icon(
              onPressed: _busy ? null : _startCamera,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tomar otra selfie'))
        else
          FilledButton.icon(
              onPressed: _busy ? null : _takeSelfie,
              icon: const Icon(Icons.camera_alt_outlined),
              label: Text(_capturing ? 'Tomando selfie…' : 'Tomar selfie')),
        if (_cameraActive)
          TextButton(
              onPressed: _capturing ? null : _closeCamera,
              child: const Text('Cerrar cámara')),
      ]);
    }
    return OutlinedButton.icon(
        onPressed:
            _cameraStarting || (_enrolling && (!_consent || _document == null))
                ? null
                : _startCamera,
        icon: _cameraStarting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.camera_front_outlined),
        label: Text(_cameraStarting
            ? 'Preparando cámara…'
            : 'Abrir cámara para mi selfie'));
  }
}
