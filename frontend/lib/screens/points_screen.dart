import 'package:flutter/material.dart';

import '../ui/ir_components.dart';
import '../ui/ir_page_body.dart';
import '../ui/ir_theme.dart';

class PointsScreen extends StatelessWidget {
  const PointsScreen({
    required this.role,
    required this.points,
    required this.tier,
    super.key,
  });

  final String role;
  final int points;
  final String tier;

  @override
  Widget build(BuildContext context) {
    final isDriver = role == 'driver';
    return Scaffold(
      appBar: AppBar(title: const Text('Puntos')),
      body: IrEditorialBackdrop(
        child: IrPageBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
            children: [
              IrEntrance(
                child: IrPageIntro(
                  title: 'Puntos ${isDriver ? 'conductor' : 'pasajero'}',
                  description:
                      'Tu actividad y avance dentro de ProMaster, explicados con claridad.',
                ),
              ),
              const SizedBox(height: 28),
              IrEntrance(
                delay: const Duration(milliseconds: 80),
                child: IrPanel(
                  accent: true,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PUNTOS DISPONIBLES',
                          textScaler: TextScaler.noScaling,
                          style: TextStyle(
                              color: IrPalette.ink.withValues(alpha: .68),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.6)),
                      const SizedBox(height: 8),
                      Text('$points PI',
                          style: const TextStyle(
                              color: IrPalette.ink,
                              fontSize: 44,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -2)),
                      const SizedBox(height: 10),
                      Text('Nivel actual: $tier',
                          style: const TextStyle(
                              color: IrPalette.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 24),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: LinearProgressIndicator(
                          minHeight: 7,
                          value: _progress(points, isDriver),
                          color: IrPalette.ink,
                          backgroundColor: IrPalette.ink.withValues(alpha: .16),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isDriver
                            ? 'PI conductor = débito válido consumido / COP 10'
                            : 'PI pasajero = tarifa final válida / COP 20',
                        style: TextStyle(
                            color: IrPalette.ink.withValues(alpha: .75),
                            fontSize: 12,
                            height: 1.35),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const IrEntrance(
                delay: Duration(milliseconds: 140),
                child: IrInfoRow(
                  icon: Icons.account_tree_outlined,
                  title: 'PG-I y PG-D',
                  description:
                      'Los puntos de red se calculan por actividad válida de descendientes y se muestran separados de PI.',
                ),
              ),
              const SizedBox(height: 12),
              const IrEntrance(
                delay: Duration(milliseconds: 200),
                child: IrInfoRow(
                  icon: Icons.lock_outline,
                  title: 'Regla ProMaster',
                  description:
                      'PI, PG y UP miden actividad o elegibilidad. No crean dinero ni garantizan una bonificación.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _progress(int value, bool isDriver) {
    final threshold = isDriver ? 56000000 : 1375000;
    return (value / threshold).clamp(0.0, 1.0).toDouble();
  }
}
