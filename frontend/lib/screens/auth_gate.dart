import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/api_service.dart';
import '../services/app_auth.dart';
import '../ui/ir_components.dart';
import '../ui/ir_auth_layout.dart';
import 'complete_profile_screen.dart';
import 'driver_home_screen.dart';
import 'face_access_gate.dart';
import 'passenger_home_screen.dart';
import 'password_help_screen.dart';
import 'welcome_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _api = ApiService();
  StreamSubscription<AuthState>? _subscription;
  Future<Map<String, dynamic>>? _profile;
  String? _subject;
  bool _recovering = false;

  @override
  void initState() {
    super.initState();
    final auth = AppAuth.client?.auth;
    if (auth == null) return;
    _subject = auth.currentSession?.user.id;
    if (_subject != null) _profile = _api.getCurrentUser();
    _subscription = auth.onAuthStateChange.listen((state) {
      if (!mounted) return;
      final subject = state.session?.user.id;
      final recovery = state.event == AuthChangeEvent.passwordRecovery;
      if (!recovery && subject == _subject) return;
      setState(() {
        _subject = subject;
        _recovering = recovery;
        _profile = subject == null || recovery ? null : _api.getCurrentUser();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    }, onError: (_) {
      if (mounted) {
        setState(() => _profile = Future.error(ApiException(
            'No pudimos recuperar tu sesión. Inicia sesión de nuevo.')));
      }
    });
  }

  void _reload() => setState(() {
        _recovering = false;
        _profile = _api.getCurrentUser();
      });

  Future<void> _signOut() async {
    try {
      await _api.signOut();
    } catch (_) {
      if (mounted) _reload();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_recovering) return PasswordRecoveryScreen(onSaved: _reload);
    if (_profile == null) return const WelcomeScreen();
    return FutureBuilder<Map<String, dynamic>>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body:
                  Center(child: IrLoadingState(label: 'Preparando tu cuenta')));
        }
        if (snapshot.error is ProfileRequiredException) {
          return CompleteProfileScreen(
              api: _api,
              onSaved: _reload,
              needsLegacyLink:
                  snapshot.error is LegacyAccountLinkRequiredException);
        }
        if (snapshot.hasError) {
          return Scaffold(
              body: SafeArea(
                  child: Center(
                      child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              IrInlineMessage(
                  message: snapshot.error is ApiException
                      ? (snapshot.error as ApiException).message
                      : 'No pudimos cargar tu cuenta. Revisa tu conexión.',
                  error: true),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: _reload, child: const Text('Intentar de nuevo')),
              TextButton(
                  onPressed: () async {
                    try {
                      await _api.signOut();
                    } catch (_) {
                      if (mounted) _reload();
                    }
                  },
                  child: const Text('Cerrar sesión')),
            ]),
          ))));
        }
        final user = snapshot.data!;
        return FaceAccessGate(
          key: ValueKey(user['id']),
          api: _api,
          onProfileChanged: _reload,
          onSignOut: _signOut,
          child: user['role'] == 'driver'
              ? DriverHomeScreen(api: _api, user: user)
              : PassengerHomeScreen(api: _api, user: user),
        );
      },
    );
  }
}
