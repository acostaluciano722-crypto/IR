import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_public.dart';

class AppAuth {
  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: defaultSupabaseUrl);
  static const publishableKey = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: defaultSupabasePublishableKey);
  static SupabaseClient? _client;
  static SupabaseClient? get client => _client;
  static bool get enabled => _client != null;

  static String get redirectUrl => kIsWeb
      ? Uri.base.origin
      : const String.fromEnvironment('SUPABASE_AUTH_REDIRECT_URL',
          defaultValue: 'ir://auth/callback');

  static Future<void> initialize() async {
    if (!const bool.fromEnvironment('SUPABASE_AUTH_ENABLED',
        defaultValue: true)) {
      return;
    }
    const url = supabaseUrl;
    const key = publishableKey;
    if (url.isEmpty && key.isEmpty) return;
    if (url.isEmpty || key.isEmpty || key.startsWith('sb_secret_')) {
      throw StateError('Configura la URL y la clave publicable de Supabase.');
    }
    await Supabase.initialize(
      url: url,
      publishableKey: key,
      authOptions:
          const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
    _client = Supabase.instance.client;
  }

  static String errorMessage(AuthException error) => switch (error.code) {
        'invalid_credentials' => 'El correo o la contraseña no son correctos.',
        'email_not_confirmed' => 'Confirma tu correo para iniciar sesión.',
        'user_already_exists' => 'Ya existe una cuenta con ese correo.',
        'weak_password' =>
          'Usa una contraseña más segura, de al menos 8 caracteres.',
        'over_email_send_rate_limit' ||
        'over_request_rate_limit' =>
          'Espera unos minutos antes de intentarlo de nuevo.',
        'provider_disabled' ||
        'unsupported_provider' =>
          'El acceso con Google aún no está disponible. Usa tu correo.',
        _ => 'No pudimos completar el acceso. Inténtalo de nuevo.',
      };
}
