import 'package:flutter/material.dart';

class PointsScreen extends StatelessWidget {
  const PointsScreen(
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
    return Scaffold(
      appBar: AppBar(title: const Text('Puntos')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Puntos ${isDriver ? 'conductor' : 'pasajero'}',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
              'Esta sección muestra únicamente actividad y progreso ProMaster. Los puntos no son dinero.',
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$points PI',
                        style: const TextStyle(
                            fontSize: 34, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('Nivel actual: $tier',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 18),
                    const Text('Progreso PI',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _progress(points, isDriver)),
                    const SizedBox(height: 8),
                    Text(
                        isDriver
                            ? 'Driver PI = débito válido consumido / COP 10'
                            : 'Passenger PI = tarifa final válida / COP 20',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ]),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
              child: ListTile(
                  leading: Icon(Icons.account_tree_outlined),
                  title: Text('PG-I y PG-D'),
                  subtitle: Text(
                      'Los puntos de red se calculan por actividad válida de descendientes y se muestran separados de PI.'))),
          const SizedBox(height: 12),
          const Card(
              child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('Regla ProMaster'),
                  subtitle: Text(
                      'PI, PG y UP miden actividad o elegibilidad. No crean dinero ni garantizan una bonificación.'))),
        ],
      ),
    );
  }

  double _progress(int value, bool isDriver) {
    final threshold = isDriver ? 56000000 : 1375000;
    return (value / threshold).clamp(0.0, 1.0).toDouble();
  }
}
