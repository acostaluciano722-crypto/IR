import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_mobile/screens/bonus_screen.dart';
import 'package:ir_mobile/screens/login_screen.dart';
import 'package:ir_mobile/screens/points_screen.dart';
import 'package:ir_mobile/screens/register_screen.dart';
import 'package:ir_mobile/screens/role_section_screen.dart';
import 'package:ir_mobile/screens/welcome_screen.dart';
import 'package:ir_mobile/ui/ir_theme.dart';

const _capture = bool.fromEnvironment('CAPTURE_UI');
const _phase = String.fromEnvironment('CAPTURE_PHASE', defaultValue: 'after');

Future<void> loadReviewFonts() async {
  if (!_capture) return;
  final fonts = {
    'Arial': 'C:/Windows/Fonts/arial.ttf',
    'Georgia': 'C:/Windows/Fonts/georgia.ttf',
    'MaterialIcons':
        '${Platform.environment['FLUTTER_ROOT'] ?? 'C:/Users/pc/develop/flutter'}/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
  };
  for (final entry in fonts.entries) {
    final file = File(entry.value);
    if (await file.exists()) {
      await (FontLoader(entry.key)
            ..addFont(file.readAsBytes().then(ByteData.sublistView)))
          .load();
    }
  }
}

Future<void> captureUi(WidgetTester tester, String name) async {
  if (!_capture) return;
  await expectLater(find.byKey(const ValueKey('capture')),
      matchesGoldenFile('../artifacts/ui/$_phase/$name.png'));
}

Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  Size size = const Size(390, 844),
  bool light = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  irLightMode.value = light;
  await tester.pumpWidget(MaterialApp(
    theme: light ? irLightTheme() : irDarkTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: RepaintBoundary(key: const ValueKey('capture'), child: child!),
    ),
    home: screen,
  ));
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUpAll(loadReviewFonts);
  final screens = <String, Widget>{
    'welcome': const WelcomeScreen(),
    'login': const LoginScreen(),
    'register': const RegisterScreen(),
    'points':
        const PointsScreen(role: 'passenger', points: 1200, tier: 'Inicial'),
    'bonus': const BonusScreen(role: 'driver', points: 2500, tier: 'Inicial'),
    'history': const RoleSectionScreen(
        title: 'Historial de viajes', role: 'passenger', items: []),
  };
  for (final entry in screens.entries) {
    testWidgets('${entry.key} fits a phone and large text', (tester) async {
      await pumpScreen(tester, entry.value);
      await captureUi(tester, entry.key);
      expect(tester.takeException(), isNull);
      await pumpScreen(tester, entry.value,
          size: const Size(1024, 768), light: true);
      await captureUi(tester, '${entry.key}-tablet-light');
      expect(tester.takeException(), isNull);
      await pumpScreen(tester, entry.value,
          size: const Size(844, 390), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await pumpScreen(tester, entry.value,
          size: const Size(320, 568), textScale: 1.6);
      expect(tester.takeException(), isNull);
    });
  }
}
