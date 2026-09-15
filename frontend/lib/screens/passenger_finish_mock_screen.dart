import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mock_data.dart';
import '../state/passenger_app_state.dart';

class PassengerFinishMockScreen extends StatefulWidget {
  const PassengerFinishMockScreen({super.key});

  @override
  State<PassengerFinishMockScreen> createState() =>
      _PassengerFinishMockScreenState();
}

class _PassengerFinishMockScreenState extends State<PassengerFinishMockScreen> {
  int rating = 5;
  final selectedTags = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PassengerAppState>();
    final offer = state.selectedOffer;
    final tags = ['Excelente servicio', 'Puntual', 'Conducción segura'];

    return Scaffold(
      appBar: AppBar(title: const Text('Finalización y calificación')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Icon(Icons.check_circle_outline,
              color: Color(0xFFC9A227), size: 64),
          const SizedBox(height: 8),
          const Text('Viaje completado',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Tarifa final registrada: ${cop(offer?.amount ?? state.proposal)}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    const Text('Método: Efectivo directo al conductor'),
                    const SizedBox(height: 12),
                    const Text('PI Ganado: +1.000 PI',
                        style: TextStyle(
                            color: Color(0xFF9A7614),
                            fontWeight: FontWeight.w900)),
                    const Text('Se reflejará en tu resumen tras la validación.',
                        style: TextStyle(color: Colors.black54, fontSize: 12)),
                  ]),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Califica tu experiencia',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
                5,
                (index) => IconButton(
                      onPressed: () => setState(() => rating = index + 1),
                      icon: Icon(
                          index < rating ? Icons.star : Icons.star_border,
                          color: const Color(0xFFC9A227),
                          size: 34),
                    )),
          ),
          Wrap(
            spacing: 8,
            children: tags
                .map((tag) => FilterChip(
                      label: Text(tag),
                      selected: selectedTags.contains(tag),
                      onSelected: (value) => setState(() {
                        if (value) {
                          selectedTags.add(tag);
                        } else {
                          selectedTags.remove(tag);
                        }
                      }),
                    ))
                .toList(),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: () {
              state.reset();
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            child: const Text('Enviar calificación'),
          ),
        ],
      ),
    );
  }
}
