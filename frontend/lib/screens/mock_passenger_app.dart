import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/passenger_app_state.dart';
import 'passenger_home_mock_screen.dart';

class MockPassengerApp extends StatefulWidget {
  const MockPassengerApp({super.key});
  @override
  State<MockPassengerApp> createState() => _MockPassengerAppState();
}

class _MockPassengerAppState extends State<MockPassengerApp> {
  int index = 0;
  static const titles = ['Inicio', 'Viajes', 'ProMaster', 'Soporte', 'Perfil'];

  @override
  Widget build(BuildContext context) {
    const placeholders = [
      _MockSection(
          icon: Icons.history,
          title: 'Viajes',
          detail: 'Aquí aparecerá tu historial de viajes.'),
      _MockSection(
          icon: Icons.account_tree_outlined,
          title: 'ProMaster',
          detail: 'Progreso, red, ciclos y referidos.'),
      _MockSection(
          icon: Icons.support_agent_outlined,
          title: 'Soporte',
          detail: 'Ayuda y seguridad IR.'),
      _MockSection(
          icon: Icons.person_outline,
          title: 'Perfil',
          detail: 'Tus datos y preferencias.'),
    ];
    return ChangeNotifierProvider(
      create: (_) => PassengerAppState(),
      child: Scaffold(
        appBar: AppBar(title: Text(titles[index])),
        body: index == 0
            ? const PassengerHomeMockScreen()
            : placeholders[index - 1],
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Inicio'),
            NavigationDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: 'Viajes'),
            NavigationDestination(
                icon: Icon(Icons.account_tree_outlined),
                selectedIcon: Icon(Icons.account_tree),
                label: 'ProMaster'),
            NavigationDestination(
                icon: Icon(Icons.support_agent_outlined),
                selectedIcon: Icon(Icons.support_agent),
                label: 'Soporte'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Perfil'),
          ],
        ),
      ),
    );
  }
}

class _MockSection extends StatelessWidget {
  const _MockSection(
      {required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: const Color(0xFFC9A227), size: 56),
        const SizedBox(height: 14),
        Text(title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(detail, style: const TextStyle(color: Colors.black54))
      ]));
}
