import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ir_mobile/screens/login_screen.dart';
import 'package:ir_mobile/screens/register_screen.dart';
import 'package:ir_mobile/screens/welcome_screen.dart';
import 'package:ir_mobile/screens/driver_wallet_screen.dart';
import 'package:ir_mobile/services/api_service.dart';
import 'package:ir_mobile/ui/ir_brand.dart';
import 'package:ir_mobile/ui/ir_components.dart';
import 'package:ir_mobile/ui/ir_theme.dart';

import 'ui_review_test.dart' show pumpScreen, captureUi, loadReviewFonts;

class _PendingLogin extends ApiService {
  final result = Completer<Map<String, dynamic>>();
  int calls = 0;
  @override
  Future<Map<String, dynamic>> login(String username, String password) {
    calls++;
    return result.future;
  }
}

class _WalletApi extends ApiService {
  int balance = 50000;
  int recharges = 0;
  @override
  Future<Map<String, dynamic>> getDriverMe() async => {
        'wallet_balance': '$balance.00',
        'reserved_balance': '1500.00',
        'available_balance': '${balance - 1500}.00',
      };
  @override
  Future<List<Map<String, dynamic>>> getDriverWalletTransactions() async => [];
  @override
  Future<Map<String, dynamic>> driverWalletRecharge(int amount) async {
    balance += amount;
    recharges++;
    return {'wallet_balance': balance, 'mode': 'sandbox'};
  }
}

void main() {
  setUpAll(loadReviewFonts);
  testWidgets('wallet confirms the selected amount and refreshes balances',
      (tester) async {
    final api = _WalletApi();
    await pumpScreen(tester, DriverWalletScreen(api: api));
    expect(find.text('COP 48.500'), findsOneWidget);
    await captureUi(tester, 'wallet');
    await tester.enterText(find.byType(TextFormField), '20000');
    await tester.ensureVisible(find.text('Revisar recarga'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar recarga'));
    await tester.pumpAndSettle();
    expect(api.recharges, 0);
    expect(
        find.text('Vas a recargar COP 20.000 en tu cartera.'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(api.recharges, 1);
    expect(find.text('COP 68.500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('registration validates fields and adapts to driver selection',
      (tester) async {
    await pumpScreen(tester, const RegisterScreen(),
        size: const Size(320, 568));
    final create = find.widgetWithText(FilledButton, 'Crear cuenta');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pump();
    expect(find.text('Completa este campo.'), findsWidgets);
    expect(find.text('Usa al menos 8 caracteres.'), findsOneWidget);
    await tester.ensureVisible(find.text('Conductor'));
    await tester.tap(find.text('Conductor'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Placa del vehículo'));
    expect(find.text('Número de documento'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'login blocks repeated submissions and handles leaving while pending',
      (tester) async {
    final api = _PendingLogin();
    await pumpScreen(tester, LoginScreen(api: api));
    await tester.enterText(
        find.byType(TextFormField).at(0), 'usuario@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');
    final submit = find.widgetWithText(FilledButton, 'Iniciar sesión');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(api.calls, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.result.completeError(ApiException('Sin conexión'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('buttons acknowledge press and reduced motion removes scaling',
      (tester) async {
    for (final reduced in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          theme: irDarkTheme(),
          home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: const WelcomeScreen())));
      await tester.pump(const Duration(milliseconds: 700));
      final button = find.widgetWithText(FilledButton, 'Crear cuenta');
      final gesture = await tester.startGesture(tester.getCenter(button));
      await tester.pump(const Duration(milliseconds: 150));
      final scale = tester.widget<AnimatedScale>(
          find.descendant(of: button, matching: find.byType(AnimatedScale)));
      expect(scale.scale, reduced ? 1 : .97);
      await gesture.cancel();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('welcome opens account screens with a brief IR route reveal',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: irDarkTheme(),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: const WelcomeScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    final registerButton = find.widgetWithText(FilledButton, 'Crear cuenta');
    await tester.ensureVisible(registerButton);
    await tester.tap(registerButton);
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 700));
    expect(
        find.text('Crea tu cuenta como pasajero o conductor.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('welcome route keeps a short fade when motion is reduced',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: irDarkTheme(),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const WelcomeScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 700));
    final registerButton = find.widgetWithText(FilledButton, 'Crear cuenta');
    await tester.ensureVisible(registerButton);
    await tester.tap(registerButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(
        find.text('Crea tu cuenta como pasajero o conductor.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loading state uses accessible IR styling', (tester) async {
    await pumpScreen(
      tester,
      const Scaffold(
        body: Center(
          child: IrLoadingState(label: 'Preparando tu espacio de conductor'),
        ),
      ),
    );

    expect(find.text('Preparando tu espacio de conductor'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('brand logo keeps its proportions across responsive sizes',
      (tester) async {
    for (final viewport in [
      const Size(320, 568),
      const Size(844, 390),
      const Size(1024, 768),
    ]) {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(MaterialApp(
        theme: irDarkTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: viewport,
            textScaler: const TextScaler.linear(1.6),
          ),
          child: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    IrBrandLogo(size: 88),
                    IrBrandLogo(size: 42, showWordmark: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final logos = find.byType(Image);
      expect(logos, findsNWidgets(2));
      for (final logo in logos.evaluate()) {
        final size = tester.getSize(find.byWidget(logo.widget));
        expect(size.width, closeTo(size.height, .1));
      }
      expect(tester.takeException(), isNull);
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  test('registration exposes server field errors', () async {
    await http.runWithClient(() async {
      final api = ApiService();
      await expectLater(
          api.register(
              name: 'Persona',
              identifier: 'duplicado@example.test',
              phone: '3000000000',
              role: 'passenger',
              password: 'password123'),
          throwsA(isA<ApiException>().having((error) => error.message,
              'message', contains('Ya existe una cuenta'))));
    },
        () => MockClient((request) async => http.Response(
            '{"identifier":["Ya existe una cuenta con ese correo."]}', 400)));
  });
}
