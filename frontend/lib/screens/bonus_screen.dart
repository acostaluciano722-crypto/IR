import 'package:flutter/material.dart';

import '../ui/ir_components.dart';
import '../ui/ir_page_body.dart';
import '../ui/ir_theme.dart';

class BonusScreen extends StatelessWidget {
  const BonusScreen({
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
      appBar: AppBar(title: const Text('Bonificaciones')),
      body: IrEditorialBackdrop(
        child: IrPageBody(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
            children: [
              IrEntrance(
                child: IrPageIntro(
                  title: isDriver
                      ? 'Bonificaciones conductor'
                      : 'Bonificaciones pasajero',
                  description:
                      'Consulta tu elegibilidad y el estado real de cada beneficio.',
                ),
              ),
              const SizedBox(height: 28),
              IrEntrance(
                delay: const Duration(milliseconds: 80),
                child: IrPanel(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$points PI',
                                style: const TextStyle(
                                    fontSize: 38,
                                    height: 1,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1.5)),
                            const SizedBox(height: 10),
                            Text('Nivel $tier',
                                style: TextStyle(
                                    color: context.irColors.muted,
                                    fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: IrPalette.accent,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        child: const Icon(Icons.auto_awesome_outlined,
                            color: IrPalette.ink),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const IrEntrance(
                delay: Duration(milliseconds: 140),
                child: IrInfoRow(
                  icon: Icons.hourglass_top_outlined,
                  title: 'En progreso',
                  description:
                      'Los bonos aparecen como validados o liquidados después de la confirmación del sistema.',
                ),
              ),
              const SizedBox(height: 12),
              const IrEntrance(
                delay: Duration(milliseconds: 200),
                child: IrInfoRow(
                  icon: Icons.lock_outline,
                  title: 'Sin monto garantizado',
                  description:
                      'UP, PI y PG no equivalen automáticamente a COP. La liquidación depende del período y de los fondos válidos.',
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isDriver
                    ? 'PI conductor = débito válido consumido / COP 10'
                    : 'PI pasajero = tarifa final válida / COP 20',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: context.irColors.muted, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
