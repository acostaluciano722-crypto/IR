import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_mobile/screens/face_verification_screen.dart';
import 'package:ir_mobile/screens/login_screen.dart';
import 'package:ir_mobile/screens/profile_screen.dart';
import 'package:ir_mobile/screens/register_screen.dart';
import 'package:ir_mobile/screens/welcome_screen.dart';
import 'package:ir_mobile/services/api_service.dart';
import 'package:ir_mobile/services/face_verification.dart';

import 'home_ui_test.dart'
    show
        buildPassengerReviewScreen,
        buildDriverReviewScreen,
        loadMobilityReviewAssets,
        useMobilityReviewPlatforms;
import 'ui_review_test.dart' show loadReviewFonts, pumpScreen, captureUi;

// Visual evidence uses synthetic profiles and a platform-view map placeholder.
// It never connects to an account, camera or location service.
class _ReviewApi extends ApiService {
  @override
  bool get usesSupabase => true;
  @override
  Future<bool> isGoogleSignInAvailable() async => false;
  @override
  Future<FaceVerificationStatus> getFaceVerificationStatus() async =>
      FaceVerificationStatus(
          enrolled: true,
          available: true,
          required: true,
          verificationDue: false,
          state: 'verified',
          consentVersion: '2026-11-03-v2',
          verificationDueAt: DateTime(2027, 1, 3));
}

const _face = FaceVerificationStatus(
  enrolled: false,
  available: true,
  required: true,
  verificationDue: true,
  state: 'not_enrolled',
  consentVersion: '2026-11-03-v2',
);

void main() {
  setUpAll(() async {
    await loadReviewFonts();
    await loadMobilityReviewAssets();
  });
  setUp(useMobilityReviewPlatforms);
  for (final frame in <String, Size>{
    'phone': const Size(390, 844),
    'desktop': const Size(1440, 900),
  }.entries) {
    final screens = <String, Widget Function()>{
      'welcome': () => const WelcomeScreen(),
      'login': () => LoginScreen(api: _ReviewApi()),
      'register': () => RegisterScreen(api: _ReviewApi()),
      'passenger': buildPassengerReviewScreen,
      'driver': buildDriverReviewScreen,
      'profile': () => ProfileScreen(
          api: _ReviewApi(), name: 'Cuenta de prueba IR', role: 'passenger'),
      'face': () => FaceVerificationScreen(
          api: _ReviewApi(),
          initialStatus: _face,
          requiredVerification: true,
          onSignOut: () async {}),
    };
    for (final screen in screens.entries) {
      testWidgets('review ${screen.key} ${frame.key}', (tester) async {
        await pumpScreen(tester, screen.value(), size: frame.value);
        await tester.runAsync(() async {
          final context = tester.element(find.byType(MaterialApp));
          await precacheImage(
              const AssetImage('assets/branding/ir_logo.png'), context);
        });
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull);
        await captureUi(tester, '${screen.key}-${frame.key}');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
  for (final register in [false, true]) {
    testWidgets('review user width ${register ? 'register' : 'login'}',
        (tester) async {
      final screen = register
          ? RegisterScreen(api: _ReviewApi())
          : LoginScreen(api: _ReviewApi());
      await pumpScreen(tester, screen, size: const Size(922, 900));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      await captureUi(tester, '${register ? 'register' : 'login'}-user-922');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
