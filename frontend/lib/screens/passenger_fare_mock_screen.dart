import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mock_data.dart';
import '../state/passenger_app_state.dart';
import 'passenger_search_mock_screen.dart';

class PassengerFareMockScreen extends StatelessWidget {
  const PassengerFareMockScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final state = context.watch<PassengerAppState>();
    final trip = state.trip;
    if (trip == null) {
      return const Scaffold(
          body: Center(child: Text('Prepara un destino para continuar.')));
    }
    return Scaffold(
        appBar: AppBar(title: const Text('Categoría y tarifa')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFF24272A),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ruta estimada',
                        style: TextStyle(color: Colors.white60, fontSize: 12)),
                    const SizedBox(height: 8),
                    Text('${trip.origin}  →  ${trip.destination}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                        '${trip.distanceKm.toStringAsFixed(1)} km · ${trip.durationMinutes} min aproximados',
                        style: const TextStyle(color: Colors.white70))
                  ])),
          const SizedBox(height: 20),
          const Text('Elige una categoría',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          SizedBox(
              height: 110,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, index) {
                    final item = categories[index];
                    final selected = state.category == item;
                    return GestureDetector(
                        onTap: () => state.setCategory(item),
                        child: Container(
                            width: 132,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFC9A227)
                                    : const Color(0xFF24272A),
                                borderRadius: BorderRadius.circular(14)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                      item.contains('Moto')
                                          ? Icons.two_wheeler
                                          : Icons.directions_car,
                                      color: selected
                                          ? Colors.black
                                          : Colors.white70),
                                  const Spacer(),
                                  Text(item,
                                      style: TextStyle(
                                          color: selected
                                              ? Colors.black
                                              : Colors.white,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12))
                                ])));
                  })),
          const SizedBox(height: 18),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFF1EEE5),
                  borderRadius: BorderRadius.circular(16)),
              child: Column(children: [
                const _FareLine(
                    label: 'Tarifa recomendada',
                    value: '\$20.000 COP',
                    strong: true),
                const SizedBox(height: 8),
                const _FareLine(
                    label: 'Mínimo legal aplicable', value: '\$12.250 COP'),
                const SizedBox(height: 10),
                const Text(
                    'La recomendada es orientativa; la propuesta no puede estar por debajo del mínimo.',
                    style: TextStyle(color: Colors.black54, fontSize: 12))
              ])),
          const SizedBox(height: 16),
          TextFormField(
              initialValue: state.proposal.toString(),
              keyboardType: TextInputType.number,
              onChanged: state.setProposal,
              decoration: InputDecoration(
                  labelText: 'Tu propuesta',
                  prefixText: '\$ ',
                  suffixText: 'COP',
                  errorText: state.proposalIsValid
                      ? null
                      : 'No puede ser menor al mínimo legal.')),
          const SizedBox(height: 18),
          FilledButton.icon(
              onPressed: state.proposalIsValid
                  ? () {
                      state.submitRequest();
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const PassengerSearchMockScreen()));
                    }
                  : null,
              icon: const Icon(Icons.send_outlined),
              label: const Text('Solicitar viaje')),
        ]));
  }
}

class _FareLine extends StatelessWidget {
  const _FareLine(
      {required this.label, required this.value, this.strong = false});
  final String label;
  final String value;
  final bool strong;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(value,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: strong ? const Color(0xFF9A7614) : Colors.black87))
      ]);
}
