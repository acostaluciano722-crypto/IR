import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../mock_data.dart';
import '../state/passenger_app_state.dart';
import 'passenger_active_trip_mock_screen.dart';

class PassengerMatchMockScreen extends StatelessWidget {
  const PassengerMatchMockScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PassengerAppState>();
    final offer = state.selectedOffer;
    if (offer == null) {
      return const Scaffold(
          body: Center(child: Text('Selecciona una oferta para continuar.')));
    }
    return Scaffold(
        appBar: AppBar(title: const Text('Conductor seleccionado')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
              height: 210,
              decoration: BoxDecoration(
                  color: const Color(0xFF25282B),
                  borderRadius: BorderRadius.circular(18)),
              child: const Center(
                  child: Icon(Icons.directions_car,
                      color: Color(0xFFC9A227), size: 60))),
          const SizedBox(height: 14),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const CircleAvatar(
                              radius: 28,
                              backgroundColor: Color(0xFF24272A),
                              child:
                                  Icon(Icons.person, color: Color(0xFFC9A227))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text(
                                  '${offer.name}\n★ ${offer.rating} · ETA ${offer.etaMinutes} min',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 17)))
                        ]),
                        const SizedBox(height: 14),
                        Text('${offer.vehicle} · Placa ${offer.plate}'),
                        Text('Tarifa acordada: ${cop(offer.amount)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              IconButton(
                                  onPressed: () {},
                                  icon: const Icon(Icons.chat_bubble_outline),
                                  tooltip: 'Chat'),
                              IconButton(
                                  onPressed: () {},
                                  icon: const Icon(Icons.call_outlined),
                                  tooltip: 'Llamada'),
                              IconButton(
                                  onPressed: () {},
                                  icon: const Icon(Icons.share_outlined),
                                  tooltip: 'Compartir')
                            ])
                      ]))),
          const SizedBox(height: 12),
          FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.security_outlined),
              label: const Text('Centro de seguridad')),
          const SizedBox(height: 8),
          OutlinedButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PassengerActiveTripMockScreen())),
              child: const Text('Simular llegada del conductor'))
        ]));
  }
}
