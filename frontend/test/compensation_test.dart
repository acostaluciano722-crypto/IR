import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ir_mobile/screens/driver_compensation_screen.dart';
import 'package:ir_mobile/services/api_service.dart';

import 'ui_review_test.dart' show loadReviewFonts, pumpScreen;

class CompensationApi extends ApiService {
  bool fail = false;
  final account = <String, dynamic>{
    'personal_pv': '10025.75000',
    'pv_to_unlock': '0',
    'downline_enabled': true,
    'today': '2026-11-09',
    'daily_left_pv': '300000',
    'daily_right_pv': '350000',
    'daily_grade': 'Hierro',
    'daily_score': 1,
    'mastery': null,
    'mastery_period_start': '2026-11-01',
    'mastery_personal_pv': '25.75000',
    'mastery_left_pv': '900000',
    'mastery_right_pv': '1000000',
    'bonus_balance': '1080.01',
    'member_code': '1f7ef47d-5cf5-4945-b089-087417fc5a8d',
    'network': {
      'role': 'driver',
      'position': 2,
      'parent_position': 1,
      'side': 'left',
      'depth': 1
    },
    'pending_rules': ['Fórmula de utilidad neta'],
    'payouts': [
      {
        'amount': '1080.01',
        'kind': 'weekly',
        'start': '2026-11-01',
        'end': '2026-11-07',
        'payable_on': '2026-11-08',
        'status': 'credited'
      },
    ],
    'incentives': [],
  };
  final plan = <String, dynamic>{
    'source': 'PLAN COMPENSACION IR CONDUCTORES.pdf',
    'grades': [
      {
        'name': 'Hierro',
        'degree': 8,
        'personal_pv': 10000,
        'daily_weak_pv': 300000,
        'score': 1
      },
    ],
    'masteries': [
      {
        'name': 'Bronce',
        'rate': '0.10',
        'prerequisite': '3.000.000 PV en cada lado.',
        'incentive': r'$1.000.000 en efectivo'
      },
    ],
    'terms': ['Períodos: 1 al 15 y 16 al final del mes.'],
  };

  @override
  Future<Map<String, dynamic>> getDriverCompensation(
      {bool plan = false}) async {
    if (fail) throw ApiException('Sin conexión. Inténtalo de nuevo.');
    return plan ? this.plan : account;
  }
}

void main() {
  setUpAll(loadReviewFonts);

  testWidgets('Compensación muestra PV reales y se adapta a móvil y tableta',
      (tester) async {
    final api = CompensationApi();
    for (final capture in [
      ('phone', const Size(390, 844), 1.0),
      ('tablet', const Size(1024, 768), 1.0),
      ('phone-large-text', const Size(320, 740), 1.8),
    ]) {
      await pumpScreen(tester, DriverCompensationScreen(api: api),
          size: capture.$2, textScale: capture.$3);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await expectLater(
            find.byKey(const ValueKey('capture')),
            matchesGoldenFile(
                '../../artifacts/compensation/${capture.$1}.png'));
      }
      await tester.scrollUntilVisible(find.text('10.025,75 PV'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('10.025,75 PV'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Grado de hoy'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Grado de hoy'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Bonos y liquidaciones'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await expectLater(
            find.byKey(const ValueKey('capture')),
            matchesGoldenFile(
                '../../artifacts/compensation/${capture.$1}-details.png'));
      }
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Reintento recupera el estado y muestra pagos con centavos',
      (tester) async {
    final api = CompensationApi()..fail = true;
    await pumpScreen(tester, DriverCompensationScreen(api: api));
    expect(find.text('Sin conexión. Inténtalo de nuevo.'), findsOneWidget);
    api.fail = false;
    await tester.tap(find.text('Volver a intentar'));
    await tester.pumpAndSettle();
    expect(find.text('10.025,75 PV'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Saldo de bonos abonados'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('COP 1.080,01'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Antes de 10000 PV muestra la meta pendiente y un historial vacío',
      (tester) async {
    final api = CompensationApi();
    api.account.addAll({
      'personal_pv': '10',
      'pv_to_unlock': '9990',
      'downline_enabled': false,
      'payouts': [],
      'bonus_balance': '0'
    });
    await pumpScreen(tester, DriverCompensationScreen(api: api));
    expect(find.textContaining('Te faltan 9.990 PV'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.textContaining('Aún no tienes liquidaciones.'), 400,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Aún no tienes liquidaciones.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
