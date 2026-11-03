import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_mobile/screens/face_access_gate.dart';
import 'package:ir_mobile/screens/face_verification_screen.dart';
import 'package:ir_mobile/services/api_service.dart';
import 'package:ir_mobile/services/face_verification.dart';

class _FacePolicyApi extends ApiService {
  _FacePolicyApi(this.status);
  final FaceVerificationStatus status;
  @override
  Future<FaceVerificationStatus> getFaceVerificationStatus() async => status;
}

FaceVerificationStatus _policy(
        {required bool enrolled, required bool due, bool mandatory = true}) =>
    FaceVerificationStatus(
      enrolled: enrolled,
      available: true,
      required: mandatory,
      verificationDue: due,
      state: !enrolled
          ? 'not_enrolled'
          : due
              ? 'due'
              : 'verified',
      consentVersion: 'ir-face-v2',
      verificationDueAt: enrolled && !due
          ? DateTime.now().add(const Duration(days: 30))
          : null,
    );

void main() {
  for (final enrolled in [false, true]) {
    testWidgets(
        'required ${enrolled ? 'expired' : 'new'} check protects transport content',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: FaceAccessGate(
        api: _FacePolicyApi(_policy(enrolled: enrolled, due: true)),
        onProfileChanged: () {},
        onSignOut: () async {},
        child: const Scaffold(body: Text('Contenido de movilidad')),
      )));
      await tester.pumpAndSettle();
      expect(find.byType(FaceVerificationScreen), findsOneWidget);
      expect(find.text('Contenido de movilidad'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'current check allows the transport surface without requesting another selfie',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: FaceAccessGate(
      api: _FacePolicyApi(_policy(enrolled: true, due: false)),
      onProfileChanged: () {},
      onSignOut: () async {},
      child: const Scaffold(body: Text('Contenido de movilidad')),
    )));
    await tester.pumpAndSettle();
    expect(find.text('Contenido de movilidad'), findsOneWidget);
    expect(find.byType(FaceVerificationScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
