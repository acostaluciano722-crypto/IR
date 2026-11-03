import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_mobile/screens/complete_profile_screen.dart';
import 'package:ir_mobile/screens/login_screen.dart';
import 'package:ir_mobile/screens/password_help_screen.dart';
import 'package:ir_mobile/services/api_service.dart';

import 'ui_review_test.dart' show captureUi, loadReviewFonts, pumpScreen;

class _SupabaseApi extends ApiService {
  int googleCalls = 0;
  String? resetEmail;
  String? linkedPassword;
  @override
  bool get usesSupabase => true;
  @override
  Future<bool> isGoogleSignInAvailable() async => true;
  @override
  Future<void> signInWithGoogle() async {
    googleCalls++;
  }

  @override
  Future<void> resetPassword(String email) async {
    resetEmail = email;
  }

  @override
  Future<void> linkLegacyAccount(String password) async {
    linkedPassword = password;
  }
}

void main() {
  setUpAll(loadReviewFonts);

  testWidgets('Google and recovery controls fit phone and tablet',
      (tester) async {
    final api = _SupabaseApi();
    for (final viewport in [const Size(390, 844), const Size(1024, 768)]) {
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpScreen(tester, LoginScreen(api: api), size: viewport);
      await tester.runAsync(() async {
        for (final asset in [
          'assets/branding/ir_logo.png',
          'assets/icons/google_g.png'
        ]) {
          await precacheImage(
              AssetImage(asset), tester.element(find.byType(LoginScreen)));
        }
      });
      await tester.pumpAndSettle();
      await captureUi(tester, 'supabase-login-${viewport.width.toInt()}');
      final google = find.text('Continuar con Google');
      expect(google, findsOneWidget);
      await tester.ensureVisible(google);
      await tester.pumpAndSettle();
      await tester.tap(google);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(api.googleCalls, 2);
  });

  testWidgets(
      'password recovery confirms request without revealing account existence',
      (tester) async {
    final api = _SupabaseApi();
    await pumpScreen(tester, PasswordHelpScreen(api: api));
    await tester.enterText(find.byType(TextFormField), 'test@example.test');
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
    expect(api.resetEmail, 'test@example.test');
    expect(find.textContaining('Si hay una cuenta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'existing Google user can link the old account without changing its role',
      (tester) async {
    final api = _SupabaseApi();
    bool saved = false;
    await pumpScreen(
        tester,
        CompleteProfileScreen(
            api: api, needsLegacyLink: true, onSaved: () => saved = true));
    await captureUi(tester, 'supabase-link-account');
    expect(find.text('Conductor'), findsNothing);
    await tester.enterText(find.byType(TextFormField), 'old-password-123');
    await tester.tap(find.text('Vincular mi cuenta'));
    await tester.pumpAndSettle();
    expect(api.linkedPassword, 'old-password-123');
    expect(saved, isTrue);
    expect(tester.takeException(), isNull);
  });
}
