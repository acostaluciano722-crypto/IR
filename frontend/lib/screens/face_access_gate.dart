import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/face_verification.dart';
import '../ui/ir_auth_layout.dart';
import '../ui/ir_components.dart';
import 'face_verification_screen.dart';

/// Keeps the transport flow behind the server's current facial policy.
class FaceAccessGate extends StatefulWidget {
  const FaceAccessGate(
      {required this.api,
      required this.child,
      required this.onProfileChanged,
      required this.onSignOut,
      super.key});
  final ApiService api;
  final Widget child;
  final VoidCallback onProfileChanged;
  final Future<void> Function() onSignOut;

  @override
  State<FaceAccessGate> createState() => _FaceAccessGateState();
}

class _FaceAccessGateState extends State<FaceAccessGate> {
  late Future<FaceVerificationStatus> _status;
  FaceVerificationStatus? _lastStatus;
  StreamSubscription<void>? _required;
  Timer? _deadline;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _status = _load();
    _required = widget.api.faceVerificationRequiredEvents.listen((_) {
      if (!mounted || _loading) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      _refresh();
    });
  }

  Future<FaceVerificationStatus> _load() async {
    _loading = true;
    try {
      final result = await widget.api.getFaceVerificationStatus();
      if (!mounted) return result;
      _lastStatus = result;
      _deadline?.cancel();
      final dueAt = result.verificationDueAt;
      if (result.required && !result.verificationDue && dueAt != null) {
        final remaining = dueAt.difference(DateTime.now());
        // Long browser timers are clamped. Revisit the deadline at most hourly.
        final delay = remaining.isNegative
            ? const Duration(seconds: 1)
            : remaining > const Duration(hours: 1)
                ? const Duration(hours: 1)
                : remaining;
        _deadline = Timer(delay, () {
          if (mounted) _refresh();
        });
      }
      return result;
    } finally {
      _loading = false;
    }
  }

  void _refresh() {
    if (mounted) setState(() => _status = _load());
  }

  @override
  void dispose() {
    _required?.cancel();
    _deadline?.cancel();
    super.dispose();
  }

  bool get _mayKeepContent {
    final value = _lastStatus;
    if (value == null) return false;
    if (!value.required) return true;
    return !value.verificationDue &&
        (value.verificationDueAt?.isAfter(DateTime.now()) ?? false);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FaceVerificationStatus>(
        future: _status,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            if (_mayKeepContent) return widget.child;
            return const Scaffold(
                body: Center(
                    child: IrLoadingState(label: 'Comprobando tu perfil')));
          }
          if (snapshot.hasError) {
            return IrAuthLayout(
                title: 'Comprobemos tu perfil',
                subtitle:
                    'Necesitamos confirmar el estado de tu comprobación facial para continuar.',
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      IrInlineMessage(
                          message: snapshot.error is ApiException
                              ? (snapshot.error as ApiException).message
                              : 'No pudimos consultar tu perfil. Revisa tu conexión.',
                          error: true),
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: _refresh,
                          child: const Text('Intentar de nuevo')),
                      TextButton(
                          onPressed: widget.onSignOut,
                          child: const Text('Cerrar sesión')),
                    ]));
          }
          final status = snapshot.data!;
          if (status.needsVerification) {
            return FaceVerificationScreen(
                api: widget.api,
                initialStatus: status,
                requiredVerification: true,
                onCompleted: widget.onProfileChanged,
                onSignOut: widget.onSignOut);
          }
          return widget.child;
        },
      );
}
