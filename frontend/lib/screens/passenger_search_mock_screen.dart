import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../mock_data.dart';
import '../state/passenger_app_state.dart';
import 'passenger_match_mock_screen.dart';

class PassengerSearchMockScreen extends StatefulWidget {
  const PassengerSearchMockScreen({super.key});
  @override
  State<PassengerSearchMockScreen> createState() =>
      _PassengerSearchMockScreenState();
}

class _PassengerSearchMockScreenState extends State<PassengerSearchMockScreen> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) context.read<PassengerAppState>().revealNextOffer();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PassengerAppState>();
    return Scaffold(
        appBar: AppBar(title: const Text('Buscando / negociación')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: const Color(0xFF24272A),
                  borderRadius: BorderRadius.circular(18)),
              child: const Row(children: [
                CircularProgressIndicator(
                    color: Color(0xFFC9A227), strokeWidth: 2),
                SizedBox(width: 14),
                Expanded(
                    child: Text('Buscando conductores elegibles...',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800)))
              ])),
          const SizedBox(height: 14),
          Text('Tu propuesta: ${cop(state.proposal)}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ...state.offers.map((offer) => _Offer(
              offer: offer,
              onTap: () {
                state.selectOffer(offer);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const PassengerMatchMockScreen()));
              })),
          if (state.offers.isEmpty) const LinearProgressIndicator(),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: () =>
                  Navigator.popUntil(context, (route) => route.isFirst),
              icon: const Icon(Icons.close),
              label: const Text('Cancelar solicitud'))
        ]));
  }
}

class _Offer extends StatelessWidget {
  const _Offer({required this.offer, required this.onTap});
  final DriverOffer offer;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CircleAvatar(
                  backgroundColor: Color(0xFF24272A),
                  child: Icon(Icons.person, color: Color(0xFFC9A227))),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(offer.name,
                      style: const TextStyle(fontWeight: FontWeight.w800))),
              Text(cop(offer.amount),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, color: Color(0xFF9A7614)))
            ]),
            const SizedBox(height: 8),
            Text(
                '${offer.vehicle} · ${offer.plate} · ETA ${offer.etaMinutes} min · ★ ${offer.rating}'),
            const SizedBox(height: 10),
            const LinearProgressIndicator(value: .72, color: Color(0xFFC9A227)),
            const SizedBox(height: 10),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: onTap, child: const Text('Seleccionar oferta')))
          ])));
}
