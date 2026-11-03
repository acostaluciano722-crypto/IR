import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ir_mobile/screens/face_verification_screen.dart';
import 'package:ir_mobile/services/api_service.dart';
import 'package:ir_mobile/services/face_verification.dart';
import 'package:ir_mobile/services/selfie_camera.dart';

import 'ui_review_test.dart' show pumpScreen;

FaceVerificationStatus _status({
  bool enrolled = false,
  bool available = true,
  bool due = true,
}) =>
    FaceVerificationStatus(
        enrolled: enrolled,
        available: available,
        required: true,
        verificationDue: due,
        state: !enrolled
            ? 'not_enrolled'
            : due
                ? 'due'
                : 'verified',
        consentVersion: '2026-11-03-v2',
        verificationDueAt: enrolled ? DateTime.utc(2026, 11, 3) : null);

Uint8List _fixture() => File('assets/icons/google_g.png').readAsBytesSync();

class _Camera implements SelfieCamera {
  _Camera({this.startError});
  final CameraException? startError;
  int starts = 0;
  int captures = 0;
  int closes = 0;

  @override
  Future<void> initialize() async {
    starts++;
    if (startError != null) throw startError!;
  }

  @override
  Widget buildPreview() => const ColoredBox(
      color: Colors.black, child: Center(child: Icon(Icons.face_outlined)));
  @override
  Future<FaceCapture> capture() async {
    captures++;
    return FaceCapture(bytes: _fixture(), filename: 'selfie.png');
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

class _FaceApi extends ApiService {
  FaceVerificationStatus current = _status();
  bool matches = true;
  int enrollments = 0;
  int verifications = 0;
  int revocations = 0;
  String? consentVersion;

  @override
  Future<FaceVerificationStatus> getFaceVerificationStatus() async => current;

  @override
  Future<FaceVerificationStatus> enrollFace({
    required Uint8List documentBytes,
    required String documentFilename,
    required Uint8List selfieBytes,
    required String selfieFilename,
    required String consentVersion,
  }) async {
    expect(documentBytes, isNotEmpty);
    expect(selfieBytes, isNotEmpty);
    expect(documentFilename, 'document.png');
    expect(selfieFilename, 'selfie.png');
    enrollments++;
    this.consentVersion = consentVersion;
    return current = _status(enrolled: true, due: false);
  }

  @override
  Future<FaceVerificationResult> verifyFace({
    required Uint8List selfieBytes,
    required String selfieFilename,
  }) async {
    verifications++;
    if (matches) current = _status(enrolled: true, due: false);
    return FaceVerificationResult(
        status: current,
        verified: matches,
        message:
            matches ? null : 'La selfie no coincide. Toma una nueva foto.');
  }

  @override
  Future<void> revokeFaceEnrollment() async {
    revocations++;
    current = _status(available: false);
  }
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'document and consent precede live camera; accepted enrollment refreshes profile',
      (tester) async {
    final api = _FaceApi();
    final camera = _Camera();
    int profileRefreshes = 0;
    int completions = 0;
    await pumpScreen(
        tester,
        FaceVerificationScreen(
          api: api,
          initialStatus: api.current,
          requiredVerification: true,
          cameraFactory: () => camera,
          documentPicker: () async =>
              FaceCapture(bytes: _fixture(), filename: 'document.png'),
          onProfileChanged: () => profileRefreshes++,
          onCompleted: () => completions++,
        ));
    final openText = find.text('Abrir cámara para mi selfie');
    final openButton = find
        .ancestor(
            of: openText,
            matching:
                find.byWidgetPredicate((widget) => widget is OutlinedButton))
        .first;
    expect(tester.widget<OutlinedButton>(openButton).onPressed, isNull);
    expect(camera.starts, 0);
    await _tap(tester, 'Seleccionar foto del documento');
    final consent = find.byType(CheckboxListTile);
    await tester.ensureVisible(consent);
    await tester.tap(consent);
    await tester.pumpAndSettle();
    await _tap(tester, 'Abrir cámara para mi selfie');
    expect(camera.starts, 1);
    await _tap(tester, 'Tomar selfie');
    expect(camera.closes, 1);
    await _tap(tester, 'Comparar documento y selfie');
    expect(api.enrollments, 1);
    expect(api.consentVersion, '2026-11-03-v2');
    expect(profileRefreshes, 1);
    expect(completions, 1);
    expect(find.textContaining('La coincidencia facial se comprobó'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failed periodic selfie does not finish the gate or replace reference',
      (tester) async {
    final api = _FaceApi()
      ..current = _status(enrolled: true)
      ..matches = false;
    final camera = _Camera();
    int completions = 0;
    await pumpScreen(
        tester,
        FaceVerificationScreen(
            api: api,
            initialStatus: api.current,
            requiredVerification: true,
            cameraFactory: () => camera,
            onCompleted: () => completions++));
    expect(find.text('Seleccionar foto del documento'), findsNothing);
    await _tap(tester, 'Abrir cámara para mi selfie');
    await _tap(tester, 'Tomar selfie');
    await _tap(tester, 'Comprobar mi selfie');
    expect(api.verifications, 1);
    expect(completions, 0);
    expect(api.current.verificationDue, isTrue);
    expect(find.text('La selfie no coincide. Toma una nueva foto.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference can be revoked while inference is unavailable',
      (tester) async {
    final api = _FaceApi()
      ..current = _status(enrolled: true, available: false, due: false);
    int refreshes = 0;
    await pumpScreen(
        tester,
        FaceVerificationScreen(
            api: api,
            initialStatus: api.current,
            onProfileChanged: () => refreshes++));
    expect(find.text('Abrir cámara para mi selfie'), findsNothing);
    await _tap(tester, 'Eliminar referencia facial');
    await tester.tap(find.text('Eliminar referencia'));
    await tester.pumpAndSettle();
    expect(api.revocations, 1);
    expect(refreshes, 1);
    expect(find.text('Tu referencia facial fue eliminada.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'denied camera permission does not submit or allow gallery selfies',
      (tester) async {
    final api = _FaceApi()..current = _status(enrolled: true);
    final camera =
        _Camera(startError: CameraException('CameraAccessDenied', 'denied'));
    await pumpScreen(
        tester,
        FaceVerificationScreen(
            api: api, initialStatus: api.current, cameraFactory: () => camera));
    await _tap(tester, 'Abrir cámara para mi selfie');
    expect(
        find.textContaining('Permite el acceso a la cámara'), findsOneWidget);
    expect(find.text('Tomar selfie'), findsNothing);
    expect(api.verifications, 0);
    expect(camera.captures, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('backgrounding a live camera releases the device',
      (tester) async {
    final api = _FaceApi()..current = _status(enrolled: true);
    final camera = _Camera();
    await pumpScreen(
        tester,
        FaceVerificationScreen(
            api: api, initialStatus: api.current, cameraFactory: () => camera));
    await _tap(tester, 'Abrir cámara para mi selfie');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(camera.closes, 1);
    expect(find.textContaining('La cámara se ha pausado'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Tomar selfie'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
      'each enrollment retry obtains a fresh challenge and sends both images with consent',
      () async {
    int challenges = 0;
    int submissions = 0;
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Token session-token');
      if (request.url.path.endsWith('/challenge/')) {
        challenges++;
        expect(jsonDecode(request.body)['purpose'], 'enroll');
        return http.Response(
            jsonEncode({'challenge_token': 'challenge-$challenges'}), 200);
      }
      submissions++;
      expect(request.url.path, '/api/profile/face/enroll/');
      final body = utf8.decode(request.bodyBytes, allowMalformed: true);
      expect(body, contains('name="document"'));
      expect(body, contains('name="selfie"'));
      expect(body, contains('2026-11-03-v2'));
      expect(body, contains('challenge-$challenges'));
      if (submissions == 1) {
        return http.Response(
            jsonEncode({'code': 'face_mismatch', 'detail': 'No coincide.'}),
            422);
      }
      return http.Response(
          jsonEncode({
            'enrolled': true,
            'available': true,
            'required': true,
            'verification_due': false,
            'state': 'verified',
            'consent_version': '2026-11-03-v2'
          }),
          201);
    });
    addTearDown(client.close);
    final api = ApiService(baseUrl: 'http://ir.test/api', client: client)
      ..token = 'session-token';
    Future<FaceVerificationStatus> enroll() => api.enrollFace(
        documentBytes: _fixture(),
        documentFilename: 'document.png',
        selfieBytes: _fixture(),
        selfieFilename: 'selfie.png',
        consentVersion: '2026-11-03-v2');
    await expectLater(enroll(), throwsA(isA<FaceVerificationException>()));
    expect((await enroll()).hasCurrentVerification, isTrue);
    expect(challenges, 2);
    expect(submissions, 2);
  });

  test('business denial emits facial gate event', () async {
    final client = MockClient((request) async => http.Response(
        jsonEncode({
          'code': 'face_verification_required',
          'detail': 'Renueva tu comprobación.'
        }),
        403));
    addTearDown(client.close);
    final api = ApiService(baseUrl: 'http://ir.test/api', client: client);
    final event = api.faceVerificationRequiredEvents.first;
    await expectLater(api.getRides(), throwsA(isA<ApiException>()));
    await event;
  });
}
