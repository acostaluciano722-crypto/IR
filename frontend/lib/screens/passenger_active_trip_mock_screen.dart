import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../mock_data.dart';
import '../state/passenger_app_state.dart';
import 'passenger_finish_mock_screen.dart';

class PassengerActiveTripMockScreen extends StatelessWidget {
  const PassengerActiveTripMockScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PassengerAppState>();
    final trip = state.trip;
    final offer = state.selectedOffer;
    return Scaffold(
        appBar: AppBar(title: const Text('Viaje activo')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
              height: 250,
              decoration: BoxDecoration(
                  color: const Color(0xFF25282B),
                  borderRadius: BorderRadius.circular(18)),
              child: const Center(
                  child: Icon(Icons.navigation,
                      color: Color(0xFFC9A227), size: 64))),
          const SizedBox(height: 16),
          const Text('EN VIAJE',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF9A7614))),
          const SizedBox(height: 8),
          Text('Destino: ${trip?.destination ?? 'Destino seleccionado'}',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          Text('Tarifa acordada: ${cop(offer?.amount ?? state.proposal)}'),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.security_outlined),
              label: const Text('Seguridad')),
          OutlinedButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.report_problem_outlined),
              label: const Text('Reportar problema')),
          OutlinedButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PassengerFinishMockScreen())),
              child: const Text('Simular llegada a destino'))
        ]));
  }
}
