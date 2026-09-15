import 'package:flutter/material.dart';

import '../ui/ir_theme.dart';

class BonusScreen extends StatelessWidget {
  const BonusScreen(
      {required this.role,
      required this.points,
      required this.tier,
      super.key});

  final String role;
  final int points;
  final String tier;

  @override
  Widget build(BuildContext context) {
    final isDriver = role == 'driver';
    return Theme(
      data: irDarkTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Bonificaciones')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
                isDriver
                    ? 'Bonificaciones conductor'
                    : 'Bonificaciones pasajero',
                style: const TextStyle(
                  color: IrPalette.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
                'Tus puntos muestran actividad y elegibilidad. No son dinero ni un monto garantizado.',
                style: TextStyle(color: IrPalette.muted)),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$points PI',
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text('Nivel $tier',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 14),
                      const LinearProgressIndicator(value: null),
                      const SizedBox(height: 10),
                      Text(
                          isDriver
                              ? 'PI conductor = débito válido consumido / COP 10'
                              : 'PI pasajero = tarifa final válida / COP 20',
                          style: const TextStyle(
                              fontSize: 12, color: IrPalette.muted)),
                    ]),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: ListTile(
                leading: Icon(Icons.hourglass_top_outlined),
                title: Text('Estado actual: en progreso'),
                subtitle: Text(
                    'Los bonos se muestran como validados o liquidados solo después de la confirmación del backend.'),
              ),
            ),
            const SizedBox(height: 16),
            const Card(
              child: ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Sin monto garantizado'),
                subtitle: Text(
                    'UP, PI y PG no equivalen automáticamente a COP. La liquidación depende del período y de los fondos válidos.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
