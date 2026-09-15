import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/passenger_app_state.dart';
import 'passenger_fare_mock_screen.dart';

class PassengerHomeMockScreen extends StatelessWidget {
  const PassengerHomeMockScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PassengerAppState>();
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const _MapMock(),
          const SizedBox(height: 14),
          TextField(
              onChanged: state.setDestination,
              decoration: const InputDecoration(
                  hintText: '¿A dónde vas?', prefixIcon: Icon(Icons.search))),
          const SizedBox(height: 12),
          const Row(children: [
            _Quick(label: 'Casa', icon: Icons.home_outlined),
            SizedBox(width: 8),
            _Quick(label: 'Trabajo', icon: Icons.work_outline),
            SizedBox(width: 8),
            _Quick(label: 'Reciente', icon: Icons.history)
          ]),
          const SizedBox(height: 20),
          const Text('¿Qué necesitas hoy?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
              'Selecciona un destino para consultar categorías y tarifa.',
              style: TextStyle(color: Colors.black54)),
          const SizedBox(height: 18),
          FilledButton.icon(
              onPressed: () {
                state.prepareTrip();
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PassengerFareMockScreen()));
              },
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Elegir destino')),
        ]);
  }
}

class _MapMock extends StatelessWidget {
  const _MapMock();
  @override
  Widget build(BuildContext context) => Container(
      height: 190,
      decoration: BoxDecoration(
          color: const Color(0xFF25282B),
          borderRadius: BorderRadius.circular(18)),
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _GridPainter())),
        const Positioned(
            left: 18,
            top: 16,
            child: Text('CARTAGENA',
                style: TextStyle(
                    color: Colors.white54,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800))),
        const Positioned(
            left: 28,
            bottom: 38,
            child: Icon(Icons.location_on, color: Color(0xFFC9A227), size: 42)),
        const Positioned(
            left: 18,
            bottom: 14,
            child: Text('Ubicación actual',
                style: TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w700))),
        const Positioned(
            right: 16,
            top: 16,
            child: Icon(Icons.my_location, color: Color(0xFFC9A227)))
      ]));
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF3A3E42);
    for (var x = 0.0; x < size.width; x += 42) {
      canvas.drawLine(Offset(x, 0), Offset(x + 80, size.height), paint);
    }
    for (var y = 20.0; y < size.height; y += 42) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y - 15), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Quick extends StatelessWidget {
  const _Quick({required this.label, required this.icon});
  final String label;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Expanded(
      child: OutlinedButton.icon(
          onPressed: () {},
          icon: Icon(icon, size: 18),
          label: Text(label, overflow: TextOverflow.ellipsis)));
}
